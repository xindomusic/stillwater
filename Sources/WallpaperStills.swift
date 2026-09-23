import Foundation

/// PNG stills saved for the native macOS wallpaper. Each "Set as wallpaper" writes new
/// files, so older stills are pruned, conservatively: macOS only reports the wallpaper of
/// connected displays on the current Space, so a still that looks unused may still be
/// showing on another Space or on a monitor that is unplugged right now.
enum WallpaperStills {
    /// The newest stills are always kept, whatever their age.
    static let newestKept = 8
    /// Older stills are only deleted after this long.
    static let minimumAge: TimeInterval = 14 * 24 * 60 * 60

    struct Still {
        var url: URL
        var created: Date
    }

    static func folder() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("Stillwater/Stills", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Stills that can be deleted: PNGs not in `keeping`, not among the newest, and old enough.
    static func obsolete(existing: [Still], keeping: [URL], now: Date = Date()) -> [URL] {
        let kept = Set(keeping.map { $0.standardizedFileURL.path })
        let stills = existing.filter { $0.url.pathExtension.lowercased() == "png" }.sorted { $0.created > $1.created }
        return stills.dropFirst(newestKept)
            .filter { !kept.contains($0.url.standardizedFileURL.path) && now.timeIntervalSince($0.created) > minimumAge }
            .map(\.url)
    }

    /// Deletes stills that are safe to remove. Failures are harmless and ignored.
    static func prune(in folder: URL, keeping: [URL]) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let stills = files.map { url in
            // An unreadable date counts as old; the newest-eight and in-use rules still protect it.
            Still(url: url, created: (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }
        for url in obsolete(existing: stills, keeping: keeping) { try? FileManager.default.removeItem(at: url) }
    }
}
