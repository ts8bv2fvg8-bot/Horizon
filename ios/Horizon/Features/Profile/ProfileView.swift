import PhotosUI
import SwiftUI

struct ProfileView: View {
    @Environment(\.api) private var api
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ConfigStore.self) private var config
    @Environment(CampusProximityMonitor.self) private var proximity
    @State private var profile: Loadable<Profile> = .idle
    @State private var editing = false
    @State private var photo: PhotosPickerItem?
    @State private var uploadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if auth.isSignedIn {
                    LoadableView(state: profile, retry: load) { p in content(p) }
                } else {
                    SignInPrompt(
                        title: "Welcome to Horizon",
                        message: "Sign in with your Planning Center account to manage your profile, serving schedule, groups and giving."
                    )
                }
            }
            .navigationTitle("Profile")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: auth.isSignedIn) { if auth.isSignedIn { await load() } }
            .sheet(isPresented: $editing) {
                if let p = profile.value {
                    EditProfileView(original: p) { updated in profile = .loaded(updated) }
                }
            }
            .onChange(of: photo) { _, item in Task { await upload(item) } }
        }
    }

    @ViewBuilder private func content(_ p: Profile) -> some View {
        List {
            Section {
                HStack(spacing: 16) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        AvatarView(url: p.avatarUrl, name: p.name, size: 72)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.circle.fill").font(.title3).foregroundStyle(.white, Theme.accent)
                            }
                    }
                    .accessibilityLabel("Change profile photo")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.title3.bold())
                        if let campus = p.campus { Text(campus).foregroundStyle(.secondary) }
                        if let membership = p.membership { Text(membership).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let uploadError { Text(uploadError).font(.footnote).foregroundStyle(.red) }
                Button("Edit Profile") { editing = true }
            }

            Section("Contact") {
                ForEach(p.emails) { e in LabeledContent(e.location ?? "Email", value: e.address) }
                ForEach(p.phoneNumbers) { ph in LabeledContent(ph.location ?? "Phone", value: ph.number) }
                ForEach(p.addresses) { a in
                    LabeledContent(a.location ?? "Address") {
                        Text("\(a.streetLine1)\n\(a.city), \(a.state) \(a.zip)").multilineTextAlignment(.trailing)
                    }
                }
            }

            if let household = p.household {
                Section(household.name) {
                    ForEach(household.members) { m in
                        HStack {
                            AvatarView(url: m.avatarUrl, name: m.name, size: 32)
                            Text(m.name)
                            Spacer()
                            if m.child { Text("Child").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Button { router.open(config.churchCenterProfileURL, title: "Household") } label: {
                        Label("Add or edit household members", systemImage: "person.badge.plus")
                    }
                }
            }

            Section("My Horizon") {
                Button { dismiss(); router.showServing = true } label: { Label("Serving schedule & preferences", systemImage: "calendar") }
                Button { dismiss(); router.selectedTab = .groups } label: { Label("My groups", systemImage: "person.3") }
                Button { dismiss(); router.showCheckIn = true } label: { Label("Check-ins", systemImage: "qrcode") }
                Button { router.open(config.myRegistrationsURL, title: "My Registrations") } label: { Label("My registrations", systemImage: "ticket") }
                Button { dismiss(); router.selectedTab = .giving } label: { Label("My giving", systemImage: "heart") }
            }

            Section("Settings") {
                if proximity.authorization == .notDetermined {
                    Button { proximity.requestPermission() } label: { Label("Enable arrival check-in reminders", systemImage: "location") }
                } else if proximity.authorization == .authorizedWhenInUse {
                    Button { proximity.requestAlwaysPermission() } label: { Label("Remind me to check in when I arrive", systemImage: "location.fill") }
                }
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) { Label("Notifications & privacy", systemImage: "gear") }
                Button("Sign Out", role: .destructive) { auth.signOut(); profile = .idle }
            }
        }
    }

    private func load() async {
        if profile.value == nil { profile = .loading }
        do {
            let p: Profile = try await api.get("/v1/me", authenticated: true)
            profile = .loaded(p)
            auth.updateIdentity(name: p.nickname ?? p.firstName, avatar: p.avatarUrl)
        } catch { profile = .failed(error) }
    }

    private func upload(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let jpeg = image.resizedForAvatar().jpegData(compressionQuality: 0.85) ?? data
        do {
            let p: Profile = try await api.raw("PUT", "/v1/me/avatar", body: jpeg, contentType: "image/jpeg", authenticated: true)
            profile = .loaded(p)
            auth.updateIdentity(name: p.nickname ?? p.firstName, avatar: p.avatarUrl)
            uploadError = nil
        } catch { uploadError = error.localizedDescription }
    }
}

private extension UIImage {
    func resizedForAvatar(maxSide: CGFloat = 800) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
