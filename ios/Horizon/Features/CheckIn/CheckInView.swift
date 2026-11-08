import SwiftUI

/// Check-in for Horizon Kids, Youth and other Check-Ins events.
///
/// Planning Center's Check-Ins API is read-only (Planning Center has said a writable API isn't
/// on its roadmap for child-safety reasons), so the check-in itself happens in Church
/// Center's mobile check-in flow, opened in-app. This screen adds what an app can do
/// natively: knowing when check-in is open or you've arrived, and showing your household's
/// security codes afterwards.
struct CheckInView: View {
    @Environment(\.api) private var api
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ConfigStore.self) private var config
    @Environment(CampusProximityMonitor.self) private var proximity
    @State private var status: CheckInStatus?
    @State private var recent: [RecentCheckIn] = []

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: proximity.isOnCampus ? "location.circle.fill" : "qrcode.viewfinder")
                        .font(.system(size: 44)).foregroundStyle(Theme.accent)
                    Text(headline).font(.title2.bold())
                    Text("Check in your family from your phone, then scan your code at any check-in station to print name tags.")
                        .foregroundStyle(.secondary)
                    Button {
                        router.open(config.checkInsURL, title: "Check In")
                    } label: {
                        Label("Start Check-In", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.vertical, 6)
            }

            if let events = status?.events, !events.isEmpty {
                Section("Open now") {
                    ForEach(events, id: \.self) { e in
                        LabeledContent(e.eventName, value: e.startsAt.formatted(date: .omitted, time: .shortened))
                    }
                }
            }

            if auth.isSignedIn {
                Section("Today's check-ins") {
                    if recent.isEmpty { Text("No one in your household is checked in yet.").foregroundStyle(.secondary) }
                    ForEach(recent) { c in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(c.name).font(.headline)
                                Text("\(c.eventName) · \(c.checkedInAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let code = c.securityCode {
                                Text(code).font(.title3.monospaced().bold())
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                    .accessibilityLabel("Security code \(code)")
                            }
                        }
                    }
                }
            }

            if proximity.authorization == .notDetermined {
                Section {
                    Button { proximity.requestPermission() } label: {
                        Label("Remind me to check in when I arrive on campus", systemImage: "bell.badge")
                    }
                }
            }

            Section("First time with kids?") {
                Button { router.open(AppConfig.churchCenterURL.appending(path: "people/forms/184312"), title: "Horizon Kids Registration") } label: {
                    Label("Pre-register your kids", systemImage: "figure.and.child.holdinghands")
                }
            }
        }
        .navigationTitle("Check In")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .refreshable { await load() }
        .task { await load() }
    }

    private var headline: String {
        if proximity.isOnCampus { return "Welcome to Horizon!" }
        if status?.open == true { return "Check-in is open" }
        return "Check In"
    }

    private func load() async {
        status = try? await api.get("/v1/check-ins/status")
        if auth.isSignedIn { recent = (try? await api.get("/v1/me/check-ins", authenticated: true)) ?? [] }
    }
}
