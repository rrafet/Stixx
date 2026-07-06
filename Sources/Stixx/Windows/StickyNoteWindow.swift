import AppKit

/// A single sticky note's window: no title bar, color fills the entire
/// window. Only the close button remains of the traffic lights (a sticky
/// note is never minimized or zoomed), and even that stays hidden until
/// the mouse is over the note.
final class StickyNoteWindow: NSWindow {
    init(contentRect: NSRect, color: NSColor) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isOpaque = true
        hasShadow = true
        isMovableByWindowBackground = true
        backgroundColor = color
        minSize = NSSize(width: 120, height: 100)
        isRestorable = false
        collectionBehavior = [.fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Double-clicking the (invisible) titlebar normally zooms the window;
    /// for a sticky note that gesture collapses/expands it instead.
    override func zoom(_ sender: Any?) {
        (delegate as? StickyNoteWindowController)?.toggleCollapse(sender)
    }
}
