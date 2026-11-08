import SwiftUI

/// Brand styling. Placeholder colors (navy + sunrise orange) — swap in the exact hex values
/// from Horizon's brand guide in Assets.xcassets.
enum Theme {
    static let accent = Color("AccentColor")
    static let navy = Color("BrandNavy")
    static let cornerRadius: CGFloat = 16
    static let heroGradient = LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal)
    }
}

struct AvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 44

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Theme.navy
                Text(initials).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct RemoteImage: View {
    let url: URL?
    var aspectRatio: CGFloat = 16 / 9

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: LinearGradient(colors: [Theme.navy, Theme.navy.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
            }
            .clipped()
    }
}

extension Int {
    /// Formats cents as currency, e.g. 12500 → "$125.00".
    var centsFormatted: String {
        (Double(self) / 100).formatted(.currency(code: "USD"))
    }
}
