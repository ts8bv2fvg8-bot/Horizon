import Foundation
import SwiftUI

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
    var isUnauthorized: Bool { status == 401 }
}

/// Talks to the Horizon backend (backend/). Public endpoints work signed out; `/v1/me/*`
/// endpoints send the member's Planning Center access token so the backend can verify
/// who they are.
struct APIClient: Sendable {
    let baseURL: URL
    let auth: AuthManager?
    var session: URLSession = .shared

    init(baseURL: URL = AppConfig.apiBaseURL, auth: AuthManager?) {
        self.baseURL = baseURL
        self.auth = auth
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = ISO8601DateFormatter.withFractional.date(from: s) ?? ISO8601DateFormatter.plain.date(from: s) { return date }
            if let date = DateFormatter.dayOnly.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognized date \(s)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    func get<T: Decodable>(_ path: String, authenticated: Bool = false) async throws -> T {
        try await send("GET", path, body: Optional<Empty>.none, authenticated: authenticated)
    }

    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?, authenticated: Bool = true) async throws -> T {
        let data = try body.map { try Self.encoder.encode($0) }
        return try await raw(method, path, body: data, contentType: "application/json", authenticated: authenticated)
    }

    func raw<T: Decodable>(_ method: String, _ path: String, body: Data?, contentType: String, authenticated: Bool, retry: Bool = true) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: String(path.drop { $0 == "/" })))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            guard let token = try await auth?.validAccessToken() else {
                throw APIError(status: 401, message: "Sign in with Planning Center to continue.")
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, authenticated, retry, let auth {
            _ = try await auth.refresh()
            return try await raw(method, path, body: body, contentType: contentType, authenticated: authenticated, retry: false)
        }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Something went wrong. Please try again."
            throw APIError(status: status, message: message)
        }
        return try Self.decoder.decode(T.self, from: data)
    }
}

struct Empty: Codable {}

private struct APIClientKey: EnvironmentKey {
    static let defaultValue = APIClient(auth: nil)
}

extension EnvironmentValues {
    var api: APIClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}

extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain = ISO8601DateFormatter()
}

extension DateFormatter {
    static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
