import Foundation

/// Plain-text sticky note record. Codable for JSON persistence.
/// Decoding is backward-compatible: notes saved before newer fields existed
/// simply fall back to their defaults instead of failing to load.
struct Note: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var color: NoteColor
    var fontStyle: NoteFontStyle
    var fontSize: Double
    var isPinned: Bool
    var isTranslucent: Bool
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(
        id: UUID = UUID(),
        text: String = "",
        color: NoteColor,
        fontStyle: NoteFontStyle = .system,
        fontSize: Double = 16,
        isPinned: Bool = false,
        isTranslucent: Bool = false,
        x: Double,
        y: Double,
        width: Double = 220,
        height: Double = 220
    ) {
        self.id = id
        self.text = text
        self.color = color
        self.fontStyle = fontStyle
        self.fontSize = fontSize
        self.isPinned = isPinned
        self.isTranslucent = isTranslucent
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x
            y = newValue.origin.y
            width = newValue.width
            height = newValue.height
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, color, fontStyle, fontSize, isPinned, isTranslucent, x, y, width, height
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        color = try c.decode(NoteColor.self, forKey: .color)
        fontStyle = try c.decodeIfPresent(NoteFontStyle.self, forKey: .fontStyle) ?? .system
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 16
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isTranslucent = try c.decodeIfPresent(Bool.self, forKey: .isTranslucent) ?? false
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
    }
}
