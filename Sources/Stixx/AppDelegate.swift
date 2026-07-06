import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let noteManager = NoteManager()
    private var preferencesController: PreferencesWindowController?
    private var searchPanelController: SearchPanelController?
    private var statusItem: NSStatusItem?
    private var newNoteHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()
        noteManager.loadAndRestoreWindows()
        // ⌥⌘N from anywhere: jot a note without switching apps first.
        newNoteHotKey = GlobalHotKey { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.noteManager.createNewNote()
        }
    }

    /// Stixx behaves like a regular document-based app: it keeps running,
    /// with its Dock icon and menu bar, even when every note is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        noteManager.flushPendingSave()
    }

    /// Clicking the Dock icon with nothing on screen brings the notes back,
    /// or starts a fresh one if every note has been deleted.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if noteManager.hasNotes {
                noteManager.bringAllNotesToFront()
            } else {
                noteManager.createNewNote()
            }
        }
        return true
    }

    @objc func newNote(_ sender: Any?) {
        noteManager.createNewNote()
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController()
        }
        preferencesController?.show()
    }

    @objc func showAllNotes(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        noteManager.bringAllNotesToFront()
    }

    @objc func showSearch(_ sender: Any?) {
        if searchPanelController == nil {
            searchPanelController = SearchPanelController(manager: noteManager)
        }
        searchPanelController?.show()
    }

    @objc func restoreLastDeletedNote(_ sender: Any?) {
        noteManager.restoreLastDeletedNote()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(restoreLastDeletedNote(_:)) {
            return noteManager.hasRecentlyDeleted
        }
        return true
    }

    /// Menu bar presence, so Stixx is reachable even with no note in sight —
    /// and the app's whole face when the Dock icon is hidden.
    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Stixx")

        let menu = NSMenu()
        let newItem = NSMenuItem(title: "New Note", action: #selector(newNote(_:)), keyEquivalent: "n")
        newItem.target = self
        menu.addItem(newItem)
        let showItem = NSMenuItem(title: "Show All Notes", action: #selector(showAllNotes(_:)), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        let findItem = NSMenuItem(title: "Find Notes…", action: #selector(showSearch(_:)), keyEquivalent: "")
        findItem.target = self
        menu.addItem(findItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showPreferences(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Stixx", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        statusItem = item
    }

    private func buildMainMenu() {
        let appName = "Stixx"
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let prefsItem = NSMenuItem(title: "Settings…", action: #selector(showPreferences(_:)), keyEquivalent: ",")
        prefsItem.target = self
        appMenu.addItem(prefsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let newItem = NSMenuItem(title: "New Note", action: #selector(newNote(_:)), keyEquivalent: "n")
        newItem.target = self
        fileMenu.addItem(newItem)
        let findItem = NSMenuItem(title: "Find Notes…", action: #selector(showSearch(_:)), keyEquivalent: "f")
        findItem.target = self
        fileMenu.addItem(findItem)
        fileMenu.addItem(.separator())
        // ⌘W deletes the note (after the usual confirmation) — the honest
        // name for what closing a sticky note actually does.
        fileMenu.addItem(withTitle: "Delete Note", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let reopenItem = NSMenuItem(title: "Reopen Last Deleted Note", action: #selector(restoreLastDeletedNote(_:)), keyEquivalent: "T")
        reopenItem.target = self
        fileMenu.addItem(reopenItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let formatMenuItem = NSMenuItem()
        let formatMenu = NSMenu(title: "Format")
        let fontMenuItem = NSMenuItem(title: "Font", action: nil, keyEquivalent: "")
        let fontSubmenu = NSMenu(title: "Font")
        fontSubmenu.addItem(NSMenuItem(title: "System", action: #selector(StickyNoteWindowController.selectSystemFont(_:)), keyEquivalent: ""))
        fontSubmenu.addItem(NSMenuItem(title: "Rounded", action: #selector(StickyNoteWindowController.selectRoundedFont(_:)), keyEquivalent: ""))
        fontSubmenu.addItem(NSMenuItem(title: "Serif", action: #selector(StickyNoteWindowController.selectSerifFont(_:)), keyEquivalent: ""))
        fontSubmenu.addItem(NSMenuItem(title: "Monospaced", action: #selector(StickyNoteWindowController.selectMonospacedFont(_:)), keyEquivalent: ""))
        fontMenuItem.submenu = fontSubmenu
        formatMenu.addItem(fontMenuItem)
        let colorMenuItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let colorSubmenu = NSMenu(title: "Color")
        for (index, color) in NoteColor.allCases.enumerated() {
            let item = NSMenuItem(
                title: color.displayName,
                action: #selector(StickyNoteWindowController.colorItemSelected(_:)),
                keyEquivalent: "\(index + 1)"
            )
            item.image = StickyNoteWindowController.swatchImage(for: color.background)
            item.representedObject = color.rawValue
            colorSubmenu.addItem(item)
        }
        colorMenuItem.submenu = colorSubmenu
        formatMenu.addItem(colorMenuItem)
        formatMenu.addItem(.separator())
        formatMenu.addItem(NSMenuItem(title: "Bigger", action: #selector(StickyNoteWindowController.increaseFontSize(_:)), keyEquivalent: "+"))
        formatMenu.addItem(NSMenuItem(title: "Smaller", action: #selector(StickyNoteWindowController.decreaseFontSize(_:)), keyEquivalent: "-"))
        formatMenu.addItem(.separator())
        let translucentItem = NSMenuItem(title: "Translucent", action: #selector(StickyNoteWindowController.toggleTranslucent), keyEquivalent: "t")
        translucentItem.keyEquivalentModifierMask = [.command, .option]
        formatMenu.addItem(translucentItem)
        let pinItem = NSMenuItem(title: "Keep on Top", action: #selector(StickyNoteWindowController.togglePin(_:)), keyEquivalent: "p")
        pinItem.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(pinItem)
        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let collapseItem = NSMenuItem(title: "Collapse Note", action: #selector(StickyNoteWindowController.toggleCollapse(_:)), keyEquivalent: "m")
        collapseItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(collapseItem)
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
