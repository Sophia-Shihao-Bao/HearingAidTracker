import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject {
    // Published values your UI can bind to
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var lastUpdate: Date?
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var statusText: String = "Location idle"

    // Internals
    private let manager = CLLocationManager()
    private var timer: Timer?
    private(set) var interval: TimeInterval = 30

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = true
        // Foreground-only: do NOT set allowsBackgroundLocationUpdates unless you want background tracking.
    }

    // One-time permission prompt / convenience
    func request() {
        let status = manager.authorizationStatus
        authorization = status
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            statusText = "Location permission denied/restricted"
        default:
            break
        }
    }

    // Start a periodic "poll" using requestLocation() every N seconds
    func startPeriodicUpdates(seconds: TimeInterval = 30) {
        interval = seconds
        statusText = "Location updating every \(Int(seconds))s"
        // Kick off immediately with a one-shot
        request()
        manager.requestLocation()

        // Reset timer
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Only ask if authorized; avoids spamming errors
            let st = self.manager.authorizationStatus
            if st == .authorizedWhenInUse || st == .authorizedAlways {
                self.manager.requestLocation()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopPeriodicUpdates() {
        timer?.invalidate()
        timer = nil
        statusText = "Location stopped"
    }

    // Optional: continuous updates switch (not used here, but handy)
    func startContinuous() {
        request()
        manager.startUpdatingLocation()
        statusText = "Location continuous"
    }

    func stopContinuous() {
        manager.stopUpdatingLocation()
        statusText = "Location stopped"
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        switch authorization {
        case .authorizedWhenInUse, .authorizedAlways:
            statusText = "Location authorized"
        case .denied:
            statusText = "Location denied"
        case .restricted:
            statusText = "Location restricted"
        case .notDetermined:
            statusText = "Location not determined"
        @unknown default:
            statusText = "Location unknown"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        coordinate = latest.coordinate
        lastUpdate = Date()
        // You can print for debugging if you like:
        // print("[LOC] \(latest.coordinate.latitude), \(latest.coordinate.longitude) @ \(latest.timestamp)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusText = "Location error: \(error.localizedDescription)"
        // Don’t spam—Timer will try again on the next tick.
    }
}
