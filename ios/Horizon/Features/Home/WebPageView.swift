import SwiftUI

/// A page from www.horizoncommunity.church, rendered natively.
struct WebPageView: View {
    let slug: String
    let fallbackTitle: String
    @Environment(\.api) private var api
    @State private var page: Loadable<WebPage> = .idle
    @State private var height: CGFloat = 400

    var body: some View {
        ScrollView {
            LoadableView(state: page, retry: load) { page in
                VStack(alignment: .leading, spacing: 16) {
                    if let image = page.imageUrl {
                        RemoteImage(url: image).clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius)).padding(.horizontal)
                    }
                    HTMLContentView(html: page.html, height: $height).frame(height: height)
                    Link(destination: page.url) { Label("View on horizoncommunity.church", systemImage: "safari") }
                        .font(.footnote).padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(page.value?.title ?? fallbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { if page.value == nil { await load() } }
    }

    private func load() async {
        page = .loading
        do { page = .loaded(try await api.get("/v1/content/pages/\(slug)")) } catch { page = .failed(error) }
    }
}
