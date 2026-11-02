import Foundation
import AuthenticationServices
import UIKit

/// Runs the Spotify PKCE login in the app. The share extension cannot show a login, so this is the
/// only place tokens are created; they land in the shared Keychain for the extension to use.
@MainActor
final class SpotifyAuthCoordinator: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var displayName: String?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private var session: ASWebAuthenticationSession?
    private let presentationContext = PresentationContext()

    init() {
        refresh()
    }

    func refresh() {
        Task {
            isConnected = await SpotifyClient.shared.isAuthorized()
            let profile = SpotifyClient.shared.profile
            displayName = profile?.displayName ?? profile?.id
        }
    }

    func connect() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let pkce = SpotifyClient.PKCE.generate()
            let authURL = try SpotifyClient.shared.authorizationURL(pkce: pkce)

            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: AppGroup.urlScheme) { url, error in
                    if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: error ?? MusicServiceError.invalidResponse)
                    }
                }
                session.presentationContextProvider = presentationContext
                session.prefersEphemeralWebBrowserSession = false
                self.session = session
                if !session.start() {
                    continuation.resume(throwing: MusicServiceError.notConfigured("Could not open the Spotify login."))
                }
            }

            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

            guard value("state") == pkce.state else {
                throw MusicServiceError.notConfigured("The login answer did not match the request. Try again.")
            }
            if let refused = value("error") {
                throw MusicServiceError.notConfigured("Spotify refused the login: \(refused).")
            }
            guard let code = value("code") else { throw MusicServiceError.invalidResponse }

            try await SpotifyClient.shared.exchange(code: code, pkce: pkce)
            refresh()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The user closed the sheet. Not an error worth showing.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        SpotifyClient.shared.disconnect()
        refresh()
    }
}

private final class PresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
