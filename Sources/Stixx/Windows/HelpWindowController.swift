import AppKit

/// A small read-only Help window: the questions people actually ask, each
/// with a two-line answer. Selectable text, no chrome, nothing to configure.
@MainActor
final class HelpWindowController: NSWindowController {
    private static let entries: [(question: String, answer: String)] = [
        ("How do I create a stix?",
         "Press \u{2318}N, or \u{2325}\u{2318}N from inside any app. Every stix saves itself as you type — there is no Save step for its contents."),
        ("How do I make a checklist?",
         "Type \"[]\" and a space at the start of a line. Click the box to check an item off; the faint tally in the top-right corner tracks your progress."),
        ("How do I make a bullet list?",
         "Type \"- \" or \"* \" at the start of a line. Tab indents an item, \u{21E7}Tab brings it back out. Return on an empty item ends the list."),
        ("What does the tray button do?",
         "The leftmost of the three top-right controls saves the stix on the spot \u{2014} a quick checkmark confirms it \u{2014} and the note stays put. To tuck a stix away instead, right-click it and choose Save for Later; bring it back from File > Saved Stixx or Find (\u{2318}F), and every saved stix returns on the next launch anyway."),
        ("How do I collapse a stix to its title?",
         "Click the chevron at the far right of the top-right controls, double-click the stix's top edge, or press \u{21E7}\u{2318}M. The same gesture expands it again."),
        ("How do I change a stix's color or font?",
         "Right-click the stix: the eight colors sit at the top and the Font submenu holds the four supported styles \u{2014} System, Rounded, Serif, and Monospaced. The Format menu has the same options; \u{2318}1 to \u{2318}8 switch colors from the keyboard."),
        ("How do I make a stix translucent?",
         "Right-click it and choose Translucent, or press \u{2325}\u{2318}T. The Glass tint slider in Settings (\u{2318},) sets how much of the note's color stays over the frosted glass."),
        ("How do I keep a stix above every window?",
         "Click the pin \u{2014} the middle of the three controls in its top-right corner \u{2014} or press \u{21E7}\u{2318}P."),
        ("My stixx are scattered all over the screen.",
         "Window > Tidy Up Stixx (\u{2303}\u{2318}T) slides them into a neat grid from the top-left, keeping each stix's size and its place in the reading order."),
        ("I deleted a stix by accident.",
         "File > Reopen Last Deleted Stix (\u{21E7}\u{2318}T) brings it back \u{2014} available until you quit Stixx."),
        ("Where are my notes stored?",
         "On your Mac only, as a JSON file inside Stixx's private sandbox container. Stixx has no network access; nothing ever leaves your computer."),
        ("Can Stixx live only in the menu bar?",
         "Yes \u{2014} turn on \"Hide Dock icon\" in Settings (\u{2318},). The menu bar note icon keeps everything reachable.")
    ]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stixx Help"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: 240)
        window.center()
        super.init(window: window)

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 18)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(Self.content())

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        window.contentView = scrollView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func content() -> NSAttributedString {
        let questionStyle = NSMutableParagraphStyle()
        questionStyle.paragraphSpacingBefore = 14
        questionStyle.paragraphSpacing = 2
        let answerStyle = NSMutableParagraphStyle()
        answerStyle.lineSpacing = 2
        let result = NSMutableAttributedString()
        for (index, entry) in entries.enumerated() {
            let style = index == 0 ? answerStyle : questionStyle
            result.append(NSAttributedString(string: entry.question + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style
            ]))
            result.append(NSAttributedString(string: entry.answer + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: answerStyle
            ]))
        }
        return result
    }
}
