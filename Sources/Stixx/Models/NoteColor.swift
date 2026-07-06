import AppKit

/// The classic Stickies color palette, redrawn with flat, Tahoe-appropriate tones.
/// Each color adapts between light and dark appearance so text stays legible.
enum NoteColor: String, CaseIterable, Codable {
    case yellow, blue, green, pink, purple, gray

    var displayName: String {
        switch self {
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        case .green: return "Green"
        case .pink: return "Pink"
        case .purple: return "Purple"
        case .gray: return "Gray"
        }
    }

    /// Background fill, adapts automatically to the window's active appearance.
    var background: NSColor {
        NSColor(name: rawValue + "Background") { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            switch self {
            case .yellow:
                return dark ? NSColor(calibratedRed: 0.46, green: 0.38, blue: 0.10, alpha: 1)
                            : NSColor(calibratedRed: 1.00, green: 0.93, blue: 0.68, alpha: 1)
            case .blue:
                return dark ? NSColor(calibratedRed: 0.13, green: 0.27, blue: 0.46, alpha: 1)
                            : NSColor(calibratedRed: 0.78, green: 0.89, blue: 1.00, alpha: 1)
            case .green:
                return dark ? NSColor(calibratedRed: 0.14, green: 0.36, blue: 0.22, alpha: 1)
                            : NSColor(calibratedRed: 0.78, green: 0.94, blue: 0.80, alpha: 1)
            case .pink:
                return dark ? NSColor(calibratedRed: 0.46, green: 0.18, blue: 0.30, alpha: 1)
                            : NSColor(calibratedRed: 1.00, green: 0.82, blue: 0.88, alpha: 1)
            case .purple:
                return dark ? NSColor(calibratedRed: 0.32, green: 0.20, blue: 0.46, alpha: 1)
                            : NSColor(calibratedRed: 0.89, green: 0.82, blue: 1.00, alpha: 1)
            case .gray:
                return dark ? NSColor(calibratedRed: 0.26, green: 0.26, blue: 0.27, alpha: 1)
                            : NSColor(calibratedRed: 0.90, green: 0.90, blue: 0.91, alpha: 1)
            }
        }
    }

    /// The note's ink color: a hand-picked tone that reads as a deliberate
    /// pairing with `background` rather than plain system black/white text.
    var textColor: NSColor {
        NSColor(name: rawValue + "Ink") { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            switch self {
            case .yellow:
                return dark ? NSColor(calibratedRed: 0.98, green: 0.93, blue: 0.78, alpha: 1)
                            : NSColor(calibratedRed: 0.42, green: 0.32, blue: 0.05, alpha: 1)
            case .blue:
                return dark ? NSColor(calibratedRed: 0.83, green: 0.92, blue: 1.00, alpha: 1)
                            : NSColor(calibratedRed: 0.07, green: 0.20, blue: 0.42, alpha: 1)
            case .green:
                return dark ? NSColor(calibratedRed: 0.82, green: 0.97, blue: 0.86, alpha: 1)
                            : NSColor(calibratedRed: 0.08, green: 0.28, blue: 0.14, alpha: 1)
            case .pink:
                return dark ? NSColor(calibratedRed: 1.00, green: 0.90, blue: 0.94, alpha: 1)
                            : NSColor(calibratedRed: 0.42, green: 0.08, blue: 0.20, alpha: 1)
            case .purple:
                return dark ? NSColor(calibratedRed: 0.92, green: 0.87, blue: 1.00, alpha: 1)
                            : NSColor(calibratedRed: 0.24, green: 0.10, blue: 0.42, alpha: 1)
            case .gray:
                return dark ? NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
                            : NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.16, alpha: 1)
            }
        }
    }

    /// Next color in the palette, used to cycle default colors for new notes.
    var next: NoteColor {
        let all = NoteColor.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}
