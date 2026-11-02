import Foundation

/// Picks the most tracklist-like text out of several candidates (page description, page body, ...).
public enum SetlistDetector {
    public static func best(from texts: [String], title: String? = nil, sourceURL: URL? = nil) -> Setlist {
        let parser = TracklistParser()
        var best = Setlist(title: title, sourceURL: sourceURL, entries: [], confidence: 0)
        var bestRank = -1.0
        for text in texts {
            let setlist = parser.parse(text, title: title, sourceURL: sourceURL)
            let rank = Double(setlist.searchableEntries.count) * max(setlist.confidence, 0.05)
                + (setlist.isLikelySetlist ? 100 : 0)
            if rank > bestRank {
                bestRank = rank
                best = setlist
            }
        }
        return best
    }

    /// If the whole text is just a link, return it so the caller can fetch the page instead.
    public static func soleURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.matches(#"^https?://\S+$"#, options: .caseInsensitive) else { return nil }
        return URL(string: trimmed)
    }

    /// Removes site suffixes from page titles: "Boiler Room Set | Free Listening on SoundCloud" -> "Boiler Room Set".
    public static func cleanTitle(_ title: String?) -> String? {
        guard var cleaned = title?.collapsingWhitespace(), !cleaned.isEmpty else { return nil }
        cleaned = cleaned.replacingPattern(
            #"\s*(\||-|–|—|·)\s*(free listening on soundcloud|stream .* on soundcloud|soundcloud|mixcloud|youtube|youtube music|1001tracklists|tracklist)\s*$"#,
            with: "",
            options: .caseInsensitive
        )
        cleaned = cleaned.replacingPattern(#"^stream\s+"#, with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingPattern(#"\s+by\s+[^|]+\|\s*listen online for free on soundcloud\s*$"#, with: "", options: .caseInsensitive)
        if cleaned.count > 70 {
            cleaned = String(cleaned.prefix(70)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return cleaned.isEmpty ? nil : cleaned
    }
}
