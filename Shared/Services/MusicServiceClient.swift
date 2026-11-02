import Foundation
import SetlistCore

struct SavedPlaylist: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let url: URL?
    let service: MusicService
}

enum MusicServiceError: LocalizedError {
    case notAuthorized(MusicService)
    case notConfigured(String)
    case http(Int, String)
    case invalidResponse
    case nothingToSave

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let service):
            return "Connect \(service.displayName) in the DJ Sync Toggle app first."
        case .notConfigured(let what):
            return what
        case .http(let code, let body):
            return "The service answered with HTTP \(code). \(body)"
        case .invalidResponse:
            return "The service sent an answer the app could not read."
        case .nothingToSave:
            return "No tracks were selected."
        }
    }
}

/// What the sync engine needs from a streaming service.
protocol MusicServiceClient: AnyObject, Sendable {
    var service: MusicService { get }
    func isAuthorized() async -> Bool
    /// Search the catalog for a single track.
    func search(term: String, limit: Int) async throws -> [TrackCandidate]
    /// Create a new playlist in the user's library with the given candidate IDs, in order.
    func createPlaylist(named name: String, description: String?, trackIDs: [String]) async throws -> SavedPlaylist
}

enum MusicServiceFactory {
    static func client(for service: MusicService) -> MusicServiceClient {
        switch service {
        case .spotify: return SpotifyClient.shared
        case .appleMusic: return AppleMusicClient.shared
        }
    }
}
