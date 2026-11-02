import Foundation
import SetlistCore

/// Matches a setlist against a streaming catalog and saves the result as a playlist.
struct SyncEngine {
    /// Keeps well under Spotify's development-mode rate limit.
    var maxConcurrentSearches = 3

    func match(
        _ setlist: Setlist,
        using client: MusicServiceClient,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async -> [TrackMatch] {
        let entries = setlist.searchableEntries
        guard !entries.isEmpty else { return [] }

        var results = [TrackMatch?](repeating: nil, count: entries.count)
        var completed = 0

        await withTaskGroup(of: (Int, TrackMatch).self) { group in
            var nextIndex = 0
            while nextIndex < min(maxConcurrentSearches, entries.count) {
                let index = nextIndex
                let entry = entries[index]
                group.addTask { (index, await Self.matchOne(entry, using: client)) }
                nextIndex += 1
            }
            for await (index, match) in group {
                results[index] = match
                completed += 1
                progress(completed, entries.count)
                if nextIndex < entries.count {
                    let pending = nextIndex
                    let entry = entries[pending]
                    nextIndex += 1
                    group.addTask { (pending, await Self.matchOne(entry, using: client)) }
                }
            }
        }
        return results.compactMap { $0 }
    }

    static func matchOne(_ entry: SetlistEntry, using client: MusicServiceClient) async -> TrackMatch {
        let query = TrackNormalizer.query(for: entry)
        var candidates = (try? await client.search(term: query.searchTerm, limit: 5)) ?? []
        var match = MatchScorer.best(for: entry, query: query, among: candidates)
        if !match.isConfident, query.fallbackSearchTerm != query.searchTerm {
            candidates += (try? await client.search(term: query.fallbackSearchTerm, limit: 5)) ?? []
            match = MatchScorer.best(for: entry, query: query, among: candidates)
        }
        return match
    }

    func save(
        matches: [TrackMatch],
        selected: Set<UUID>,
        setlist: Setlist,
        playlistName: String,
        using client: MusicServiceClient
    ) async throws -> SavedPlaylist {
        let ids = matches.filter { selected.contains($0.id) }.compactMap { $0.candidate?.id }
        guard !ids.isEmpty else { throw MusicServiceError.nothingToSave }
        var description = "Synced with DJ Sync Toggle"
        if let source = setlist.sourceURL {
            description += " from \(source.absoluteString)"
        }
        // Spotify caps playlist descriptions at 300 characters.
        return try await client.createPlaylist(named: playlistName, description: String(description.prefix(300)), trackIDs: ids)
    }
}
