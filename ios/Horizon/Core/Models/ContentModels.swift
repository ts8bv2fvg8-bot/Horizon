import Foundation

struct HomeContent: Decodable {
    struct Hero: Decodable { let title: String; let subtitle: String; let imageUrl: URL?; let url: URL }
    struct PageLink: Decodable, Identifiable, Hashable { let slug: String; let title: String; var id: String { slug } }
    let hero: Hero
    let announcements: [Announcement]
    let pages: [PageLink]
}

struct Announcement: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let imageUrl: URL?
    let url: URL
    let publishedAt: Date?
}

struct WebPage: Decodable, Identifiable {
    let slug: String
    let title: String
    let summary: String
    let imageUrl: URL?
    let html: String
    let url: URL
    var id: String { slug }
}

struct Sermon: Decodable, Identifiable, Hashable {
    let guid: String
    let title: String
    let summary: String
    let link: String
    let publishedAt: Date?
    let imageUrl: URL?
    let audioUrl: URL?
    let durationSeconds: Int?
    let speaker: String?
    var id: String { guid }
}
