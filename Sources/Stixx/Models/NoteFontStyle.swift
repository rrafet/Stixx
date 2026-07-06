import AppKit

/// A small, curated set of system font designs — no third-party fonts,
/// nothing that reads as a novelty typeface.
enum NoteFontStyle: String, CaseIterable, Codable {
    case system, rounded, serif, monospaced

    var displayName: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .monospaced: return "Monospaced"
        }
    }

    func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        switch self {
        case .system:
            return base
        case .rounded:
            guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return NSFont(descriptor: descriptor, size: size) ?? base
        case .serif:
            guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
            return NSFont(descriptor: descriptor, size: size) ?? base
        case .monospaced:
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}
