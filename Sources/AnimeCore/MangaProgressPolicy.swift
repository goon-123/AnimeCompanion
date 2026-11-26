import Foundation

public enum MangaProgressPolicy {
    public static let maximumChapter = 10000.0
    /// A new link, replacement source or different account requires fresh consent.
    public static func consentKey(for link: MangaSourceLink) -> String {
        "manga.progress.automatic." + link.id + "." + link.title.id + "." + String(link.updatedAt.timeIntervalSince1970)
    }
    public static func link(for titleID: String, accountID: String?, links: [MangaSourceLink]) -> MangaSourceLink? {
        guard let accountID else { return nil }
        return links.filter { $0.library.accountID == accountID && $0.title.id == titleID }
            .max { $0.updatedAt < $1.updatedAt }
    }
    public static func automaticChapter(_ chapter: SourceMangaChapter) -> Double? {
        let name = chapter.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let special = #"(?i)\b(extra|bonus|special|omake|prologue|epilogue|one[- ]?shot|volume|part|fragment)\b"#
        if name.range(of: special, options: .regularExpression) != nil { return nil }
        let pattern = #"(?i)^(?:chapter|chap|ch\.?|episode|ep\.?)\s*#?\s*(\d+(?:\.\d+)?)(?:\s*[:\-–].*|\s*)$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let parsed: Double? = regex?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)).flatMap {
            Range($0.range(at: 1), in: name).flatMap { Double(name[$0]) }
        }
        let explicit = chapter.chapterNumber.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        guard let value = explicit ?? parsed, value > 0, value <= maximumChapter, value.rounded(.down) == value,
              parsed.map({ explicit == nil || $0 == explicit }) ?? true else { return nil }
        return value
    }
    public static func automaticLink(for titleID: String, accountID: String?, links: [MangaSourceLink], enabledKeys: Set<String>) -> MangaSourceLink? {
        guard let accountID else { return nil }
        let matches = links.filter { $0.library.accountID == accountID && $0.title.id == titleID && enabledKeys.contains(consentKey(for: $0)) }
        return matches.count == 1 ? matches.first : nil
    }
    public static func shouldAdvance(current: Double?, proposed: Double) -> Bool {
        proposed.isFinite && proposed > 0 && proposed <= maximumChapter && proposed > (current ?? 0)
    }
}

/// The automatic/manual reader action must never overwrite unrelated tracking fields.
public struct MangaBakaProgressUpdate: Encodable, Sendable {
    public let chapter: Double
    public init(chapter: Double) throws {
        guard chapter.isFinite, chapter > 0, chapter <= MangaProgressPolicy.maximumChapter else {
            throw MangaBakaError.message("Enter a chapter greater than 0 and no higher than 10,000.")
        }
        self.chapter = chapter
    }
    private enum CodingKeys: String, CodingKey { case chapter = "progress_chapter" }
}
