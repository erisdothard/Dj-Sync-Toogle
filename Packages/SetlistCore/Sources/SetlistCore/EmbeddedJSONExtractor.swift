import Foundation

/// Pulls string values out of JSON that sites embed in their HTML.
///
/// YouTube keeps the full video description in `ytInitialPlayerResponse` under `"shortDescription"`,
/// and SoundCloud keeps a track's description in its hydration blob under `"description"`.
/// The meta tags on those pages are truncated, so this is where tracklists in a "bio" actually live.
public enum EmbeddedJSONExtractor {
    /// Keys whose values are worth running through the tracklist parser, in priority order.
    public static let descriptionKeys = ["shortDescription", "description", "attributedDescription"]

    /// Every decoded value of `"key":"..."` found in `html`, longest first, de-duplicated.
    public static func strings(forKey key: String, in html: String) -> [String] {
        let marker = "\"\(key)\":\""
        var results: [String] = []
        var searchRange = html.startIndex..<html.endIndex

        while let markerRange = html.range(of: marker, range: searchRange) {
            let valueStart = markerRange.upperBound
            if let (raw, end) = scanJSONString(in: html, from: valueStart), let decoded = decodeJSONString(raw) {
                results.append(decoded)
                searchRange = end..<html.endIndex
            } else {
                searchRange = markerRange.upperBound..<html.endIndex
            }
        }

        var seen = Set<String>()
        return results
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    /// All description-like strings from the known keys, longest first.
    public static func descriptions(in html: String) -> [String] {
        var seen = Set<String>()
        return descriptionKeys
            .flatMap { strings(forKey: $0, in: html) }
            .filter { seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    /// Scans a JSON string body (opening quote already consumed) up to its closing quote.
    /// Returns the raw escaped contents and the index just past the closing quote.
    static func scanJSONString(in text: String, from start: String.Index) -> (String, String.Index)? {
        var index = start
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return (String(text[start..<index]), text.index(after: index))
            } else if character == "\n" {
                // A real newline inside a JSON string means this was not JSON after all.
                return nil
            }
            index = text.index(after: index)
        }
        return nil
    }

    static func decodeJSONString(_ raw: String) -> String? {
        guard let data = "\"\(raw)\"".data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String
        else { return nil }
        return value
    }
}
