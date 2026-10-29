import Foundation
import SwiftSoup

public enum CommunityTextSegment: Equatable, Sendable {
    case text(String)
    case spoiler(String)
}

/// Native text only: no script execution, inline image loading or hidden accessibility text.
/// Unsupported/unbalanced spoiler delimiters fail closed by hiding the entire comment.
public enum CommunityText {
    public static func segments(_ raw: String) -> [CommunityTextSegment] {
        let input = String(raw.prefix(100_000))
        var hidden: [String] = []
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        func token(_ content: String) -> String {
            let value = "AC\(nonce)S\(hidden.count)END"
            hidden.append(content)
            return value
        }
        var text = input
        let patterns = [#"(?is)\[spoiler(?:=[^\]]*)?\](.*?)\[/spoiler\]"#,
                        #"(?s)~!(.*?)!~"#, #"(?s)>!(.*?)!<"#,
                        #"(?is)\[([^\]]*)\]\((?:/s|#s)\s+[\"'](.*?)[\"']\)"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let whole = Range(match.range, in: text), let content = Range(match.range(at: match.numberOfRanges - 1), in: text) else { continue }
                let replacement = token(String(text[content]))
                text.replaceSubrange(whole, with: replacement)
            }
        }
        do {
            let document = try SwiftSoup.parseBodyFragment(text)
            try document.select("script,style,noscript").remove()
            for element in try document.select("[class*=spoiler], [class*=Spoiler], details, spoiler, [data-spoiler]") {
                let content = try element.text()
                try element.text(token(content))
            }
            for element in try document.select("br") { try element.before("\n") }
            for element in try document.select("p,div,li,blockquote,pre") {
                try element.prepend("\n"); try element.append("\n")
            }
            text = try document.body()?.text(trimAndNormaliseWhitespace: false) ?? text
        } catch {
            if input.localizedCaseInsensitiveContains("spoiler") || !hidden.isEmpty { return [.spoiler(plain(input))] }
            text = plain(input)
        }
        if text.range(of: #"(?i)\[/?spoiler|~!|!~|>!|!<|\]\((?:/s|#s)"#, options: .regularExpression) != nil {
            return [.spoiler(plain(input))]
        }
        func reveal(_ value: String, depth: Int = 0) -> String {
            guard depth < 8 else { return "[Nested spoiler]" }
            var result = value
            for index in hidden.indices {
                let marker = "AC\(nonce)S\(index)END"
                if result.contains(marker) { result = result.replacingOccurrences(of: marker, with: reveal(hidden[index], depth: depth + 1)) }
            }
            return plain(result)
        }
        let pattern = "AC\(nonce)S(\\d+)END"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [.text(text)] }
        var pieces: [CommunityTextSegment] = []
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let indexRange = Range(match.range(at: 1), in: text), let index = Int(text[indexRange]), hidden.indices.contains(index) else { continue }
            if cursor < range.lowerBound { pieces.append(.text(String(text[cursor..<range.lowerBound]))) }
            pieces.append(.spoiler(reveal(hidden[index])))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { pieces.append(.text(String(text[cursor...]))) }
        return pieces.isEmpty ? [.text("[No text]")] : pieces
    }
    private static func plain(_ value: String) -> String {
        (try? SwiftSoup.parseBodyFragment(value).body()?.text(trimAndNormaliseWhitespace: false)) ?? value
    }
}
