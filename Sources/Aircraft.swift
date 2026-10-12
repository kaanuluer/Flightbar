import Foundation

struct Aircraft: Identifiable, Equatable {
    var hex: String
    var callsign: String
    var registration: String?
    var typeCode: String?
    var altitudeFeet: Double?
    var groundSpeedKnots: Double?
    var trackDegrees: Double?
    var verticalRateFPM: Double?
    var latitude: Double
    var longitude: Double
    var distanceKm: Double
    var emergency: String?

    var id: String { hex }

    var callsignDisplay: String {
        if !callsign.isEmpty { return callsign }
        if let registration, !registration.isEmpty { return registration }
        return hex.uppercased()
    }

    var airlineName: String? {
        Catalog.airline(for: callsign)
    }

    var typeName: String {
        if let typeCode, let name = Catalog.aircraftName(for: typeCode) {
            return name
        }
        if let typeCode, !typeCode.isEmpty { return typeCode }
        return "Unknown type"
    }

    var identityLine: String? {
        let parts = [airlineName, registration].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var distanceText: String {
        Self.km.string(from: NSNumber(value: distanceKm)).map { "\($0) km" } ?? String(format: "%.1f km", distanceKm)
    }

    var altitudeText: String {
        guard let altitudeFeet else { return "Unknown" }
        let meters = altitudeFeet * 0.3048
        return "\(Self.whole.string(from: NSNumber(value: altitudeFeet)) ?? "\(Int(altitudeFeet))") ft · \(Self.whole.string(from: NSNumber(value: meters)) ?? "\(Int(meters))") m"
    }

    var speedText: String {
        guard let groundSpeedKnots else { return "Unknown" }
        let kmh = groundSpeedKnots * 1.852
        let knots = Self.whole.string(from: NSNumber(value: groundSpeedKnots)) ?? "\(Int(groundSpeedKnots))"
        let speed = Self.whole.string(from: NSNumber(value: kmh)) ?? "\(Int(kmh))"
        return "\(knots) kt · \(speed) km/h"
    }

    var headingText: String {
        guard let trackDegrees else { return "Unknown" }
        let normalized = (trackDegrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((normalized + 22.5) / 45.0) % 8
        return String(format: "%03.0f° %@", normalized, names[index])
    }

    var verticalText: String {
        guard let verticalRateFPM else { return "Unknown" }
        if abs(verticalRateFPM) < 64 { return "Level" }
        let amount = Self.whole.string(from: NSNumber(value: abs(verticalRateFPM))) ?? "\(Int(abs(verticalRateFPM)))"
        if verticalRateFPM > 0 { return "Climbing · \(amount) ft/min" }
        return "Descending · \(amount) ft/min"
    }

    var menuLine: String {
        "\(callsignDisplay) · \(distanceText) · \(altitudeText)"
    }

    var hasEmergency: Bool {
        guard let emergency else { return false }
        return emergency.lowercased() != "none" && !emergency.isEmpty
    }

    private static let whole: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let km: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

enum Radar {
    static let radiusChoices: [Double] = [1, 2, 3, 5, 8, 10, 15, 20, 30, 50]
    static let pollSeconds: TimeInterval = 5

    static func exitKm(_ radiusKm: Double) -> Double {
        radiusKm * 1.15
    }

    static func queryNm(_ radiusKm: Double) -> Int {
        let nauticalMiles = radiusKm / 1.852
        return min(100, max(2, Int(ceil(nauticalMiles * 1.25 + 1))))
    }

    static func label(_ radiusKm: Double) -> String {
        "\(Int(radiusKm.rounded())) km"
    }
}

enum FlightParser {
    static func aircraft(from row: [String: Any], user: (latitude: Double, longitude: Double)) -> Aircraft? {
        guard let hex = string(row["hex"]), !hex.isEmpty else { return nil }
        guard let latitude = number(row["lat"]), let longitude = number(row["lon"]) else { return nil }
        if abs(latitude) < 0.01, abs(longitude) < 0.01 { return nil }
        if let seen = number(row["seen_pos"]), seen > 30 { return nil }

        let altitude = number(row["alt_baro"])
        let isGround: Bool = {
            if let text = row["alt_baro"] as? String, text.lowercased() == "ground" { return true }
            return false
        }()
        if isGround { return nil }
        let speed = number(row["gs"])
        if let altitude, altitude < 150, (speed ?? 0) < 40 { return nil }

        let distance = haversineKm(
            latitude1: user.latitude,
            longitude1: user.longitude,
            latitude2: latitude,
            longitude2: longitude
        )
        let emergency = string(row["emergency"])
        return Aircraft(
            hex: hex.lowercased(),
            callsign: string(row["flight"])?.uppercased() ?? "",
            registration: string(row["r"]),
            typeCode: string(row["t"])?.uppercased(),
            altitudeFeet: altitude,
            groundSpeedKnots: speed,
            trackDegrees: number(row["track"]) ?? number(row["true_heading"]) ?? number(row["mag_heading"]),
            verticalRateFPM: number(row["baro_rate"]) ?? number(row["geom_rate"]),
            latitude: latitude,
            longitude: longitude,
            distanceKm: distance,
            emergency: emergency
        )
    }

    static func haversineKm(latitude1: Double, longitude1: Double, latitude2: Double, longitude2: Double) -> Double {
        let earth = 6371.0
        let dLat = (latitude2 - latitude1) * .pi / 180
        let dLon = (longitude2 - longitude1) * .pi / 180
        let lat1 = latitude1 * .pi / 180
        let lat2 = latitude2 * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earth * asin(min(1, sqrt(a)))
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String, let value = Double(text) { return value }
        return nil
    }
}
