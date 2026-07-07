import AppKit

/// Owns the in-memory note list and every open note window. Bridges window
/// controllers to disk persistence.
@MainActor
final class NoteManager {
    private var notes: [UUID: Note] = [:]
    private var controllers: [UUID: StickyNoteWindowController] = [:]
    private let saver = DebouncedSaver()
    private var lastColor: NoteColor = .gray
    private var lastOrigin: CGPoint?
    /// Notes deleted this session, most recent last, restorable via
    /// File > Reopen Last Deleted Note until the app quits.
    private var recentlyDeleted: [Note] = []

    var hasNotes: Bool { !notes.isEmpty }
    /// True when at least one stix has a window on screen (stashed ones don't).
    var hasOpenNotes: Bool { !controllers.isEmpty }
    var hasRecentlyDeleted: Bool { !recentlyDeleted.isEmpty }

    private var mouseUpMonitor: Any?

    /// The hints stix: seeded on a first-ever launch and reachable any time
    /// from Help > Show Welcome Stix. Uses the real list markers, so the
    /// checkbox is clickable and the bullets show the actual list styling.
    static let welcomeText = """
        Welcome to Stixx
        \u{2022} \u{2318}N makes a new stix \u{00B7} \u{2325}\u{2318}N works from any app
        \u{2022} Type "- " for a list, "[]" for a checklist
        \u{2610} Click a box to check it off
        \u{2022} Tab / \u{21E7}Tab indent list items
        \u{2022} Right-click a stix for colors and options
        \u{2022} The tray button saves a stix right away (\u{2318}S)
        \u{2022} The chevron collapses it to just its title
        \u{2022} \u{2318}F finds anything, saved stixx included
        """

    /// Loads persisted notes and opens a window for each — including the
    /// ones saved for later: putting a stix away lasts for the session, and
    /// a fresh launch brings every note back where it was left. On a
    /// first-ever launch (no saved file), seeds one welcome note, matching
    /// Stickies.
    func loadAndRestoreWindows() {
        installSnapMonitor()
        var loaded = NotesStore.load()
        if loaded.isEmpty {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            loaded = [Note(
                text: Self.welcomeText,
                color: .yellow,
                x: screen.minX + 60,
                y: screen.maxY - 400,
                width: 300,
                height: 320
            )]
        }
        let hadStashed = loaded.contains(where: \.isStashed)
        for var note in loaded {
            note.isStashed = false
            notes[note.id] = note
            showWindow(for: fitted(note))
        }
        if let last = loaded.last {
            lastColor = last.color
            lastOrigin = CGPoint(x: last.x, y: last.y)
        }
        if hadStashed {
            persist()
        }
    }

    func createNewNote() {
        let color = lastColor.next
        let origin = nextOrigin()
        let note = Note(color: color, isPinned: AppPreferences.shared.alwaysFloating, x: origin.x, y: origin.y)
        notes[note.id] = note
        lastColor = color
        lastOrigin = origin
        showWindow(for: note, animated: true)
        persist()
    }

    /// Opens a fresh copy of the welcome/tips stix, for Help > Show Welcome
    /// Stix — the seeded one is long gone by the time anyone looks for it.
    func createWelcomeStix() {
        let origin = nextOrigin()
        let note = Note(text: Self.welcomeText, color: .yellow, x: origin.x, y: origin.y, width: 300, height: 320)
        notes[note.id] = note
        lastOrigin = origin
        showWindow(for: note, animated: true)
        persist()
    }

    func noteDidChange(_ note: Note) {
        notes[note.id] = note
        persist()
    }

    func deleteNote(id: UUID) {
        guard let note = notes.removeValue(forKey: id) else { return }
        recentlyDeleted.append(note)
        controllers.removeValue(forKey: id)
        persist()
    }

    /// Brings back the most recently deleted note, window and all.
    func restoreLastDeletedNote() {
        guard let note = recentlyDeleted.popLast() else { return }
        let restored = fitted(note)
        notes[restored.id] = restored
        showWindow(for: restored, animated: true)
        persist()
    }

    // MARK: Stashing (save & put away)

