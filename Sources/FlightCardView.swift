import SwiftUI

struct FlightCardView: View {
    let aircraft: Aircraft
    @ObservedObject private var detailsStore = AircraftDetailsStore.shared

    private var details: AircraftDetails? { detailsStore.entries[aircraft.detailsKey] }
    private var identity: String? {
        let parts = [details?.airline ?? aircraft.airlineName, aircraft.registration].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            if let identity {
                Text(identity)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            Text(details?.model ?? aircraft.typeName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 1)
                .padding(.vertical, 2)

            if let owner = details?.owner { fact("Owner", owner) }
            if let country = details?.country { fact("Country", country) }
            if let route = details?.liveRoute {
                fact("Route", route)
                Text("Current flight · FlightAware")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            } else if let route = details?.route {
                fact("Route", route)
                Text("Database route · unconfirmed for this flight")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            if let status = details?.status { fact("Status", status) }
            if let arrival = details?.arrival {
                fact("Arrival", arrival.formatted(date: .omitted, time: .shortened) + " local")
            }

            fact("Altitude", aircraft.altitudeText)
            fact("Speed", aircraft.speedText)
            fact("Heading", aircraft.headingText)
            fact("Vertical", aircraft.verticalText)

            if aircraft.hasEmergency, let emergency = aircraft.emergency {
                Text("Emergency · \(emergency.uppercased())")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            HStack {
                if let url = aircraft.moreInfoURL {
                    Link("More info…", destination: url)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.cyan)
                        .help("Open aircraft or flight details in your browser")
                }
                Spacer()
                if details?.loading == true {
                    ProgressView().controlSize(.mini)
                } else if details?.model != nil || details?.owner != nil || details?.route != nil {
                    Text("adsbdb").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
            }
            if let message = details?.message {
                Text(message).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            if let message = details?.flightAwareMessage {
                Text(message).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 286, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10).opacity(0.94))
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
