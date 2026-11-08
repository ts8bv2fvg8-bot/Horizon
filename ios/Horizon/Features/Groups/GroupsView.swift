import MapKit
import SwiftUI

@MainActor
@Observable
final class GroupsModel {
    var groups: Loadable<[ChurchGroup]> = .idle
    var types: [GroupType] = []
    var mine: Loadable<[MyGroupMembership]> = .idle

    func loadDirectory(api: APIClient) async {
        if groups.value == nil { groups = .loading }
        async let t: [GroupType] = api.get("/v1/group-types")
        do { groups = .loaded(try await api.get("/v1/groups")) } catch { if groups.value == nil { groups = .failed(error) } }
        types = (try? await t) ?? types
    }

    func loadMine(api: APIClient) async {
        if mine.value == nil { mine = .loading }
        do { mine = .loaded(try await api.get("/v1/me/groups", authenticated: true)) } catch { mine = .failed(error) }
    }
}

struct GroupsView: View {
    enum Segment: String, CaseIterable { case find = "Find a Group", mine = "My Groups" }

    @Environment(\.api) private var api
    @Environment(AuthManager.self) private var auth
    @Environment(AppRouter.self) private var router
    @State private var model = GroupsModel()
    @State private var segment: Segment = .find

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Groups", selection: $segment) {
                    ForEach(Segment.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .bottom])

                switch segment {
                case .find:
                    GroupFinderView(model: model)
                case .mine:
                    if auth.isSignedIn {
                        MyGroupsView(model: model)
                    } else {
                        SignInPrompt(title: "Your Groups", message: "Sign in to see your groups, upcoming meetings and leader tools.")
                    }
                }
            }
            .navigationTitle("Groups")
            .toolbar { ProfileToolbarButton() }
            .task { await model.loadDirectory(api: api) }
            .task(id: auth.isSignedIn) { if auth.isSignedIn { await model.loadMine(api: api) } }
        }
    }
}

// MARK: - Finder

struct GroupFinderView: View {
    let model: GroupsModel
    @Environment(\.api) private var api
    @Environment(AppRouter.self) private var router
    @Environment(ConfigStore.self) private var config
    @State private var query = ""
    @State private var selectedType: String?
    @State private var day: String?
    @State private var showMap = false

    private static let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private func filtered(_ groups: [ChurchGroup]) -> [ChurchGroup] {
        groups.filter { g in
            (selectedType == nil || g.groupTypeId == selectedType)
                && (day == nil || (g.schedule ?? "").localizedCaseInsensitiveContains(day!) || g.tags.contains(day!))
                && (query.isEmpty || g.name.localizedCaseInsensitiveContains(query) || g.summary.localizedCaseInsensitiveContains(query)
                    || g.tags.contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        LoadableView(state: model.groups, retry: { await model.loadDirectory(api: api) }) { groups in
            let results = filtered(groups)
            VStack(spacing: 0) {
                filters
                if showMap {
                    GroupsMapView(groups: results, campus: config.primaryCampus)
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label("No groups match", systemImage: "person.3")
                    } description: {
                        Text("Try a different filter, or let us help you find one.")
                    } actions: {
                        Button("Help Me Find a Group") {
                            router.open(AppConfig.churchCenterURL.appending(path: "people/forms/10180"), title: "Find a Group")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(results) { group in
                        NavigationLink(value: group) { GroupRow(group: group) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationDestination(for: ChurchGroup.self) { GroupDetailView(group: $0) }
        }
        .searchable(text: $query, prompt: "Search groups")
        .refreshable { await model.loadDirectory(api: api) }
        .onAppear {
            if let id = router.groupsFilterTypeID { selectedType = id; router.groupsFilterTypeID = nil }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showMap.toggle() } label: { Image(systemName: showMap ? "list.bullet" : "map") }
                    .accessibilityLabel(showMap ? "Show list" : "Show map")
            }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Any day") { day = nil }
                    ForEach(Self.days, id: \.self) { d in Button(d) { day = d } }
                } label: {
                    FilterChip(title: day ?? "Any day", selected: day != nil, systemImage: "calendar")
                }
                FilterChip(title: "All", selected: selectedType == nil) { selectedType = nil }
                ForEach(model.types) { type in
                    FilterChip(title: type.name, selected: selectedType == type.id) { selectedType = selectedType == type.id ? nil : type.id }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    var systemImage: String?
    var action: (() -> Void)?

    var body: some View {
        let label = HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(selected ? Theme.accent : Color(.secondarySystemBackground), in: Capsule())
        .foregroundStyle(selected ? .white : .primary)

        if let action { Button(action: action) { label }.buttonStyle(.plain) } else { label }
    }
}

struct GroupRow: View {
    let group: ChurchGroup
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: group.imageUrl, aspectRatio: 1).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name).font(.headline)
                if let schedule = group.schedule { Text(schedule).font(.subheadline).foregroundStyle(.secondary) }
                HStack(spacing: 6) {
                    if let type = group.groupTypeName { Text(type) }
                    if group.meetsOnline { Label("Online", systemImage: "video.fill") }
                    else if let loc = group.location?.name { Label(loc, systemImage: "mappin") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if group.isFull { Text("Full").font(.caption.bold()).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 4)
    }
}

struct GroupsMapView: View {
    let groups: [ChurchGroup]
    let campus: Campus
    @State private var selection: ChurchGroup?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position, selection: $selection) {
            UserAnnotation()
            Marker("Horizon", systemImage: "building.columns.fill", coordinate: .init(latitude: campus.latitude, longitude: campus.longitude))
                .tint(Theme.navy)
            ForEach(groups.filter { $0.location?.coordinate != nil }) { group in
                Marker(group.name, systemImage: "person.3.fill", coordinate: group.location!.coordinate!)
                    .tint(Theme.accent)
                    .tag(group)
            }
        }
        .mapControls { MapUserLocationButton() }
        .sheet(item: $selection) { group in
            NavigationStack { GroupDetailView(group: group) }.presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Detail

struct GroupDetailView: View {
    let group: ChurchGroup
    @Environment(AppRouter.self) private var router
    @State private var descriptionHeight: CGFloat = 200

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(url: group.imageUrl).clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                Text(group.name).font(.title.bold())
                VStack(alignment: .leading, spacing: 8) {
                    if let schedule = group.schedule { Label(schedule, systemImage: "clock") }
                    if group.meetsOnline { Label("Meets online", systemImage: "video") }
                    if let loc = group.location {
                        Label(loc.address ?? loc.name ?? "Location shared after you join", systemImage: "mappin.and.ellipse")
                    }
                    Label("\(group.membersCount) members", systemImage: "person.2")
                    if let type = group.groupTypeName { Label(type, systemImage: "tag") }
                }
                .foregroundStyle(.secondary)

                Button {
                    router.open(group.churchCenterUrl, title: group.name)
                } label: {
                    Text(group.isFull ? "Group is full" : group.joinLabel).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(group.isFull || group.isClosed)

                if let coordinate = group.location?.coordinate {
                    Map(initialPosition: .region(.init(center: coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000))) {
                        if group.location?.approximate == true {
                            MapCircle(center: coordinate, radius: 800).foregroundStyle(Theme.accent.opacity(0.25))
                        } else {
                            Marker(group.name, coordinate: coordinate)
                        }
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .allowsHitTesting(false)
                }

                if !group.descriptionHtml.isEmpty {
                    HTMLContentView(html: group.descriptionHtml, height: $descriptionHeight)
                        .frame(height: descriptionHeight)
                        .padding(.horizontal, -16)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ShareLink(item: group.churchCenterUrl) }
    }
}
