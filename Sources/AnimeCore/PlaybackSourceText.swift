import Foundation

/// Add-on text is display data, never an expression to evaluate. Keep diagnostics out of source rows.
public enum PlaybackSourceText {
    /// Remove only the broken expression, preserving audio/quality text on the same line.
    /// Parentheses are scanned as text and are never evaluated.
    public static func readable(_ raw: String) -> String {
        let text = String(raw.prefix(65_536)).replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: " ")
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        return text.components(separatedBy: .newlines).map { original in
            var line = original
            while let marker = line.range(of: #"(?i)(?:invalid expression|template error)\s*\("#, options: .regularExpression) {
                var depth = 1, end = marker.upperBound
                var quote: Character?, escaped = false
                while end < line.endIndex && depth > 0 {
                    let character = line[end]
                    if escaped { escaped = false }
                    else if character == "\\" { escaped = true }
                    else if let active = quote { if character == active { quote = nil } }
                    else if character == "\"" || character == "'" { quote = character }
                    else if character == "(" { depth += 1 }
                    else if character == ")" { depth -= 1 }
                    end = line.index(after: end)
                }
                line.replaceSubrange(marker.lowerBound..<end, with: " ")
            }
            return line
        }.joined(separator: "\n")
    }

    public static func clean(_ raw: String?, maximumLines: Int = 4, maximumCharacters: Int = 280) -> String? {
        guard let raw, maximumLines > 0, maximumCharacters > 0 else { return nil }
        let text = readable(raw)
        var seen = Set<String>()
        let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
            let lower = line.lowercased()
            guard !["invalid expression", "template error", "syntaxerror", "referenceerror", "typeerror", "{{", "}}", "${", "<%", "%>"].contains(where: { lower.contains($0) }) else { return nil }
            let printable = String(line.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " ·|,;–—"))
            guard !printable.isEmpty, seen.insert(printable).inserted else { return nil }
            return printable
        }
        guard !lines.isEmpty else { return nil }
        let result = lines.prefix(maximumLines).joined(separator: "\n")
        return result.count > maximumCharacters ? String(result.prefix(maximumCharacters)) + "…" : result
    }
}
