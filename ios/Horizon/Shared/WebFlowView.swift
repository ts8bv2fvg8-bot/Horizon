import SafariServices
import SwiftUI
import WebKit

/// Presents a Church Center flow (registration, group join, attendance, check-in, forms).
///
/// Planning Center doesn't expose write APIs for registrations, check-ins or group
/// attendance, so — like Church Center's own app and most third-party church apps — those
/// steps run on Church Center's mobile web pages inside the app. The web view uses the
/// default (persistent) data store, so members sign into Church Center once and stay
/// signed in.
struct WebFlowView: View {
    let destination: WebDestination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch destination.style {
        case .safari:
            SafariView(url: destination.url).ignoresSafeArea()
        case .inApp:
            NavigationStack {
                ChurchCenterWebView(url: destination.url)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(destination.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(item: destination.url) { Image(systemName: "square.and.arrow.up") }
                        }
                    }
            }
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Theme.accent)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

struct ChurchCenterWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = nil
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        /// Keep Church Center and Planning Center inside the app; open everything else
        /// (maps, phone, email, payment providers) externally.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, let host = url.host?.lowercased() else { return decisionHandler(.allow) }
            let inApp = ["churchcenter.com", "planningcenteronline.com", "planningcenter.com", "horizoncommunity.church", "stripe.com", "hcaptcha.com", "recaptcha.net", "google.com", "gstatic.com"]
            if url.scheme == "http" || url.scheme == "https", inApp.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                decisionHandler(.allow)
            } else if action.navigationType == .linkActivated || !(url.scheme?.hasPrefix("http") ?? false) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

/// Renders website HTML with native typography (used for pages pulled from
/// horizoncommunity.church).
struct HTMLContentView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        let document = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          body { font: -apple-system-body; margin: 0; padding: 0 16px; color: CanvasText; background: transparent; }
          h1,h2,h3 { font-family: -apple-system; line-height: 1.2; }
          img, video, iframe { max-width: 100%; height: auto; border-radius: 12px; }
          a { color: #F4852E; }
        </style></head><body>\(html)</body></html>
        """
        webView.loadHTMLString(document, baseURL: AppConfig.websiteURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        let height: Binding<CGFloat>
        init(height: Binding<CGFloat>) { self.height = height }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { value, _ in
                if let h = value as? CGFloat { DispatchQueue.main.async { self.height.wrappedValue = h + 24 } }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
