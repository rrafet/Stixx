import AppKit

/// Plain NSTextView that prepends note actions (color swatches, delete) to
/// the standard right-click editing menu, plus lightweight auto-lists:
/// "- " or "* " at the start of a line becomes a bullet, "[]" becomes a
/// clickable checkbox, Return continues the list, Return on an empty item
/// ends it, clicking a checkbox toggles it, and Tab / ⇧Tab indent and
/// outdent list lines (leading tab characters carry the nesting level).
final class StickyTextView: NSTextView {
    var extraMenuItemsProvider: (() -> [NSMenuItem])? = nil

    static let bullet = "\u{2022} "
    static let uncheckedBox = "\u{2610} "
    static let checkedBox = "\u{2611} "
    private static let listMarkers = [bullet, uncheckedBox, checkedBox]

    /// If the line containing `location` is a list line — leading tabs, then
    /// a marker — returns its start, nesting depth, and marker.
    private func listLineInfo(at location: Int) -> (lineStart: Int, tabCount: Int, marker: String)? {
        let text = string as NSString
        guard text.length > 0 else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
        var index = lineRange.location
        while index < NSMaxRange(lineRange), text.character(at: index) == 0x09 { index += 1 }
        let rest = text.substring(with: NSRange(location: index, length: NSMaxRange(lineRange) - index))
        guard let marker = Self.listMarkers.first(where: { rest.hasPrefix($0) }) else { return nil }
        return (lineRange.location, index - lineRange.location, marker)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let typed = insertString as? String, typed == " " {
            let selection = selectedRange()
            let text = string as NSString
            if selection.length == 0 {
                let lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
                // The marker may sit after leading tabs on an indented line.
                var contentStart = lineStart
                while contentStart < selection.location, text.character(at: contentStart) == 0x09 { contentStart += 1 }
                // "- " or "* " at the start of a line turns into a bullet.
                if selection.location == contentStart + 1,
                   text.character(at: contentStart) == 0x2D || text.character(at: contentStart) == 0x2A { // "-" or "*"
                    super.insertText(typed, replacementRange: replacementRange)
                    convertMarker(at: contentStart, length: 2, to: Self.bullet)
                    return
                }
                // "[] " at the start of a line turns into a checkbox.
                if selection.location == contentStart + 2,
                   text.character(at: contentStart) == 0x5B, text.character(at: contentStart + 1) == 0x5D { // "[]"
                    super.insertText(typed, replacementRange: replacementRange)
                    convertMarker(at: contentStart, length: 3, to: Self.uncheckedBox)
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
        guard selection.length == 0, let info = listLineInfo(at: selection.location) else {
            super.insertNewline(sender)
            return
        }
        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let prefixLength = info.tabCount + info.marker.count
        if line.dropFirst(prefixLength).trimmingCharacters(in: .whitespaces).isEmpty {
            // Return on an empty item ends the list instead of adding another.
            let markerRange = NSRange(location: info.lineStart, length: prefixLength)
            if shouldChangeText(in: markerRange, replacementString: "") {
                replaceCharacters(in: markerRange, with: "")
                didChangeText()
            }
            return
        }
        super.insertNewline(sender)
        // The next item keeps the nesting level; a checked line continues
        // with a fresh unchecked box.
        let continuationMarker = info.marker == Self.bullet ? Self.bullet : Self.uncheckedBox
        let continuation = String(repeating: "\t", count: info.tabCount) + continuationMarker
        insertText(continuation, replacementRange: selectedRange())
    }

    // MARK: Indenting (Tab / ⇧Tab)

    override func insertTab(_ sender: Any?) {
        if indentListLines(by: 1) { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if indentListLines(by: -1) { return }
        super.insertBacktab(sender)
    }

    /// Indents (or outdents) every list line touched by the selection by one
    /// tab. Returns false when the selection contains no list line, so Tab
    /// keeps its usual meaning in plain text.
    private func indentListLines(by delta: Int) -> Bool {
        let text = string as NSString
        guard text.length > 0 else { return false }
        let coveredLines = text.lineRange(for: selectedRange())
        var lineStarts: [Int] = []
        var index = coveredLines.location
        repeat {
            let line = text.lineRange(for: NSRange(location: index, length: 0))
            lineStarts.append(line.location)
            index = NSMaxRange(line)
        } while index < NSMaxRange(coveredLines)
        // Bottom-up, so each edit leaves the earlier line offsets intact.
        var foundListLine = false
        for start in lineStarts.reversed() {
            guard let info = listLineInfo(at: start) else { continue }
            foundListLine = true
            if delta > 0 {
                let insertion = NSRange(location: info.lineStart, length: 0)
                if shouldChangeText(in: insertion, replacementString: "\t") {
                    replaceCharacters(in: insertion, with: "\t")
                    didChangeText()
                }
            } else if info.tabCount > 0 {
                let removal = NSRange(location: info.lineStart, length: 1)
                if shouldChangeText(in: removal, replacementString: "") {
                    replaceCharacters(in: removal, with: "")
                    didChangeText()
                }
            }
        }
        return foundListLine
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
        // Only the marker position counts — a ☐ typed mid-sentence is text.
        var markerStart = text.lineRange(for: NSRange(location: index, length: 0)).location
        while markerStart < index, text.character(at: markerStart) == 0x09 { markerStart += 1 }
        return index == markerStart ? index : nil
    }

    private func toggleCheckbox(at index: Int) {
        let text = string as NSString
        let replacement = text.character(at: index) == 0x2610 ? "\u{2611}" : "\u{2610}"
        let range = NSRange(location: index, length: 1)
        if shouldChangeText(in: range, replacementString: replacement) {
            // Crossfade the restyle (dim + strikethrough appearing or
            // vanishing) instead of snapping, so checking off feels done
            // rather than merely edited.
            wantsLayer = true
            let transition = CATransition()
            transition.duration = 0.16
            transition.type = .fade
            transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.add(transition, forKey: "checkboxToggle")
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
                // The stock Font submenu leads to the Fonts panel, whose
                // families and colors a plain-text stix can't hold anyway;
                // the note's own Font menu (four styles) replaces it above.
                if Self.opensFontPanel(item) { continue }
                standard?.removeItem(item)
                combined.addItem(item)
            }
        }
        return combined
    }

    private static func opensFontPanel(_ item: NSMenuItem) -> Bool {
        guard let submenu = item.submenu else { return false }
        let fontPanelActions: [Selector] = [
            #selector(NSFontManager.orderFrontFontPanel(_:)),
            #selector(NSFontManager.addFontTrait(_:))
        ]
        return submenu.items.contains { subitem in
            guard let action = subitem.action else { return false }
            return fontPanelActions.contains(action)
        }
    }
}
