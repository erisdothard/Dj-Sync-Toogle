import Foundation
import SetlistCore

struct SyncRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var setTitle: String
    var sourceURL: URL?
    var sourceKey: String?
    var service: MusicService
    var playlistName: String
    var playlistURL: URL?
    var savedCount: Int
    var totalCount: Int
    /// Display text of entries that were not saved, so the user can hunt for them later.
    var unmatched: [String]
}

/// Past syncs, stored as JSON in the app-group container so both the app and the extension see them.
@MainActor
final class SyncHistoryStore: ObservableObject {
    static let shared = SyncHistoryStore()

    @Published private(set) var records: [SyncRecord] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
            ?? (AppGroup.containerURL ?? FileManager.default.temporaryDirectory).appendingPathComponent("sync-history.json")
        reload()
    }

    func reload() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SyncRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }

    func add(_ record: SyncRecord) {
        records.insert(record, at: 0)
        persist()
    }

    func remove(_ record: SyncRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    /// The most recent sync of the same source, if any.
    func record(forSource url: URL) -> SyncRecord? {
        let key = Self.sourceKey(for: url)
        return records.first { $0.sourceKey == key }
    }

    /// Same video shared from the app, Safari or a short link should count as the same source.
    static func sourceKey(for url: URL) -> String {
        if let videoID = YouTubeDescriptionFetcher.videoID(from: url) {
            return "youtube:\(videoID)"
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let host = components?.host?.lowercased().replacingOccurrences(of: "www.", with: "") ?? ""
        let path = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        return "\(host)/\(path)"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
