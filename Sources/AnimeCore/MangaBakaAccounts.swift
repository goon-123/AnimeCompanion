import Foundation

/// Safe to publish to account pickers: no tokens or refresh credentials.
public struct MangaBakaAccountIdentity: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let profile: MangaBakaProfile?
    public var name: String { profile?.name ?? "Saved MangaBaka account" }
}

/// Persist the complete registry only in the device Keychain. Selection and
/// credential replacement are committed together before publishing a switch.
public struct MangaBakaAccounts: Codable, Equatable, Sendable {
    public struct Session: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public fileprivate(set) var profile: MangaBakaProfile?
        public fileprivate(set) var credential: MangaBakaCredential
        public var identity: MangaBakaAccountIdentity { .init(id: id, profile: profile) }
    }
    public private(set) var sessions: [Session]
    public private(set) var selectedID: UUID?
    public var selected: Session? { sessions.first { $0.id == selectedID } }
    public var identities: [MangaBakaAccountIdentity] { sessions.map(\.identity) }
    public init(legacy: MangaBakaCredential? = nil) {
        if let legacy {
            let session = Session(id: UUID(), profile: nil, credential: legacy)
            sessions = [session]; selectedID = session.id
        } else { sessions = []; selectedID = nil }
    }
    private enum CodingKeys: String, CodingKey { case schema, sessions, selectedID }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schema) == 1 else { throw MangaBakaError.invalidResponse }
        sessions = try c.decode([Session].self, forKey: .sessions)
        selectedID = try c.decodeIfPresent(UUID.self, forKey: .selectedID)
        let profiles = sessions.compactMap { $0.profile?.id }
        guard Set(sessions.map(\.id)).count == sessions.count, Set(profiles).count == profiles.count,
              sessions.isEmpty ? selectedID == nil : selected != nil else { throw MangaBakaError.invalidResponse }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .schema); try c.encode(sessions, forKey: .sessions)
        try c.encodeIfPresent(selectedID, forKey: .selectedID)
    }
    /// A sign-in for an already saved server identity refreshes that row.
    @discardableResult
    public mutating func add(profile: MangaBakaProfile, credential: MangaBakaCredential) -> UUID {
        if let index = sessions.firstIndex(where: { $0.profile?.id == profile.id || ($0.profile == nil && $0.credential == credential) }) {
            sessions[index].profile = profile; sessions[index].credential = credential
            selectedID = sessions[index].id
        } else {
            let value = Session(id: UUID(), profile: profile, credential: credential)
            sessions.append(value); selectedID = value.id
        }
        return selectedID!
    }
    public mutating func select(_ id: UUID) throws {
        guard sessions.contains(where: { $0.id == id }) else { throw MangaBakaError.message("This MangaBaka account is no longer saved.") }
        selectedID = id
    }
    public mutating func updateCredential(_ credential: MangaBakaCredential, for id: UUID) throws {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { throw MangaBakaError.invalidResponse }
        sessions[index].credential = credential
    }
    /// Bind a migrated, previously unnamed session to its verified server ID.
    /// Merge a duplicate identity without replacing any other person's session.
    @discardableResult
    public mutating func updateProfile(_ profile: MangaBakaProfile, for id: UUID) throws -> UUID {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              sessions[index].profile.map({ $0.id == profile.id }) ?? true else { throw MangaBakaError.invalidResponse }
        if let duplicate = sessions.firstIndex(where: { $0.id != id && $0.profile?.id == profile.id }) {
            let selected = selectedID == id, destination = sessions[duplicate].id
            sessions[duplicate].profile = profile
            sessions[duplicate].credential = sessions[index].credential
            sessions.remove(at: index)
            if selected { selectedID = destination }
            return destination
        }
        sessions[index].profile = profile
        return id
    }
    public mutating func remove(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if selectedID == id { selectedID = sessions.first?.id }
    }
}
