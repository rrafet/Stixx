import Testing
import Foundation
import AppKit
@testable import Stixx

struct NoteModelTests {
    @Test func codableRoundTrip() throws {
        let note = Note(
            text: "Hello\nWorld",
            color: .blue,
            fontStyle: .serif,
            fontSize: 18,
            isPinned: true,
            isTranslucent: true,
            x: 10, y: 20, width: 300, height: 200
        )
        let data = try JSONEncoder().encode([note])
        let decoded = try JSONDecoder().decode([Note].self, from: data)
        #expect(decoded == [note])
    }

    /// Notes saved before newer fields existed must load with defaults
    /// instead of failing — this guards the upgrade path.
    @Test func decodingLegacyNoteFillsDefaults() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","text":"legacy","color":"yellow","x":1,"y":2,"width":100,"height":100}]
        """
        let notes = try JSONDecoder().decode([Note].self, from: Data(json.utf8))
        #expect(notes.count == 1)
        #expect(notes[0].fontStyle == .system)
        #expect(notes[0].fontSize == 16)
        #expect(!notes[0].isPinned)
        #expect(!notes[0].isTranslucent)
    }

    @Test func frameAccessorRoundTrips() {
        var note = Note(color: .gray, x: 0, y: 0)
        note.frame = CGRect(x: 5, y: 6, width: 240, height: 180)
        #expect(note.x == 5)
        #expect(note.y == 6)
        #expect(note.width == 240)
        #expect(note.height == 180)
        #expect(note.frame == CGRect(x: 5, y: 6, width: 240, height: 180))
    }
}

struct NoteColorTests {
    /// Cycling `next` must visit every color exactly once and wrap around.
    @Test func nextCyclesThroughAllColorsAndWraps() {
        var seen = Set<NoteColor>()
        var color = NoteColor.yellow
        for _ in 0..<NoteColor.allCases.count {
            seen.insert(color)
            color = color.next
        }
        #expect(seen.count == NoteColor.allCases.count)
        #expect(color == .yellow)
    }
}

struct NoteFontStyleTests {
    @Test func everyStyleProducesAFontAtBothWeights() {
        for style in NoteFontStyle.allCases {
            #expect(style.font(size: 16).pointSize == 16)
            #expect(style.font(size: 16, weight: .semibold).pointSize == 16)
        }
    }
}

struct DebouncedSaverTests {
    @MainActor
    @Test func flushRunsPendingWorkExactlyOnce() {
        let saver = DebouncedSaver()
        var runs = 0
        saver.schedule { runs += 1 }
        saver.flushNow()
        #expect(runs == 1)
        saver.flushNow()
        #expect(runs == 1, "a second flush must not re-run stale work")
    }

    @MainActor
    @Test func latestScheduledWorkWins() {
        let saver = DebouncedSaver()
        var winner = ""
        saver.schedule { winner = "first" }
        saver.schedule { winner = "second" }
        saver.flushNow()
        #expect(winner == "second")
    }
}
