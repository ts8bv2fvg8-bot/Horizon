import Foundation

struct AppRemoteConfig: Decodable {
    struct Organization: Decodable { let name: String; let website: String; let churchCenter: String }
    struct Links: Decodable {
        let give: URL
        let checkIns: URL
        let myProfile: URL
        let myRegistrations: URL
        let groups: URL
        let registrations: URL
        let sermons: URL
    }
    let organization: Organization
    let campuses: [Campus]
    let links: Links
    let nextSteps: [NextStepSection]
    let schedulePreferences: [String]
}

struct Campus: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let street: String
    let city: String
    let state: String
    let zip: String
    let phone: String
    let email: String
    let latitude: Double
    let longitude: Double
    let geofenceRadiusMeters: Double
    let serviceTimes: [String]

    var fullAddress: String { "\(street), \(city), \(state) \(zip)" }

    static let tualatin = Campus(
        id: "20920", name: "Tualatin Campus", street: "23370 SW Boones Ferry Rd", city: "Tualatin", state: "OR",
        zip: "97062", phone: "503-612-6688", email: "tualatin@horizoncommunity.church",
        latitude: 45.3712, longitude: -122.7623, geofenceRadiusMeters: 200,
        serviceTimes: ["Sunday 9:30 AM", "Sunday 11:00 AM"]
    )
}

struct NextStepSection: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let steps: [NextStep]
}

struct NextStep: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let action: NextStepAction
}

enum NextStepAction: Decodable, Hashable {
    case form(id: String, url: URL)
    case signup(id: String, url: URL)
    case groups(typeID: String?)
    case serve
    case web(URL)

    private enum CodingKeys: String, CodingKey { case kind, formId, signupId, url, groupTypeId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "form": self = .form(id: try c.decode(String.self, forKey: .formId), url: try c.decode(URL.self, forKey: .url))
        case "signup": self = .signup(id: try c.decode(String.self, forKey: .signupId), url: try c.decode(URL.self, forKey: .url))
        case "groups": self = .groups(typeID: try c.decodeIfPresent(String.self, forKey: .groupTypeId))
        case "serve": self = .serve
        default: self = .web(try c.decode(URL.self, forKey: .url))
        }
    }
}
