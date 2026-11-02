import Foundation

/// Scores how well a search result matches a setlist entry. 1.0 is a certain match.
public enum MatchScorer {
    /// Matches at or above this score are selected automatically.
    public static let acceptThreshold = 0.62

    public static func best(for entry: SetlistEntry, query: TrackQuery? = nil, among candidates: [TrackCandidate]) -> TrackMatch {
        let query = query ?? TrackNormalizer.query(for: entry)
        var bestCandidate: TrackCandidate?
        var bestScore = 0.0
        for candidate in candidates {
            let score = self.score(query: query, candidate: candidate)
            if score > bestScore {
                bestScore = score
                bestCandidate = candidate
            }
        }
        return TrackMatch(entry: entry, candidate: bestCandidate, score: bestScore)
    }

    public static func score(query: TrackQuery, candidate: TrackCandidate) -> Double {
        // Run the candidate through the same normalizer so "Title - Extended Mix" compares to "Title".
        let candidateQuery = TrackNormalizer.query(artist: candidate.artists.joined(separator: ", "), title: candidate.title)

        let queryTitle = TrackNormalizer.normalizedTokens(query.title)
        let candidateTitle = TrackNormalizer.normalizedTokens(candidateQuery.title)
        let titleSimilarity = similarity(queryTitle, candidateTitle)

        let queryArtists = TrackNormalizer.normalizedTokens(query.allArtists.joined(separator: " "))
        let candidateArtists = TrackNormalizer.normalizedTokens(candidateQuery.allArtists.joined(separator: " "))
        // Without an artist on the setlist side we cannot judge, so stay neutral rather than punish.
        let artistSimilarity = queryArtists.isEmpty ? 0.5 : similarity(queryArtists, candidateArtists)

        var score = 0.6 * titleSimilarity + 0.4 * artistSimilarity

        switch (query.remixTag, candidateQuery.remixTag) {
        case (nil, nil):
            break
        case (let wanted?, let got?):
            let tagSimilarity = similarity(TrackNormalizer.normalizedTokens(wanted), TrackNormalizer.normalizedTokens(got))
            score += 0.15 * (2 * tagSimilarity - 1)
        case (nil, _?):
            // We wanted the original and got a remix.
            score -= 0.2
        case (_?, nil):
            // We wanted a remix and got the original.
            score -= 0.25
        }

        return min(max(score, 0), 1)
    }

    /// Dice coefficient over token sets, with a floor when one set is fully contained in the other.
    static func similarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let dice = 2 * Double(intersection) / Double(a.count + b.count)
        if intersection == min(a.count, b.count) {
            return max(dice, 0.8)
        }
        return dice
    }
}
