import AppKit

/// Owns one note's window: builds the text view, forwards edits/moves/resizes
/// back to the NoteManager, offers a right-click color + translucency menu,
/// a Format menu (font family + size) reachable via the responder chain, a
/// top-right pin button for per-note "always on top", and the close-to-delete
/// confirmation.
@MainActor
final class StickyNoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSMenuItemValidation {
    static let minFontSize: Double = 12
    static let maxFontSize: Double = 28
    /// How strongly the note's color tints the frosted glass in translucent
    /// mode. Low on purpose: the blur should read as glass, not paint.
    private static let translucentTintAlpha: CGFloat = 0.22
    /// Resting opacity of the pin on a pinned note, so its state stays
    /// visible even when the controls have faded out.
    private static let restingPinAlpha: CGFloat = 0.55

    private(set) var note: Note
    private weak var manager: NoteManager?
    private let textView: StickyTextView
    private let scrollView: NSScrollView
    private let effectView: NSVisualEffectView
    private let tintView: NSBox
    private let paperView: PaperGradientView
    private let pinButton: NSButton
    private var isMouseInside = false
    /// While collapsed, holds the height to restore on expand; nil otherwise.
    private var expandedHeight: CGFloat?
    private var lastMoveAt: Date?
    private static let collapsedHeight: CGFloat = 44

    /// True right after the user dragged this note, used by NoteManager to
    /// decide whether a mouse-up should trigger edge snapping.
    var wasRecentlyDragged: Bool {
        lastMoveAt.map { Date().timeIntervalSince($0) < 0.4 } ?? false
    }

