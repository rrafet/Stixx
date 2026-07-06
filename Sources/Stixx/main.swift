import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(AppPreferences.shared.hideDockIcon ? .accessory : .regular)
    app.run()
}
