import SwiftUI

@MainActor
@Observable
final class HomeModel {
    var content: Loadable<HomeContent> = .idle
    var sermons: [Sermon] = []
    var events: [ChurchEvent] = []
    var checkIn: CheckInStatus?
    var nextServing: ServingSchedule?
    var pendingServingCount = 0

    func load(api: APIClient, signedIn: Bool) async {
        if content.value == nil { content = .loading }
        async let home: HomeContent = api.get("/v1/content/home")
        async let sermons: [Sermon] = api.get("/v1/sermons")
        async let events: [ChurchEvent] = api.get("/v1/events")
        async let status: CheckInStatus = api.get("/v1/check-ins/status")

        do { content = .loaded(try await home) } catch { if content.value == nil { content = .failed(error) } }
        self.sermons = (try? await sermons) ?? self.sermons
        self.events = Array(((try? await events) ?? self.events).prefix(8))
        self.checkIn = try? await status

        if signedIn, let serving: ServingOverview = try? await api.get("/v1/me/serving", authenticated: true) {
            nextServing = serving.schedules.first { !$0.isDeclined }
            pendingServingCount = serving.schedules.filter(\.isPending).count
        } else {
            nextServing = nil
            pendingServingCount = 0
        }
    }
}

struct HomeView: View {
    @Environment(\.api) private var api
    @Environment(AuthManager.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ConfigStore.self) private var config
    @Environment(CampusProximityMonitor.self) private var proximity
    @State private var model = HomeModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if proximity.isOnCampus || (model.checkIn?.open ?? false) {
                        CheckInBanner(eventNames: model.checkIn?.events.map(\.eventName) ?? []) { router.showCheckIn = true }
                            .padding(.horizontal)
                    }

                    LoadableView(state: model.content, retry: reload) { content in
                        HeroCard(hero: content.hero, campus: config.primaryCampus)
                            .padding(.horizontal)
                    }

                    QuickActions().padding(.horizontal)

                    if let serving = model.nextServing {
                        ServingCard(schedule: serving, pendingCount: model.pendingServingCount) { router.showServing = true }
                            .padding(.horizontal)
                    }

                    if let latest = model.sermons.first {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Latest Message").font(.title3.bold())
                                Spacer()
                                NavigationLink("All Messages") { SermonsView(sermons: model.sermons) }
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal)
                            NavigationLink { SermonDetailView(sermon: latest) } label: { SermonHeroCard(sermon: latest) }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                        }
                    }

                    if !model.events.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Coming Up", actionTitle: "See All") { router.selectedTab = .events }
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(model.events) { event in
                                        NavigationLink { EventDetailView(event: event) } label: { EventCard(event: event).frame(width: 260) }
                                            .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    if let content = model.content.value {
                        if !content.announcements.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "What's Happening")
                                ForEach(content.announcements) { item in
                                    Button { router.open(item.url, title: item.title, style: .safari) } label: { AnnouncementRow(item: item) }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Get to Know Horizon")
                            VStack(spacing: 0) {
                                ForEach(content.pages) { page in
                                    NavigationLink { WebPageView(slug: page.slug, fallbackTitle: page.title) } label: {
                                        HStack {
                                            Text(page.title)
                                            Spacer()
                                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                        }
                                        .padding()
                                    }
                                    .buttonStyle(.plain)
                                    if page != content.pages.last { Divider().padding(.leading) }
                                }
                            }
                            .card()
                            .padding(.horizontal)
                        }
                    }

                    CampusFooter(campus: config.primaryCampus).padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(greeting)
            .toolbar { ProfileToolbarButton() }
            .refreshable { await reload() }
            .task(id: auth.isSignedIn) { await reload() }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        if let first = auth.displayName?.split(separator: " ").first { return "\(part), \(first)" }
        return "Welcome Home"
    }

    private func reload() async { await model.load(api: api, signedIn: auth.isSignedIn) }
}

// MARK: - Components

private struct HeroCard: View {
    let hero: HomeContent.Hero
    let campus: Campus
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: hero.imageUrl, aspectRatio: 4 / 3)
            Theme.heroGradient
            VStack(alignment: .leading, spacing: 6) {
                Text(hero.title).font(.title.bold())
                Text(hero.subtitle).font(.subheadline).lineLimit(3)
                Text(campus.serviceTimes.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .foregroundStyle(.white)
            .padding()
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .onTapGesture { router.open(hero.url, title: "Horizon", style: .safari) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct QuickAction: Identifiable {
    let title: String
    let icon: String
    let action: () -> Void
    var id: String { title }
}

private struct QuickActions: View {
    @Environment(AppRouter.self) private var router
    @Environment(ConfigStore.self) private var config

    var body: some View {
        let actions = [
            QuickAction(title: "Check In", icon: "qrcode.viewfinder") { router.showCheckIn = true },
            QuickAction(title: "Give", icon: "heart.fill") { router.open(config.giveURL, title: "Give", style: .safari) },
            QuickAction(title: "Plan a Visit", icon: "calendar.badge.plus") {
                router.open(AppConfig.churchCenterURL.appending(path: "people/forms/10185"), title: "Plan a Visit")
            },
            QuickAction(title: "Prayer", icon: "hands.and.sparkles.fill") {
                router.open(AppConfig.churchCenterURL.appending(path: "people/forms/10182"), title: "Prayer Request")
            },
        ]
        HStack(spacing: 12) {
            ForEach(actions) { item in
                Button(action: item.action) {
                    VStack(spacing: 8) {
                        Image(systemName: item.icon).font(.title2)
                        Text(item.title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .card()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
        }
    }
}

private struct CheckInBanner: View {
    let eventNames: [String]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(.title)
                VStack(alignment: .leading) {
                    Text("Check-in is open").font(.headline)
                    Text(eventNames.isEmpty ? "Welcome to Horizon! Tap to check in." : eventNames.joined(separator: ", "))
                        .font(.subheadline).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding()
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ServingCard: View {
    let schedule: ServingSchedule
    let pendingCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.clock.fill").font(.title).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pendingCount > 0 ? "\(pendingCount) serving request\(pendingCount == 1 ? "" : "s") to review" : "You're serving next")
                        .font(.headline)
                    Text("\(schedule.shortDates ?? schedule.dates ?? "") · \(schedule.title)")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .card()
        }
        .buttonStyle(.plain)
    }
}

private struct AnnouncementRow: View {
    let item: Announcement
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: item.imageUrl, aspectRatio: 1)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).lineLimit(2)
                Text(item.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .card()
    }
}

struct CampusFooter: View {
    let campus: Campus
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(campus.name).font(.headline)
            Text(campus.serviceTimes.joined(separator: " · ")).font(.subheadline)
            Link(destination: URL(string: "http://maps.apple.com/?q=Horizon+Community+Church&address=\(campus.fullAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!) {
                Label(campus.fullAddress, systemImage: "map.fill")
            }
            Link(destination: URL(string: "tel:\(campus.phone.filter(\.isNumber))")!) { Label(campus.phone, systemImage: "phone.fill") }
            Link(destination: URL(string: "mailto:\(campus.email)")!) { Label(campus.email, systemImage: "envelope.fill") }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .card()
    }
}
