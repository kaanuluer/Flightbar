import AppKit
import Combine
import CoreLocation
import SwiftUI
import UserNotifications

enum PlaceSource: String {
    case unset
    case device
    case manual
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var overhead: [Aircraft] = []
    @Published private(set) var recent: [Aircraft] = []
    @Published private(set) var statusLine = localized("Waiting for location access")
    @Published private(set) var detailLine = localized("Radius %@", "3 km")
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
    @Published var fliesAcrossMenuBar = false {
        didSet {
            guard fliesAcrossMenuBar != oldValue else { return }
            UserDefaults.standard.set(fliesAcrossMenuBar, forKey: Keys.fly)
        }
    }
    @Published var showsPlaneCount = false {
        didSet {
            guard showsPlaneCount != oldValue else { return }
            UserDefaults.standard.set(showsPlaneCount, forKey: Keys.count)
        }
    }
    @Published var flagFilter: DbFlagFilter = .all {
        didSet {
            guard flagFilter != oldValue else { return }
            UserDefaults.standard.set(flagFilter.rawValue, forKey: Keys.flags)
            Task { await poll() }
        }
    }
    @Published var notificationsEnabled = false {
        didSet {
            guard !suppressNotificationWrite, notificationsEnabled != oldValue else { return }
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notify)
            guard notificationsEnabled else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                Task { @MainActor in
                    guard !granted else { return }
                    self.suppressNotificationWrite = true
                    self.notificationsEnabled = false
                    self.suppressNotificationWrite = false
                    self.placeNote = localized("Notifications stay off until they’re allowed in System Settings → Notifications.")
                }
            }
        }
    }
    @Published var notifyQuery = "" {
        didSet {
            guard notifyQuery != oldValue else { return }
            UserDefaults.standard.set(notifyQuery, forKey: Keys.notifyQuery)
        }
    }
    @Published private(set) var placeSource: PlaceSource = .unset
    @Published private(set) var manualLabel = ""
    @Published var placeNote = ""

    private let locationService = LocationService()
    private var suppressNotificationWrite = false
    private var location: CLLocation?
    private var inside: Set<String> = []
    private var missed: [String: Int] = [:]
    private var polling = false
    private var nextPollAllowed = Date.distantPast
    private var pollTimer: Timer?
    private var lastUpdate: Date?
    private var lastError: String?

    var showsLocationSettings: Bool {
        placeSource == .device && (authorization == .denied || authorization == .restricted)
    }

    var needsPlaceChoice: Bool {
        switch placeSource {
        case .manual:
            return location == nil
        case .device:
            return false
        case .unset:
            return true
        }
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
        fliesAcrossMenuBar = UserDefaults.standard.bool(forKey: Keys.fly)
        showsPlaneCount = UserDefaults.standard.bool(forKey: Keys.count)
        if let raw = UserDefaults.standard.string(forKey: Keys.flags),
           let filter = DbFlagFilter(rawValue: raw) {
            flagFilter = filter
        }
        notificationsEnabled = UserDefaults.standard.bool(forKey: Keys.notify)
        notifyQuery = UserDefaults.standard.string(forKey: Keys.notifyQuery) ?? ""
        if let raw = UserDefaults.standard.string(forKey: Keys.place),
           let source = PlaceSource(rawValue: raw) {
            placeSource = source
        }
        manualLabel = UserDefaults.standard.string(forKey: Keys.manualLabel) ?? ""
    }

    func start() {
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
        authorization = locationService.authorizationStatus
        switch placeSource {
        case .manual:
            restoreManualPlace()
        case .device:
            locationService.beginRequesting()
        case .unset:
            if authorization == .authorized || authorization == .authorizedAlways {
                placeSource = .device
                UserDefaults.standard.set(PlaceSource.device.rawValue, forKey: Keys.place)
                locationService.beginRequesting()
            }
        }
        let timer = Timer(timeInterval: Radar.pollSeconds, repeats: true) { _ in
            Task { @MainActor in
                await AppModel.shared.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        refreshLabels()

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
        let sample = makeSample()
        recent.removeAll { $0.isSample }
        recent.insert(sample, at: 0)
        if recent.count > 8 { recent.removeLast(recent.count - 8) }
        if pinned || CommandLine.arguments.contains("--preview-card") {
            FlightLane.shared.presentPinned(sample)
            return
        }
        FlightLane.shared.showDetails(sample, under: nil)
        if fliesAcrossMenuBar || CommandLine.arguments.contains("--preview") {
            FlightLane.shared.present(sample)
        }
    }

    func aircraft(hex: String) -> Aircraft? {
        overhead.first { $0.hex == hex } ?? recent.first { $0.hex == hex }
    }

    /// Brings Flightbar forward, then asks. The system dialog does not appear while the app is an agent.
    func useDeviceLocation() {
        placeSource = .device
        UserDefaults.standard.set(PlaceSource.device.rawValue, forKey: Keys.place)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.locationService.beginRequesting()
                self.applyAuthorization(self.locationService.authorizationStatus)
            }
        }
    }

    func useTypedPlace(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            placeNote = localized("Enter a city, a postal code, or latitude, longitude.")
            return
        }
        if let coordinate = CoordinateEntry.parse(trimmed) {
            useCoordinates(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), label: trimmed)
            return
        }
        placeNote = localized("Looking up %@. A city or postal code is sent to Apple’s geocoder.", trimmed)
        CLGeocoder().geocodeAddressString(trimmed) { [weak self] marks, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let location = marks?.first?.location else {
                    self.placeNote = localized("Couldn’t find that place. Try a city, a postal code, or latitude, longitude.")
                    return
                }
                let mark = marks?.first
                let parts = [mark?.locality, mark?.administrativeArea, mark?.postalCode, mark?.country]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                let label = parts.isEmpty ? trimmed : parts.joined(separator: ", ")
                self.useCoordinates(location, label: label)
            }
        }
    }

    func useCoordinates(_ location: CLLocation, label: String) {
        locationService.stop()
        placeSource = .manual
        manualLabel = label
        UserDefaults.standard.set(PlaceSource.manual.rawValue, forKey: Keys.place)
        UserDefaults.standard.set(location.coordinate.latitude, forKey: Keys.manualLat)
        UserDefaults.standard.set(location.coordinate.longitude, forKey: Keys.manualLon)
        UserDefaults.standard.set(label, forKey: Keys.manualLabel)
        self.location = location
        placeNote = localized("Using %@. Location Services is not used.", label)
        refreshLabels()
        Task { await poll() }
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
        if placeSource == .device {
            switch status {
            case .authorized, .authorizedAlways:
                placeNote = localized("Using Location Services.")
            case .denied, .restricted:
                placeNote = localized("Location access is off. Turn it on in Location Settings, or enter a place.")
            case .notDetermined:
                placeNote = localized("macOS will ask for location while Flightbar is open.")
            default:
                break
            }
        }
        refreshLabels()
    }

    private func note(_ location: CLLocation) {
        guard placeSource == .device else { return }
        let firstFix = self.location == nil
        self.location = location
        refreshLabels()
        guard firstFix else { return }
        Task { await poll() }
    }

    private func restoreManualPlace() {
        let latitude = UserDefaults.standard.double(forKey: Keys.manualLat)
        let longitude = UserDefaults.standard.double(forKey: Keys.manualLon)
        guard UserDefaults.standard.object(forKey: Keys.manualLat) != nil,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return }
        location = CLLocation(latitude: latitude, longitude: longitude)
        placeNote = manualLabel.isEmpty ? localized("Using a saved place.") : localized("Using %@.", manualLabel)
        Task { await poll() }
    }

    private func makeSample() -> Aircraft {
        let coordinate = location?.coordinate
        return Aircraft(
            hex: "demo-\(UUID().uuidString.prefix(6))",
            callsign: "THY1",
            registration: "TC-JJZ",
            typeCode: "B77W",
            altitudeFeet: 4200,
            groundSpeedKnots: 230,
            trackDegrees: 268,
            verticalRateFPM: -780,
            latitude: coordinate?.latitude ?? 41.0082,
            longitude: coordinate?.longitude ?? 28.9784,
            distanceKm: 2.4,
            emergency: nil,
            geometricAltitudeFeet: 4310,
            geometricVerticalRateFPM: -760,
            squawk: "1000",
            trueHeadingDegrees: 266,
            magneticHeadingDegrees: 270,
            category: "A5",
            dbFlags: nil,
            typeDescription: "Boeing 777-300ER",
            isSample: true
        )
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
        let watch = aircraft.filter { $0.distanceKm.isFinite && $0.matches(flagFilter) }
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
            if fliesAcrossMenuBar {
                FlightLane.shared.present(plane)
            }
            announce(plane)
        }
        if recent.count > 8 { recent.removeLast(recent.count - 8) }
        for plane in watch {
            FlightLane.shared.refresh(plane)
            if let index = recent.firstIndex(where: { $0.hex == plane.hex }) {
                recent[index] = plane
            }
        }
    }

    private func announce(_ aircraft: Aircraft) {
        guard notificationsEnabled, !aircraft.isSample else { return }
        let query = notifyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let haystack = [
                aircraft.callsign,
                aircraft.registration,
                aircraft.typeCode,
                aircraft.typeName,
                aircraft.typeDescription
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
            guard haystack.contains(query.lowercased()) else { return }
        }
        let content = UNMutableNotificationContent()
        content.title = localized("%@ entered", aircraft.callsignDisplay)
        var parts = [aircraft.typeName, aircraft.distanceText, aircraft.altitudeText]
        if !aircraft.flagLabels.isEmpty {
            parts.append(aircraft.flagLabels.joined(separator: ", "))
        }
        content.body = parts.joined(separator: " · ")
        let request = UNNotificationRequest(
            identifier: "flightbar-\(aircraft.hex)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func refreshLabels() {
        let range = Radar.label(radiusKm)
        if placeSource == .unset && location == nil {
            if authorization == .denied || authorization == .restricted {
                statusLine = localized("Location access is off. Enter a place instead.")
            } else {
                statusLine = localized("Choose Location Services or enter a place")
            }
        } else if placeSource == .device && (authorization == .denied || authorization == .restricted) {
            statusLine = localized("Location access is off. Enter a place instead.")
        } else if location == nil {
            statusLine = placeSource == .device
                ? localized("Getting your location")
                : localized("Choose Location Services or enter a place")
        } else if overhead.isEmpty {
            statusLine = localized("Watching%1$@ · no aircraft within %2$@%3$@", placePhrase, range, filterPhrase)
        } else if overhead.count == 1 {
            statusLine = localized("Watching%1$@ · 1 aircraft within %2$@%3$@", placePhrase, range, filterPhrase)
        } else {
            statusLine = localized(
                "Watching%1$@ · %2$@ aircraft within %3$@%4$@",
                placePhrase,
                "\(overhead.count)",
                range,
                filterPhrase
            )
        }

        if let lastError, lastUpdate == nil || Date().timeIntervalSince(lastUpdate ?? .distantPast) > 20 {
            detailLine = lastError
        } else if let lastUpdate {
            detailLine = localized("Last check %@", Self.time.string(from: lastUpdate))
        } else {
            detailLine = localized("Radius %@", range)
        }
    }

    private var placePhrase: String {
        guard placeSource == .manual, !manualLabel.isEmpty else { return "" }
        return localized(" near %@", manualLabel)
    }

    private var filterPhrase: String {
        flagFilter == .all ? "" : " · \(flagFilter.menuTitle)"
    }

    private enum Keys {
        static let radius = "radiusKm"
        static let color = "planeColor"
        static let fly = "fliesAcrossMenuBar"
        static let count = "showsPlaneCount"
        static let flags = "flagFilter"
        static let notify = "notificationsEnabled"
        static let notifyQuery = "notifyQuery"
        static let place = "placeSource"
        static let manualLat = "manualLatitude"
        static let manualLon = "manualLongitude"
        static let manualLabel = "manualLabel"
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .medium
        return formatter
    }()
}