    /// Saved-for-later stixx, for the Saved Stixx menus.
    func stashedNotes() -> [Note] {
        notes.values
            .filter(\.isStashed)
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    /// Saves a stix and closes its window without deleting it; it stays on
    /// disk and can be reopened from the Saved Stixx menu or the Find panel.
    func stashNote(id: UUID) {
        guard var note = notes[id] else { return }
        note.isStashed = true
        notes[id] = note
        controllers.removeValue(forKey: id)?.closeForStash()
        persist()
    }

    /// Reopens a stashed stix, window and all, where it was left.
    func reopenStashedNote(id: UUID) {
        guard var note = notes[id], note.isStashed else { return }
        note.isStashed = false
        notes[id] = note
        showWindow(for: fitted(note), animated: true)
        persist()
    }

    /// Forces any pending debounced save to disk immediately. Call before quit.
    func flushPendingSave() {
        saver.flushNow()
    }

    /// Restyles every open note window, so a Settings change (the glass
    /// tint slider) is visible the moment the slider moves.
    func refreshAllNoteStyles() {
        for controller in controllers.values {
            controller.refreshStyle()
        }
    }

    /// Orders every note window to the front, used by the menu bar item.
    func bringAllNotesToFront() {
        for controller in controllers.values {
            controller.window?.orderFront(nil)
        }
        controllers.values.first?.window?.makeKey()
    }

    // MARK: Tidy up

    /// Lines the open stixx up in a grid, one screen at a time: reading
    /// order (top row first, left to right) is preserved, sizes are kept,
    /// and rows wrap at the screen edge. A gentle slide, not a teleport.
    func tidyUp() {
        let onScreen = controllers.values.compactMap { controller -> (NSWindow, NSScreen)? in
            guard let window = controller.window,
                  let screen = window.screen ?? NSScreen.main else { return nil }
            return (window, screen)
        }
        for (screen, group) in Dictionary(grouping: onScreen, by: { $0.1 }) {
            tidy(group.map(\.0), within: screen.visibleFrame.insetBy(dx: 24, dy: 24))
        }
    }

    private func tidy(_ windows: [NSWindow], within area: NSRect) {
        // Rows are decided by where each stix sits now: anything within
        // 40pt vertically counts as the same row, then left beats right.
        let ordered = windows.sorted { a, b in
            if abs(a.frame.maxY - b.frame.maxY) > 40 { return a.frame.maxY > b.frame.maxY }
            return a.frame.minX < b.frame.minX
        }
        let gutter: CGFloat = 16
        var x = area.minX
        var rowTop = area.maxY
        var rowHeight: CGFloat = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for window in ordered {
                let size = window.frame.size
                if x > area.minX, x + size.width > area.maxX {
                    x = area.minX
                    rowTop -= rowHeight + gutter
                    rowHeight = 0
                }
                let target = NSRect(x: x, y: rowTop - size.height, width: size.width, height: size.height)
                window.animator().setFrame(target, display: true)
                x += size.width + gutter
                rowHeight = max(rowHeight, size.height)
            }
        }
    }

    /// Snapshot of every note, for the Find Notes panel.
    func allNotes() -> [Note] {
        Array(notes.values)
    }

    /// All notes as one human-readable text document, for File > Export.
    func exportText() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        let sorted = notes.values
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var lines = ["Stixx Notes — exported \(formatter.string(from: Date()))"]
        for text in sorted {
            lines.append("\n\u{2014}\u{2014}\u{2014}\n")
            lines.append(text)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Edge snapping

    /// When a drag of a note window ends, nudge it into alignment with
    /// nearby note edges and the screen's visible frame. Snapping happens
    /// on mouse-up (not during the drag) so the note never fights the hand.
    private func installSnapMonitor() {
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            MainActor.assumeIsolated {
                self?.snapWindowAfterDrag(event.window)
            }
            return event
        }
    }

    private func snapWindowAfterDrag(_ window: NSWindow?) {
        guard let window,
              let controller = controllers.values.first(where: { $0.window === window }),
              controller.wasRecentlyDragged else { return }
        let snapped = snappedFrame(for: window.frame, excluding: controller.note.id)
        guard snapped != window.frame else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(snapped, display: true)
        }
    }

    private func snappedFrame(for frame: NSRect, excluding id: UUID) -> NSRect {
        let threshold: CGFloat = 8
        var bestX: CGFloat?
        var bestY: CGFloat?
        func consider(_ delta: CGFloat, into best: inout CGFloat?) {
            if abs(delta) <= threshold, abs(delta) < abs(best ?? .greatestFiniteMagnitude) {
                best = delta
            }
        }
        for (otherID, controller) in controllers where otherID != id {
            guard let other = controller.window?.frame else { continue }
            for target in [other.minX, other.maxX] {
                consider(target - frame.minX, into: &bestX)
                consider(target - frame.maxX, into: &bestX)
            }
            for target in [other.minY, other.maxY] {
                consider(target - frame.minY, into: &bestY)
                consider(target - frame.maxY, into: &bestY)
            }
        }
        if let visible = NSScreen.screens.first(where: { $0.frame.intersects(frame) })?.visibleFrame {
            consider(visible.minX - frame.minX, into: &bestX)
            consider(visible.maxX - frame.maxX, into: &bestX)
            consider(visible.minY - frame.minY, into: &bestY)
            consider(visible.maxY - frame.maxY, into: &bestY)
        }
        var snapped = frame
        if let bestX { snapped.origin.x += bestX }
        if let bestY { snapped.origin.y += bestY }
        return snapped
    }

    /// Brings one note's window to the front, used by the Find panel.
    /// A stashed stix has no window, so it is reopened instead.
    func focusNote(id: UUID) {
        if let controller = controllers[id] {
            controller.window?.makeKeyAndOrderFront(nil)
        } else {
            reopenStashedNote(id: id)
        }
    }

    private func showWindow(for note: Note, animated: Bool = false) {
        let controller = StickyNoteWindowController(note: note, manager: self)
        controllers[note.id] = controller
        if animated {
            controller.presentAnimated()
        } else {
            controller.showWindow(nil)
        }
    }

    /// If a note's saved position no longer intersects any connected screen
    /// (e.g. an external display was disconnected), relocate it into view.
    private func fitted(_ note: Note) -> Note {
        var note = note
        let frame = note.frame
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if !onScreen {
            let origin = nextOrigin()
            note.x = origin.x
            note.y = origin.y
        }
        return note
    }

    private func nextOrigin() -> CGPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let base = lastOrigin ?? CGPoint(x: screen.minX + 40, y: screen.maxY - 260)
        var next = CGPoint(x: base.x + 24, y: base.y - 24)
        if next.x + 220 > screen.maxX || next.y < screen.minY {
            next = CGPoint(x: screen.minX + 40, y: screen.maxY - 260)
        }
        return next
    }

    private func persist() {
        let snapshot = notes
        saver.schedule {
            NotesStore.save(Array(snapshot.values))
        }
    }
}
