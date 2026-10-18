import Foundation

/// PNG stills saved for the native macOS wallpaper. Saved files are retained until the
/// user removes them: macOS only reports connected displays on the current Space, so
/// neither age nor absence from that list proves an older still is unused.
enum WallpaperStills {
    static func folder() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("Stillwater/Stills", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// How much the retained stills are holding, so Settings can show it and offer the
    /// folder for manual cleanup. Retention stays manual-only (see above); this just
    /// makes the accumulating PNGs visible instead of silent disk growth.
    struct Summary: Equatable {
        var count = 0
        var bytes: Int64 = 0
    }

    static func summary(in folder: URL) -> Summary {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var summary = Summary()
        for url in files where url.pathExtension.lowercased() == "png" {
            summary.count += 1
            summary.bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return summary
    }

    /// The stills folder whether or not it exists yet, plus its summary; never creates it.
    static func current() -> (folder: URL, summary: Summary)? {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return nil }
        let folder = support.appendingPathComponent("Stillwater/Stills", isDirectory: true)
        return (folder, summary(in: folder))
    }

    /// A fresh name makes macOS reload the image without overwriting another Space's wallpaper.
    static func save(_ data: Data, theme: AquariumTheme, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("\(theme.rawValue)-\(UUID().uuidString).png")
        try data.write(to: url, options: .atomic)
        return url
    }
}
