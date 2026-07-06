import AppKit

/// Plain NSTextView that prepends note actions (color swatches, delete) to
/// the standard right-click editing menu, plus lightweight auto-lists:
/// "- " or "* " at the start of a line becomes a bullet, "[]" becomes a
/// clickable checkbox, Return continues the list, Return on an empty item
/// ends it, and clicking a checkbox toggles it.
final class StickyTextView: NSTextView {
    var extraMenuItemsProvider: (() -> [NSMenuItem])? = nil

    static let bullet = "\u{2022} "
    static let uncheckedBox = "\u{2610} "
    static let checkedBox = "\u{2611} "

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let typed = insertString as? String, typed == " " {
            let selection = selectedRange()
            let text = string as NSString
            if selection.length == 0 {
                let lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
                // "- " or "* " at the start of a line turns into a bullet.
                if selection.location == lineStart + 1,
                   text.character(at: lineStart) == 0x2D || text.character(at: lineStart) == 0x2A { // "-" or "*"
                    super.insertText(typed, replacementRange: replacementRange)
                    convertMarker(at: lineStart, length: 2, to: Self.bullet)
                    return
                }
                // "[] " at the start of a line turns into a checkbox.
                if selection.location == lineStart + 2,
                   text.character(at: lineStart) == 0x5B, text.character(at: lineStart + 1) == 0x5D { // "[]"
                    super.insertText(typed, replacementRange: replacementRange)
                    convertMarker(at: lineStart, length: 3, to: Self.uncheckedBox)
                    return
                }
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    private func convertMarker(at location: Int, length: Int, to marker: String) {
        let range = NSRange(location: location, length: length)
        if shouldChangeText(in: range, replacementString: marker) {
            replaceCharacters(in: range, with: marker)
            didChangeText()
        }
    }

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let markers = [Self.bullet, Self.uncheckedBox, Self.checkedBox]
        if let marker = markers.first(where: { line.hasPrefix($0) }) {
            if line.dropFirst(2).trimmingCharacters(in: .whitespaces).isEmpty {
                // Return on an empty item ends the list instead of adding another.
                let markerRange = NSRange(location: lineRange.location, length: 2)
                if shouldChangeText(in: markerRange, replacementString: "") {
                    replaceCharacters(in: markerRange, with: "")
                    didChangeText()
                }
                return
            }
            super.insertNewline(sender)
            // A checked line continues with a fresh unchecked box.
            let continuation = marker == Self.bullet ? Self.bullet : Self.uncheckedBox
            insertText(continuation, replacementRange: selectedRange())
            return
        }
        super.insertNewline(sender)
    }

    // MARK: Checkbox toggling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = checkboxIndex(at: point) {
            toggleCheckbox(at: index)
            return
        }
        super.mouseDown(with: event)
    }

    private func checkboxIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let index = layoutManager.characterIndex(for: containerPoint, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
        let text = string as NSString
        guard text.length > 0, index < text.length else { return nil }
        let character = text.character(at: index)
        guard character == 0x2610 || character == 0x2611 else { return nil }
        let lineStart = text.lineRange(for: NSRange(location: index, length: 0)).location
        return index == lineStart ? index : nil
    }

    private func toggleCheckbox(at index: Int) {
        let text = string as NSString
        let replacement = text.character(at: index) == 0x2610 ? "\u{2611}" : "\u{2610}"
        let range = NSRange(location: index, length: 1)
        if shouldChangeText(in: range, replacementString: replacement) {
            replaceCharacters(in: range, with: replacement)
            didChangeText()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let standard = super.menu(for: event)
        guard let extras = extraMenuItemsProvider?(), !extras.isEmpty else { return standard }

        let combined = NSMenu()
        for item in extras {
            combined.addItem(item)
        }
        if let standardItems = standard?.items, !standardItems.isEmpty {
            combined.addItem(.separator())
            for item in Array(standardItems) {
                standard?.removeItem(item)
                combined.addItem(item)
            }
        }
        return combined
    }
}
