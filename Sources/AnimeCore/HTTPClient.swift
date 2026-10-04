import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ServiceError: LocalizedError, Equatable {
    case http(Int), unauthorized, rateLimited(Int), message(String), invalidResponse
    public var errorDescription: String? {
        switch self {
        case .http(let code): return "The service returned HTTP \(code). Please try again."
        case .unauthorized: return "Your AniList connection expired. Please reconnect."
        case .rateLimited(let seconds): return "AniList is busy. Please try again in \(seconds) seconds."
        case .message(let message): return message
        case .invalidResponse: return "The service returned an unexpected response."
        }
    }
}

/// An injectable transport keeps real parsing and request behavior testable without live accounts.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
public struct URLSessionTransport: HTTPTransport {
    public let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        return (data, response)
    }
}

public enum HTTPValidation {
    public static func check(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw ServiceError.unauthorized
        case 429:
            throw ServiceError.rateLimited(max(1, Int(response.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60))
        default: throw ServiceError.http(response.statusCode)
        }
    }
}
