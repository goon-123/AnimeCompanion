import Foundation
import CZlib

public struct MangaExtensionCatalog: Codable, Sendable {
    public let name: String
    public let signingKey: String
    public var extensions: [MangaExtensionDescriptor]

    /// Keiyoushi's current index: gzip-compressed protobuf. Unknown protobuf
    /// fields are skipped so additive upstream schema changes remain readable.
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 8_000_000 else { throw MangaExtensionError.oversized }
        let decoded = try gunzipIfNeeded(data)
        let root = try Fields(decoded)
        let name = try root.string(1), signingKey = try root.string(3).lowercased()
        guard name == "Keiyoushi", signingKey == MangaRepository.fingerprint,
              let listData = root.bytes(101), root.bytes(102) == nil else { throw MangaExtensionError.invalidCatalog }
        let list = try Fields(listData)
        let entries = try list.allBytes(1).map { try descriptor(Fields($0)) }
        guard !entries.isEmpty, entries.count <= 10_000, Set(entries.map(\.id)).count == entries.count else { throw MangaExtensionError.invalidCatalog }
        return Self(name: name, signingKey: signingKey, extensions: entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    private static func descriptor(_ fields: Fields) throws -> MangaExtensionDescriptor {
        let name = try fields.string(1), package = try fields.string(2), api = try fields.string(4)
        let version = try fields.string(6), code = Int64(bitPattern: fields.integer(5))
        guard let resourcesData = fields.bytes(3), !name.isEmpty, !version.isEmpty, code > 0,
              package.range(of: "^eu\\.kanade\\.tachiyomi\\.extension\\.[A-Za-z0-9_.]+$", options: .regularExpression) != nil,
              fields.integer(7) <= 3 else { throw MangaExtensionError.invalidCatalog }
        let resources = try Fields(resourcesData)
        let apkString = try resources.string(1)
        guard let apk = URL(string: apkString), let p = URLComponents(url: apk, resolvingAgainstBaseURL: false),
              p.scheme == "https", p.host == "github.com", p.user == nil, p.password == nil,
              p.query == nil, p.fragment == nil, p.port == nil,
              p.path.hasPrefix("/keiyoushi/extensions/releases/download/"), p.path.hasSuffix(".apk"),
              !p.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { throw MangaExtensionError.invalidCatalog }
        let icon = try resources.string(2)
        let sources = try fields.allBytes(8).map { data -> MangaSourceDescriptor in
            let source = try Fields(data)
            return MangaSourceDescriptor(id: String(Int64(bitPattern: source.integer(1))), name: try source.string(2),
                language: try source.string(3), homeURL: try source.string(4))
        }
        guard !sources.isEmpty, sources.count <= 512 else { throw MangaExtensionError.invalidCatalog }
        return MangaExtensionDescriptor(name: name, packageName: package, apiVersion: api, versionCode: code,
            versionName: version, apkURL: apk, iconURL: URL(string: icon), contentWarning: Int(fields.integer(7)), sources: sources, sha256: nil)
    }

    private static func gunzipIfNeeded(_ data: Data) throws -> Data {
        guard data.starts(with: [0x1f, 0x8b]) else { return data }
        var stream = z_stream()
        guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw MangaExtensionError.invalidCatalog }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { raw -> Data in
            stream.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            var output = Data(), buffer = [UInt8](repeating: 0, count: 16_384)
            while true {
                let (status, written) = buffer.withUnsafeMutableBytes { block -> (Int32, Int) in
                    stream.next_out = block.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(block.count)
                    let code = inflate(&stream, Z_NO_FLUSH)
                    return (code, block.count - Int(stream.avail_out))
                }
                guard output.count + written <= 16_000_000 else { throw MangaExtensionError.oversized }
                output.append(contentsOf: buffer.prefix(written))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else { throw MangaExtensionError.invalidCatalog }
                    return output
                }
                guard status == Z_OK, written > 0 else { throw MangaExtensionError.invalidCatalog }
            }
        }
    }
}

/// The small index schema needs length-delimited values and int64s, not a
/// generated dependency. Int64 IDs never pass through Double/NSNumber.
private struct Fields {
    private enum Value { case bytes(Data), integer(UInt64) }
    private var fields: [Int: [Value]] = [:]
    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        var offset = 0
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            for index in 0..<10 {
                guard offset < bytes.count else { throw MangaExtensionError.invalidCatalog }
                let byte = bytes[offset]; offset += 1
                guard index < 9 || byte <= 1 else { throw MangaExtensionError.invalidCatalog }
                result |= UInt64(byte & 0x7f) << (index * 7)
                if byte & 0x80 == 0 { return result }
            }
            throw MangaExtensionError.invalidCatalog
        }
        while offset < bytes.count {
            let key = try varint(), field = key >> 3, wire = key & 7
            guard field > 0, field < 1 << 29 else { throw MangaExtensionError.invalidCatalog }
            switch wire {
            case 0: fields[Int(field), default: []].append(.integer(try varint()))
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - offset) else { throw MangaExtensionError.invalidCatalog }
                let end = offset + Int(length)
                fields[Int(field), default: []].append(.bytes(Data(bytes[offset..<end]))); offset = end
            case 1, 5:
                let count = wire == 1 ? 8 : 4
                guard offset + count <= bytes.count else { throw MangaExtensionError.invalidCatalog }
                offset += count
            default: throw MangaExtensionError.invalidCatalog
            }
        }
    }
    func bytes(_ field: Int) -> Data? { if case .bytes(let value) = fields[field]?.last { return value }; return nil }
    func integer(_ field: Int) -> UInt64 { if case .integer(let value) = fields[field]?.last { return value }; return 0 }
    func string(_ field: Int) throws -> String {
        guard let data = bytes(field) else { return "" }
        guard let text = String(data: data, encoding: .utf8) else { throw MangaExtensionError.invalidCatalog }
        return text
    }
    func allBytes(_ field: Int) throws -> [Data] {
        try (fields[field] ?? []).map { value in
            guard case .bytes(let data) = value else { throw MangaExtensionError.invalidCatalog }
            return data
        }
    }
}
