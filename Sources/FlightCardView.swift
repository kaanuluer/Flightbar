import SwiftUI

struct FlightCardView: View {
    let aircraft: Aircraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if aircraft.isSample {
                Text("Sample aircraft. This is a demo, not a live flight.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(aircraft.callsignDisplay)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(aircraft.distanceText)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
            }
            if let identity = aircraft.identityLine {
                Text(identity)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            Text(aircraft.typeName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
            if let code = aircraft.typeCode, !code.isEmpty, code != aircraft.typeName {
                fact("Type code", code)
            }
            if let description = aircraft.typeDescription, description != aircraft.typeName {
                fact("Type detail", description)
            }
            if !aircraft.flagLabels.isEmpty {
                fact("DB flags", aircraft.flagLabels.joined(separator: " · "))
            }

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 1)
                .padding(.vertical, 2)

            fact("Altitude", aircraft.altitudeText)
            if let geometric = aircraft.geometricAltitudeText {
                fact("WGS84 alt", geometric)
            }
            fact("Speed", aircraft.speedText)
            fact("Track", aircraft.headingText)
            if let heading = aircraft.trueHeadingDegrees {
                fact("True hdg", Aircraft.direction(heading))
            }
            if let heading = aircraft.magneticHeadingDegrees {
                fact("Mag hdg", Aircraft.direction(heading))
            }
            fact("Vertical", aircraft.verticalText)
            if let rate = aircraft.geometricVerticalRateFPM {
                fact("Geom rate", Self.rate(rate))
            }
            if let squawk = aircraft.squawk {
                fact("Squawk", squawk)
            }
            if let category = aircraft.category {
                fact("Category", category)
            }
            fact("Position", aircraft.positionText)

            if aircraft.hasEmergency, let emergency = aircraft.emergency {
                Text("Emergency · \(emergency.uppercased())")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 320, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10).opacity(0.94))
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private static func rate(_ feetPerMinute: Double) -> String {
        if abs(feetPerMinute) < 64 { return "Level" }
        let amount = Int(abs(feetPerMinute).rounded())
        if feetPerMinute > 0 { return "Climbing · \(amount) ft/min" }
        return "Descending · \(amount) ft/min"
    }
}
