import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    case home, groups, events, giving, nextSteps
}

/// A Church Center (or other web) flow presented inside the app.
struct WebDestination: Identifiable, Hashable {
    enum Style { case inApp, safari }
    let id = UUID()
    let title: String
    let url: URL
    var style: Style = .inApp
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var web: WebDestination?
    var showProfile = false
    var showServing = false
    var showCheckIn = false
    var groupsFilterTypeID: String?

    func open(_ url: URL, title: String, style: WebDestination.Style = .inApp) {
        web = WebDestination(title: title, url: url, style: style)
    }

    func perform(_ action: NextStepAction) {
        switch action {
        case .form(_, let url), .signup(_, let url), .web(let url):
            open(url, title: "Next Step")
        case .groups(let typeID):
            groupsFilterTypeID = typeID
            selectedTab = .groups
        case .serve:
            showServing = true
        }
    }

    /// horizonchurch://tab/groups, horizonchurch://check-in, horizonchurch://serving
    func handleDeepLink(_ url: URL) {
        guard url.scheme == AppConfig.oauthCallbackScheme else { return }
        switch url.host {
        case "tab":
            if let tab = AppTab(rawValue: url.lastPathComponent) { selectedTab = tab }
        case "check-in": showCheckIn = true
        case "serving": showServing = true
        case "give": selectedTab = .giving
        default: break
        }
    }
}
