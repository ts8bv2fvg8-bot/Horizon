import SwiftUI

/// Giving runs on Church Center Giving, opened in Safari View Controller.
///
/// Why not a native card form: Planning Center's Giving API records donations that were
/// processed elsewhere — it doesn't process cards. Church Center Giving handles payment
/// methods, Apple Pay, recurring gifts and receipts. Opening it in Safari also matches App
/// Store guideline 3.2.2, which asks apps that aren't approved nonprofits to collect
/// donations outside the app (Safari or SMS).
struct GivingView: View {
    @Environment(\.api) private var api
    @Environment(AuthManager.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ConfigStore.self) private var config
    @State private var summary: Loadable<GivingSummary> = .idle

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "heart.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.accent)
                        Text("Generosity changes lives").font(.title2.bold())
                        Text("Your giving fuels the mission of Horizon Community Church in Tualatin and around the world.")
                            .foregroundStyle(.secondary)
                        Button { router.open(config.giveURL, title: "Give", style: .safari) } label: {
                            Label("Give Now", systemImage: "arrow.up.right").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding(.vertical, 8)
                }

                if auth.isSignedIn {
                    givingHistory
                } else {
                    Section {
                        Text("Sign in to see your giving history and recurring gifts.").foregroundStyle(.secondary)
                    }
                }

                Section("Manage") {
                    // Church Center's giving page links to the member's gift history, recurring
                    // gifts, payment methods and statements once they're signed in.
                    Button { router.open(config.giveURL, title: "Giving", style: .safari) } label: {
                        Label("Recurring gifts, payment methods & statements", systemImage: "creditcard")
                    }
                }

                Section("Other ways to give") {
                    Label("In person during any service", systemImage: "building.columns")
                    Label("Mail a check to \(config.primaryCampus.fullAddress)", systemImage: "envelope")
                }
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Giving")
            .toolbar { ProfileToolbarButton() }
            .refreshable { await load() }
            .task(id: auth.isSignedIn) { if auth.isSignedIn { await load() } }
        }
    }

    @ViewBuilder private var givingHistory: some View {
        switch summary {
        case .loaded(let s):
            Section("\(String(s.year)) Giving") {
                HStack {
                    Text("Year to date")
                    Spacer()
                    Text(s.yearToDateCents.centsFormatted).font(.title3.bold()).monospacedDigit()
                }
            }
            if !s.recurring.isEmpty {
                Section("Recurring") {
                    ForEach(s.recurring) { r in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(r.amountCents.centsFormatted).font(.headline)
                                Text(r.schedule ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let next = r.nextOccurrence {
                                Text("Next \(next.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Recent Gifts") {
                if s.gifts.isEmpty { Text("No gifts yet.").foregroundStyle(.secondary) }
                ForEach(s.gifts.prefix(20)) { gift in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(gift.funds.joined(separator: ", ")).font(.headline)
                            Text([gift.receivedAt?.formatted(date: .abbreviated, time: .omitted), gift.method].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(gift.amountCents.centsFormatted).monospacedDigit().strikethrough(gift.refunded)
                    }
                }
            }
        case .failed(let error):
            Section { Text(error.localizedDescription).foregroundStyle(.secondary) }
        default:
            Section { ProgressView().frame(maxWidth: .infinity) }
        }
    }

    private func load() async {
        if summary.value == nil { summary = .loading }
        do { summary = .loaded(try await api.get("/v1/me/giving", authenticated: true)) } catch { summary = .failed(error) }
    }
}
