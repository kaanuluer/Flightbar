import AppKit
import Combine
import Foundation
import Security

// Identifiers are validated before being placed in API or website paths.
enum AircraftIdentifier {
    static func normalized(_ value: String?, maxLength: Int = 16) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !text.isEmpty, text.count <= maxLength,
              text.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) || $0 == 45 }) else { return nil }
        return text
    }

    static func hex(_ value: String) -> String? {
        guard value.count == 6, value.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { return nil }
        return value.uppercased()
    }
}

extension Aircraft {
    var detailsKey: String { "\(hex)|\(callsign)|\(registration ?? "")" }

    var moreInfoURL: URL? {
        if let ident = AircraftIdentifier.normalized(callsign, maxLength: 8)
            ?? AircraftIdentifier.normalized(registration) {
            return URL(string: "https://www.flightaware.com/live/flight/\(ident.replacingOccurrences(of: "-", with: ""))")
        }
        if let hex = AircraftIdentifier.hex(hex) {
            return URL(string: "https://www.planespotters.net/hex/\(hex)")
        }
        return nil
    }
}

struct AircraftDetails: Equatable {
    var model: String?
    var owner: String?
    var country: String?
    var airline: String?
    var route: String?
    var liveRoute: String?
    var status: String?
    var arrival: Date?
    var loading = false
    var message: String?
    var flightAwareMessage: String?
}

struct ADSBDetailsResponse: Decodable {
    var response: Payload
    struct Payload: Decodable {
        var aircraft: Airframe?
        var flightroute: Route?
    }
    struct Airframe: Decodable {
        var type: String?
        var manufacturer: String?
        var registered_owner: String?
        var registered_owner_country_name: String?
    }
    struct Route: Decodable {
        var airline: Airline?
        var origin: Airport?
        var destination: Airport?
    }
    struct Airline: Decodable { var name: String? }
    struct Airport: Decodable {
        var iata_code: String?
        var icao_code: String?
        var name: String?
        var label: String? { clean(iata_code) ?? clean(icao_code) ?? clean(name) }
    }
    var details: AircraftDetails {
        let aircraft = response.aircraft
        var result = AircraftDetails()
        result.model = [clean(aircraft?.manufacturer), clean(aircraft?.type)].compactMap { $0 }.joined(separator: " ")
        if result.model?.isEmpty == true { result.model = nil }
        result.owner = clean(aircraft?.registered_owner)
        result.country = clean(aircraft?.registered_owner_country_name)
        result.airline = clean(response.flightroute?.airline?.name)
        if let origin = response.flightroute?.origin?.label, let destination = response.flightroute?.destination?.label {
            result.route = "\(origin) → \(destination)"
        }
        return result
    }
}

