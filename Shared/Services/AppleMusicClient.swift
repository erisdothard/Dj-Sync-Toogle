import Foundation
import MusicKit
import SetlistCore

/// Apple Music through MusicKit. Authorization is requested in the main app;
/// the extension can search and create playlists once the status is `.authorized`.
final class AppleMusicClient: MusicServiceClient, @unchecked Sendable {
    static let shared = AppleMusicClient()

    let service: MusicService = .appleMusic

    func isAuthorized() async -> Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    @MainActor
    func requestAuthorization() async -> MusicAuthorization.Status {
        await MusicAuthorization.request()
    }

    func search(term: String, limit: Int) async throws -> [TrackCandidate] {
        guard await isAuthorized() else { throw MusicServiceError.notAuthorized(.appleMusic) }
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = limit
        let response = try await request.response()
        return response.songs.map { song in
            TrackCandidate(
                id: song.id.rawValue,
                service: .appleMusic,
                title: song.title,
                artists: [song.artistName],
                album: song.albumTitle,
                durationMs: song.duration.map { Int($0 * 1000) },
                artworkURL: song.artwork?.url(width: 300, height: 300),
                externalURL: song.url
            )
        }
    }

    func createPlaylist(named name: String, description: String?, trackIDs: [String]) async throws -> SavedPlaylist {
        guard await isAuthorized() else { throw MusicServiceError.notAuthorized(.appleMusic) }
        guard !trackIDs.isEmpty else { throw MusicServiceError.nothingToSave }

        let ids = trackIDs.map { MusicItemID($0) }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids)
        let songs = try await request.response().items
        // The catalog answers in its own order; restore the set order.
        let ordered = trackIDs.compactMap { id in songs.first { $0.id.rawValue == id } }

        let playlist = try await MusicLibrary.shared.createPlaylist(name: name, description: description, items: ordered)
        return SavedPlaylist(id: playlist.id.rawValue, name: playlist.name, url: playlist.url, service: .appleMusic)
    }
}
