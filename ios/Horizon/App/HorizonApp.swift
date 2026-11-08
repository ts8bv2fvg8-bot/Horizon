import SwiftUI

@main
struct HorizonApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth = AuthManager()
    @State private var router = AppRouter()
    @State private var config = ConfigStore()
    @State private var proximity = CampusProximityMonitor()
    @State private var player = SermonPlayer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(auth)
                .environment(router)
                .environment(config)
                .environment(proximity)
                .environment(player)
                .environment(\.api, APIClient(auth: auth))
                .tint(Theme.accent)
                .task {
                    await config.load(api: APIClient(auth: auth))
                    proximity.start(campuses: config.campuses)
                }
                .onOpenURL { router.handleDeepLink($0) }
        }
    }
}
