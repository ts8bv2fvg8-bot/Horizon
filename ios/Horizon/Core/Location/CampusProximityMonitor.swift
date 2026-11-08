import CoreLocation
import Observation
import UserNotifications

/// Watches for arrival on campus so the app can surface check-in. Uses region monitoring
/// (low power, works when the app is closed) and posts a local notification on Sundays or
/// whenever a check-in window is open.
@MainActor
@Observable
final class CampusProximityMonitor: NSObject, CLLocationManagerDelegate {
    private(set) var isOnCampus = false
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var lastLocation: CLLocation?

    private let manager = CLLocationManager()
    private var campuses: [Campus] = []

    override init() {
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    func start(campuses: [Campus]) {
        self.campuses = campuses
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else { return }
        startMonitoring()
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }

    private func startMonitoring() {
        manager.requestLocation()
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        for campus in campuses {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: campus.latitude, longitude: campus.longitude),
                radius: campus.geofenceRadiusMeters,
                identifier: "campus-\(campus.id)"
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    private func updateOnCampus(_ location: CLLocation) {
        lastLocation = location
        isOnCampus = campuses.contains { campus in
            location.distance(from: CLLocation(latitude: campus.latitude, longitude: campus.longitude)) <= campus.geofenceRadiusMeters
        }
    }

    private func notifyArrival() {
        let isSunday = Calendar.current.component(.weekday, from: Date()) == 1
        guard isSunday else { return }
        let content = UNMutableNotificationContent()
        content.title = "Welcome to Horizon!"
        content.body = "Tap to check in your family."
        content.userInfo = ["deepLink": "horizonchurch://check-in"]
        let request = UNNotificationRequest(identifier: "campus-arrival", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedAlways || status == .authorizedWhenInUse { self.startMonitoring() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.updateOnCampus(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            self.isOnCampus = true
            self.notifyArrival()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in self.isOnCampus = false }
    }
}
