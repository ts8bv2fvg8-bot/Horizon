import SwiftUI

struct SermonHeroCard: View {
    let sermon: Sermon
    @Environment(SermonPlayer.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: sermon.imageUrl, aspectRatio: 16 / 9)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sermon.title).font(.headline).lineLimit(2)
                    Text([sermon.speaker, sermon.publishedAt?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if sermon.audioUrl != nil {
                    Button { player.current?.id == sermon.id ? player.toggle() : player.play(sermon) } label: {
                        Image(systemName: player.current?.id == sermon.id && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                    }
                    .accessibilityLabel("Play message")
                }
            }
            .padding()
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

struct SermonsView: View {
    let sermons: [Sermon]
    @State private var query = ""

    private var filtered: [Sermon] {
        query.isEmpty ? sermons : sermons.filter { $0.title.localizedCaseInsensitiveContains(query) || ($0.speaker ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List(filtered) { sermon in
            NavigationLink { SermonDetailView(sermon: sermon) } label: {
                HStack(spacing: 12) {
                    RemoteImage(url: sermon.imageUrl, aspectRatio: 16 / 9).frame(width: 96).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sermon.title).font(.headline).lineLimit(2)
                        Text(sermon.publishedAt?.formatted(date: .abbreviated, time: .omitted) ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Search messages")
        .navigationTitle("Messages")
    }
}

struct SermonDetailView: View {
    let sermon: Sermon
    @Environment(SermonPlayer.self) private var player
    @Environment(AppRouter.self) private var router

    private var isCurrent: Bool { player.current?.id == sermon.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(url: sermon.imageUrl, aspectRatio: 16 / 9)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                Text(sermon.title).font(.title2.bold())
                Text([sermon.speaker, sermon.publishedAt?.formatted(date: .long, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)

                if sermon.audioUrl != nil {
                    VStack(spacing: 8) {
                        Slider(value: Binding(get: { isCurrent ? player.progress : 0 }, set: { player.seek(to: $0) }),
                               in: 0...max(1, isCurrent ? player.duration : Double(sermon.durationSeconds ?? 1)))
                            .disabled(!isCurrent)
                        HStack(spacing: 40) {
                            Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }.disabled(!isCurrent)
                            Button { isCurrent ? player.toggle() : player.play(sermon) } label: {
                                Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 56))
                            }
                            Button { player.skip(30) } label: { Image(systemName: "goforward.30") }.disabled(!isCurrent)
                        }
                        .font(.title2)
                    }
                    .padding()
                    .card()
                }

                if let url = URL(string: sermon.link), !sermon.link.isEmpty {
                    Button { router.open(url, title: sermon.title) } label: {
                        Label("Watch on Church Center", systemImage: "play.rectangle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                if !sermon.summary.isEmpty { Text(sermon.summary) }
            }
            .padding()
        }
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = URL(string: sermon.link) { ShareLink(item: url) }
        }
    }
}
