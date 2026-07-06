import AppKit

/// A small floating "Find Notes" panel: type to filter every note by its
/// text, click a result (or press Return) to bring that note to front.
/// With an empty query it doubles as an overview list of all notes.
@MainActor
final class SearchPanelController: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private struct Result {
        let id: UUID
        let title: String
        let snippet: String
        let color: NoteColor
    }

    private weak var manager: NoteManager?
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var results: [Result] = []

    init(manager: NoteManager) {
        self.manager = manager
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 380),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Find Stixx"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()
        super.init(window: panel)

        searchField.placeholderString = "Search stixx"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 42
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(searchField)
        content.addSubview(scrollView)
        content.addSubview(emptyLabel)
        panel.contentView = content

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    // MARK: Results

    private func refresh() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        let notes = (manager?.allNotes() ?? [])
            .filter { query.isEmpty || $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        results = notes
            .map { note in
                // A stashed stix still shows up here — selecting it reopens
                // its window — but its row says so.
                let snippet = Self.snippet(for: note, matching: query)
                return Result(
                    id: note.id,
                    title: note.displayTitle,
                    snippet: note.isStashed ? (snippet.isEmpty ? "Saved" : "Saved \u{00B7} \(snippet)") : snippet,
                    color: note.color
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        emptyLabel.stringValue = query.isEmpty ? "No stixx yet" : "No matching stixx"
        emptyLabel.isHidden = !results.isEmpty
        tableView.reloadData()
    }

    /// The first line containing the query; without a query, the second line
    /// of the note, so the row shows more than the title alone.
    private static func snippet(for note: Note, matching query: String) -> String {
        let lines = note.text.split(separator: "\n", omittingEmptySubsequences: true)
        if !query.isEmpty,
           let match = lines.dropFirst().first(where: { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
            return String(match).trimmingCharacters(in: .whitespaces)
        }
        return lines.dropFirst().first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    private func openResult(at row: Int) {
        guard results.indices.contains(row) else { return }
        NSApp.activate(ignoringOtherApps: true)
        manager?.focusNote(id: results[row].id)
        window?.close()
    }

    @objc private func rowClicked() {
        openResult(at: tableView.clickedRow)
    }

    // MARK: NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            openResult(at: tableView.selectedRow >= 0 ? tableView.selectedRow : 0)
            return true
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
            let delta = commandSelector == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            let next = min(max(tableView.selectedRow + delta, 0), results.count - 1)
            if next >= 0 {
                tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
                tableView.scrollRowToVisible(next)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            window?.close()
            return true
        default:
            return false
        }
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let result = results[row]
        let identifier = NSUserInterfaceItemIdentifier("resultCell")

        let cell: NSTableCellView
        let titleField: NSTextField
        let snippetField: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView,
           let reusedTitle = reused.textField,
           let reusedSnippet = reused.subviews.compactMap({ $0 as? NSTextField }).last {
            cell = reused
            titleField = reusedTitle
            snippetField = reusedSnippet
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let swatch = NSImageView()
            swatch.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(swatch)
            cell.imageView = swatch

            titleField = NSTextField(labelWithString: "")
            titleField.font = .systemFont(ofSize: 13, weight: .medium)
            titleField.lineBreakMode = .byTruncatingTail
            titleField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(titleField)
            cell.textField = titleField

            snippetField = NSTextField(labelWithString: "")
            snippetField.font = .systemFont(ofSize: 11)
            snippetField.textColor = .secondaryLabelColor
            snippetField.lineBreakMode = .byTruncatingTail
            snippetField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(snippetField)

            NSLayoutConstraint.activate([
                swatch.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                swatch.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                swatch.widthAnchor.constraint(equalToConstant: 14),
                swatch.heightAnchor.constraint(equalToConstant: 14),
                titleField.leadingAnchor.constraint(equalTo: swatch.trailingAnchor, constant: 8),
                titleField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                titleField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 5),
                snippetField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
                snippetField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
                snippetField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1)
            ])
        }

        cell.imageView?.image = StickyNoteWindowController.swatchImage(for: result.color.background)
        titleField.stringValue = result.title
        snippetField.stringValue = result.snippet
        return cell
    }
}
