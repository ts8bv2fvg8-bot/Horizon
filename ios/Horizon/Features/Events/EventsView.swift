import EventKit
import EventKitUI
import SwiftUI

struct EventsView: View {
    @Environment(\.api) private var api
    @Environment(AppRouter.self) private var router
    @Environment(ConfigStore.self) private var config
    @State private var events: Loadable<[ChurchEvent]> = .idle
    @State private var query = ""
    @State private var registrationOnly = false

    private func grouped(_ events: [ChurchEvent]) -> [(String, [ChurchEvent])] {
        let filtered = events.filter { e in
            (!registrationOnly || e.canRegister)
                && (query.isEmpty || e.title.localizedCaseInsensitiveContains(query) || e.summary.localizedCaseInsensitiveContains(query))
        }
        let byMonth = Dictionary(grouping: filtered) { $0.startsAt.map { $0.formatted(.dateTime.month(.wide).year()) } ?? "Ongoing" }
        return byMonth
            .map { ($0.key, $0.value) }
            .sorted { ($0.1.first?.startsAt ?? .distantFuture) < ($1.1.first?.startsAt ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            LoadableView(state: events, retry: load) { events in
                List {
                    Section {
                        Toggle("Open for registration", isOn: $registrationOnly)
                        Button { router.open(config.myRegistrationsURL, title: "My Registrations") } label: {
                            Label("My Registrations", systemImage: "ticket.fill")
                        }
                    }
                    ForEach(grouped(events), id: \.0) { month, items in
                        Section(month) {
                            ForEach(items) { event in
                                NavigationLink { EventDetailView(event: event) } label: { EventRow(event: event) }
                            }
                        }
                    }
                }
                .overlay {
                    if grouped(events).isEmpty { ContentUnavailableView.search(text: query) }
                }
            }
            .navigationTitle("Events")
            .searchable(text: $query, prompt: "Search events")
            .toolbar { ProfileToolbarButton() }
            .refreshable { await load() }
            .task { if events.value == nil { await load() } }
        }
    }

    private func load() async {
        if events.value == nil { events = .loading }
        do { events = .loaded(try await api.get("/v1/events")) } catch { if events.value == nil { events = .failed(error) } }
    }
}

struct EventRow: View {
    let event: ChurchEvent
    var body: some View {
        HStack(spacing: 12) {
            DateBadge(date: event.startsAt)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.headline).lineLimit(2)
                if let start = event.startsAt {
                    Text(event.allDay ? start.formatted(date: .complete, time: .omitted) : start.formatted(.dateTime.weekday().hour().minute()))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if event.canRegister {
                    Text("Registration open").font(.caption.bold()).foregroundStyle(Theme.accent)
                } else if event.atCapacity {
                    Text("Full").font(.caption.bold()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct DateBadge: View {
    let date: Date?
    var body: some View {
        VStack(spacing: 0) {
            Text(date?.formatted(.dateTime.month(.abbreviated)).uppercased() ?? "ANY").font(.caption2.bold()).foregroundStyle(Theme.accent)
            Text(date?.formatted(.dateTime.day()) ?? "—").font(.title2.bold())
        }
        .frame(width: 52, height: 52)
        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct EventCard: View {
    let event: ChurchEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: event.imageUrl, aspectRatio: 16 / 9)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline).lineLimit(1)
                Text(event.startsAt?.formatted(.dateTime.weekday().month().day().hour().minute()) ?? "Ongoing")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

struct EventDetailView: View {
    let event: ChurchEvent
    @Environment(AppRouter.self) private var router
    @State private var descriptionHeight: CGFloat = 200
    @State private var calendarEvent: EKEvent?
    private let store = EKEventStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(url: event.imageUrl).clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                Text(event.title).font(.title.bold())
                VStack(alignment: .leading, spacing: 8) {
                    if let start = event.startsAt {
                        Label(event.allDay ? start.formatted(date: .complete, time: .omitted) : start.formatted(date: .complete, time: .shortened), systemImage: "calendar")
                    }
                    if let location = event.location { Label(location, systemImage: "mappin.and.ellipse") }
                }
                .foregroundStyle(.secondary)

                HStack {
                    if let url = event.registrationUrl {
                        Button { router.open(url, title: "Register") } label: {
                            Text(event.atCapacity ? "Event Full" : event.registrationOpen ? "Register" : "Registration Closed").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!event.canRegister)
                    } else {
                        Button { router.open(event.detailsUrl, title: event.title) } label: { Text("Details").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                    }
                    if event.startsAt != nil {
                        Button { addToCalendar() } label: { Image(systemName: "calendar.badge.plus").frame(height: 22) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Add to calendar")
                    }
                }
                .controlSize(.large)

                if !event.descriptionHtml.isEmpty {
                    HTMLContentView(html: event.descriptionHtml, height: $descriptionHeight)
                        .frame(height: descriptionHeight)
                        .padding(.horizontal, -16)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ShareLink(item: event.detailsUrl) }
        .sheet(item: Binding(get: { calendarEvent.map(IdentifiedEvent.init) }, set: { calendarEvent = $0?.event })) { wrapper in
            CalendarEditView(event: wrapper.event, store: store)
        }
    }

    private func addToCalendar() {
        let e = EKEvent(eventStore: store)
        e.title = event.title
        e.startDate = event.startsAt
        e.endDate = event.endsAt ?? event.startsAt?.addingTimeInterval(3600)
        e.isAllDay = event.allDay
        e.location = event.location
        e.url = event.detailsUrl
        calendarEvent = e
    }
}

private struct IdentifiedEvent: Identifiable {
    let event: EKEvent
    var id: ObjectIdentifier { ObjectIdentifier(event) }
}

/// The system "add event" sheet. Needs no calendar permission prompt on iOS 17+.
struct CalendarEditView: UIViewControllerRepresentable {
    let event: EKEvent
    let store: EKEventStore
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.event = event
        vc.eventStore = store
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { dismiss() }
    }
}
