import Foundation

public enum MangaExtensionError: LocalizedError, Equatable {
    case invalidSourceSettings
    case invalidRepository, invalidCatalog, oversized, checksumUnavailable, checksumMismatch, packageMismatch, unsupportedAPI, sourceUnavailable, runtimeUnavailable, runtimeFailure
    public var errorDescription: String? {
        switch self {
        case .invalidSourceSettings: return "These source settings could not be saved. Check the values and try again."
        case .invalidRepository: return "Use the Keiyoushi website, GitHub repository, repo.json or index.pb link."
        case .invalidCatalog: return "Keiyoushi returned an unreadable extension catalog. Try refreshing it."
        case .oversized: return "This extension response exceeds the device’s size limit."
        case .checksumUnavailable: return "A matching package checksum is unavailable. Refresh the catalog before installing."
        case .checksumMismatch: return "The downloaded package did not match its published checksum. Refresh the catalog and try again."
        case .packageMismatch: return "The package identity or version did not match this extension. The previous version is unchanged."
        case .unsupportedAPI: return "This extension needs a different version of the source runtime."
        case .sourceUnavailable: return "This source is unavailable or has been removed. Refresh the extension catalog."
        case .runtimeUnavailable: return "The on-device manga runtime is missing from this build. Install a build that includes it."
        case .runtimeFailure: return "This source could not run on this device. It may need a runtime update or the website may be unavailable."
        }
    }
}

/// The requested repository only. Old install links deliberately resolve to v2;
/// Keiyoushi's legacy index.min.json now contains outdated-app placeholders.
public struct MangaRepository: Codable, Equatable, Sendable {
    public static let keiyoushi = try! MangaRepository("https://keiyoushi.github.io")
    public static let fingerprint = "9add655a78e96c4ec7a53ef89dccb557cb5d767489fac5e785d671a5a75d4da2"
    public let indexURL: URL
    public let checksumsURL: URL
    public init(_ input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = URLComponents(string: value), p.scheme?.lowercased() == "https",
              p.user == nil, p.password == nil, p.query == nil, p.fragment == nil,
              p.port == nil || p.port == 443 else { throw MangaExtensionError.invalidRepository }
        let host = p.host?.lowercased() ?? ""
        let path = p.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let valid: Bool
        if host == "keiyoushi.github.io" { valid = path.isEmpty || path == "extensions" }
        else if host == "github.com" {
            valid = ["keiyoushi/extensions", "keiyoushi/extensions/tree/repo", "keiyoushi/extensions/raw/repo", "keiyoushi/extensions/raw/refs/heads/repo"].contains(path)
                || ["raw/repo", "raw/refs/heads/repo", "blob/repo"].contains { prefix in
                    ["index.pb", "repo.json", "index.json", "index.min.json"].contains { path == "keiyoushi/extensions/\(prefix)/\($0)" }
                }
        } else if host == "raw.githubusercontent.com" {
            valid = ["keiyoushi/extensions/repo", "keiyoushi/extensions/refs/heads/repo"].contains(path)
                || ["repo", "refs/heads/repo"].contains { prefix in
                    ["index.pb", "repo.json", "index.json", "index.min.json"].contains { path == "keiyoushi/extensions/\(prefix)/\($0)" }
                }
        } else { valid = false }
        guard valid else { throw MangaExtensionError.invalidRepository }
        indexURL = URL(string: "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb")!
        checksumsURL = URL(string: "https://raw.githubusercontent.com/keiyoushi/extensions/repo/release-assets.json")!
    }
}

public struct MangaSourceDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public let homeURL: String
    public init(id: String, name: String, language: String, homeURL: String) {
        self.id = id; self.name = name; self.language = language; self.homeURL = homeURL
    }
}

public struct MangaExtensionDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String { packageName }
    public let name: String
    public let packageName: String
    public let apiVersion: String
    public let versionCode: Int64
    public let versionName: String
    public let apkURL: URL
    public let iconURL: URL?
    public let contentWarning: Int
    public let sources: [MangaSourceDescriptor]
    public var sha256: String?
    public var supportsRuntime: Bool { ["1.4", "1.5", "1.6"].contains(apiVersion) }
    public var modernAPI: Bool { apiVersion == "1.6" }
    public var adult: Bool { contentWarning == 2 || contentWarning == 3 }
    public var languages: [String] { Array(Set(sources.map(\.language))).sorted() }
    public func matches(query: String, language: String, includeAdult: Bool) -> Bool {
        guard includeAdult || !adult else { return false }
        guard language.isEmpty || sources.contains(where: { $0.language == language || $0.language == "all" }) else { return false }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || name.localizedCaseInsensitiveContains(text) || sources.contains { $0.name.localizedCaseInsensitiveContains(text) }
    }
}

