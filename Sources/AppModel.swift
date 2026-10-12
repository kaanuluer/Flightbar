import AppKit
import Combine
import CoreLocation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var overhead: [Aircraft] = []
    @Published private(set) var recent: [Aircraft] = []
    @Published private(set) var statusLine = "Waiting for location access"
    @Published private(set) var detailLine = "Radius 3 km"
    @Published private(set) var menuSymbol = "location"
    @Published var radiusKm: Double = 3 {
        didSet {
            guard radiusKm != oldValue else { return }
            UserDefaults.standard.set(radiusKm, forKey: Keys.radius)
            refreshLabels()
            Task { await poll() }
        }
    }
    @Published var planeColor: PlaneTint = .white {
        didSet {
            guard planeColor != oldValue else { return }
            UserDefaults.standard.set(planeColor.rawValue, forKey: Keys.color)
            FlightLane.shared.applyTint(planeColor)
        }
    }

    private let locationService = LocationService()
    private var location: CLLocation?
    private var inside: Set<String> = []
    private var missed: [String: Int] = [:]
    private var polling = false
    private var nextPollAllowed = Date.distantPast
    private var pollTimer: Timer?
    private var lastUpdate: Date?
    private var lastError: String?

    var showsLocationSettings: Bool {
        authorization == .denied || authorization == .restricted
    }

    private init() {
        if let stored = UserDefaults.standard.object(forKey: Keys.radius) as? Double,
           Radar.radiusChoices.contains(stored) {
            radiusKm = stored
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.color),
           let tint = PlaneTint(rawValue: raw) {
            planeColor = tint
        }
    }

    func start() {
        MenuBarGeometry.shared.refresh()
        locationService.onAuthorization = { [weak self] status in
            Task { @MainActor in
                self?.applyAuthorization(status)
            }
        }
        locationService.onLocation = { [weak self] location in
            Task { @MainActor in
                self?.note(location)
            }
        }
        locationService.start()
        let timer = Timer(timeInterval: Radar.pollSeconds, repeats: true) { _ in
            Task { @MainActor in
                await AppModel.shared.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        if CommandLine.arguments.contains("--preview-card") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                MainActor.assumeIsolated { self?.preview(pinned: true) }
            }
        } else if CommandLine.arguments.contains("--preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                MainActor.assumeIsolated { self?.preview(pinned: false) }
            }
        }
    }

    func pollNow() {
        Task { await poll() }
    }

    func preview(pinned: Bool = false) {
        let sample = Aircraft(
            hex: "demo-\(UUID().uuidString.prefix(6))",
            callsign: "THY1",
            registration: "TC-JJZ",
            typeCode: "B77W",
            altitudeFeet: 4200,
            groundSpeedKnots: 230,
            trackDegrees: 268,
            verticalRateFPM: -780,
            latitude: location?.coordinate.latitude ?? 41,
            longitude: location?.coordinate.longitude ?? 29,
            distanceKm: 2.4,
            emergency: nil
        )
        recent.removeAll { $0.hex == sample.hex }
        recent.insert(sample, at: 0)
        if recent.count > 8 { recent.removeLast(recent.count - 8) }
        if pinned {
            FlightLane.shared.presentPinned(sample)
        } else {
            FlightLane.shared.present(sample)
        }
    }

    func openLocationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ]
        for text in candidates {
            guard let url = URL(string: text) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    private func applyAuthorization(_ status: CLAuthorizationStatus) {
        authorization = status
        refreshLabels()
    }

    private func note(_ location: CLLocation) {
        let firstFix = self.location == nil
        self.location = location
        refreshLabels()
        guard firstFix else { return }
        Task { await poll() }
    }

    private func poll() async {
        guard let location else { return }
        guard !polling, Date() >= nextPollAllowed else { return }
        polling = true
        defer { polling = false }
        switch await TrafficClient.fetch(around: location, radiusKm: radiusKm) {
        case let .success(aircraft):
            lastError = nil
            lastUpdate = Date()
            ingest(aircraft)
        case let .failure(error):
            lastError = error.message
            if case .rateLimited = error {
                nextPollAllowed = Date().addingTimeInterval(30)
            }
        }
        refreshLabels()
    }

    private func ingest(_ aircraft: [Aircraft]) {
        let watch = aircraft.filter { $0.distanceKm.isFinite }
        let byHex = Dictionary(watch.map { ($0.hex, $0) }, uniquingKeysWith: { first, _ in first })
        var nowInside = Set<String>()
        var entered: [Aircraft] = []

        let trigger = radiusKm
        let exit = Radar.exitKm(radiusKm)
        for (hex, plane) in byHex where plane.distanceKm <= trigger {
            nowInside.insert(hex)
            missed[hex] = 0
            if !inside.contains(hex) { entered.append(plane) }
        }
        for hex in inside where !nowInside.contains(hex) {
            if let plane = byHex[hex], plane.distanceKm <= exit {
                nowInside.insert(hex)
                missed[hex] = 0
            }
        }
        for hex in inside.subtracting(nowInside) {
            let count = (missed[hex] ?? 0) + 1
            missed[hex] = count
            if count <= 2 {
                nowInside.insert(hex)
            } else {
                missed[hex] = nil
            }
        }

        inside = nowInside
        overhead = watch
            .filter { nowInside.contains($0.hex) && $0.distanceKm <= exit }
            .sorted { $0.distanceKm < $1.distanceKm }

        for plane in entered.sorted(by: { $0.distanceKm < $1.distanceKm }) {
            recent.removeAll { $0.hex == plane.hex }
            recent.insert(plane, at: 0)
            FlightLane.shared.present(plane)
        }
        if recent.count > 8 { recent.removeLast(recent.count - 8) }
        for plane in watch {
            FlightLane.shared.refresh(plane)
            if let index = recent.firstIndex(where: { $0.hex == plane.hex }) {
                recent[index] = plane
            }
        }
    }

    private func refreshLabels() {
        switch authorization {
        case .denied, .restricted:
            menuSymbol = "location.slash"
            statusLine = "Location access is off"
        case .notDetermined:
            menuSymbol = "location"
            statusLine = "Waiting for location access"
        default:
            menuSymbol = "airplane"
            if location == nil {
                statusLine = "Getting your location"
            } else if overhead.isEmpty {
                statusLine = "Watching · no aircraft within \(Radar.label(radiusKm))"
            } else if overhead.count == 1 {
                statusLine = "Watching · 1 aircraft within \(Radar.label(radiusKm))"
            } else {
                statusLine = "Watching · \(overhead.count) aircraft within \(Radar.label(radiusKm))"
            }
        }

        if let lastError, lastUpdate == nil || Date().timeIntervalSince(lastUpdate ?? .distantPast) > 20 {
            detailLine = lastError
        } else if let lastUpdate {
            detailLine = "Last check \(Self.time.string(from: lastUpdate))"
        } else {
            detailLine = "Radius \(Radar.label(radiusKm))"
        }
    }

    private enum Keys {
        static let radius = "radiusKm"
        static let color = "planeColor"
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeStyle = .medium
        return formatter
    }()
}
