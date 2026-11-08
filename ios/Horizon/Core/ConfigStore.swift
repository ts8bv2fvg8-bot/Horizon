import Foundation
import Observation

/// Remote configuration from /v1/config, so staff can change next steps, links and campus
/// details without shipping an app update. Falls back to built-in values offline.
@MainActor
@Observable
final class ConfigStore {
    private(set) var remote: AppRemoteConfig?

    var campuses: [Campus] { remote?.campuses ?? [.tualatin] }
    var primaryCampus: Campus { campuses.first ?? .tualatin }
    var nextSteps: [NextStepSection] { remote?.nextSteps ?? [] }
    var giveURL: URL { remote?.links.give ?? AppConfig.giveURL }
    var checkInsURL: URL { remote?.links.checkIns ?? AppConfig.checkInsURL }
    var myRegistrationsURL: URL { remote?.links.myRegistrations ?? AppConfig.churchCenterURL.appending(path: "registrations/reservations") }
    var churchCenterProfileURL: URL { remote?.links.myProfile ?? AppConfig.churchCenterURL.appending(path: "me") }
    var sermonsURL: URL { remote?.links.sermons ?? AppConfig.churchCenterURL.appending(path: "channels/6131") }
    var schedulePreferences: [String] {
        remote?.schedulePreferences ?? ["Every week", "Every other week (A)", "Every other week (B)", "Once a month", "Twice a month", "Choose weeks"]
    }

    func load(api: APIClient) async {
        if let config: AppRemoteConfig = try? await api.get("/v1/config") { remote = config }
    }
}
