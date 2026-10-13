import Foundation

@main
struct AircraftDetailsTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "AircraftDetailsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func aircraft(callsign: String = "THY1", registration: String? = "TC-JJZ", hex: String = "4ba95a") -> Aircraft {
        Aircraft(hex: hex, callsign: callsign, registration: registration, typeCode: "B77W",
                 latitude: 41, longitude: 29, distanceKm: 2.4)
    }

    @MainActor static func main() async throws {
        try expect(aircraft().moreInfoURL?.absoluteString == "https://www.flightaware.com/live/flight/THY1", "Callsign link")
        try expect(aircraft(callsign: "").moreInfoURL?.absoluteString == "https://www.flightaware.com/live/flight/TCJJZ", "Registration fallback")
        try expect(aircraft(callsign: "", registration: nil).moreInfoURL?.absoluteString == "https://www.planespotters.net/hex/4BA95A", "Hex fallback")
        try expect(aircraft(callsign: "https://evil.test", registration: "../escape", hex: "invalid").moreInfoURL == nil, "Unsafe identifiers rejected")
        try expect(AircraftIdentifier.hex("~4ba95a") == nil, "Non-ICAO address rejected")
        try expect(AircraftIdentifier.normalized(" thy1 ", maxLength: 8) == "THY1", "Whitespace normalized")
        try expect(AircraftIdentifier.normalized("THY123456", maxLength: 8) == nil, "Overlong callsign rejected")

        let fixture = #"{"response":{"aircraft":{"type":"777 3F2ER","manufacturer":"Boeing","registered_owner":"Turkish Airlines","registered_owner_country_name":"Turkey"},"flightroute":{"airline":{"name":"Turkish Airlines"},"origin":{"iata_code":"IST"},"destination":{"icao_code":"KJFK"}}}}"#
        let metadata = try JSONDecoder().decode(ADSBDetailsResponse.self, from: Data(fixture.utf8)).details
        try expect(metadata.model == "Boeing 777 3F2ER", "Manufacturer and model")
        try expect(metadata.owner == "Turkish Airlines" && metadata.country == "Turkey", "Owner and country")
        try expect(metadata.route == "IST → KJFK", "Mixed airport identifiers")
        let missing = try JSONDecoder().decode(ADSBDetailsResponse.self, from: Data(#"{"response":{"aircraft":null,"flightroute":null}}"#.utf8)).details
        try expect(missing.model == nil && missing.route == nil, "Missing optional metadata")
        let aircraftOnly = try JSONDecoder().decode(ADSBDetailsResponse.self, from: Data(#"{"response":{"aircraft":{"manufacturer":"Cessna"}}}"#.utf8)).details
        try expect(aircraftOnly.model == "Cessna", "Aircraft without route")

        let now = ISO8601DateFormatter().date(from: "2026-10-12T20:00:00Z")!
        let flights = #"{"flights":[{"registration":"TC-WRONG","actual_off":"2026-10-12T19:00:00Z","status":"Wrong aircraft"},{"registration":"TC-JJZ","actual_off":"2026-10-12T18:00:00Z","actual_on":"2026-10-12T19:00:00Z","status":"Landed"},{"registration":"TC-JJZ","actual_off":"2026-10-13T18:00:00Z","status":"Future"},{"registration":"TCJJZ","actual_off":"2026-10-12T17:00:00Z","status":"En Route","origin":{"code_iata":"IST"},"destination":{"code_iata":"JFK"},"estimated_in":"2026-10-12T22:00:00Z"}]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(AeroAPIResponse.self, from: Data(flights.utf8))
        let current = response.currentFlight(registration: "TC-JJZ", now: now)
        try expect(current?.status == "En Route", "Match tail and airborne time; reject landed and future legs")
        try expect(current?.destination?.label == "JFK" && current?.estimated_in != nil, "Live route and arrival")
        try expect(response.currentFlight(registration: "N12345", now: now) == nil, "Do not attach a reused callsign to another aircraft")
        try expect(response.currentFlight(registration: "TC-JJZ", now: now.addingTimeInterval(96 * 3600)) == nil, "Reject stale flights")
        var requests: [URL] = []
        let store = AircraftDetailsStore(transport: { url, key in
            try expect(key == nil, "No paid API key without opt-in")
            requests.append(url)
            await Task.yield()
            return Data(fixture.utf8)
        }, apiKey: { nil })
        async let first: Void = store.load(aircraft())
        async let second: Void = store.load(aircraft())
        _ = await (first, second)
        try expect(requests.count == 1, "Concurrent card requests deduplicated")
        await store.load(aircraft())
        try expect(requests.count == 1, "Repeated position updates reuse cached metadata")
        try expect(requests[0].host == "api.adsbdb.com" && !requests[0].absoluteString.contains("lat/"), "Identifier-only request")
        try expect(store.entries[aircraft().detailsKey]?.owner == "Turkish Airlines", "Store publishes decoded details")
        store.reset()
        await store.load(aircraft())
        try expect(requests.count == 2, "Changing credentials invalidates cache")
        let failingStore = AircraftDetailsStore(transport: { _, _ in throw URLError(.timedOut) }, apiKey: { nil })
        await failingStore.load(aircraft())
        try expect(failingStore.entries[aircraft().detailsKey]?.message != nil, "API failures leave a usable card")
        try expect(failingStore.entries[aircraft().detailsKey]?.loading == false, "Spinner stops on failure")

        var paidRequests: [URL] = []
        let currentFixture = "{\"flights\":[{\"registration\":\"TC-JJZ\",\"actual_off\":\"\(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)))\",\"status\":\"En Route\",\"origin\":{\"code_iata\":\"IST\"},\"destination\":{\"code_iata\":\"JFK\"}}]}"
        let paidStore = AircraftDetailsStore(transport: { url, key in
            if url.host == "aeroapi.flightaware.com" {
                try expect(key == "test-only-key", "Key supplied only to FlightAware")
                try expect(!url.absoluteString.contains("test-only-key"), "Key kept out of query string")
                paidRequests.append(url)
                return Data(currentFixture.utf8)
            }
            try expect(key == nil, "Key not supplied to adsbdb")
            return Data(fixture.utf8)
        }, apiKey: { "test-only-key" })
        await paidStore.load(aircraft())
        try expect(paidStore.entries[aircraft().detailsKey]?.liveRoute == "IST → JFK", "Opt-in live enrichment")
        let parameters = URLComponents(url: paidRequests[0], resolvingAgainstBaseURL: false)?.queryItems ?? []
        try expect(parameters.contains(URLQueryItem(name: "max_pages", value: "1")), "Paid lookup limited to one page")
        await paidStore.load(aircraft(callsign: "THY2"))
        try expect(paidRequests.count == 1, "Paid requests throttled across different cards")

        if CommandLine.arguments.contains("--live") {
            let url = URL(string: "https://api.adsbdb.com/v0/aircraft/TC-JJZ?callsign=THY1")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            try expect((response as? HTTPURLResponse)?.statusCode == 200, "Public API response")
            let live = try JSONDecoder().decode(ADSBDetailsResponse.self, from: data).details
            try expect(live.model != nil && live.owner != nil, "Public API aircraft decoding")
            print("Public adsbdb integration passed (no credentials or user location sent)")
        }
        print("Aircraft detail and flight matching tests passed")
    }
}
