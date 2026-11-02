import Foundation
import CryptoKit
import SetlistCore

/// Spotify Web API client using the PKCE flow, so no client secret ships in the app.
/// Authorization happens in the main app (see `SpotifyAuthCoordinator`); the extension only refreshes.
final class SpotifyClient: MusicServiceClient, @unchecked Sendable {
    static let shared = SpotifyClient()

    static let redirectURI = "\(AppGroup.urlScheme)://spotify-callback"
    static let scopes = ["playlist-modify-private", "playlist-modify-public", "playlist-read-private"]
    private static let accountsBase = URL(string: "https://accounts.spotify.com")!
    private static let apiBase = URL(string: "https://api.spotify.com/v1")!

    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
    }

    struct Profile: Codable, Equatable {
        let id: String
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    let service: MusicService = .spotify

    private let keychain = KeychainStore(service: "com.syntra.djsynctoggle.spotify")
    private let tokensKey = "tokens"
    private let profileKey = "profile"
    private let session: URLSession
    private let refreshLock = NSLock()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// The user's own client ID from settings, else the build-time one from Info.plist (see project.yml).
    var clientID: String? {
        SyncSettings.effectiveSpotifyClientID
    }

    var tokens: Tokens? { keychain.read(Tokens.self, key: tokensKey) }
    var profile: Profile? { keychain.read(Profile.self, key: profileKey) }

    func isAuthorized() async -> Bool {
        guard let tokens else { return false }
        return tokens.refreshToken != nil || tokens.expiresAt > Date()
    }

    func disconnect() {
        keychain.delete(key: tokensKey)
        keychain.delete(key: profileKey)
    }

    // MARK: - PKCE authorization

    struct PKCE {
        let verifier: String
        let challenge: String
        let state: String

        static func generate() -> PKCE {
            let verifier = randomString(length: 64)
            let digest = SHA256.hash(data: Data(verifier.utf8))
            let challenge = Data(digest).base64URLEncoded()
            return PKCE(verifier: verifier, challenge: challenge, state: randomString(length: 16))
        }

        private static func randomString(length: Int) -> String {
            let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            return String((0..<length).map { _ in alphabet.randomElement()! })
        }
    }

    func authorizationURL(pkce: PKCE) throws -> URL {
        guard let clientID else {
            throw MusicServiceError.notConfigured("Add a Spotify Client ID in Settings first.")
        }
        var components = URLComponents(url: Self.accountsBase.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " "))
        ]
        return components.url!
    }

    func exchange(code: String, pkce: PKCE) async throws {
        guard let clientID else {
            throw MusicServiceError.notConfigured("Add a Spotify Client ID in Settings first.")
        }
        let response = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": pkce.verifier
        ])
        try keychain.write(response.tokens(fallbackRefreshToken: nil), key: tokensKey)
        let profile = try await currentProfile()
        try keychain.write(profile, key: profileKey)
    }

    private func validAccessToken() async throws -> String {
        guard let current = tokens else { throw MusicServiceError.notAuthorized(.spotify) }
        if current.expiresAt.timeIntervalSinceNow > 60 {
            return current.accessToken
        }
        guard let refreshToken = current.refreshToken, let clientID else {
            throw MusicServiceError.notAuthorized(.spotify)
        }
        let response = try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ])
        let refreshed = response.tokens(fallbackRefreshToken: refreshToken)
        refreshLock.lock()
        defer { refreshLock.unlock() }
        try keychain.write(refreshed, key: tokensKey)
        return refreshed.accessToken
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }

        func tokens(fallbackRefreshToken: String?) -> Tokens {
            Tokens(
                accessToken: accessToken,
                refreshToken: refreshToken ?? fallbackRefreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
            )
        }
    }

    private func tokenRequest(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.accountsBase.appendingPathComponent("api/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(form).data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - API

    func currentProfile() async throws -> Profile {
        try await get("me", query: [:], as: Profile.self)
    }

    func search(term: String, limit: Int) async throws -> [TrackCandidate] {
        let response = try await get(
            "search",
            query: ["q": term, "type": "track", "limit": String(limit)],
            as: SearchResponse.self
        )
        return response.tracks.items.map { track in
            TrackCandidate(
                id: track.uri,
                service: .spotify,
                title: track.name,
                artists: track.artists.map(\.name),
                album: track.album?.name,
                durationMs: track.durationMs,
                artworkURL: track.album?.images?.first.flatMap { URL(string: $0.url) },
                externalURL: track.externalUrls?["spotify"].flatMap { URL(string: $0) }
            )
        }
    }

    func createPlaylist(named name: String, description: String?, trackIDs: [String]) async throws -> SavedPlaylist {
        guard !trackIDs.isEmpty else { throw MusicServiceError.nothingToSave }
        let userID: String
        if let cached = profile?.id {
            userID = cached
        } else {
            userID = try await currentProfile().id
        }
        let playlist = try await post(
            "users/\(userID)/playlists",
            body: ["name": name, "description": description ?? "", "public": false],
            as: PlaylistResponse.self
        )
        // Spotify accepts at most 100 URIs per call.
        for chunk in stride(from: 0, to: trackIDs.count, by: 100) {
            let uris = Array(trackIDs[chunk..<min(chunk + 100, trackIDs.count)])
            _ = try await post("playlists/\(playlist.id)/tracks", body: ["uris": uris], as: SnapshotResponse.self)
        }
        return SavedPlaylist(
            id: playlist.id,
            name: playlist.name,
            url: playlist.externalUrls?["spotify"].flatMap { URL(string: $0) },
            service: .spotify
        )
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, query: [String: String], as type: T.Type) async throws -> T {
        var components = URLComponents(url: Self.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        return try await perform(request, as: type)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any], as type: T.Type) async throws -> T {
        var request = URLRequest(url: Self.apiBase.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request, as: type)
    }

    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type, retried: Bool = false) async throws -> T {
        var request = request
        let token = try await validAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode == 429, !retried {
            let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1
            try await Task.sleep(nanoseconds: UInt64(min(retryAfter, 10) * 1_000_000_000))
            return try await perform(request, as: type, retried: true)
        }
        try Self.check(response, data: data)
        return try JSONDecoder().decode(type, from: data)
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw MusicServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? ""
            throw MusicServiceError.http(http.statusCode, body)
        }
    }

    private static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
    }

    // MARK: - Wire types

    private struct SearchResponse: Decodable {
        let tracks: Page
        struct Page: Decodable { let items: [Track] }
    }

    private struct Track: Decodable {
        let id: String
        let uri: String
        let name: String
        let artists: [Artist]
        let album: Album?
        let durationMs: Int?
        let externalUrls: [String: String]?

        enum CodingKeys: String, CodingKey {
            case id, uri, name, artists, album
            case durationMs = "duration_ms"
            case externalUrls = "external_urls"
        }
    }

    private struct Artist: Decodable { let name: String }

    private struct Album: Decodable {
        let name: String
        let images: [Image]?
        struct Image: Decodable { let url: String }
    }

    private struct PlaylistResponse: Decodable {
        let id: String
        let name: String
        let externalUrls: [String: String]?

        enum CodingKeys: String, CodingKey {
            case id, name
            case externalUrls = "external_urls"
        }
    }

    private struct SnapshotResponse: Decodable {
        let snapshotId: String?
        enum CodingKeys: String, CodingKey { case snapshotId = "snapshot_id" }
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
