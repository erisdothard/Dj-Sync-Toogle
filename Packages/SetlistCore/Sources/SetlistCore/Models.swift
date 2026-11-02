import Foundation

/// A streaming service the app can save playlists to.
public enum MusicService: String, Codable, CaseIterable, Sendable, Identifiable {
    case spotify
    case appleMusic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        }
    }
}

/// One line of a DJ tracklist after parsing.
public struct SetlistEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    /// 1-based position in the set.
    public var index: Int
    public var artist: String?
    public var title: String
    /// The line exactly as it appeared in the source.
    public var rawLine: String
    /// Cue time inside the mix, e.g. "01:23:45", when the source had one.
    public var timestamp: String?
    /// Record label, when the source listed one in trailing brackets, e.g. "[Anjunadeep]".
    public var label: String?
    /// True for lines that were marked "w/" (played over the previous track).
    public var isMashupContinuation: Bool
    /// True for "ID - ID" lines: an unknown track that cannot be searched for.
    public var isUnidentified: Bool

    public init(
        id: UUID = UUID(),
        index: Int,
        artist: String?,
        title: String,
        rawLine: String,
        timestamp: String? = nil,
        label: String? = nil,
        isMashupContinuation: Bool = false,
        isUnidentified: Bool = false
    ) {
        self.id = id
        self.index = index
        self.artist = artist
        self.title = title
        self.rawLine = rawLine
        self.timestamp = timestamp
        self.label = label
        self.isMashupContinuation = isMashupContinuation
        self.isUnidentified = isUnidentified
    }

    /// "Artist - Title" for display.
    public var displayText: String {
        if let artist, !artist.isEmpty { return "\(artist) - \(title)" }
        return title
    }
}

/// A parsed tracklist plus how confident the parser is that the source really was one.
public struct Setlist: Codable, Equatable, Sendable {
    public var title: String?
    public var sourceURL: URL?
    public var entries: [SetlistEntry]
    /// Fraction of non-empty source lines that parsed as tracks (0...1).
    public var confidence: Double

    public init(title: String? = nil, sourceURL: URL? = nil, entries: [SetlistEntry], confidence: Double) {
        self.title = title
        self.sourceURL = sourceURL
        self.entries = entries
        self.confidence = confidence
    }

    /// Entries that can actually be searched for (everything except "ID - ID").
    public var searchableEntries: [SetlistEntry] {
        entries.filter { !$0.isUnidentified }
    }

    /// Heuristic used by the share sheet to decide whether to offer a sync at all.
    public var isLikelySetlist: Bool {
        searchableEntries.count >= 3 && confidence >= 0.4
    }
}

/// A track returned by a streaming service search.
public struct TrackCandidate: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Service-specific identifier (Spotify URI or Apple Music catalog ID).
    public let id: String
    public let service: MusicService
    public let title: String
    public let artists: [String]
    public let album: String?
    public let durationMs: Int?
    public let artworkURL: URL?
    public let externalURL: URL?

    public init(
        id: String,
        service: MusicService,
        title: String,
        artists: [String],
        album: String? = nil,
        durationMs: Int? = nil,
        artworkURL: URL? = nil,
        externalURL: URL? = nil
    ) {
        self.id = id
        self.service = service
        self.title = title
        self.artists = artists
        self.album = album
        self.durationMs = durationMs
        self.artworkURL = artworkURL
        self.externalURL = externalURL
    }

    public var artistLine: String { artists.joined(separator: ", ") }
}

/// The best candidate the matcher found for one setlist entry.
public struct TrackMatch: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { entry.id }
    public let entry: SetlistEntry
    public let candidate: TrackCandidate?
    /// 0...1 confidence that `candidate` is the right track.
    public let score: Double

    public init(entry: SetlistEntry, candidate: TrackCandidate?, score: Double) {
        self.entry = entry
        self.candidate = candidate
        self.score = score
    }

    public var isConfident: Bool {
        candidate != nil && score >= MatchScorer.acceptThreshold
    }
}
