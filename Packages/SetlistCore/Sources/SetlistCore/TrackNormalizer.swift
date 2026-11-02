import Foundation

/// What we actually send to a streaming service search, derived from a setlist entry.
public struct TrackQuery: Equatable, Sendable {
    public var artists: [String]
    public var title: String
    public var featuredArtists: [String]
    /// "Kölsch Remix", "Club Edit", ... when the entry names a specific version.
    public var remixTag: String?

    public init(artists: [String], title: String, featuredArtists: [String] = [], remixTag: String? = nil) {
        self.artists = artists
        self.title = title
        self.featuredArtists = featuredArtists
        self.remixTag = remixTag
    }

    /// Plain search string: "Artist Title Remix Tag".
    public var searchTerm: String {
        var parts = [artists.joined(separator: " "), title]
        if let remixTag { parts.append(remixTag) }
        return parts.filter { !$0.isEmpty }.joined(separator: " ").collapsingWhitespace()
    }

    /// Looser search used when the full query returns nothing: first artist + title only.
    public var fallbackSearchTerm: String {
        [artists.first ?? "", title].filter { !$0.isEmpty }.joined(separator: " ").collapsingWhitespace()
    }

    public var allArtists: [String] { artists + featuredArtists }
}

public enum TrackNormalizer {
    /// Strips version noise, pulls out featured artists and remix tags.
    public static func query(for entry: SetlistEntry) -> TrackQuery {
        query(artist: entry.artist ?? "", title: entry.title)
    }

    public static func query(artist artistText: String, title titleText: String) -> TrackQuery {
        var title = titleText
        var featured: [String] = []
        var remixTag: String?

        for group in title.allMatches(groupPattern) {
            let content = (group[1] ?? group[2] ?? "").trimmingCharacters(in: .whitespaces)
            switch classify(content) {
            case .featured(let names): featured += names
            case .remix(let tag): if remixTag == nil { remixTag = tag }
            case .noise, .other: break
            }
        }
        title = title.replacingPattern(groupPattern, with: " ")

        if let match = title.firstMatch(inlineFeatPattern, options: .caseInsensitive), let names = match[2] {
            featured += splitArtists(names)
            title = title.replacingPattern(inlineFeatPattern, with: "", options: .caseInsensitive)
        }
        // Spotify-style suffix: "Title - Extended Mix", "Title - Kölsch Remix".
        if let match = title.firstMatch(#"^(.+?)\s+[-–—]\s+(.+)$"#), let head = match[1], let tail = match[2] {
            switch classify(tail) {
            case .remix(let tag):
                if remixTag == nil { remixTag = tag }
                title = head
            case .featured(let names):
                featured += names
                title = head
            case .noise:
                title = head
            case .other:
                break
            }
        }
        title = title.replacingPattern(trailingNoisePattern, with: "", options: .caseInsensitive)

        var artistText = artistText
        if let match = artistText.firstMatch(inlineFeatPattern, options: .caseInsensitive), let names = match[2] {
            featured += splitArtists(names)
            artistText = artistText.replacingPattern(inlineFeatPattern, with: "", options: .caseInsensitive)
        }

        return TrackQuery(
            artists: splitArtists(artistText),
            title: title.collapsingWhitespace(),
            featuredArtists: featured,
            remixTag: remixTag
        )
    }

    /// Lowercased, diacritic-folded, punctuation-free tokens used for similarity scoring.
    public static func normalizedTokens(_ text: String) -> Set<String> {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "$", with: "s")
        let cleaned = folded.replacingPattern(#"[^a-z0-9]+"#, with: " ")
        return Set(cleaned.split(separator: " ").map(String.init).filter { !$0.isEmpty })
    }

    /// "A & B feat. C, D x E" -> ["A", "B", "C", "D", "E"]
    public static func splitArtists(_ text: String) -> [String] {
        text.replacingPattern(artistSeparatorPattern, with: "\u{1F}", options: .caseInsensitive)
            .split(separator: "\u{1F}")
            .map { String($0).collapsingWhitespace() }
            .filter { !$0.isEmpty }
    }

    // MARK: - Internals

    enum GroupKind {
        case featured([String])
        case remix(String)
        case noise
        case other
    }

    static let groupPattern = #"\(([^)]*)\)|\[([^\]]*)\]"#
    static let inlineFeatPattern = #"\s+(feat\.?|ft\.?|featuring)\s+(.+)$"#
    static let artistSeparatorPattern = #"\s*(?:,|&|\+|\bx\b|\bvs\.?\b|\band\b|\bb2b\b)\s*"#
    static let trailingNoisePattern = #"\s+(?:original mix|extended mix|radio edit|club mix|extended version|original version)\s*$"#

    static let noiseTags: Set<String> = [
        "original mix", "extended mix", "radio edit", "radio mix", "club mix", "extended version",
        "original version", "extended", "original", "album version", "single version", "explicit",
        "clean", "official audio", "official video", "official music video", "lyric video", "audio",
        "hq", "free download", "out now", "free dl", "premiere", "snippet", "preview", "full track"
    ]

    static let remixWords = [
        "remix", "bootleg", "rework", "vip", "flip", "mashup", "edit", "dub", "mix", "version",
        "refix", "rmx", "rework", "cover", "live", "acoustic", "instrumental"
    ]

    static func classify(_ content: String) -> GroupKind {
        let lowered = content.lowercased().collapsingWhitespace()
        if lowered.isEmpty { return .other }
        if noiseTags.contains(lowered) { return .noise }
        if let match = content.firstMatch(#"^(?:feat\.?|ft\.?|featuring|with)\s+(.+)$"#, options: .caseInsensitive),
           let names = match[1] {
            return .featured(splitArtists(names))
        }
        if remixWords.contains(where: { lowered.hasSuffix($0) || lowered.contains(" \($0) ") || lowered.contains(" \($0)") }) {
            return .remix(content.collapsingWhitespace())
        }
        return .other
    }
}
