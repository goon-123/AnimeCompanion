import Foundation

/// Add-on text is display data, never an expression to evaluate. Keep diagnostics out of source rows.
public enum PlaybackSourceText {
    public static func clean(_ raw: String?, maximumLines: Int = 4, maximumCharacters: Int = 280) -> String? {
        guard let raw, maximumLines > 0, maximumCharacters > 0 else { return nil }
        let text = String(raw.prefix(8_192))
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: " ")
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        var seen = Set<String>()
        let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
            let lower = line.lowercased()
            guard !["invalid expression", "template error", "syntaxerror", "referenceerror", "typeerror", "{{", "}}", "${", "<%", "%>"].contains(where: { lower.contains($0) }) else { return nil }
            let printable = String(line.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard !printable.isEmpty, seen.insert(printable).inserted else { return nil }
            return printable
        }
        guard !lines.isEmpty else { return nil }
        let result = lines.prefix(maximumLines).joined(separator: "\n")
        return result.count > maximumCharacters ? String(result.prefix(maximumCharacters)) + "…" : result
    }
}
