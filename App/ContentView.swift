import SwiftUI
import MusicKit
import SetlistCore

struct ContentView: View {
    @EnvironmentObject private var settings: SyncSettings
    @EnvironmentObject private var history: SyncHistoryStore
    @EnvironmentObject private var spotifyAuth: SpotifyAuthCoordinator

    @State private var appleMusicStatus = MusicAuthorization.currentStatus

    var body: some View {
        NavigationStack {
            Form {
                shareSheetSection
                spotifySection
                appleMusicSection
                playlistSection
                advancedSection
                toolsSection
            }
            .navigationTitle("DJ Sync Toggle")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            history.reload()
            spotifyAuth.refresh()
            appleMusicStatus = MusicAuthorization.currentStatus
        }
    }

    // MARK: - Sections

    private var shareSheetSection: some View {
        Section {
            Toggle(isOn: $settings.autoSyncEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-sync from the Share Sheet")
                    Text(settings.autoSyncEnabled ? "Shared sets are saved without asking." : "You review matches before saving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.green)

            Picker("Save to", selection: $settings.service) {
                ForEach(MusicService.allCases) { service in
                    Text(service.displayName).tag(service)
                }
            }
        } header: {
            Text("Share Sheet")
        } footer: {
            Text("Share a YouTube mix, a SoundCloud or Mixcloud set, copied tracklist text, or a screenshot to “DJ Sync”.")
        }
    }

    private var spotifySection: some View {
        Section {
            if spotifyAuth.isConnected {
                LabeledContent("Connected", value: spotifyAuth.displayName ?? "Spotify")
                Button("Disconnect", role: .destructive) { spotifyAuth.disconnect() }
            } else {
                if AppGroup.infoPlistValue("SpotifyClientID") == nil {
                    TextField("Spotify Client ID", text: $settings.spotifyClientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                }
                Button {
                    Task { await spotifyAuth.connect() }
                } label: {
                    if spotifyAuth.isWorking {
                        ProgressView()
                    } else {
                        Text("Connect Spotify")
                    }
                }
                .disabled(spotifyAuth.isWorking || SyncSettings.effectiveSpotifyClientID == nil)
            }
            if let message = spotifyAuth.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            NavigationLink("How to get a Spotify Client ID") { SpotifyHelpView() }
        } header: {
            Text("Spotify")
        } footer: {
            Text("Spotify limits each developer app to 5 users, so you connect with your own free Spotify app.")
        }
    }

    private var appleMusicSection: some View {
        Section("Apple Music") {
            switch appleMusicStatus {
            case .authorized:
                LabeledContent("Access", value: "Allowed")
            case .denied, .restricted:
                LabeledContent("Access", value: "Denied")
                Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            default:
                Button("Allow Apple Music access") {
                    Task { appleMusicStatus = await AppleMusicClient.shared.requestAuthorization() }
                }
            }
        }
    }

    private var playlistSection: some View {
        Section {
            TextField("Playlist name prefix (optional)", text: $settings.playlistPrefix)
            Toggle("Include unsure matches when auto-syncing", isOn: $settings.includeLowConfidence)
        } header: {
            Text("Playlists")
        } footer: {
            Text("Each set becomes a new playlist named “\(settings.playlistPrefix)Set title · date”.")
        }
    }

    private var advancedSection: some View {
        Section {
            TextField("YouTube Data API key (optional)", text: $settings.youtubeAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
        } header: {
            Text("Advanced")
        } footer: {
            Text("Without a key the YouTube description is read from the page itself, which works but can break when YouTube changes its markup.")
        }
    }

    private var toolsSection: some View {
        Section("Tools") {
            NavigationLink("Try it with pasted text or a link") { TryItView() }
            NavigationLink {
                HistoryView()
            } label: {
                LabeledContent("History", value: "\(history.records.count)")
            }
        }
    }
}

struct SpotifyHelpView: View {
    var body: some View {
        List {
            Section("Steps") {
                step(1, "Open developer.spotify.com/dashboard and sign in with the Spotify account you want playlists on. The account needs Premium.")
                step(2, "Create an app. Any name and description.")
                step(3, "Add this Redirect URI exactly: \(SpotifyClient.redirectURI)")
                step(4, "Tick “Web API”, save, and copy the Client ID.")
                step(5, "Paste the Client ID in the Spotify section and tap Connect.")
            }
            Section("Why") {
                Text("Spotify's development mode allows up to 5 users per app and is meant for apps that manage a single account. Registering your own app keeps you within those rules without waiting for a partner approval.")
                    .font(.footnote)
            }
            Section {
                Button("Copy redirect URI") { UIPasteboard.general.string = SpotifyClient.redirectURI }
            }
        }
        .navigationTitle("Spotify Client ID")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).").bold()
            Text(text)
        }
        .font(.subheadline)
    }
}
