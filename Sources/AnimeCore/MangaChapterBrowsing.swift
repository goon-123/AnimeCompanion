import Foundation

public enum MangaChapterFilter: String, CaseIterable, Identifiable, Sendable {
    case all, unread, read
    public var id: String { rawValue }
    public var title: String { switch self { case .all: return "All"; case .unread: return "Unread"; case .read: return "Read" } }
}

public enum MangaChapterBrowsing {
    public static func chapters(_ chapters: [SourceMangaChapter], record: MangaReadingRecord?, query: String,
                                filter: MangaChapterFilter, newestFirst: Bool = false) -> [SourceMangaChapter] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let completed = Set((record?.positions ?? []).filter(\.completed).map(\.chapterURL))
        let result = chapters.filter { chapter in
            let matches = query.isEmpty || chapter.name.localizedCaseInsensitiveContains(query) ||
                chapter.chapterNumber.map { String(format: "%g", $0).localizedCaseInsensitiveContains(query) } == true
            return matches && (filter == .all || (filter == .read ? completed.contains(chapter.url) : !completed.contains(chapter.url)))
        }
        return newestFirst ? Array(result.reversed()) : result
    }
    public static func scanlator(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["", "unknown", "n/a", "none", "null", "?"].contains(text.lowercased()) ? nil : text
    }
}

extension MangaSourceReference {
    /// Some APKs return relative paths. Only share actual web addresses.
    public func webURL(for path: String) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("{"), !path.hasPrefix("["), path.contains("/"),
              let base = URL(string: homeURL),
              let url = URL(string: path, relativeTo: base)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}
