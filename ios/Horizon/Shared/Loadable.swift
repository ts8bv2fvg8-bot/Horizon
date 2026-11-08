import SwiftUI

enum Loadable<Value> {
    case idle, loading, loaded(Value), failed(Error)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }
}

/// Renders a `Loadable`, with loading, error and retry states.
struct LoadableView<Value, Content: View>: View {
    let state: Loadable<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        case .loaded(let value):
            content(value)
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await retry() } }.buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Shown in place of member-only content when signed out.
struct SignInPrompt: View {
    @Environment(AuthManager.self) private var auth
    let title: String
    let message: String
    @State private var error: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "person.crop.circle.badge.checkmark")
        } description: {
            VStack(spacing: 8) {
                Text(message)
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
        } actions: {
            Button {
                Task {
                    do { try await auth.signIn(); error = nil }
                    catch AuthError.cancelled {}
                    catch { self.error = error.localizedDescription }
                }
            } label: {
                Label("Sign in with Planning Center", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
