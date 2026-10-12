import CoreLocation
import Foundation

final class LocationService: NSObject, CLLocationManagerDelegate {
    var onLocation: ((CLLocation) -> Void)?
    var onAuthorization: ((CLAuthorizationStatus) -> Void)?

    private let manager = CLLocationManager()
    private var configured = false

    /// Reading status does not present a dialog.
    var authorizationStatus: CLAuthorizationStatus {
        configureIfNeeded()
        return manager.authorizationStatus
    }

    /// Presents the system prompt when status is not determined.
    /// The app must be in the foreground first. A menu-bar-only app that calls
    /// this at launch never shows the dialog, and status stays notDetermined.
    func beginRequesting() {
        configureIfNeeded()
        onAuthorization?(manager.authorizationStatus)
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized:
            beginUpdates()
        default:
            break
        }
    }

    func stop() {
        guard configured else { return }
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorization?(manager.authorizationStatus)
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorized:
            beginUpdates()
        default:
            stop()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocation?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("Flightbar location error: \(error.localizedDescription)")
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        manager.activityType = .other
    }

    private func beginUpdates() {
        if manager.accuracyAuthorization == .reducedAccuracy {
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "FlightbarPrecise") { _ in }
        }
        manager.startUpdatingLocation()
    }
}

enum CoordinateEntry {
    /// Accepts "41.01, 28.98" and "41.01 28.98". Anything else is a place name.
    static func parse(_ text: String) -> CLLocationCoordinate2D? {
        let pattern = #"^\s*([+-]?\d+(?:\.\d+)?)\s*[, ]\s*([+-]?\d+(?:\.\d+)?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let latRange = Range(match.range(at: 1), in: text),
              let lonRange = Range(match.range(at: 2), in: text),
              let latitude = Double(text[latRange]),
              let longitude = Double(text[lonRange]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