    init(note: Note, manager: NoteManager) {
        self.note = note
        self.manager = manager

        let containerView = HoverTrackingView()
        let effectView = NSVisualEffectView()
        let tintView = NSBox()
        let paperView = PaperGradientView()
        let scrollView = NSScrollView()
        let textView = StickyTextView()
        let pinButton = NSButton()
        self.effectView = effectView
        self.tintView = tintView
        self.paperView = paperView
        self.scrollView = scrollView
        self.textView = textView
        self.pinButton = pinButton

        let window = StickyNoteWindow(contentRect: note.frame, color: note.color.background)

        super.init(window: window)

        window.delegate = self
        window.title = Self.windowTitle(for: note.text)

        containerView.wantsLayer = true

        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.string = note.text
        textView.delegate = self
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.extraMenuItemsProvider = { [weak self] in self?.buildContextMenuItems() ?? [] }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        // Close/pin only appear when the mouse reaches the top edge of the
        // note. Text starts just low enough (10pt here + the text view's
        // own 14pt inset) that the appearing controls graze the headroom
        // instead of landing on the first line; the automatic inset would
        // push it down by a whole titlebar instead.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)

        // Behind-window blur used only when the note's "Translucent" option
        // is on; hidden (and free) otherwise. .hudWindow is the most
        // see-through material, and .active keeps the glass alive while the
        // note sits unfocused in the background — where sticky notes live.
        effectView.blendingMode = .behindWindow
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.isHidden = true

        // A whisper of the note's color over the glass, instead of the text
        // view painting a half-opaque background over the whole blur.
        tintView.boxType = .custom
        tintView.borderWidth = 0
        tintView.cornerRadius = 0
        tintView.titlePosition = .noTitle
        tintView.isHidden = true

        for view in [effectView, tintView, paperView, scrollView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                view.topAnchor.constraint(equalTo: containerView.topAnchor),
                view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }
        window.contentView = containerView

        // A pin button in the empty top-right corner of the (hidden) title
        // bar, using the same native API window tab bars / toolbars use to
        // add accessories there — no manual overlay layout needed.
        pinButton.frame = NSRect(x: 0, y: 0, width: 26, height: 24)
        pinButton.isBordered = false
        pinButton.imagePosition = .imageOnly
        pinButton.setButtonType(.momentaryChange)
        pinButton.target = self
        pinButton.action = #selector(togglePin(_:))
        pinButton.toolTip = "Keep this note on top"
        let pinAccessory = NSTitlebarAccessoryViewController()
        pinAccessory.view = pinButton
        pinAccessory.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(pinAccessory)

        // Controls stay invisible until the mouse is over the note; only the
        // close button survives of the traffic lights.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.alphaValue = 0
        pinButton.alphaValue = note.isPinned ? Self.restingPinAlpha : 0
        containerView.onHoverChanged = { [weak self] inside in
            guard let self else { return }
            self.isMouseInside = inside
            self.updateControlVisibility(animated: true)
        }

        applyWindowLevel()
        applyStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func windowTitle(for text: String) -> String {
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
        let trimmed = firstLine.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? "Note" : String(trimmed.prefix(40))
    }

    private func applyWindowLevel() {
        window?.level = note.isPinned ? .floating : .normal
    }

    /// Re-applies background, ink color, font, translucency, and paragraph
    /// spacing in one place, so any single change can never drift out of sync
    /// with the rest of the note's appearance.
    private func applyStyle() {
        let background = note.color.background
        let ink = note.color.textColor
        let font = note.fontStyle.font(size: CGFloat(note.fontSize))
        let translucent = note.isTranslucent

        // The note body never draws its own background. Opaque notes get a
        // paper gradient underneath; translucent notes get blur + a thin
        // tint, with the text floating directly on the glass.
        effectView.isHidden = !translucent
        tintView.isHidden = !translucent
        tintView.fillColor = background.withAlphaComponent(Self.translucentTintAlpha)
        paperView.isHidden = translucent
        paperView.fillColor = background
        window?.isOpaque = !translucent
        window?.backgroundColor = translucent ? .clear : background
        scrollView.drawsBackground = false

        textView.font = font
        textView.textColor = ink
        textView.insertionPointColor = ink
        textView.selectedTextAttributes = [.backgroundColor: ink.withAlphaComponent(0.18)]

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes[.paragraphStyle] = paragraphStyle
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        if fullRange.length > 0 {
            textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        }
        applyTextStyling()

        let symbolName = note.isPinned ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Keep this note on top")?
            .withSymbolConfiguration(config)
        pinButton.contentTintColor = ink.withAlphaComponent(note.isPinned ? 0.95 : 0.5)
        updateControlVisibility(animated: false)
    }

    /// The note's first line is its title: rendered semibold, like Notes,
    /// so a wall of stickies can be scanned at a glance. Checked-off
    /// checklist lines read as done: dimmed and struck through past the
    /// box. Reapplied after every edit since any keystroke can change both.
    private func applyTextStyling() {
        guard let storage = textView.textStorage else { return }
        let text = textView.string as NSString
        guard text.length > 0 else { return }
        let ink = note.color.textColor
        let bodyFont = note.fontStyle.font(size: CGFloat(note.fontSize))
        let titleFont = note.fontStyle.font(size: CGFloat(note.fontSize), weight: .semibold)
        let full = NSRange(location: 0, length: text.length)
        let newlineIndex = text.range(of: "\n").location
        let titleLength = newlineIndex == NSNotFound ? text.length : newlineIndex
        storage.beginEditing()
        storage.addAttribute(.font, value: bodyFont, range: full)
        if titleLength > 0 {
            storage.addAttribute(.font, value: titleFont, range: NSRange(location: 0, length: titleLength))
        }
        storage.addAttribute(.foregroundColor, value: ink, range: full)
        storage.removeAttribute(.strikethroughStyle, range: full)
        text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            guard lineRange.length >= 1, text.character(at: lineRange.location) == 0x2611 else { return } // "☑"
            storage.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.45), range: lineRange)
            if lineRange.length > 2 {
                let checkedText = NSRange(location: lineRange.location + 2, length: lineRange.length - 2)
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: checkedText)
            }
        }
        storage.endEditing()
    }

    /// Fades the close button and pin in when the mouse is over the note and
    /// out when it leaves. A pinned note keeps its pin faintly visible so the
    /// pinned state never becomes invisible.
    private func updateControlVisibility(animated: Bool) {
        let closeButton = window?.standardWindowButton(.closeButton)
        let controlAlpha: CGFloat = isMouseInside ? 1 : 0
        let pinAlpha: CGFloat = isMouseInside ? 1 : (note.isPinned ? Self.restingPinAlpha : 0)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                closeButton?.animator().alphaValue = controlAlpha
                pinButton.animator().alphaValue = pinAlpha
            }
        } else {
            closeButton?.alphaValue = controlAlpha
            pinButton.alphaValue = pinAlpha
        }
    }

    /// Collapses the note to a title-bar-sized strip (or expands it back),
    /// keeping the top edge in place — the classic Stickies gesture, reached
    /// via double-clicking the top edge or Window > Collapse Note.
    @objc func toggleCollapse(_ sender: Any?) {
        guard let window else { return }
        var frame = window.frame
        if let restoredHeight = expandedHeight {
            frame.origin.y = frame.maxY - restoredHeight
            frame.size.height = restoredHeight
            expandedHeight = nil
        } else {
            expandedHeight = frame.height
            frame.origin.y = frame.maxY - Self.collapsedHeight
            frame.size.height = Self.collapsedHeight
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    // MARK: Pin button

    @objc func togglePin(_ sender: Any?) {
        note.isPinned.toggle()
        applyWindowLevel()
        applyStyle()
        manager?.noteDidChange(note)
    }

    // MARK: Context menu (color + translucency + delete)

    private func buildContextMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for color in NoteColor.allCases {
            let item = NSMenuItem(title: color.displayName, action: #selector(colorItemSelected(_:)), keyEquivalent: "")
            item.target = self
            item.image = Self.swatchImage(for: color.background)
            item.state = (color == note.color) ? .on : .off
            item.representedObject = color.rawValue
            items.append(item)
        }
        items.append(.separator())

        let translucentItem = NSMenuItem(title: "Translucent", action: #selector(toggleTranslucent), keyEquivalent: "")
        translucentItem.target = self
        translucentItem.state = note.isTranslucent ? .on : .off
        items.append(translucentItem)

        let deleteItem = NSMenuItem(title: "Delete Note", action: #selector(deleteRequested), keyEquivalent: "")
        deleteItem.target = self
        items.append(.separator())
        items.append(deleteItem)
        return items
    }

    static func swatchImage(for color: NSColor, size: CGFloat = 14) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let inset: CGFloat = 1.5
        let path = NSBezierPath(ovalIn: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2))
        color.setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.2).setStroke()
        path.lineWidth = 1
        path.stroke()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    @objc func colorItemSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let color = NoteColor(rawValue: raw) else { return }
        note.color = color
        // Crossfade the whole content from the old color to the new one.
        let transition = CATransition()
        transition.duration = 0.2
        transition.type = .fade
        window?.contentView?.layer?.add(transition, forKey: "colorFade")
        applyStyle()
        manager?.noteDidChange(note)
    }

    @objc func toggleTranslucent() {
        note.isTranslucent.toggle()
        applyStyle()
        manager?.noteDidChange(note)
    }

    @objc private func deleteRequested() {
        guard let window else { return }
        if confirmDeletion(for: window) {
            animateOutAndClose()
        }
    }

    /// Shows the window with a quick fade + grow, used for newly created
    /// and restored notes (launch restores appear instantly).
    func presentAnimated() {
        guard let window else { return }
        let target = note.frame
        window.setFrame(target.insetBy(dx: target.width * 0.03, dy: target.height * 0.03), display: false)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(target, display: true)
        }
    }

    /// Fades the note out, then closes for real; windowWillClose does the
    /// actual deletion, so every close path stays consistent.
    private func animateOutAndClose() {
        guard let window else { return }
        window.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
        })
    }

    private func confirmDeletion(for window: NSWindow) -> Bool {
        guard AppPreferences.shared.confirmBeforeDelete else { return true }
        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "You can bring it back with File > Reopen Last Deleted Note (\u{21E7}\u{2318}T) until you quit Stixx."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.alertStyle = .warning
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            AppPreferences.shared.confirmBeforeDelete = false
        }
        return response == .alertFirstButtonReturn
    }

    // MARK: Format menu (font family + size), reached via the responder chain

    @objc func selectSystemFont(_ sender: Any?) { setFontStyle(.system) }
    @objc func selectRoundedFont(_ sender: Any?) { setFontStyle(.rounded) }
    @objc func selectSerifFont(_ sender: Any?) { setFontStyle(.serif) }
    @objc func selectMonospacedFont(_ sender: Any?) { setFontStyle(.monospaced) }
    @objc func increaseFontSize(_ sender: Any?) { changeFontSize(by: 2) }
    @objc func decreaseFontSize(_ sender: Any?) { changeFontSize(by: -2) }

    private func setFontStyle(_ style: NoteFontStyle) {
        guard note.fontStyle != style else { return }
        note.fontStyle = style
        applyStyle()
        manager?.noteDidChange(note)
    }

    private func changeFontSize(by delta: Double) {
        let newSize = min(max(note.fontSize + delta, Self.minFontSize), Self.maxFontSize)
        guard newSize != note.fontSize else { return }
        note.fontSize = newSize
        applyStyle()
        manager?.noteDidChange(note)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectSystemFont(_:)):
            menuItem.state = note.fontStyle == .system ? .on : .off
        case #selector(selectRoundedFont(_:)):
            menuItem.state = note.fontStyle == .rounded ? .on : .off
        case #selector(selectSerifFont(_:)):
            menuItem.state = note.fontStyle == .serif ? .on : .off
        case #selector(selectMonospacedFont(_:)):
            menuItem.state = note.fontStyle == .monospaced ? .on : .off
        case #selector(increaseFontSize(_:)):
            return note.fontSize < Self.maxFontSize
        case #selector(decreaseFontSize(_:)):
            return note.fontSize > Self.minFontSize
        case #selector(colorItemSelected(_:)):
            menuItem.state = (menuItem.representedObject as? String) == note.color.rawValue ? .on : .off
        case #selector(toggleTranslucent):
            menuItem.state = note.isTranslucent ? .on : .off
        case #selector(togglePin(_:)):
            menuItem.state = note.isPinned ? .on : .off
        case #selector(toggleCollapse(_:)):
            menuItem.title = expandedHeight == nil ? "Collapse Note" : "Expand Note"
        default:
            break
        }
        return true
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        note.text = textView.string
        window?.title = Self.windowTitle(for: note.text)
        applyTextStyling()
        manager?.noteDidChange(note)
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        lastMoveAt = Date()
        syncFrame()
    }

    func windowDidResize(_ notification: Notification) {
        syncFrame()
    }

    private func syncFrame() {
        guard let frame = window?.frame else { return }
        note.frame = frame
        manager?.noteDidChange(note)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard confirmDeletion(for: sender) else { return false }
        // Deny the immediate close and run the fade-out instead;
        // animateOutAndClose ends in close(), which skips this check.
        animateOutAndClose()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        manager?.deleteNote(id: note.id)
    }
}

/// Opaque note background: the note color with a whisper of a vertical
/// gradient (3% lighter at the top), so the note reads as paper rather
/// than a flat rectangle. Resolved at draw time, so it adapts to
/// light/dark appearance automatically.
private final class PaperGradientView: NSView {
    var fillColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let top = fillColor.blended(withFraction: 0.05, of: .white),
              let gradient = NSGradient(starting: top, ending: fillColor) else {
            fillColor.setFill()
            bounds.fill()
            return
        }
        gradient.draw(in: bounds, angle: -90)
    }
}

/// Content view that reports mouse enter/exit over a strip along the top
/// edge of the note — the only place the hover controls live. Tracking
/// areas are geometric, so this fires even while the mouse is over the
/// titlebar controls that float above the content.
private final class HoverTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private let hotZoneHeight: CGFloat = 34

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let zone = NSRect(x: 0, y: bounds.maxY - hotZoneHeight, width: bounds.width, height: hotZoneHeight)
        addTrackingArea(NSTrackingArea(
            rect: zone,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}
