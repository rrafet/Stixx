import Foundation

/// Thin, typed wrapper around UserDefaults for the app's few preferences.
/// No other persistent state lives here — notes themselves are in NotesStore.
@MainActor
final class AppPreferences {
    static let shared = AppPreferences()

    private enum Key {
        static let alwaysFloating = "alwaysFloating"
        static let confirmBeforeDelete = "confirmBeforeDelete"
        static let hideDockIcon = "hideDockIcon"
        static let glassTintStrength = "glassTintStrength"
    }

    /// Range of the glass tint slider. Zero is pure frosted glass with no
    /// color at all; past ~0.5 the tint starts to read as paint over the
    /// blur instead of glass, so the scale stops there.
    static let glassTintRange: ClosedRange<Double> = 0...0.5
    static let defaultGlassTint: Double = 0.22

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.alwaysFloating: false,
            Key.confirmBeforeDelete: true,
            Key.hideDockIcon: false,
            Key.glassTintStrength: Self.defaultGlassTint
        ])
    }

    /// Default pin state for newly created notes. Each note's own pin button
    /// (top-right of its window) can then override this individually.
    var alwaysFloating: Bool {
        get { defaults.bool(forKey: Key.alwaysFloating) }
        set { defaults.set(newValue, forKey: Key.alwaysFloating) }
    }

    /// When true, closing a note asks for confirmation before deleting it.
    var confirmBeforeDelete: Bool {
        get { defaults.bool(forKey: Key.confirmBeforeDelete) }
        set { defaults.set(newValue, forKey: Key.confirmBeforeDelete) }
    }

    /// When true, Stixx runs as a menu-bar-only app with no Dock icon.
    var hideDockIcon: Bool {
        get { defaults.bool(forKey: Key.hideDockIcon) }
        set { defaults.set(newValue, forKey: Key.hideDockIcon) }
    }

    /// How strongly a translucent stix keeps its color over the frosted
    /// glass. Applies to every translucent note; adjustable in Settings.
    var glassTintStrength: Double {
        get {
            let raw = defaults.double(forKey: Key.glassTintStrength)
            return min(max(raw, Self.glassTintRange.lowerBound), Self.glassTintRange.upperBound)
        }
        set { defaults.set(newValue, forKey: Key.glassTintStrength) }
    }
}
