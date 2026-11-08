import SwiftUI

struct RootTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthManager.self) private var auth

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            GroupsView()
                .tabItem { Label("Groups", systemImage: "person.3.fill") }
                .tag(AppTab.groups)
            EventsView()
                .tabItem { Label("Events", systemImage: "calendar") }
                .tag(AppTab.events)
            GivingView()
                .tabItem { Label("Giving", systemImage: "heart.fill") }
                .tag(AppTab.giving)
            NextStepsView()
                .tabItem { Label("Next Steps", systemImage: "arrow.up.right.circle.fill") }
                .tag(AppTab.nextSteps)
        }
        .sheet(item: $router.web) { destination in
            WebFlowView(destination: destination)
        }
        .sheet(isPresented: $router.showProfile) { ProfileView() }
        .sheet(isPresented: $router.showServing) { NavigationStack { ServingView() } }
        .sheet(isPresented: $router.showCheckIn) { NavigationStack { CheckInView() } }
    }
}

/// Toolbar avatar button shown on every tab: opens the profile/account sheet.
struct ProfileToolbarButton: ToolbarContent {
    @Environment(AppRouter.self) private var router
    @Environment(AuthManager.self) private var auth

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { router.showProfile = true } label: {
                if auth.isSignedIn {
                    AvatarView(url: auth.avatarURL, name: auth.displayName ?? "", size: 32)
                } else {
                    Image(systemName: "person.crop.circle").font(.title2)
                }
            }
            .accessibilityLabel("My profile")
        }
    }
}
