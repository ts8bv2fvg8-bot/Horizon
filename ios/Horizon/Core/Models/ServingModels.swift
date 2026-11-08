import Foundation

struct ServingOverview: Decodable {
    let schedules: [ServingSchedule]
    let blockouts: [Blockout]
    let positions: [PositionPreference]
    let preferences: Preferences

    struct Preferences: Codable, Equatable {
        var maxPlansPerMonth: Int?
        var maxPlansPerDay: Int?

        private enum CodingKeys: String, CodingKey { case maxPlansPerMonth, maxPlansPerDay }

        /// Encodes nil as null so "No limit" clears the value in Planning Center.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(maxPlansPerMonth, forKey: .maxPlansPerMonth)
            try c.encode(maxPlansPerDay, forKey: .maxPlansPerDay)
        }
    }
}

struct ServingSchedule: Decodable, Identifiable, Hashable {
    let id: String
    let serviceTypeName: String?
    let teamName: String?
    let positionName: String?
    let dates: String?
    let shortDates: String?
    let sortDate: Date?
    let timesDescription: String?
    let status: String
    let declineReason: String?
    let respondsTo: String?

    var isPending: Bool { status == "U" }
    var isConfirmed: Bool { status == "C" }
    var isDeclined: Bool { status == "D" }
    var title: String { [teamName, positionName].compactMap { $0 }.joined(separator: " · ") }
}

struct Blockout: Decodable, Identifiable, Hashable {
    let id: String
    let reason: String
    let startsAt: Date
    let endsAt: Date
    let repeatFrequency: String
}

struct PositionPreference: Codable, Identifiable, Hashable {
    let id: String
    let positionName: String
    var schedulePreference: String
    var preferredWeeks: [String]
}

struct NewBlockout: Encodable {
    let reason: String
    let startsAt: Date
    let endsAt: Date
}

struct DeclineBody: Encodable { let reason: String }

struct ServingPreferencesUpdate: Encodable {
    struct Position: Encodable { let id: String; let schedulePreference: String; let preferredWeeks: [String] }
    let positions: [Position]
    let preferences: ServingOverview.Preferences
}
