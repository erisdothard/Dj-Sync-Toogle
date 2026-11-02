import Foundation

/// Turns free text (a SoundCloud description, a 1001Tracklists page, a pasted list, OCR output)
/// into `SetlistEntry` values. One line in, at most one entry out.
public struct TracklistParser: Sendable {
    public init() {}

    public func parse(_ text: String, title: String? = nil, sourceURL: URL? = nil) -> Setlist {
        var entries: [SetlistEntry] = []
        var nonEmptyLines = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            nonEmptyLines += 1
            if let entry = parseLine(line, index: entries.count + 1) {
                entries.append(entry)
            }
        }

        let confidence = nonEmptyLines == 0 ? 0 : Double(entries.count) / Double(nonEmptyLines)
        return Setlist(title: title, sourceURL: sourceURL, entries: entries, confidence: confidence)
    }

    /// Parses a single line. Returns `nil` when the line does not look like a track.
    public func parseLine(_ rawLine: String, index: Int) -> SetlistEntry? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line.count <= 200, !line.contains("http") else { return nil }

        line = line.replacingPattern(Patterns.leadingBullet, with: "")
        line = line.replacingPattern(Patterns.leadingIndex, with: "")

        var timestamp: String?
        if let match = line.firstMatch(Patterns.leadingTimestamp), let found = match[1] {
            timestamp = found
            line = line.replacingPattern(Patterns.leadingTimestamp, with: "")
        } else if let match = line.firstMatch(Patterns.trailingTimestamp), let found = match[1] {
            timestamp = found
            line = line.replacingPattern(Patterns.trailingTimestamp, with: "")
        }
        // "[00:00] 03. Artist - Title": the index can sit behind the timestamp.
        line = line.replacingPattern(Patterns.leadingIndex, with: "")

        var isMashup = false
        if line.matches(Patterns.mashupPrefix, options: .caseInsensitive) {
            isMashup = true
            line = line.replacingPattern(Patterns.mashupPrefix, with: "", options: .caseInsensitive)
        }

        var label: String?
        if let match = line.firstMatch(Patterns.trailingBracket), let content = match[1] {
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            // "[Anjunadeep]" is a label; "[Extended Mix]" is part of the title.
            if !Patterns.looksLikeVersionTag(trimmed) && !trimmed.isEmpty {
                label = trimmed
                line = line.replacingPattern(Patterns.trailingBracket, with: "")
            }
        }
        line = line.collapsingWhitespace()
        guard !line.isEmpty else { return nil }

        if line.matches(Patterns.unidentified, options: .caseInsensitive) {
            return SetlistEntry(
                index: index,
                artist: nil,
                title: "ID",
                rawLine: rawLine,
                timestamp: timestamp,
                label: label,
                isMashupContinuation: isMashup,
                isUnidentified: true
            )
        }

        guard let parts = split(line), isPlausible(artist: parts.artist, title: parts.title) else { return nil }

        // "Artist - ID" or "ID - Title": half the information is missing, so it cannot be searched.
        if parts.artist.matches(Patterns.unidentifiedPart, options: .caseInsensitive)
            || parts.title.matches(Patterns.unidentifiedPart, options: .caseInsensitive) {
            return SetlistEntry(
                index: index,
                artist: parts.artist,
                title: parts.title,
                rawLine: rawLine,
                timestamp: timestamp,
                label: label,
                isMashupContinuation: isMashup,
                isUnidentified: true
            )
        }

        return SetlistEntry(
            index: index,
            artist: parts.artist,
            title: parts.title,
            rawLine: rawLine,
            timestamp: timestamp,
            label: label,
            isMashupContinuation: isMashup,
            isUnidentified: false
        )
    }

    // MARK: - Internals

    private func split(_ line: String) -> (artist: String, title: String)? {
        if let regex = RegexCache.regex(Patterns.separator, options: []),
           let match = regex.firstMatch(in: line, range: line.fullRange),
           let range = Range(match.range, in: line) {
            let artist = String(line[line.startIndex..<range.lowerBound]).collapsingWhitespace()
            let title = String(line[range.upperBound...]).collapsingWhitespace()
            return (artist, title)
        }
        // "Title by Artist" is the only other form we accept without a dash.
        if let match = line.firstMatch(Patterns.byForm, options: .caseInsensitive),
           let title = match[1], let artist = match[2],
           !Patterns.byFormStopWords.contains(title.lowercased().collapsingWhitespace()) {
            return (artist.collapsingWhitespace(), title.collapsingWhitespace())
        }
        return nil
    }

    private func isPlausible(artist: String, title: String) -> Bool {
        guard !artist.isEmpty, !title.isEmpty else { return false }
        let artistWords = artist.split(separator: " ").count
        let titleWords = title.split(separator: " ").count
        guard artistWords <= 10, titleWords <= 16 else { return false }
        // A line of prose that happens to contain " - " usually ends with a full stop. Titles rarely do.
        if title.hasSuffix(".") && !title.hasSuffix("..") { return false }
        return true
    }
}

enum Patterns {
    static let leadingBullet = #"^[\-\*•·▪►>]+\s+"#
    /// "1. ", "1) ", "(1) ", "[1] ", "#1 ", "1: " but not "01:23".
    static let leadingIndex = #"^(?:[\(\[]?\d{1,3}(?:[\.\)\]]\s*|:\s+)|#\d{1,3}\s*)"#
    static let leadingTimestamp = #"^[\[\(]?((?:\d{1,2}:)?\d{1,2}:\d{2})[\]\)]?\s*(?:[-–—:|]\s*)?"#
    static let trailingTimestamp = #"\s*[\[\(@]?\s*((?:\d{1,2}:)?\d{1,2}:\d{2})\s*[\]\)]?\s*$"#
    static let mashupPrefix = #"^(?:w/\s*|(?:vs\.?|\+)\s+)"#
    static let trailingBracket = #"\s*\[([^\]]*)\]\s*$"#
    static let unidentified = #"^(?:id|\?+|unknown|untitled)\s*[-–—]\s*(?:id|\?+|unknown|untitled)(?=\s|\(|\[|$).*$"#
    static let unidentifiedPart = #"^(?:id|\?+|unknown|untitled)(?:\s*[\(\[].*)?$"#
    static let separator = #"\s+[-–—]\s+"#
    static let byForm = #"^(.{1,80}?)\s+by\s+(.{1,60})$"#
    /// "Mixed by X", "Recorded by X" are credits, not tracks.
    static let byFormStopWords: Set<String> = [
        "mixed", "recorded", "hosted", "presented", "powered", "produced", "mastered", "photo", "photos",
        "video", "tracklist", "set", "mix", "live set", "dj set", "compiled", "selected", "curated", "supported"
    ]

    private static let versionWords = [
        "remix", "mix", "edit", "bootleg", "dub", "version", "rework", "vip", "flip",
        "mashup", "live", "acoustic", "instrumental", "refix", "rmx", "extended", "original"
    ]

    static func looksLikeVersionTag(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return versionWords.contains { lowered.contains($0) }
    }
}
