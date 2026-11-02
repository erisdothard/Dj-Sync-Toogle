import Foundation
import UIKit
import SetlistCore

enum ExtractionError: LocalizedError {
    case unreadablePage
    case emptyImage
    case noDescription

    var errorDescription: String? {
        switch self {
        case .unreadablePage: return "The page could not be loaded."
        case .emptyImage: return "The image could not be read."
        case .noDescription: return "No description was found on the page."
        }
    }
}

/// Turns whatever was shared into a `Setlist`.
struct SetlistExtractor {
    var session: URLSession = .shared

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func extract(from input: SharedInput, titleHint: String? = nil) async throws -> Setlist {
        switch input {
        case .text(let text):
            if let url = SetlistDetector.soleURL(in: text) {
                return try await extract(fromURL: url, titleHint: titleHint)
            }
            return TracklistParser().parse(text, title: SetlistDetector.cleanTitle(titleHint))
        case .url(let url):
            return try await extract(fromURL: url, titleHint: titleHint)
        case .image(let image):
            let text = try await ImageTextRecognizer.recognize(image)
            return TracklistParser().parse(text, title: SetlistDetector.cleanTitle(titleHint))
        }
    }

    func extract(fromURL url: URL, titleHint: String?) async throws -> Setlist {
        // Site-specific paths first: they return the full description where the HTML only has a teaser.
        if let videoID = YouTubeDescriptionFetcher.videoID(from: url),
           let page = try? await YouTubeDescriptionFetcher(session: session).fetch(videoID: videoID) {
            return detect(page, url: url, hint: titleHint)
        }
        if MixcloudFetcher.handles(url), let page = try? await MixcloudFetcher(session: session).fetch(url) {
            return detect(page, url: url, hint: titleHint)
        }
        let page = try await Self.fetchHTML(url, session: session)
        return detect(page, url: url, hint: titleHint)
    }

    private func detect(_ page: ExtractedPage, url: URL, hint: String?) -> Setlist {
        let title = SetlistDetector.cleanTitle(page.title) ?? SetlistDetector.cleanTitle(hint)
        return SetlistDetector.best(from: page.candidateTexts, title: title, sourceURL: url)
    }

    static func fetchHTML(_ url: URL, session: URLSession) async throws -> ExtractedPage {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        // Skips Google's consent interstitial in the EU.
        request.setValue("CONSENT=YES+1; SOCS=CAI", forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExtractionError.unreadablePage
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ExtractionError.unreadablePage
        }
        return HTMLTextExtractor.extract(from: html)
    }
}

/// YouTube: Data API when a key is configured (compliant, stable), page HTML otherwise.
struct YouTubeDescriptionFetcher {
    var session: URLSession

    static func videoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            return parts.first.flatMap(validID)
        }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") || host.hasSuffix("youtube-nocookie.com") else {
            return nil
        }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
            return validID(v)
        }
        if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) {
            return validID(parts[1])
        }
        return nil
    }

    private static func validID(_ candidate: String) -> String? {
        candidate.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil ? candidate : nil
    }

    func fetch(videoID: String) async throws -> ExtractedPage {
        let key = SyncSettings.effectiveYouTubeAPIKey
        var page: ExtractedPage
        if let key, let fromAPI = try? await fetchViaAPI(videoID: videoID, key: key) {
            page = fromAPI
        } else {
            page = try await fetchViaHTML(videoID: videoID)
        }
        // Tracklists often sit in a pinned or top comment instead of the description.
        // Comments are not in the page HTML, so this needs the Data API key.
        if let key, let comments = try? await fetchComments(videoID: videoID, key: key) {
            page.embeddedDescriptions += comments
        }
        return page
    }

    private struct CommentsResponse: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable {
                struct TopLevel: Decodable {
                    struct CommentSnippet: Decodable {
                        let textOriginal: String
                    }
                    let snippet: CommentSnippet
                }
                let topLevelComment: TopLevel
            }
            let snippet: Snippet
        }
        let items: [Item]
    }

    /// Top 50 comments by relevance (1 quota unit). The detector picks whichever text parses best.
    private func fetchComments(videoID: String, key: String) async throws -> [String] {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/commentThreads")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "videoId", value: videoID),
            URLQueryItem(name: "order", value: "relevance"),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "textFormat", value: "plainText"),
            URLQueryItem(name: "key", value: key)
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExtractionError.unreadablePage
        }
        return try JSONDecoder().decode(CommentsResponse.self, from: data).items
            .map(\.snippet.topLevelComment.snippet.textOriginal)
            .filter { $0.count >= 40 }
    }

    private struct APIResponse: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable {
                let title: String
                let description: String
            }
            let snippet: Snippet
        }
        let items: [Item]
    }

    private func fetchViaAPI(videoID: String, key: String) async throws -> ExtractedPage {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "id", value: videoID),
            URLQueryItem(name: "key", value: key)
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExtractionError.unreadablePage
        }
        guard let item = try JSONDecoder().decode(APIResponse.self, from: data).items.first else {
            throw ExtractionError.noDescription
        }
        return ExtractedPage(title: item.snippet.title, description: nil, embeddedDescriptions: [item.snippet.description], bodyText: "")
    }

    private func fetchViaHTML(videoID: String) async throws -> ExtractedPage {
        let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)&hl=en")!
        let page = try await SetlistExtractor.fetchHTML(url, session: session)
        guard !page.embeddedDescriptions.isEmpty else { throw ExtractionError.noDescription }
        return page
    }
}

/// Mixcloud has a public JSON API that mirrors the page path.
struct MixcloudFetcher {
    var session: URLSession

    static func handles(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "mixcloud.com" || host.hasSuffix(".mixcloud.com")
    }

    private struct Cloudcast: Decodable {
        let name: String?
        let description: String?
    }

    func fetch(_ url: URL) async throws -> ExtractedPage {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { throw ExtractionError.unreadablePage }
        let apiURL = URL(string: "https://api.mixcloud.com/\(parts[0])/\(parts[1])/")!
        let (data, response) = try await session.data(from: apiURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExtractionError.unreadablePage
        }
        let cloudcast = try JSONDecoder().decode(Cloudcast.self, from: data)
        guard let description = cloudcast.description, !description.isEmpty else { throw ExtractionError.noDescription }
        return ExtractedPage(title: cloudcast.name, description: nil, embeddedDescriptions: [description], bodyText: "")
    }
}
