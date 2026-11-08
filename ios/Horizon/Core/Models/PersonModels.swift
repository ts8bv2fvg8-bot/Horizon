import Foundation

struct Profile: Codable, Equatable {
    struct Email: Codable, Identifiable, Equatable, Hashable {
        var id: String?
        var address: String
        var location: String?
        var primary: Bool?
    }
    struct Phone: Codable, Identifiable, Equatable, Hashable {
        var id: String?
        var number: String
        var location: String?
        var primary: Bool?
    }
    struct Address: Codable, Identifiable, Equatable, Hashable {
        var id: String?
        var streetLine1: String
        var streetLine2: String?
        var city: String
        var state: String
        var zip: String
        var location: String?
        var primary: Bool?

        enum CodingKeys: String, CodingKey {
            case id, city, state, zip, location, primary
            case streetLine1 = "street_line_1"
            case streetLine2 = "street_line_2"
        }
    }
    struct Household: Codable, Equatable {
        struct Member: Codable, Identifiable, Equatable { let id: String; let name: String; let child: Bool; let avatarUrl: URL? }
        let id: String
        let name: String
        let members: [Member]
    }

    let id: String
    var firstName: String
    var lastName: String
    var nickname: String?
    let name: String
    var birthdate: String?
    var anniversary: String?
    var gender: String?
    let avatarUrl: URL?
    let membership: String?
    let campus: String?
    var emails: [Email]
    var phoneNumbers: [Phone]
    var addresses: [Address]
    let household: Household?
}

/// Body for PATCH /v1/me. Only changed collections are sent.
struct ProfileUpdate: Encodable {
    struct Person: Encodable {
        var first_name: String
        var last_name: String
        var nickname: String?
        var birthdate: String?
        var anniversary: String?
        var gender: String?
    }
    struct Item<T: Encodable>: Encodable {
        let value: T
        let delete: Bool
        func encode(to encoder: Encoder) throws {
            try value.encode(to: encoder)
            if delete {
                var c = encoder.container(keyedBy: DeleteKey.self)
                try c.encode(true, forKey: .delete)
            }
        }
        private enum DeleteKey: String, CodingKey { case delete = "_delete" }
    }
    var person: Person?
    var emails: [Item<Profile.Email>]?
    var phoneNumbers: [Item<Profile.Phone>]?
    var addresses: [Item<Profile.Address>]?
}

struct CheckInStatus: Decodable {
    struct OpenEvent: Decodable, Hashable { let eventId: String; let eventName: String; let startsAt: Date }
    let open: Bool
    let events: [OpenEvent]
}

struct RecentCheckIn: Decodable, Identifiable, Hashable {
    let id: String
    let personId: String
    let name: String
    let eventName: String
    let securityCode: String?
    let checkedInAt: Date
    let checkedOutAt: Date?
}

struct GivingSummary: Decodable {
    struct Gift: Decodable, Identifiable, Hashable {
        let id: String
        let amountCents: Int
        let currency: String
        let receivedAt: Date?
        let method: String
        let refunded: Bool
        let funds: [String]
    }
    struct Recurring: Decodable, Identifiable, Hashable {
        let id: String
        let amountCents: Int
        let schedule: String?
        let nextOccurrence: Date?
        let status: String
    }
    let yearToDateCents: Int
    let year: Int
    let gifts: [Gift]
    let recurring: [Recurring]
}
