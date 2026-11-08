import SwiftUI

/// The discipleship pathway: Start Here → Know God → Find Community → Serve → Care.
/// Sections come from /v1/config so staff can edit them without an app update; every step
/// points at a real Planning Center form, signup or group type.
struct NextStepsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ConfigStore.self) private var config
    @AppStorage("completedNextSteps") private var completedRaw = ""

    private var completed: Set<String> { Set(completedRaw.split(separator: ",").map(String.init)) }

    private func toggle(_ id: String) {
        var set = completed
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        completedRaw = set.sorted().joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What's your next step?").font(.title2.bold())
                        Text("Wherever you are in your journey, there's a next step for you at Horizon.").foregroundStyle(.secondary)
                        let total = config.nextSteps.flatMap(\.steps).count
                        if total > 0 {
                            ProgressView(value: Double(completed.count), total: Double(total)).tint(Theme.accent).padding(.top, 6)
                            Text("\(completed.count) of \(total) steps taken").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if config.nextSteps.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                }

                ForEach(config.nextSteps) { section in
                    Section(section.title) {
                        ForEach(section.steps) { step in
                            Button { router.perform(step.action) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: step.systemImage)
                                        .font(.title3)
                                        .frame(width: 40, height: 40)
                                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                        .foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.title).font(.headline)
                                        Text(step.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if completed.contains(step.id) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(completed.contains(step.id) ? "Undo" : "Done") { toggle(step.id) }.tint(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Next Steps")
            .toolbar { ProfileToolbarButton() }
        }
    }
}
