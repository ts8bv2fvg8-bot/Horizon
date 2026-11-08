import SwiftUI

struct MyGroupsView: View {
    let model: GroupsModel
    @Environment(\.api) private var api
    @Environment(AppRouter.self) private var router

    var body: some View {
        LoadableView(state: model.mine, retry: { await model.loadMine(api: api) }) { memberships in
            if memberships.isEmpty {
                ContentUnavailableView {
                    Label("You're not in a group yet", systemImage: "person.3")
                } description: {
                    Text("Life is better together. Find a group that fits your schedule.")
                }
            } else {
                List {
                    ForEach(memberships) { m in
                        Section {
                            NavigationLink {
                                if m.isLeader { LeaderGroupView(membership: m) } else { MemberGroupView(membership: m) }
                            } label: {
                                HStack(spacing: 12) {
                                    RemoteImage(url: m.group.imageUrl, aspectRatio: 1).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading) {
                                        Text(m.group.name).font(.headline)
                                        if let schedule = m.group.schedule { Text(schedule).font(.subheadline).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if m.isLeader {
                                        Text("Leader").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(Theme.accent.opacity(0.15), in: Capsule()).foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                            if let next = m.upcomingEvents.first(where: { !$0.canceled }) {
                                HStack {
                                    Label(next.startsAt.formatted(.dateTime.weekday(.wide).month().day().hour().minute()), systemImage: "calendar")
                                        .font(.subheadline)
                                    Spacer()
                                    if m.isLeader {
                                        Button("Take Attendance") { router.open(next.churchCenterUrl, title: "Attendance") }
                                            .buttonStyle(.bordered).controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                }
                .refreshable { await model.loadMine(api: api) }
            }
        }
    }
}

struct MemberGroupView: View {
    let membership: MyGroupMembership
    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            Section("Upcoming") {
                if membership.upcomingEvents.isEmpty { Text("No upcoming meetings scheduled.").foregroundStyle(.secondary) }
                ForEach(membership.upcomingEvents) { event in GroupEventRow(event: event) }
            }
            Section {
                Button { router.open(membership.group.churchCenterUrl, title: membership.group.name) } label: {
                    Label("Open in Church Center (messages, resources, members)", systemImage: "bubble.left.and.bubble.right")
                }
            }
        }
        .navigationTitle(membership.group.name)
    }
}

struct GroupEventRow: View {
    let event: GroupEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.name).font(.headline).strikethrough(event.canceled)
            Text(event.startsAt.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                .font(.subheadline).foregroundStyle(.secondary)
            if event.canceled { Text("Canceled").font(.caption.bold()).foregroundStyle(.red) }
        }
    }
}

/// Leader tools: roster, attendance history and one-tap attendance for the next meeting.
///
/// Planning Center's Groups API exposes attendance as read-only, so attendance is recorded on
/// Church Center's event page (opened in-app, already signed in); this screen shows the
/// results as soon as they sync.
struct LeaderGroupView: View {
    let membership: MyGroupMembership
    @Environment(\.api) private var api
    @Environment(AppRouter.self) private var router
    @State private var detail: Loadable<LeaderGroupDetail> = .idle

    var body: some View {
        LoadableView(state: detail, retry: load) { d in
            List {
                Section("Take Attendance") {
                    let events = (d.upcomingEvents + d.recentEvents.filter { !$0.recorded }.map(\.event))
                        .filter { !$0.canceled }
                        .sorted { abs($0.startsAt.timeIntervalSinceNow) < abs($1.startsAt.timeIntervalSinceNow) }
                    if events.isEmpty { Text("No meetings need attendance.").foregroundStyle(.secondary) }
                    ForEach(events.prefix(4)) { event in
                        Button { router.open(event.churchCenterUrl, title: "Attendance") } label: {
                            HStack {
                                GroupEventRow(event: event)
                                Spacer()
                                Image(systemName: "checklist").foregroundStyle(Theme.accent)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Recent Attendance") {
                    ForEach(d.recentEvents) { past in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(past.event.startsAt.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                                Text(past.event.name).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if past.recorded {
                                Text("\(past.attendedCount) / \(d.roster.count)").monospacedDigit()
                            } else {
                                Text("Not taken").foregroundStyle(.orange).font(.subheadline)
                            }
                        }
                    }
                }

                Section("Roster (\(d.roster.count))") {
                    ForEach(d.roster) { person in
                        HStack(spacing: 12) {
                            AvatarView(url: person.avatarUrl, name: person.name, size: 36)
                            Text(person.name)
                            Spacer()
                            if person.role == "leader" { Text("Leader").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }

                Section {
                    Button { router.open(membership.group.churchCenterUrl, title: membership.group.name) } label: {
                        Label("Message members & manage group", systemImage: "envelope")
                    }
                }
            }
            .refreshable { await load() }
        }
        .navigationTitle(membership.group.name)
        .task { if detail.value == nil { await load() } }
    }

    private func load() async {
        if detail.value == nil { detail = .loading }
        do { detail = .loaded(try await api.get("/v1/me/groups/\(membership.group.id)/leader", authenticated: true)) }
        catch { detail = .failed(error) }
    }
}
