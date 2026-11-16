import SwiftUI

/// First-launch screen: members log in with their Planning Center username (email) and
/// password.
///
/// The username and password are entered on Planning Center's own login page, shown in a
/// secure system sheet (ASWebAuthenticationSession), never in a text field owned by this app.
/// Planning Center only allows third-party apps to sign people in this way (OAuth 2.0 +
/// PKCE). It also means:
/// * the app never sees or stores the member's password, only a revocable token;
/// * Planning Center's two-step verification and "Forgot password" keep working;
/// * iOS offers saved Planning Center passwords from iCloud Keychain.
struct SignInView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var signingIn = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Theme.navy.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Theme.accent)
                    Text("Horizon Community Church").font(.title.bold()).multilineTextAlignment(.center)
                    Text("Tualatin, Oregon").foregroundStyle(.white.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 14) {
                    Feature(icon: "person.crop.circle", text: "Update your profile and household")
                    Feature(icon: "calendar", text: "See your serving schedule and set preferences")
                    Feature(icon: "person.3", text: "Find a group and take attendance")
                    Feature(icon: "ticket", text: "Register for events and check in on campus")
                    Feature(icon: "heart", text: "Give through Planning Center")
                }
                .padding(.horizontal, 8)

                Spacer()

                VStack(spacing: 12) {
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            if signingIn { ProgressView().tint(.white) }
                            Text("Log in with Planning Center").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(signingIn)

                    Text("Use the same email and password you use for Planning Center or Church Center. If you've never set a password, choose \"Forgot password\" on the next screen to create one.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)

                    Button("Continue as Guest") { dismiss() }
                        .foregroundStyle(.white)
                        .padding(.top, 4)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
    }

    private func signIn() async {
        signingIn = true
        defer { signingIn = false }
        do {
            try await auth.signIn()
            error = nil
            dismiss()
        } catch AuthError.cancelled {
            // Member closed the login sheet; stay here.
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct Feature: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 28).foregroundStyle(Theme.accent)
            Text(text)
        }
    }
}