private func clean(_ text: String?) -> String? {
    guard let text else { return nil }
    let value = String(text.filter { !$0.isNewline && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }.prefix(120))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

struct AeroAPIResponse: Decodable {
    var flights: [Flight]
    struct Airport: Decodable {
        var code_iata: String?
        var code_icao: String?
        var code: String?
        var label: String? { clean(code_iata) ?? clean(code_icao) ?? clean(code) }
    }
    struct Flight: Decodable {
        var registration: String?
        var actual_off: Date?
        var actual_on: Date?
        var origin: Airport?
        var destination: Airport?
        var status: String?
        var estimated_in: Date?
    }
    // Callsigns are reused. Only display an airborne leg that matches the known tail.
    func currentFlight(registration: String?, now: Date = Date()) -> Flight? {
        let expected = AircraftIdentifier.normalized(registration)?.replacingOccurrences(of: "-", with: "")
        return flights.filter { flight in
            guard let departure = flight.actual_off, departure <= now,
                  now.timeIntervalSince(departure) < 36 * 3600, flight.actual_on == nil else { return false }
            if let expected {
                return AircraftIdentifier.normalized(flight.registration)?.replacingOccurrences(of: "-", with: "") == expected
            }
            return true
        }.max { ($0.actual_off ?? .distantPast) < ($1.actual_off ?? .distantPast) }
    }
}

// Reject redirects rather than forwarding credentials or identifiers to another host.
private final class DetailsSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class AircraftDetailsStore: ObservableObject {
    static let shared = AircraftDetailsStore()
    @Published private(set) var entries: [String: AircraftDetails] = [:]
    @Published private(set) var revision = 0
    private var expires: [String: Date] = [:]
    private var requests: [String: Task<Void, Never>] = [:]
    private var flightAwareNextRequest = Date.distantPast
    private let transport: ((URL, String?) async throws -> Data)?
    private let apiKey: () -> String?

    init(transport: ((URL, String?) async throws -> Data)? = nil,
         apiKey: @escaping () -> String? = { try? FlightAwareKeychain.read() }) {
        self.transport = transport
        self.apiKey = apiKey
    }

    private let session = URLSession(configuration: .ephemeral, delegate: DetailsSessionDelegate(), delegateQueue: nil)

    func load(_ aircraft: Aircraft) async {
        let key = aircraft.detailsKey
        if let request = requests[key] { await request.value; return }
        if let expiry = expires[key], expiry > Date() { return }
        if entries.count >= 128 {
            let expired = expires.filter { $0.value <= Date() }.map(\.key)
            for key in expired where requests[key] == nil { entries[key] = nil; expires[key] = nil }
            if entries.count >= 128 {
                guard let oldest = expires.filter({ requests[$0.key] == nil }).min(by: { $0.value < $1.value })?.key else { return }
                entries[oldest] = nil; expires[oldest] = nil
            }
        }
        let generation = revision
        let request = Task { await fetch(aircraft, generation: generation) }
        requests[key] = request
        await request.value
        if revision == generation { requests[key] = nil }
    }

    func reset() {
        for request in requests.values { request.cancel() }
        requests.removeAll()
        entries.removeAll()
        expires.removeAll()
        revision += 1
    }

    private func get(_ url: URL, apiKey: String? = nil) async throws -> Data {
        if let transport { return try await transport(url, apiKey) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Flightbar/1.0", forHTTPHeaderField: "User-Agent")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "x-apikey") }
        // Stream with a size limit so an unexpected response cannot allocate unbounded memory.
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 429 {
            if apiKey != nil { flightAwareNextRequest = Date().addingTimeInterval(60) }
            throw URLError(.resourceUnavailable)
        }
        guard (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_048_576 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    private func fetch(_ aircraft: Aircraft, generation: Int) async {
        let key = aircraft.detailsKey
        var details = AircraftDetails(loading: true)
        entries[key] = details
        let callsign = AircraftIdentifier.normalized(aircraft.callsign, maxLength: 8)
        let registration = AircraftIdentifier.normalized(aircraft.registration)
        let lookup = AircraftIdentifier.hex(aircraft.hex) ?? registration
        do {
            var components = URLComponents(string: "https://api.adsbdb.com/v0")!
            if let lookup {
                components.path += "/aircraft/\(lookup)"
                if let callsign { components.queryItems = [URLQueryItem(name: "callsign", value: callsign)] }
            } else if let callsign {
                components.path += "/callsign/\(callsign)"
            } else { throw URLError(.badURL) }
            let data = try await get(components.url!)
            details = try JSONDecoder().decode(ADSBDetailsResponse.self, from: data).details
        } catch {
            details.message = "Aircraft details unavailable"
        }
        guard !Task.isCancelled, revision == generation else { return }
        details.loading = false
        entries[key] = details
        expires[key] = Date().addingTimeInterval(details.message == nil ? 600 : 60)

        guard !aircraft.hex.hasPrefix("demo-"), let apiKey = apiKey(), let ident = registration ?? callsign else { return }
        // Personal AeroAPI allows 10 result sets/minute. Limit this app to one request per 7 seconds.
        guard Date() >= flightAwareNextRequest else {
            details.flightAwareMessage = "FlightAware request limit reached; try again shortly"
            entries[key] = details
            expires[key] = Date().addingTimeInterval(60)
            return
        }
        flightAwareNextRequest = Date().addingTimeInterval(7)
        do {
            var components = URLComponents(string: "https://aeroapi.flightaware.com/aeroapi/flights/\(ident)")!
            let formatter = ISO8601DateFormatter()
            components.queryItems = [
                URLQueryItem(name: "ident_type", value: registration == nil ? "designator" : "registration"),
                URLQueryItem(name: "start", value: formatter.string(from: Date().addingTimeInterval(-36 * 3600))),
                URLQueryItem(name: "end", value: formatter.string(from: Date())),
                URLQueryItem(name: "max_pages", value: "1")
            ]
            let data = try await get(components.url!, apiKey: apiKey)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(AeroAPIResponse.self, from: data)
            if let flight = response.currentFlight(registration: registration) {
                if let origin = flight.origin?.label, let destination = flight.destination?.label {
                    details.liveRoute = "\(origin) → \(destination)"
                }
                details.status = clean(flight.status)
                details.arrival = flight.estimated_in
            } else {
                details.flightAwareMessage = "No matching airborne flight on FlightAware"
            }
        } catch {
            details.flightAwareMessage = "FlightAware unavailable; check your API key and quota"
        }
        guard !Task.isCancelled, revision == generation else { return }
        entries[key] = details
        expires[key] = Date().addingTimeInterval(details.flightAwareMessage == nil ? 300 : 60)
    }
}

enum FlightAwareKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.uluersolutions.flightbar.aeroapi",
         kSecAttrAccount as String: "api-key"]
    }
    static func read() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) throws {
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(key.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
    struct KeychainError: LocalizedError {
        var status: OSStatus
        var errorDescription: String? { "Could not update the API key in Keychain (\(status))." }
    }

    @MainActor static func configure() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "FlightAware API key"
        alert.informativeText = "Optional: add an AeroAPI key for current flight routes, status and arrival estimates. Requests may incur FlightAware charges. The key is stored in this Mac’s Keychain. Leave blank to keep the current key."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Remove key")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = "Paste your AeroAPI key"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        do {
            switch response {
            case .alertFirstButtonReturn:
                let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }
                guard key.count <= 512, key.utf8.allSatisfy({ (33...126).contains($0) }) else {
                    throw NSError(domain: "Flightbar", code: 1, userInfo: [NSLocalizedDescriptionKey: "The key contains invalid characters."])
                }
                try save(key)
            case .alertSecondButtonReturn: try remove()
            default: return
            }
            AircraftDetailsStore.shared.reset()
        } catch {
            let failure = NSAlert()
            failure.messageText = "Could not save FlightAware settings"
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }
}
