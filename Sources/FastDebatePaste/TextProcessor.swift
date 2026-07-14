import Foundation

/// Ports the original script's ProcessText: detects "card" text that
/// is really a stray number / short equation reference and replaces it
/// with a bracketed OMITTED marker, the debate convention for omitting
/// equations and figures from a card.
enum TextProcessor {
    /// Returns the processed text. If nothing matched, returns the
    /// input unchanged (so callers can detect "was it transformed?").
    static func process(_ text: String) -> String {
        // 1. Pure number (integer, decimal, or dotted/dashed run).
        if fullMatch(text, pattern: "^\\d+([.-]\\d+)*$") {
            return "[EQUATION \(text) OMITTED]"
        }
        // 2. A short token followed by a number, e.g. "Fig. 3.2-4".
        if let groups = capture(text,
                                pattern: "^(\\w+\\.?)\\s+([\\d.-]+(?:[.-][\\d.-]+)*)$",
                                options: [.caseInsensitive]),
           groups.count >= 3 {
            let body = "\(groups[1]) \(groups[2]) OMITTED".uppercased()
            return "[\(body)]"
        }
        return text
    }

    /// Remove line breaks the way the "no line breaks" actions do:
    /// a break flanked by non-whitespace becomes a single space;
    /// every remaining break is deleted.
    static func stripLineBreaks(_ text: String) -> String {
        let nl = "(?:\\r\\n|\\r|\\n)"
        var out = replace(text,
                          pattern: "(?<![\\s])\(nl)(?![\\s])",
                          with: " ")
        out = replace(out, pattern: nl, with: "")
        return out
    }

    // MARK: - Regex helpers

    private static func fullMatch(_ text: String, pattern: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return re.firstMatch(in: text, range: range) != nil
    }

    private static func capture(_ text: String,
                                pattern: String,
                                options: NSRegularExpression.Options) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for i in 0..<m.numberOfRanges {
            if let r = Range(m.range(at: i), in: text) {
                groups.append(String(text[r]))
            } else {
                groups.append("")
            }
        }
        return groups
    }

    private static func replace(_ text: String, pattern: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return re.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
