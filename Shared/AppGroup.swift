import Foundation
import SwiftUI
import SetlistCore

/// Identifiers shared between the app and the share extension.
/// Change the prefix in `project.yml` and here together.
enum AppGroup {
    static let identifier = "group.com.syntra.djsynctoggle"
    /// On iOS an app group ID doubles as a keychain access group, which lets the extension read tokens.
    static let keychainAccessGroup = identifier
    static let urlScheme = "djsynctoggle"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Info.plist value that is set and is not the placeholder from Secrets.example.xcconfig.
    static func infoPlistValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") else { return nil }
        return trimmed
    }
}

/// UserDefaults keys shared by the app and the extension.
enum SettingsKey {
    static let autoSync = "autoSyncEnabled"
    static let service = "musicService"
    static let playlistPrefix = "playlistPrefix"
    static let includeLowConfidence = "includeLowConfidence"
    static let spotifyClientID = "spotifyClientID"
    static let youtubeAPIKey = "youtubeAPIKey"
}

/// User preferences, persisted in the app group so the share extension sees the same values.
@MainActor
final class SyncSettings: ObservableObject {
    static let shared = SyncSettings()

    private typealias Key = SettingsKey

    /// The toggle. On: a shared set is matched and saved with no further taps.
    /// Off: the share sheet shows the matches for review first.
    @Published var autoSyncEnabled: Bool {
        didSet { AppGroup.defaults.set(autoSyncEnabled, forKey: Key.autoSync) }
    }

    @Published var service: MusicService {
        didSet { AppGroup.defaults.set(service.rawValue, forKey: Key.service) }
    }

    /// Prepended to every playlist name, e.g. "DJ Sync · ".
    @Published var playlistPrefix: String {
        didSet { AppGroup.defaults.set(playlistPrefix, forKey: Key.playlistPrefix) }
    }

    /// When auto-sync is on, also save the best guess for tracks the matcher is unsure about.
    @Published var includeLowConfidence: Bool {
        didSet { AppGroup.defaults.set(includeLowConfidence, forKey: Key.includeLowConfidence) }
    }

    /// Bring-your-own Spotify app. Spotify's development mode allows 5 users per app, so each
    /// user registers a free Spotify app and pastes its client ID here. Overrides the build-time value.
    @Published var spotifyClientID: String {
        didSet { AppGroup.defaults.set(spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.spotifyClientID) }
    }

    /// Optional. With a YouTube Data API key the description is fetched through the API instead of the page HTML.
    @Published var youtubeAPIKey: String {
        didSet { AppGroup.defaults.set(youtubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.youtubeAPIKey) }
    }

    private init() {
        let defaults = AppGroup.defaults
        autoSyncEnabled = defaults.object(forKey: Key.autoSync) as? Bool ?? true
        service = MusicService(rawValue: defaults.string(forKey: Key.service) ?? "") ?? .spotify
        playlistPrefix = defaults.string(forKey: Key.playlistPrefix) ?? ""
        includeLowConfidence = defaults.object(forKey: Key.includeLowConfidence) as? Bool ?? false
        spotifyClientID = defaults.string(forKey: Key.spotifyClientID) ?? ""
        youtubeAPIKey = defaults.string(forKey: Key.youtubeAPIKey) ?? ""
    }

    /// The effective Spotify client ID: the user's own first, then the one baked in at build time.
    nonisolated static var effectiveSpotifyClientID: String? {
        if let own = AppGroup.defaults.string(forKey: SettingsKey.spotifyClientID)?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty {
            return own
        }
        return AppGroup.infoPlistValue("SpotifyClientID")
    }

    nonisolated static var effectiveYouTubeAPIKey: String? {
        if let own = AppGroup.defaults.string(forKey: SettingsKey.youtubeAPIKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty {
            return own
        }
        return AppGroup.infoPlistValue("YouTubeAPIKey")
    }

    func playlistName(for setlist: Setlist) -> String {
        let base = SetlistDetector.cleanTitle(setlist.title) ?? "DJ Set"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let name = "\(playlistPrefix)\(base) · \(formatter.string(from: Date()))"
        return String(name.prefix(100))
    }
}
