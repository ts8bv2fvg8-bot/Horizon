import AuthenticationServices
import Foundation
import Observation
import UIKit

struct OAuthTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isExpired: Bool { expiresAt.addingTimeInterval(-60) < Date() }
}

private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
}

enum AuthError: LocalizedError {
    case cancelled, missingCode, stateMismatch, notConfigured, server(String)
    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign in was cancelled."
        case .missingCode, .stateMismatch: "Planning Center didn't complete sign in. Please try again."
        case .notConfigured: "Sign in isn't configured yet (missing Planning Center client ID)."
        case .server(let message): message
        }
    }
}

/// Signs members in with their Planning Center account using OAuth 2.0 + PKCE.
///
/// Flow: ASWebAuthenticationSession → https://api.planningcenteronline.com/oauth/authorize
/// → horizonchurch://oauth/callback?code=… → POST /oauth/token (code + code_verifier).
/// Access tokens last about two hours; refresh tokens are honored for 90 days, so members
/// stay signed in as long as they open the app at least once a quarter.
@MainActor
@Observable
final class AuthManager: NSObject {
    private(set) var tokens: OAuthTokens?
    var displayName: String?
    var avatarURL: URL?
    var isSignedIn: Bool { tokens != nil }

    private let keychainAccount = "pco"
    private var refreshTask: Task<OAuthTokens, Error>?
    private var webSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        tokens = KeychainStore.load(OAuthTokens.self, account: keychainAccount)
        displayName = UserDefaults.standard.string(forKey: "displayName")
    }

    // MARK: Sign in

    func signIn() async throws {
        guard !AppConfig.pcoClientID.isEmpty, !AppConfig.pcoClientID.hasPrefix("REPLACE") else { throw AuthError.notConfigured }
        let pkce = PKCE()
        let state = PKCE.randomURLSafeString(byteCount: 16)
        var components = URLComponents(url: AppConfig.pcoAuthorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: AppConfig.pcoClientID),
            .init(name: "redirect_uri", value: AppConfig.oauthRedirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: AppConfig.pcoScopes),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: pkce.method),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: AppConfig.oauthCallbackScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { continuation.resume(throwing: AuthError.cancelled) }
                else { continuation.resume(throwing: error ?? AuthError.missingCode) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            session.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw AuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw AuthError.missingCode }

        let newTokens = try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": AppConfig.pcoClientID,
            "redirect_uri": AppConfig.oauthRedirectURI,
            "code_verifier": pkce.verifier,
        ])
        store(newTokens)
    }

    func signOut() {
        if let refresh = tokens?.refreshToken {
            var request = URLRequest(url: AppConfig.pcoRevokeURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formEncode(["token": refresh, "client_id": AppConfig.pcoClientID])
            Task { _ = try? await URLSession.shared.data(for: request) }
        }
        tokens = nil
        displayName = nil
        avatarURL = nil
        KeychainStore.delete(account: keychainAccount)
        UserDefaults.standard.removeObject(forKey: "displayName")
    }

    func updateIdentity(name: String, avatar: URL?) {
        displayName = name
        avatarURL = avatar
        UserDefaults.standard.set(name, forKey: "displayName")
    }

    // MARK: Tokens

    /// A valid access token, refreshing if needed. Concurrent callers share one refresh.
    func validAccessToken() async throws -> String? {
        guard let current = tokens else { return nil }
        if !current.isExpired { return current.accessToken }
        return try await refresh().accessToken
    }

    @discardableResult
    func refresh() async throws -> OAuthTokens {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = tokens?.refreshToken else {
            signOut()
            throw AuthError.server("Your session expired. Please sign in again.")
        }
        let task = Task { () throws -> OAuthTokens in
            try await self.requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": AppConfig.pcoClientID,
            ])
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let newTokens = try await task.value
            store(newTokens)
            return newTokens
        } catch {
            signOut()
            throw error
        }
    }

    private func store(_ newTokens: OAuthTokens) {
        tokens = newTokens
        try? KeychainStore.save(newTokens, account: keychainAccount)
    }

    private func requestTokens(_ params: [String: String]) async throws -> OAuthTokens {
        var request = URLRequest(url: AppConfig.pcoTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.server("Planning Center sign in failed. Please try again.")
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthTokens(
            accessToken: decoded.access_token,
            // Planning Center rotates refresh tokens; keep the old one if none is returned.
            refreshToken: decoded.refresh_token ?? tokens?.refreshToken,
            expiresAt: Date().addingTimeInterval(decoded.expires_in ?? 7200)
        )
    }

    nonisolated static func formEncode(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
