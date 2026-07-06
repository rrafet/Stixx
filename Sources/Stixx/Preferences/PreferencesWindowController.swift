import AppKit
import ServiceManagement

/// A tiny, single-panel settings window. Four checkboxes, nothing else.
@MainActor
final class PreferencesWindowController: NSWindowController {
    private let floatingCheckbox = NSButton(checkboxWithTitle: "New notes float on top by default", target: nil, action: nil)
    private let confirmCheckbox = NSButton(checkboxWithTitle: "Confirm before deleting a note", target: nil, action: nil)
    private let dockIconCheckbox = NSButton(checkboxWithTitle: "Hide Dock icon (menu bar only)", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Open Stixx at login", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stixx Settings"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)

        floatingCheckbox.target = self
        floatingCheckbox.action = #selector(toggleFloating)
        confirmCheckbox.target = self
        confirmCheckbox.action = #selector(toggleConfirm)
        dockIconCheckbox.target = self
        dockIconCheckbox.action = #selector(toggleDockIcon)
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)

        floatingCheckbox.state = AppPreferences.shared.alwaysFloating ? .on : .off
        confirmCheckbox.state = AppPreferences.shared.confirmBeforeDelete ? .on : .off
        dockIconCheckbox.state = AppPreferences.shared.hideDockIcon ? .on : .off
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let stack = NSStackView(views: [
            Self.labeledSetting(floatingCheckbox, caption: "New notes stay above other windows until unpinned."),
            Self.labeledSetting(confirmCheckbox, caption: "Ask before a closed note is deleted."),
            Self.labeledSetting(dockIconCheckbox, caption: "Stixx keeps running quietly in the menu bar."),
            Self.labeledSetting(loginCheckbox, caption: "Your notes appear as soon as you log in.")
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: window.contentLayoutRect)
        content.addSubview(stack)
        window.contentView = content

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20)
        ])
    }

    /// A checkbox with a small secondary-color caption underneath, indented
    /// to align with the checkbox title.
    private static func labeledSetting(_ checkbox: NSButton, caption: String) -> NSStackView {
        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = .systemFont(ofSize: 11)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.lineBreakMode = .byWordWrapping
        let captionRow = NSStackView(views: [captionLabel])
        captionRow.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)

        let stack = NSStackView(views: [checkbox, captionRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }

    @objc private func toggleFloating() {
        AppPreferences.shared.alwaysFloating = floatingCheckbox.state == .on
    }

    @objc private func toggleConfirm() {
        AppPreferences.shared.confirmBeforeDelete = confirmCheckbox.state == .on
    }

    @objc private func toggleDockIcon() {
        let hide = dockIconCheckbox.state == .on
        AppPreferences.shared.hideDockIcon = hide
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
        // Switching to accessory deactivates the app; re-activate on the next
        // runloop turn so the open windows (including this one) stay in front.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func toggleLogin() {
        // The login item registry is the source of truth, so nothing is
        // stored in AppPreferences; a failure just reverts the checkbox.
        do {
            if loginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginCheckbox.state = loginCheckbox.state == .on ? .off : .on
            NSSound.beep()
        }
    }

    func show() {
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
