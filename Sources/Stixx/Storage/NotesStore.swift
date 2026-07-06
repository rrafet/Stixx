import Foundation

/// Reads and writes the note list as JSON in ~/Library/Application Support/Stixx.
/// Writes are atomic so a crash or power loss mid-save cannot corrupt existing data.
enum NotesStore {
    private static let fileName = "notes.json"

    private static func directoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Stixx", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileURL() throws -> URL {
        try directoryURL().appendingPathComponent(fileName)
    }

    /// Loads notes from disk. Returns an empty array on first launch or if the
    /// file is missing. If the file exists but is unreadable/corrupt, it is
    /// preserved under a .bak name rather than silently discarded, and an
    /// empty list is returned so the app can still start.
    static func load() -> [Note] {
        guard let url = try? fileURL(), FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Note].self, from: data)
        } catch {
            FileHandle.standardError.write(Data("Stixx: failed to read notes.json (\(error)); backing up and starting fresh.\n".utf8))
            let backupURL = url.deletingLastPathComponent()
                .appendingPathComponent("notes-\(Int(Date().timeIntervalSince1970)).bak.json")
            try? FileManager.default.copyItem(at: url, to: backupURL)
            return []
        }
    }

    /// Persists notes atomically. Failures are logged, never thrown to the caller,
    /// since a save failure should not crash a note-taking app.
    static func save(_ notes: [Note]) {
        do {
            let url = try fileURL()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(notes)
            try data.write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("Stixx: failed to save notes.json (\(error))\n".utf8))
        }
    }
}
