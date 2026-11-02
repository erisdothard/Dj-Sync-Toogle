import Foundation

/// Small NSRegularExpression helpers so the parser reads cleanly and runs on every platform.
enum RegexCache {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    static func regex(_ pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression? {
        let key = "\(options.rawValue):\(pattern)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        guard let built = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        cache[key] = built
        return built
    }
}

extension String {
    var fullRange: NSRange { NSRange(startIndex..., in: self) }

    /// Capture groups of the first match (index 0 is the whole match). `nil` when there is no match.
    func firstMatch(_ pattern: String, options: NSRegularExpression.Options = []) -> [String?]? {
        guard let regex = RegexCache.regex(pattern, options: options),
              let match = regex.firstMatch(in: self, range: fullRange) else { return nil }
        return captures(of: match)
    }

    /// Capture groups of every match.
    func allMatches(_ pattern: String, options: NSRegularExpression.Options = []) -> [[String?]] {
        guard let regex = RegexCache.regex(pattern, options: options) else { return [] }
        return regex.matches(in: self, range: fullRange).map { captures(of: $0) }
    }

    func matches(_ pattern: String, options: NSRegularExpression.Options = []) -> Bool {
        firstMatch(pattern, options: options) != nil
    }

    func replacingPattern(_ pattern: String, with template: String, options: NSRegularExpression.Options = []) -> String {
        guard let regex = RegexCache.regex(pattern, options: options) else { return self }
        return regex.stringByReplacingMatches(in: self, range: fullRange, withTemplate: template)
    }

    func collapsingWhitespace() -> String {
        replacingPattern(#"\s+"#, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func captures(of match: NSTextCheckingResult) -> [String?] {
        (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: self) else { return nil }
            return String(self[swiftRange])
        }
    }
}
