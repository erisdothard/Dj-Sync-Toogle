import SwiftUI

@main
struct DJSyncToggleApp: App {
    @StateObject private var settings = SyncSettings.shared
    @StateObject private var history = SyncHistoryStore.shared
    @StateObject private var spotifyAuth = SpotifyAuthCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(spotifyAuth)
        }
    }
}
