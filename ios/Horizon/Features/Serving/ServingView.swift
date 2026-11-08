import SwiftUI

@MainActor
@Observable
final class ServingModel {
    var overview: Loadable<ServingOverview> = .idle
    var error: String?
    var busy = false

    func load(api: APIClient) async {
        if overview.value == nil { overview = .loading }
        do { overview = .loaded(try await api.get("/v1/me/serving", authenticated: true)) } catch { overview = .failed(error) }
    }

    func mutate(_ work: () async throws -> ServingOverview) async {
        busy = true
        defer { busy = false }
        do { overview = .loaded(try await work()); error = nil } catch { self.error = error.localizedDescription }
    }
}

/// Serving: upcoming dates (accept/decline), blockout dates and scheduling preferences —
/// all backed by Planning Center Services.
struct ServingView: View {
    @Environment(\.api) private var api
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @State private var model = ServingModel()
    @State private var declining: ServingSchedule?
    @State private var showBlockout = false
    @State private var showPreferences = false

    var body: some View {
        Group {
            if !auth.isSignedIn {
                SignInPrompt(title: "Your Serving Schedule", message: "Sign in to see when you're serving, respond to requests and set your availability.")
            } else {
                LoadableView(state: model.overview, retry: { await model.load(api: api) }) { o in
                    List {
                        if let error = model.error {
                            Section { Text(error).foregroundStyle(.red) }
                        }
                        let pending = o.schedules.filter(\.isPending)
                        if !pending.isEmpty {
                            Section("Needs your response") {
                                ForEach(pending) { s in
                                    ScheduleRow(schedule: s)
                                    HStack {
                                        Button("Accept") { Task { await respond(s, accept: true) } }.buttonStyle(.borderedProminent)
                                        Button("Decline", role: .destructive) { declining = s }.buttonStyle(.bordered)
                                    }
                                    .disabled(model.busy)
                                }
                            }
                        }
                        Section("Upcoming") {
                            let upcoming = o.schedules.filter { !$0.isPending }
                            if upcoming.isEmpty { Text("You're not scheduled yet.").foregroundStyle(.secondary) }
                            ForEach(upcoming) { ScheduleRow(schedule: $0) }
                        }
                        Section {
                            ForEach(o.blockouts) { b in
                                VStack(alignment: .leading) {
                                    Text(dateRange(b.startsAt, b.endsAt)).font(.headline)
                                    if !b.reason.isEmpty { Text(b.reason).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            .onDelete { offsets in
                                let ids = offsets.map { o.blockouts[$0].id }
                                Task {
                                    for id in ids {
                                        await model.mutate { try await api.send("DELETE", "/v1/me/serving/blockouts/\(id)", body: Optional<Empty>.none) }
                                    }
                                }
                            }
                            Button { showBlockout = true } label: { Label("Add blockout dates", systemImage: "calendar.badge.minus") }
                        } header: {
                            Text("Blockout dates")
                        } footer: {
                            Text("Let your team leaders know when you're away so you won't be scheduled.")
                        }
                        Section("Preferences") {
                            ForEach(o.positions) { p in
                                LabeledContent(p.positionName, value: p.schedulePreference)
                            }
                            if let max = o.preferences.maxPlansPerMonth {
                                LabeledContent("Max times per month", value: "\(max)")
                            }
                            Button { showPreferences = true } label: { Label("Edit serving preferences", systemImage: "slider.horizontal.3") }
                        }
                    }
                    .sheet(isPresented: $showBlockout) {
                        BlockoutForm { blockout in
                            await model.mutate { try await api.send("POST", "/v1/me/serving/blockouts", body: blockout) }
                        }
                    }
                    .sheet(isPresented: $showPreferences) {
                        PreferencesForm(positions: o.positions, preferences: o.preferences) { update in
                            await model.mutate { try await api.send("PATCH", "/v1/me/serving/preferences", body: update) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Serving")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .refreshable { await model.load(api: api) }
        .task(id: auth.isSignedIn) { if auth.isSignedIn { await model.load(api: api) } }
        .sheet(item: $declining) { s in
            DeclineForm(schedule: s) { reason in await respond(s, accept: false, reason: reason) }
        }
    }

    private func respond(_ s: ServingSchedule, accept: Bool, reason: String = "") async {
        await model.mutate {
            try await api.send("POST", "/v1/me/serving/schedules/\(s.id)/\(accept ? "accept" : "decline")", body: DeclineBody(reason: reason))
        }
    }

    private func dateRange(_ a: Date, _ b: Date) -> String {
        Calendar.current.isDate(a, inSameDayAs: b)
            ? a.formatted(date: .abbreviated, time: .omitted)
            : "\(a.formatted(date: .abbreviated, time: .omitted)) – \(b.formatted(date: .abbreviated, time: .omitted))"
    }
}

struct ScheduleRow: View {
    let schedule: ServingSchedule
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DateBadge(date: schedule.sortDate)
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.serviceTypeName ?? "Serving").font(.headline)
                Text(schedule.title).font(.subheadline)
                if let times = schedule.timesDescription { Text(times).font(.caption).foregroundStyle(.secondary) }
                if schedule.isConfirmed { Label("Confirmed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                if schedule.isDeclined { Label("Declined", systemImage: "xmark.circle.fill").font(.caption).foregroundStyle(.red) }
            }
        }
    }
}

struct DeclineForm: View {
    let schedule: ServingSchedule
    let submit: (String) async -> Void
    @State private var reason = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section { ScheduleRow(schedule: schedule) }
                Section("Reason (optional)") { TextField("Out of town, sick…", text: $reason, axis: .vertical) }
            }
            .navigationTitle("Decline")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Decline", role: .destructive) { Task { await submit(reason); dismiss() } }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct BlockoutForm: View {
    let submit: (NewBlockout) async -> Void
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Calendar.current.startOfDay(for: Date())
    @State private var reason = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("Through", selection: $end, in: start..., displayedComponents: .date)
                TextField("Reason (optional)", text: $reason)
            }
            .navigationTitle("Blockout Dates")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: end) ?? end
                        Task { await submit(NewBlockout(reason: reason, startsAt: start, endsAt: endOfDay)); dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct PreferencesForm: View {
    @State var positions: [PositionPreference]
    @State var preferences: ServingOverview.Preferences
    let submit: (ServingPreferencesUpdate) async -> Void
    @Environment(ConfigStore.self) private var config
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ForEach($positions) { $p in
                    Section(p.positionName) {
                        Picker("How often", selection: $p.schedulePreference) {
                            ForEach(config.schedulePreferences, id: \.self) { Text($0) }
                        }
                        if p.schedulePreference == "Choose weeks" {
                            ForEach(["1", "2", "3", "4", "5"], id: \.self) { week in
                                Toggle("\(ordinal(week)) week of the month", isOn: Binding(
                                    get: { p.preferredWeeks.contains(week) },
                                    set: { on in
                                        if on { p.preferredWeeks.append(week) } else { p.preferredWeeks.removeAll { $0 == week } }
                                    }
                                ))
                            }
                        }
                    }
                }
                Section("Limits") {
                    Stepper(value: Binding(get: { preferences.maxPlansPerMonth ?? 0 }, set: { preferences.maxPlansPerMonth = $0 == 0 ? nil : $0 }), in: 0...10) {
                        LabeledContent("Max times per month", value: preferences.maxPlansPerMonth.map(String.init) ?? "No limit")
                    }
                    Stepper(value: Binding(get: { preferences.maxPlansPerDay ?? 0 }, set: { preferences.maxPlansPerDay = $0 == 0 ? nil : $0 }), in: 0...5) {
                        LabeledContent("Max services per day", value: preferences.maxPlansPerDay.map(String.init) ?? "No limit")
                    }
                }
            }
            .navigationTitle("Serving Preferences")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let update = ServingPreferencesUpdate(
                            positions: positions.map { .init(id: $0.id, schedulePreference: $0.schedulePreference, preferredWeeks: $0.preferredWeeks) },
                            preferences: preferences
                        )
                        Task { await submit(update); dismiss() }
                    }
                }
            }
        }
    }

    private func ordinal(_ w: String) -> String {
        ["1": "1st", "2": "2nd", "3": "3rd", "4": "4th", "5": "5th"][w] ?? w
    }
}
