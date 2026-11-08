import Foundation

struct ChurchEvent: Decodable, Identifiable, Hashable {
    let id: String
    let source: String
    let title: String
    let summary: String
    let descriptionHtml: String
    let imageUrl: URL?
    let startsAt: Date?
    let endsAt: Date?
    let allDay: Bool
    let location: String?
    let registrationUrl: URL?
    let detailsUrl: URL
    let registrationOpen: Bool
    let atCapacity: Bool

    var canRegister: Bool { registrationUrl != nil && registrationOpen && !atCapacity }
}
