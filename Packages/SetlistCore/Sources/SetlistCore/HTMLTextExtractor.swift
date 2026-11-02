import Foundation

/// A fetched web page reduced to the pieces of text that might hold a tracklist.
public struct ExtractedPage: Equatable, Sendable {
    public var title: String?
    /// Meta description (og:description or description). Often truncated by the site.
    public var description: String?
    /// Full descriptions found in embedded JSON (YouTube's shortDescription, SoundCloud's description).
    public var embeddedDescriptions: [String]
    public var bodyText: String

    public init(title: String?, description: String?, embeddedDescriptions: [String] = [], bodyText: String) {
        self.title = title
        self.description = description
        self.embeddedDescriptions = embeddedDescriptions
        self.bodyText = bodyText
    }

    /// Texts worth running through the parser, most promising first.
    public var candidateTexts: [String] {
        var texts: [String] = embeddedDescriptions
        if let description, !description.isEmpty { texts.append(description) }
        if !bodyText.isEmpty { texts.append(bodyText) }
        return texts
    }
}

/// Dependency-free HTML to text. Good enough for SoundCloud, Mixcloud, 1001Tracklists and blogs.
public enum HTMLTextExtractor {
    public static func extract(from html: String) -> ExtractedPage {
        let title = html.firstMatch(#"<title[^>]*>([\s\S]*?)</title>"#, options: .caseInsensitive)?[1]
            .map { decodeEntities(stripTags($0)).collapsingWhitespace() }

        let description = metaContent(in: html, names: ["og:description", "twitter:description", "description"])
            .map { decodeEntities($0).replacingOccurrences(of: "\\n", with: "\n") }

        var body = html
        body = body.replacingPattern(#"<!--[\s\S]*?-->"#, with: "")
        body = body.replacingPattern(#"<(script|style|noscript|svg)[^>]*>[\s\S]*?</\1>"#, with: "", options: .caseInsensitive)
        body = body.replacingPattern(#"<br\s*/?>"#, with: "\n", options: .caseInsensitive)
        body = body.replacingPattern(#"</(p|div|li|tr|h[1-6]|section|article|td|th|blockquote|pre)>"#, with: "\n", options: .caseInsensitive)
        body = stripTags(body)
        body = decodeEntities(body)
        body = body.replacingPattern(#"[ \t\u{00A0}]+"#, with: " ")
        body = body.replacingPattern(#"\n\s*\n+"#, with: "\n")
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)

        return ExtractedPage(
            title: title,
            description: description,
            embeddedDescriptions: EmbeddedJSONExtractor.descriptions(in: html),
            bodyText: body
        )
    }

    static func metaContent(in html: String, names: [String]) -> String? {
        for name in names {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let patterns = [
                #"<meta[^>]+(?:property|name)\s*=\s*["']\#(escaped)["'][^>]*?content\s*=\s*["']([^"']*)["']"#,
                #"<meta[^>]+content\s*=\s*["']([^"']*)["'][^>]*?(?:property|name)\s*=\s*["']\#(escaped)["']"#
            ]
            for pattern in patterns {
                if let found = html.firstMatch(pattern, options: .caseInsensitive)?[1], !found.isEmpty {
                    return found
                }
            }
        }
        return nil
    }

    static func stripTags(_ text: String) -> String {
        text.replacingPattern(#"<[^>]+>"#, with: "")
    }

    static func decodeEntities(_ text: String) -> String {
        var result = text
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
            ("&#x27;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&ndash;", "–"), ("&mdash;", "—"),
            ("&hellip;", "…"), ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "“"),
            ("&auml;", "ä"), ("&ouml;", "ö"), ("&uuml;", "ü"), ("&Auml;", "Ä"), ("&Ouml;", "Ö"), ("&Uuml;", "Ü"),
            ("&szlig;", "ß"), ("&eacute;", "é"), ("&egrave;", "è"), ("&ecirc;", "ê"), ("&aacute;", "á"),
            ("&agrave;", "à"), ("&iacute;", "í"), ("&oacute;", "ó"), ("&uacute;", "ú"), ("&ntilde;", "ñ"),
            ("&ccedil;", "ç"), ("&oslash;", "ø"), ("&aring;", "å"), ("&aelig;", "æ"), ("&copy;", "©")
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Numeric entities: &#8211; and &#x2013;
        for match in result.allMatches(#"&#(x?)([0-9a-fA-F]+);"#) {
            guard let whole = match[0], let digits = match[2] else { continue }
            let isHex = (match[1] ?? "").isEmpty == false
            if let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                result = result.replacingOccurrences(of: whole, with: String(Character(scalar)))
            }
        }
        return result
    }
}
