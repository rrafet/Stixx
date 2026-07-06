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
    var hasRecentlyDeleted: Bool { !recentlyDeleted.isEmpty }

    private var mouseUpMonitor: Any?

    /// Loads persisted notes and opens a window for each. On a first-ever
    /// launch (no saved file), seeds one welcome note, matching Stickies.
    func loadAndRestoreWindows() {
        installSnapMonitor()
        var loaded = NotesStore.load()
        if loaded.isEmpty {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            loaded = [Note(
                text: "Welcome to Stixx.\n\nRight-click a note for colors and options.\n\u{2318}N new note \u{00B7} \u{2325}\u{2318}N from anywhere \u{00B7} \u{2318}F find\nType \"- \" for a list, \"[]\" for a checklist.",
                color: .yellow,
                x: screen.minX + 60,
                y: screen.maxY - 280
            )]
        }
        for note in loaded {
            notes[note.id] = note
            showWindow(for: fitted(note))
        }
        if let last = loaded.last {
            lastColor = last.color
            lastOrigin = CGPoint(x: last.x, y: last.y)
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

    /// Forces any pending debounced save to disk immediately. Call before quit.
    func flushPendingSave() {
        saver.flushNow()
    }

    /// Orders every note window to the front, used by the menu bar item.
    func bringAllNotesToFront() {
        for controller in controllers.values {
            controller.window?.orderFront(nil)
        }
        controllers.values.first?.window?.makeKey()
    }

    /// Snapshot of every note, for the Find Notes panel.
    func allNotes() -> [Note] {
        Array(notes.values)
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

    /// Brings one note's window to the front, used by the Find Notes panel.
    func focusNote(id: UUID) {
        controllers[id]?.window?.makeKeyAndOrderFront(nil)
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
