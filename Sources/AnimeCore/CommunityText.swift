import Foundation
import SwiftSoup

public enum CommunityTextSegment: Equatable, Sendable {
    case text(String)
    case spoiler(String)
    case image(URL, alt: String)
}

/// Native text and image blocks. HTML is parsed as data and never executed.
/// Spoiler extraction happens before image extraction, so hidden images are not requested.
public enum CommunityText {
    public static func imageURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    public static func segments(_ raw: String) -> [CommunityTextSegment] {
        let input = String(raw.prefix(100_000))
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var stored: [CommunityTextSegment] = []
        func token(_ piece: CommunityTextSegment) -> String {
            let marker = "AC\(nonce)S\(stored.count)END"
            stored.append(piece); return marker
        }
        var text = input
        let spoilerPatterns = [#"(?is)\[spoiler(?:=[^\]]*)?\](.*?)\[/spoiler\]"#,
                               #"(?s)~!(.*?)!~"#, #"(?s)>!(.*?)!<"#,
                               #"(?is)\[([^\]]*)\]\((?:/s|#s)\s+[\"'](.*?)[\"']\)"#]
        for pattern in spoilerPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let whole = Range(match.range, in: text), let content = Range(match.range(at: match.numberOfRanges - 1), in: text) else { continue }
                let replacement = token(.spoiler(String(text[content])))
                text.replaceSubrange(whole, with: replacement)
            }
        }
        do {
            let document = try SwiftSoup.parseBodyFragment(text)
            try document.select("script,style,noscript,iframe,object").remove()
            for element in try document.select("[class*=spoiler], [class*=Spoiler], details, spoiler, [data-spoiler]") {
                let content = try element.html()
                try element.text(token(.spoiler(content)))
            }
            for element in try document.select("img") {
                if let url = imageURL(try element.attr("src")) {
                    let alt = try element.attr("alt")
                    try element.before("\n" + token(.image(url, alt: alt.isEmpty ? "Discussion image" : alt)) + "\n")
                }
                try element.remove()
            }
            for element in try document.select("a[href]") {
                guard let url = imageURL(try element.attr("href")) else { continue }
                let label = try element.text()
                if !label.contains("AC\(nonce)") {
                    try element.text("[\(label.replacingOccurrences(of: "]", with: ""))](\(url.absoluteString))")
                }
            }
            for element in try document.select("br") { try element.before("\n") }
            for element in try document.select("p,div,li,blockquote,pre,h1,h2,h3,h4") {
                try element.prepend("\n"); try element.append("\n")
            }
            text = try document.body()?.text(trimAndNormaliseWhitespace: false) ?? text
        } catch {
            return [.spoiler(plain(input))]
        }
        // Root comments may be server-rendered HTML while raw-JSON replies still use AniList markup.
        let imagePatterns = [#"(?i)!\[([^\]]*)\]\((https://[^\s)]+)(?:\s+[\"'][^)]*[\"'])?\)"#,
                             #"(?i)(?<![\p{L}\p{N}_])img(?:\d+%?)?\((https://[^\s)]+)\)"#]
        for (index, pattern) in imagePatterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                let group = index == 0 ? 2 : 1
                guard let whole = Range(match.range, in: text), let link = Range(match.range(at: group), in: text), let url = imageURL(String(text[link])) else { continue }
                let alt = index == 0 ? Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? "Discussion image" : "Discussion image"
                let replacement = "\n" + token(.image(url, alt: alt)) + "\n"
                text.replaceSubrange(whole, with: replacement)
            }
        }
        if text.range(of: #"(?i)\[/?spoiler|~!|!~|>!|!<|\]\((?:/s|#s)"#, options: .regularExpression) != nil {
            // Remove broken delimiters from the reveal payload so tapping it cannot create another identical gate.
            let reveal = input.replacingOccurrences(of: #"(?i)\[/?spoiler[^\]]*\]|~!|!~|>!|!<"#, with: "", options: .regularExpression)
            return [.spoiler(reveal)]
        }
        func restore(_ value: String, depth: Int = 0) -> String {
            guard depth < 8 else { return "[Nested spoiler]" }
            var result = value
            for index in stored.indices {
                let marker = "AC\(nonce)S\(index)END"
                guard result.contains(marker) else { continue }
                let replacement: String
                switch stored[index] {
                case .text(let text): replacement = text
                case .spoiler(let text): replacement = "~!" + restore(text, depth: depth + 1) + "!~"
                case .image(let url, _): replacement = "img(\(url.absoluteString))"
                }
                result = result.replacingOccurrences(of: marker, with: replacement)
            }
            return result
        }
        guard let regex = try? NSRegularExpression(pattern: "AC\(nonce)S(\\d+)END") else { return [.text(plain(text))] }
        var pieces: [CommunityTextSegment] = []
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let indexRange = Range(match.range(at: 1), in: text), let index = Int(text[indexRange]), stored.indices.contains(index) else { continue }
            if cursor < range.lowerBound { appendText(String(text[cursor..<range.lowerBound]), to: &pieces) }
            if case .spoiler(let value) = stored[index] { pieces.append(.spoiler(restore(value))) }
            else { pieces.append(stored[index]) }
            cursor = range.upperBound
        }
        if cursor < text.endIndex { appendText(String(text[cursor...]), to: &pieces) }
        return pieces.isEmpty ? [.text("[No text]")] : pieces
    }
    public static func preview(_ raw: String, limit: Int = 180) -> String {
        let visible = segments(raw).compactMap { piece -> String? in if case .text(let value) = piece { return value }; return nil }.joined(separator: " ")
        return String(visible.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[#*_~`]|\s+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(max(0, limit)))
    }
    public static func previewImage(_ raw: String) -> URL? {
        segments(raw).compactMap { piece -> URL? in if case .image(let url, _) = piece { return url }; return nil }.first
    }
    private static func appendText(_ value: String, to pieces: inout [CommunityTextSegment]) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { pieces.append(.text(clean)) }
    }
    private static func plain(_ value: String) -> String {
        (try? SwiftSoup.parseBodyFragment(value).body()?.text(trimAndNormaliseWhitespace: false)) ?? value
    }
}