public struct MangaRuntimeSource: Codable, Equatable, Identifiable, Sendable {
    public let index: Int
    public let id: String
    public let name: String
    public let language: String
    public let homeURL: String
    public let supportsLatest: Bool
    public init(index: Int, id: String, name: String, language: String, homeURL: String, supportsLatest: Bool) {
        self.index = index; self.id = id; self.name = name; self.language = language
        self.homeURL = homeURL; self.supportsLatest = supportsLatest
    }
}

public struct MangaExtensionInspection: Codable, Sendable {
    public let packageName: String
    public let versionName: String?
    public let sources: [MangaRuntimeSource]
    public func validate(against entry: MangaExtensionDescriptor) throws {
        guard packageName == entry.packageName, versionName == entry.versionName,
              !sources.isEmpty, sources.count <= 512,
              Set(sources.map(\.index)).count == sources.count,
              sources.allSatisfy({ $0.index >= 0 && !$0.name.isEmpty && !$0.language.isEmpty }) else { throw MangaExtensionError.packageMismatch }
    }
}

public struct InstalledMangaExtension: Codable, Identifiable, Sendable {
    public var id: String { descriptor.id }
    public let descriptor: MangaExtensionDescriptor
    public let sources: [MangaRuntimeSource]
    public let installedAt: Date
    public var enabled: Bool
    /// Content-addressed filename: no repository-controlled path reaches the filesystem.
    public var filename: String { (descriptor.sha256 ?? "missing") + ".apk" }
    public init(descriptor: MangaExtensionDescriptor, inspection: MangaExtensionInspection, installedAt: Date = Date(), enabled: Bool = true) throws {
        try inspection.validate(against: descriptor)
        guard let digest = descriptor.sha256, digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw MangaExtensionError.checksumUnavailable }
        self.descriptor = descriptor; sources = inspection.sources; self.installedAt = installedAt; self.enabled = enabled
    }
}

/// Reader-facing data stays separate from AniList's anime-only models.
public struct SourceManga: Codable, Equatable, Identifiable, Sendable {
    public var id: String { url }
    public let url: String
    public let title: String
    public let author: String
    public let artist: String
    public let description: String
    public let genre: String
    public let status: Int
    public let thumbnailURL: String
    public init(url: String, title: String, author: String = "", artist: String = "", description: String = "",
                genre: String = "", status: Int = 0, thumbnailURL: String = "") {
        self.url = url; self.title = title; self.author = author; self.artist = artist
        self.description = description; self.genre = genre; self.status = status; self.thumbnailURL = thumbnailURL
    }
    public func merging(_ details: SourceManga) -> SourceManga {
        SourceManga(url: url, title: details.title.isEmpty ? title : details.title,
                    author: details.author.isEmpty ? author : details.author,
                    artist: details.artist.isEmpty ? artist : details.artist,
                    description: details.description.isEmpty ? description : details.description,
                    genre: details.genre.isEmpty ? genre : details.genre,
                    status: details.status == 0 ? status : details.status,
                    thumbnailURL: details.thumbnailURL.isEmpty ? thumbnailURL : details.thumbnailURL)
    }
}
public struct SourceMangaPage: Codable, Sendable {
    public let mangas: [SourceManga]; public let hasNext: Bool
    public init(mangas: [SourceManga], hasNext: Bool) { self.mangas = mangas; self.hasNext = hasNext }
}
public struct SourceMangaChapter: Codable, Hashable, Identifiable, Sendable {
    public var id: String { url }
    public let url: String
    public let name: String
    public let uploadedAt: Int64
    public let scanlator: String
    public let chapterNumber: Double?
    /// Opaque JSON provided by the extension; retains duplicate-chapter IDs.
    public let memo: String?
    public init(url: String, name: String, uploadedAt: Int64 = 0, scanlator: String = "", chapterNumber: Double? = nil, memo: String? = nil) {
        self.url = url; self.name = name; self.uploadedAt = uploadedAt; self.scanlator = scanlator; self.chapterNumber = chapterNumber
        self.memo = memo
    }
}
public struct SourceMangaImage: Codable, Hashable, Sendable {
    public let index: Int
    public let url: String
    public let imageURL: String
    public init(index: Int, url: String = "", imageURL: String) { self.index = index; self.url = url; self.imageURL = imageURL }
}
