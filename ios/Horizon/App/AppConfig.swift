import Foundation

/// Build-time configuration. Values come from Info.plist (populated from build settings in
/// project.yml) so staging and production builds can point at different backends.
enum AppConfig {
    static let apiBaseURL: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "HorizonAPIBaseURL") as? String ?? ""
        return URL(string: raw) ?? URL(string: "https://horizon-app-api.example.workers.dev")!
    }()

    // Planning Center OAuth (public client + PKCE).
    static let pcoClientID = Bundle.main.object(forInfoDictionaryKey: "PCOClientID") as? String ?? ""
    static let pcoAuthorizeURL = URL(string: "https://api.planningcenteronline.com/oauth/authorize")!
    static let pcoTokenURL = URL(string: "https://api.planningcenteronline.com/oauth/token")!
    static let pcoRevokeURL = URL(string: "https://api.planningcenteronline.com/oauth/revoke")!
    static let oauthCallbackScheme = "horizonchurch"
    static let oauthRedirectURI = "horizonchurch://oauth/callback"
    /// The app only needs to know who the member is; the backend performs every action.
    static let pcoScopes = "people"

    // Fallbacks used before /v1/config loads (and when offline).
    static let churchCenterURL = URL(string: "https://horizoncommunitychurch.churchcenter.com")!
    static let websiteURL = URL(string: "https://www.horizoncommunity.church")!
    static let giveURL = URL(string: "https://horizoncommunitychurch.churchcenter.com/giving")!
    static let checkInsURL = URL(string: "https://horizoncommunitychurch.churchcenter.com/check-ins")!
}
