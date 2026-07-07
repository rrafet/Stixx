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
    private let saveButton: NSButton
    private let collapseButton: NSButton
    /// Faint "2/5" checklist progress, visible while the controls are not.
    private let progressLabel: NSTextField
    /// Shown instead of the text view while collapsed: just the title,
    /// vertically centered in the strip — the Stickies look.
    private let collapsedTitleLabel: NSTextField
    /// Set while the window is closing because the stix was stashed, so
    /// windowWillClose doesn't treat the close as a deletion.
    private var isClosingForStash = false
    private var isMouseInside = false
    /// While collapsed, holds the height to restore on expand; nil otherwise.
    /// Backed by the note so a collapsed stix stays collapsed across launches.
    private var expandedHeight: CGFloat? {
        get { note.expandedHeight.map { CGFloat($0) } }
        set { note.expandedHeight = newValue.map(Double.init) }
    }
    private var lastMoveAt: Date?
    /// Bumped on every save-button click, so an earlier click's pending
    /// icon revert can tell it has been superseded.
    private var saveFlashGeneration = 0
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
        let saveButton = NSButton()
        let collapseButton = NSButton()
        let progressLabel = NSTextField(labelWithString: "")
        self.progressLabel = progressLabel
        let collapsedTitleLabel = NSTextField(labelWithString: "")
        self.collapsedTitleLabel = collapsedTitleLabel
        self.effectView = effectView
        self.tintView = tintView
        self.paperView = paperView
        self.scrollView = scrollView
        self.textView = textView
        self.pinButton = pinButton
        self.saveButton = saveButton
        self.collapseButton = collapseButton

        let window = StickyNoteWindow(contentRect: note.frame, color: note.color.background)

        super.init(window: window)

        window.delegate = self
        window.title = note.displayTitle

        containerView.wantsLayer = true

        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        // The Fonts panel offers families, colors, and sizes a stix can't
        // keep; its four supported styles live in the context + Format menus.
        textView.usesFontPanel = false
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
        // Collapsed-state title: replaces the whole text view while the stix
        // is a strip, so no stray second line or caret can ever peek through.
        collapsedTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        collapsedTitleLabel.lineBreakMode = .byTruncatingTail
        collapsedTitleLabel.maximumNumberOfLines = 1
        collapsedTitleLabel.isHidden = true
        containerView.addSubview(collapsedTitleLabel)
        NSLayoutConstraint.activate([
            collapsedTitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
            // Stops short of the corner accessory, tally slot included, so a
            // long title can't run under the checklist count.
            collapsedTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -114),
            collapsedTitleLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        window.contentView = containerView

        // Save + pin + collapse buttons in the empty top-right corner of the
        // (hidden) title bar, using the same native API window tab bars /
        // toolbars use to add accessories there — no manual overlay layout
        // needed. All three live in one accessory view, side by side. The
        // checklist progress label has its own slot on their left: the pin
        // and chevron stay faintly visible at rest, so the tally can never
        // share their space without landing on one of them.
        progressLabel.frame = NSRect(x: 0, y: 4, width: 50, height: 16)
        progressLabel.alignment = .right
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        progressLabel.isHidden = true
        saveButton.frame = NSRect(x: 28, y: 0, width: 26, height: 24)
        saveButton.isBordered = false
        saveButton.imagePosition = .imageOnly
        saveButton.setButtonType(.momentaryChange)
        saveButton.target = self
        saveButton.action = #selector(saveStix(_:))
        saveButton.toolTip = "Save this stix"
        pinButton.frame = NSRect(x: 54, y: 0, width: 26, height: 24)
        pinButton.isBordered = false
        pinButton.imagePosition = .imageOnly
        pinButton.setButtonType(.momentaryChange)
        pinButton.target = self
        pinButton.action = #selector(togglePin(_:))
        pinButton.toolTip = "Keep this stix on top"
        // The chevron sits at the far right so it stays put when the stix
        // collapses to a strip — the expand control never moves under the hand.
        collapseButton.frame = NSRect(x: 80, y: 0, width: 26, height: 24)
        collapseButton.isBordered = false
        collapseButton.imagePosition = .imageOnly
        collapseButton.setButtonType(.momentaryChange)
        collapseButton.target = self
        collapseButton.action = #selector(toggleCollapse(_:))
        collapseButton.toolTip = "Collapse this stix to its title"
        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 106, height: 24))
        accessoryView.addSubview(progressLabel)
        accessoryView.addSubview(collapseButton)
        accessoryView.addSubview(saveButton)
        accessoryView.addSubview(pinButton)
        let cornerAccessory = NSTitlebarAccessoryViewController()
        cornerAccessory.view = accessoryView
        cornerAccessory.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(cornerAccessory)

        // A stix saved while collapsed comes back collapsed: its frame is
        // already strip-sized, but the window's limits must match.
        if note.expandedHeight != nil {
            var frame = note.frame
            frame.origin.y = frame.maxY - Self.collapsedHeight
            frame.size.height = Self.collapsedHeight
            window.setFrame(frame, display: false)
        }
        applyCollapseConstraints()

        // Controls stay invisible until the mouse is over the note; only the
        // close button survives of the traffic lights.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.alphaValue = 0
        pinButton.alphaValue = note.isPinned ? Self.restingPinAlpha : 0
        saveButton.alphaValue = 0
        collapseButton.alphaValue = 0
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
        tintView.fillColor = background.withAlphaComponent(CGFloat(AppPreferences.shared.glassTintStrength))
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
        applyTextStyling()

        // Collapsed: the strip shows a single centered title and nothing
        // else; the text view (and any caret or second line) is hidden.
        let collapsed = expandedHeight != nil
        scrollView.isHidden = collapsed
        collapsedTitleLabel.isHidden = !collapsed
        collapsedTitleLabel.stringValue = note.displayTitle
        collapsedTitleLabel.font = note.fontStyle.font(size: min(CGFloat(note.fontSize), 15), weight: .semibold)
        collapsedTitleLabel.textColor = ink

        let symbolName = note.isPinned ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Keep this stix on top")?
            .withSymbolConfiguration(config)
        pinButton.contentTintColor = ink.withAlphaComponent(note.isPinned ? 0.95 : 0.5)
        saveButton.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Save this stix")?
            .withSymbolConfiguration(config)
        saveButton.contentTintColor = ink.withAlphaComponent(0.5)
        collapseButton.image = NSImage(
            systemSymbolName: collapsed ? "chevron.down" : "chevron.up",
            accessibilityDescription: collapsed ? "Expand this stix" : "Collapse this stix to its title"
        )?.withSymbolConfiguration(config)
        collapseButton.toolTip = collapsed ? "Expand this stix" : "Collapse this stix to its title"
        collapseButton.contentTintColor = ink.withAlphaComponent(collapsed ? 0.95 : 0.5)
        progressLabel.textColor = ink.withAlphaComponent(0.5)
        updateChecklistProgress()
        updateControlVisibility(animated: false)
    }

    /// Refreshes the faint "2/5" checklist tally shown while the controls
    /// are faded out — on a collapsed stix it is the whole status display.
    private func updateChecklistProgress() {
        var total = 0
        var done = 0
        (note.text as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: (note.text as NSString).length),
            options: [.byLines]
        ) { line, _, _, _ in
            guard let line else { return }
            let content = line.drop(while: { $0 == "\t" })
            if content.hasPrefix("\u{2610}") { total += 1 }
            if content.hasPrefix("\u{2611}") { total += 1; done += 1 }
        }
        progressLabel.stringValue = "\(done)/\(total)"
        progressLabel.isHidden = total == 0
    }

    /// The note's first line is its title: rendered semibold, like Notes,
    /// so a wall of stickies can be scanned at a glance. List lines get a
    /// hanging indent and a softened marker so wrapped text aligns and the
    /// glyphs recede behind the words; leading tabs (Tab / ⇧Tab) nest items
    /// visually. Checked-off checklist lines read as done: dimmed and struck
    /// through past the box. Reapplied after every edit since any keystroke
    /// can change all of it.
    private func applyTextStyling() {
        guard let storage = textView.textStorage else { return }
        let text = textView.string as NSString
        guard text.length > 0 else { return }
        let ink = note.color.textColor
        let bodyFont = note.fontStyle.font(size: CGFloat(note.fontSize))
        let titleFont = note.fontStyle.font(size: CGFloat(note.fontSize), weight: .semibold)
        let baseParagraph = NSMutableParagraphStyle()
        baseParagraph.lineSpacing = 3
        let full = NSRange(location: 0, length: text.length)
        let newlineIndex = text.range(of: "\n").location
        let titleLength = newlineIndex == NSNotFound ? text.length : newlineIndex
        storage.beginEditing()
        storage.addAttribute(.font, value: bodyFont, range: full)
        if titleLength > 0 {
            storage.addAttribute(.font, value: titleFont, range: NSRange(location: 0, length: titleLength))
        }
        storage.addAttribute(.foregroundColor, value: ink, range: full)
        storage.addAttribute(.paragraphStyle, value: baseParagraph, range: full)
        storage.removeAttribute(.strikethroughStyle, range: full)
        text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            self.styleLine(lineRange, text: text, storage: storage, ink: ink, bodyFont: bodyFont)
        }
        storage.endEditing()
    }

    private func styleLine(_ lineRange: NSRange, text: NSString, storage: NSTextStorage, ink: NSColor, bodyFont: NSFont) {
        guard lineRange.length >= 1 else { return }
        // Leading tabs carry the nesting level; the marker sits after them.
        var markerStart = lineRange.location
        while markerStart < NSMaxRange(lineRange), text.character(at: markerStart) == 0x09 { markerStart += 1 }
        guard markerStart < NSMaxRange(lineRange) else { return }
        let tabCount = markerStart - lineRange.location
        let first = Int(text.character(at: markerStart))

        let isBullet = first == 0x2022    // "•"
        let isUnchecked = first == 0x2610 // "☐"
        let isChecked = first == 0x2611   // "☑"
        guard isBullet || isUnchecked || isChecked else { return }

        let markerLength = min(2, NSMaxRange(lineRange) - markerStart)
        let marker = text.substring(with: NSRange(location: markerStart, length: markerLength))
        let markerWidth = (marker as NSString).size(withAttributes: [.font: bodyFont]).width
        let listParagraph = NSMutableParagraphStyle()
        listParagraph.lineSpacing = 3
        listParagraph.paragraphSpacingBefore = 2
        // Each tab advances by one marker width, and wrapped text hangs at
        // the item's text edge — nested items step in evenly.
        listParagraph.tabStops = []
        listParagraph.defaultTabInterval = markerWidth
        listParagraph.headIndent = CGFloat(tabCount + 1) * markerWidth
        storage.addAttribute(.paragraphStyle, value: listParagraph, range: lineRange)

        if isChecked {
            storage.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.45), range: lineRange)
            if NSMaxRange(lineRange) - markerStart > 2 {
                let checkedText = NSRange(location: markerStart + 2, length: NSMaxRange(lineRange) - markerStart - 2)
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: checkedText)
            }
        }

        let markerRange = NSRange(location: markerStart, length: 1)
        if isBullet {
            storage.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.55), range: markerRange)
        } else {
            // Checkboxes drawn a point larger than the text: an easier click
            // target that also reads more like a control than a character.
            let boxFont = note.fontStyle.font(size: CGFloat(note.fontSize) + 1)
            storage.addAttribute(.font, value: boxFont, range: markerRange)
            storage.addAttribute(.foregroundColor, value: ink.withAlphaComponent(isChecked ? 0.5 : 0.6), range: markerRange)
        }
    }

    /// Fades the close, save, pin, and collapse buttons in when the mouse
    /// is over the note and out when it leaves. A pinned note keeps its pin
    /// faintly visible so the pinned state never becomes invisible, and a
    /// collapsed one keeps its chevron for the same reason.
    private func updateControlVisibility(animated: Bool) {
        let closeButton = window?.standardWindowButton(.closeButton)
        let collapsed = expandedHeight != nil
        let controlAlpha: CGFloat = isMouseInside ? 1 : 0
        // No close button on a collapsed strip: it would sit on the title,
        // and a collapsed stix shouldn't be one stray click from deletion.
        // ⌘W (with its confirmation) still works.
        let closeAlpha: CGFloat = collapsed ? 0 : controlAlpha
        let pinAlpha: CGFloat = isMouseInside ? 1 : (note.isPinned ? Self.restingPinAlpha : 0)
        let collapseAlpha: CGFloat = isMouseInside ? 1 : (collapsed ? Self.restingPinAlpha : 0)
        // The tally's slot ends under the save button, so it still bows out
        // while the full control row is showing.
        let progressAlpha: CGFloat = isMouseInside ? 0 : 1
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                closeButton?.animator().alphaValue = closeAlpha
                saveButton.animator().alphaValue = controlAlpha
                collapseButton.animator().alphaValue = collapseAlpha
                pinButton.animator().alphaValue = pinAlpha
                progressLabel.animator().alphaValue = progressAlpha
            }
        } else {
            closeButton?.alphaValue = closeAlpha
            saveButton.alphaValue = controlAlpha
            collapseButton.alphaValue = collapseAlpha
            pinButton.alphaValue = pinAlpha
            progressLabel.alphaValue = progressAlpha
        }
        closeButton?.isEnabled = !collapsed
    }

    /// Collapses the note to a title-bar-sized strip (or expands it back),
    /// keeping the top edge in place — the classic Stickies gesture, reached
    /// via the chevron button, double-clicking the top edge, or ⇧⌘M.
    @objc func toggleCollapse(_ sender: Any?) {
        guard let window else { return }
        var frame = window.frame
        if let restoredHeight = expandedHeight {
            frame.origin.y = frame.maxY - restoredHeight
            frame.size.height = restoredHeight
            expandedHeight = nil
            window.makeFirstResponder(textView)
        } else {
            expandedHeight = frame.height
            frame.origin.y = frame.maxY - Self.collapsedHeight
            frame.size.height = Self.collapsedHeight
            // The text view is about to be hidden; typing must not keep
            // editing it invisibly.
            window.makeFirstResponder(nil)
        }
        // Limits first: the collapsed strip is far below the normal minimum
        // height, and the target frame would be clamped otherwise.
        applyCollapseConstraints()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
        // The chevron flips direction and stays faintly visible while
        // collapsed, so the way back is always discoverable.
        applyStyle()
        manager?.noteDidChange(note)
    }

    /// While collapsed the window is locked to the strip height (no vertical
    /// resizing); expanded, the normal limits apply.
    private func applyCollapseConstraints() {
        guard let window else { return }
        if expandedHeight != nil {
            window.minSize = NSSize(width: StickyNoteWindow.standardMinSize.width, height: Self.collapsedHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: Self.collapsedHeight)
        } else {
            window.minSize = StickyNoteWindow.standardMinSize
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    // MARK: Pin + save buttons

    @objc func togglePin(_ sender: Any?) {
        note.isPinned.toggle()
        applyWindowLevel()
        applyStyle()
        manager?.noteDidChange(note)
    }

    /// Writes the stix to disk right away and leaves it on screen. Every
    /// edit saves itself anyway, so the real job here is the reassurance:
    /// the tray melts into a checkmark for a moment, then eases back.
    @objc func saveStix(_ sender: Any?) {
        manager?.noteDidChange(note)
        manager?.flushPendingSave()
        // A fresh click restarts the moment; the stale revert below then
        // recognizes it lost its turn and leaves the icon alone.
        saveFlashGeneration += 1
        let generation = saveFlashGeneration
        setSaveButtonSymbol("checkmark", description: "Saved")
        saveButton.contentTintColor = note.color.textColor.withAlphaComponent(0.95)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.saveFlashGeneration == generation else { return }
            self.setSaveButtonSymbol("tray.and.arrow.down", description: "Save this stix")
            self.saveButton.contentTintColor = self.note.color.textColor.withAlphaComponent(0.5)
        }
    }

    /// Swaps the save button's symbol under a short crossfade, so the
    /// checkmark never snaps in or out.
    private func setSaveButtonSymbol(_ name: String, description: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(config) else { return }
        saveButton.wantsLayer = true
        let transition = CATransition()
        transition.duration = 0.25
        transition.type = .fade
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        saveButton.layer?.add(transition, forKey: "symbolSwap")
        saveButton.image = image
    }

    /// Puts the stix away for the rest of the session: the window closes but
    /// the note stays on disk, reopenable from File > Saved Stixx or the
    /// Find panel — and it returns on its own at the next launch.
    @objc func stashStix(_ sender: Any?) {
        manager?.stashNote(id: note.id)
    }

    /// Fades the window out and closes it without deleting the note.
    func closeForStash() {
        guard let window else { return }
        isClosingForStash = true
        window.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
        })
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

        // The font styles a stix actually supports, in place of the stock
        // Fonts-panel submenu the text view would offer (see StickyTextView).
        let fontItem = NSMenuItem(title: "Font", action: nil, keyEquivalent: "")
        let fontMenu = NSMenu(title: "Font")
        let styleActions: [(String, Selector)] = [
            ("System", #selector(selectSystemFont(_:))),
            ("Rounded", #selector(selectRoundedFont(_:))),
            ("Serif", #selector(selectSerifFont(_:))),
            ("Monospaced", #selector(selectMonospacedFont(_:)))
        ]
        for (title, action) in styleActions {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            fontMenu.addItem(item)
        }
        fontMenu.addItem(.separator())
        let biggerItem = NSMenuItem(title: "Bigger", action: #selector(increaseFontSize(_:)), keyEquivalent: "")
        biggerItem.target = self
        fontMenu.addItem(biggerItem)
        let smallerItem = NSMenuItem(title: "Smaller", action: #selector(decreaseFontSize(_:)), keyEquivalent: "")
        smallerItem.target = self
        fontMenu.addItem(smallerItem)
        fontItem.submenu = fontMenu
        items.append(fontItem)

        let translucentItem = NSMenuItem(title: "Translucent", action: #selector(toggleTranslucent), keyEquivalent: "")
        translucentItem.target = self
        translucentItem.state = note.isTranslucent ? .on : .off
        items.append(translucentItem)

        let stashItem = NSMenuItem(title: "Save for Later", action: #selector(stashStix(_:)), keyEquivalent: "")
        stashItem.target = self
        items.append(stashItem)

        let deleteItem = NSMenuItem(title: "Delete Stix", action: #selector(deleteRequested), keyEquivalent: "")
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

    /// Re-applies the whole appearance from current state; lets the Settings
    /// window push a new glass tint to notes that are already open.
    func refreshStyle() {
        applyStyle()
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
        alert.messageText = "Delete this stix?"
        alert.informativeText = "You can bring it back with File > Reopen Last Deleted Stix (\u{21E7}\u{2318}T) until you quit Stixx."
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
            menuItem.title = expandedHeight == nil ? "Collapse Stix" : "Expand Stix"
        default:
            break
        }
        return true
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        note.text = textView.string
        window?.title = note.displayTitle
        applyTextStyling()
        updateChecklistProgress()
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
        guard !isClosingForStash else { return }
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
