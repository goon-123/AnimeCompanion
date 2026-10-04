import Foundation

public enum NewsPeriod: String, CaseIterable, Codable, Sendable {
    case week, month
    public var label: String { self == .week ? "This week" : "This month" }
    public var days: Int { self == .week ? 7 : 30 }
}
public struct NewsRead: Codable, Sendable {
    public let article: NewsArticle
    public let date: Date
}
public struct PopularNewsArticle: Identifiable, Sendable {
    public let article: NewsArticle
    public let opens: Int
    public var id: String { article.id }
}
/// Local reading history, not an invented publisher-wide popularity metric.
public struct NewsReadingHistory: Codable, Sendable {
    public private(set) var reads: [NewsRead]
    public init() { reads = [] }
    public mutating func record(_ article: NewsArticle, at date: Date = Date()) {
        reads.removeAll { $0.date < date.addingTimeInterval(-90 * 86400) }
        reads.append(NewsRead(article: article, date: date))
        if reads.count > 500 { reads = Array(reads.suffix(500)) }
    }
    public func popular(in period: NewsPeriod, now: Date = Date(), calendar: Calendar = .current) -> [PopularNewsArticle] {
        let start = calendar.date(byAdding: .day, value: -period.days, to: now) ?? now.addingTimeInterval(Double(-period.days * 86400))
        let groups = Dictionary(grouping: reads.filter { $0.date >= start && $0.date <= now }, by: { $0.article.id })
        return groups.values.compactMap { group -> PopularNewsArticle? in
            guard let latest = group.max(by: { $0.date < $1.date }) else { return nil }
            return PopularNewsArticle(article: latest.article, opens: group.count)
        }.sorted { $0.opens == $1.opens ? $0.article.id < $1.article.id : $0.opens > $1.opens }
    }
}
