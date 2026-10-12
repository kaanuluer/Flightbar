import CoreLocation
import Foundation

enum TrafficClient {
    static func fetch(around location: CLLocation, radiusKm: Double) async -> Result<[Aircraft], TrafficError> {
        let user = (latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let lat = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), user.latitude)
        let lon = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), user.longitude)
        let path = "/lat/\(lat)/lon/\(lon)/dist/\(Radar.queryNm(radiusKm))"
        let hosts = [
            "https://api.adsb.lol/v2",
            "https://opendata.adsb.fi/api/v2"
        ]
        var lastError: TrafficError = .network
        for host in hosts {
            guard let url = URL(string: host + path) else { continue }
            switch await load(url: url, user: user) {
            case let .success(aircraft):
                return .success(aircraft)
            case let .failure(error):
                lastError = error
                if case .rateLimited = error { return .failure(error) }
            }
        }
        return .failure(lastError)
    }

    private static func load(url: URL, user: (latitude: Double, longitude: Double)) async -> Result<[Aircraft], TrafficError> {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Flightbar/1.2 (menu bar)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 { return .failure(.rateLimited) }
            guard (200..<300).contains(status) else { return .failure(.badResponse) }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.badResponse)
            }
            let rows = json["ac"] as? [[String: Any]] ?? []
            let aircraft = rows.compactMap { FlightParser.aircraft(from: $0, user: user) }
            return .success(aircraft)
        } catch {
            return .failure(.network)
        }
    }
}

enum TrafficError: Error {
    case network
    case badResponse
    case rateLimited

    var message: String {
        switch self {
        case .network, .badResponse:
            return "Couldn’t load aircraft data. Will try again."
        case .rateLimited:
            return "The data source is busy. Will try again shortly."
        }
    }
}
