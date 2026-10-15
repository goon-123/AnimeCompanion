import Foundation

public enum StreamAudioFilter: String, Codable, CaseIterable, Sendable {
    case all, english, japanese
    public var label: String {
        switch self { case .all: return "All audio"; case .english: return "English"; case .japanese: return "Japanese" }
    }
    public func includes(_ audio: StreamAudioInfo) -> Bool {
        switch self { case .all: return true; case .english: return audio.english; case .japanese: return audio.japanese }
    }
}

/// These are per-source audio reports, never the anime's general dub availability or subtitle tracks.
public struct StreamAudioInfo: Equatable, Sendable {
    public let english: Bool
    public let japanese: Bool
    public let multiAudio: Bool
    public var label: String {
        if english && japanese { return "EN + JA · English & Japanese audio" }
        if english { return "EN · English audio" }
        if japanese { return "JA · Japanese audio" }
        return multiAudio ? "Multi audio · English unconfirmed" : "Audio language unlisted"
    }
    public var searchableText: String { label + (english ? " eng" : "") + (japanese ? " jpn" : "") }

    public init(texts: [String]) {
        // AIOStreams can emit small-cap ISO codes (ᴇɴ / ᴊᴀ), names or flag emojis.
        let small = Array("ᴀʙᴄᴅᴇꜰɢʜɪᴊᴋʟᴍɴᴏᴘǫʀꜱᴛᴜᴠᴡxʏᴢ")
        let plain = Array("abcdefghijklmnopqrstuvwxyz")
        let mapping = Dictionary(uniqueKeysWithValues: zip(small, plain))
        let normalized = texts.map { text in
            String(PlaybackSourceText.readable(text).precomposedStringWithCompatibilityMapping.lowercased().map { mapping[$0] ?? $0 })
        }.joined(separator: "\n")
        multiAudio = Self.matches(#"\b(?:dual[ ._-]*audio|multi[ ._-]*audio)\b"#, in: normalized)
        let candidates = normalized.components(separatedBy: .newlines).map { original in
            var line = original
            // Erase unresolved formatter code before looking for language values.
            line = Self.removing(#"\$?\{[^\n]*?\}"#, from: line)
            if line.contains("invalid expression") || line.contains("syntaxerror") || line.contains("typeerror") || line.contains("referenceerror") { return "" }
            // English subtitles do not make a stream an English dub. AIOStreams uses 📝 for subtitles.
            let language = #"(?:en(?:[-_](?:us|gb))?|eng|english|ja|jpn|japanese|fr|fra|fre|french|es|spa|spanish|de|deu|ger|german|pt|por|portuguese|🇺🇸|🇬🇧|🇯🇵)"#
            line = Self.removing(#"(?i)(?<![\p{L}\p{N}])"# + language + #"(?:\s*(?:[/,&+]|and)\s*"# + language + #")*[ ._-]+(?:subtitles?|subs?|subbed|cc|sdh)\b(?!\s*[:=])"#, from: line)
            line = Self.removing(#"(?i)\b(?:en|eng|english)\s*\(\s*(?:subtitles?|subs?|cc|sdh)\s*\)"#, from: line)
            line = Self.removing(#"(?i)(?:\b(?:subtitles?|subs?|cc|sdh)\s*[:=/\-]?|📝|💬)[^\n]*?(?=\b(?:audio|languages?)\s*[:=]|$)"#, from: line)
            line = Self.removing(#"(?i)\b(?:no|without|not)\s+(?:english|en|eng)(?:\s+(?:audio|dub))?\b|\benglish\s+(?:audio|dub)\s+(?:not available|unavailable|absent)\b"#, from: line)
            return line
        }.joined(separator: "\n")
        english = Self.matches(#"(?<![\p{L}\p{N}])(?:en(?:[-_](?:us|gb|au))?|eng|english)(?![\p{L}\p{N}])|🇺🇸|🇬🇧"#, in: candidates)
        japanese = Self.matches(#"(?<![\p{L}\p{N}])(?:ja(?:[-_]jp)?|jpn|japanese)(?![\p{L}\p{N}])|🇯🇵"#, in: candidates)
    }
    private static func matches(_ pattern: String, in text: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
    private static func removing(_ pattern: String, from text: String) -> String { text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression) }
}

public struct StreamSourceMetadata: Equatable, Sendable {
    public let audio: StreamAudioInfo
    public let quality: String?
    public let size: String?
    public let codec: String?
    public var technicalSummary: String { [quality, codec, size].compactMap { $0 }.joined(separator: " · ") }
    public init(stream: StremioStream) {
        // Inspect every original field, not just the first cleaned/truncated description.
        let texts = [stream.name, stream.description, stream.title, stream.behaviorHints?.filename].compactMap { $0 }
        audio = StreamAudioInfo(texts: texts)
        let text = texts.map(PlaybackSourceText.readable).joined(separator: "\n")
        quality = Self.first(#"(?i)(?<!\d)(?:4320p|2160p|1440p|1080[pi]|720p|576p|480p|4k|8k)\b"#, in: text)?.uppercased().replacingOccurrences(of: "P", with: "p").replacingOccurrences(of: "I", with: "i")
        size = Self.first(#"(?i)\b\d+(?:[.,]\d+)?\s*(?:[KMGT]i?B)\b"#, in: text)
        let rawCodec = Self.first(#"(?i)\b(?:hevc|avc|[xh][ ._-]?26[45]|av1)\b"#, in: text)?.lowercased()
        codec = rawCodec.map { $0.contains("265") || $0 == "hevc" ? "HEVC" : ($0.contains("264") || $0 == "avc" ? "H.264" : "AV1") }
    }
    private static func first(_ pattern: String, in text: String) -> String? {
        text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
    }
}

public enum StreamSourceSelection {
    /// Keep provider order within each audio group and retain original indices for source actions.
    public static func indices(in streams: [StremioStream], audio: StreamAudioFilter = .all,
                               playableOnly: Bool = true, search: String = "") -> [Int] {
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = streams.map(StreamSourceMetadata.init)
        return streams.indices.filter { index in
            let stream = streams[index], info = metadata[index]
            return (!playableOnly || stream.unavailableReason == nil) && audio.includes(info.audio) &&
                (search.isEmpty || (stream.displayName + " " + stream.details + " " + info.audio.searchableText + " " + info.technicalSummary).localizedCaseInsensitiveContains(search))
        }.sorted { first, second in
            let a = metadata[first].audio.english
            let b = metadata[second].audio.english
            return a == b ? first < second : a && !b
        }
    }
}
