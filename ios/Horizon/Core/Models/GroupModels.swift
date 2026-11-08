import CoreLocation
import Foundation

struct GroupType: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
}

struct ChurchGroup: Decodable, Identifiable, Hashable {
    struct Location: Decodable, Hashable {
        let name: String?
        let address: String?
        let latitude: Double?
        let longitude: Double?
        let approximate: Bool
        var coordinate: CLLocationCoordinate2D? {
            guard let latitude, let longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
    struct Enrollment: Decodable, Hashable { let status: String; let strategy: String }

    let id: String
    let name: String
    let groupTypeId: String?
    let groupTypeName: String?
    let summary: String
    let descriptionHtml: String
    let schedule: String?
    let imageUrl: URL?
    let membersCount: Int
    let meetsOnline: Bool
    let location: Location?
    let enrollment: Enrollment?
    let churchCenterUrl: URL
    let tags: [String]

    var isFull: Bool { enrollment?.status == "full" }
    var isClosed: Bool { enrollment?.status == "closed" }
    var joinLabel: String {
        switch enrollment?.strategy {
        case "open_signup": "Join Group"
        case "closed": "Contact Leader"
        default: "Request to Join"
        }
    }
}

struct MyGroupMembership: Decodable, Identifiable, Hashable {
    struct GroupInfo: Decodable, Hashable {
        let id: String
        let name: String
        let schedule: String?
        let imageUrl: URL?
        let churchCenterUrl: URL
        let membersCount: Int
    }
    let membershipId: String
    let role: String
    let group: GroupInfo
    let upcomingEvents: [GroupEvent]
    var id: String { membershipId }
    var isLeader: Bool { role == "leader" }
}

struct GroupEvent: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let startsAt: Date
    let endsAt: Date?
    let canceled: Bool
    let location: String?
    let churchCenterUrl: URL
}

struct LeaderGroupDetail: Decodable {
    struct RosterMember: Decodable, Identifiable, Hashable {
        let personId: String?
        let name: String
        let avatarUrl: URL?
        let role: String
        var id: String { personId ?? name }
    }
    struct PastEvent: Decodable, Identifiable, Hashable {
        struct Row: Decodable, Hashable { let personId: String?; let attended: Bool }
        let event: GroupEvent
        let attendedCount: Int
        let recorded: Bool
        let attendance: [Row]
        var id: String { event.id }
    }
    let roster: [RosterMember]
    let upcomingEvents: [GroupEvent]
    let recentEvents: [PastEvent]
}
