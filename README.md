# Flightbar

Flightbar puts the aircraft overhead in the macOS menu bar. When a plane enters the radius you chose, an icon flies from the clock to the Apple logo. The pointer stops it, and the flight card opens.

**Site and download:** [kaanuluer.com/flightbar](https://kaanuluer.com/flightbar)

Direct download: [Flightbar.zip](https://kaanuluer.com/flightbar/download/Flightbar.zip)

macOS 14 or later · Apple silicon. There is no Intel build.

## Install

1. Unzip the file and move Flightbar to the Applications folder.
2. If macOS cannot verify the app, right-click Flightbar and choose Open.
3. Allow location access. Precise location is required for the range.

## What it shows

The menu remembers the range and the aircraft color. Range choices run from 1 km to 50 km. The default is 3 km.

The flight card shows the callsign, airline, registration, aircraft type, distance, altitude, speed, heading, and whether the aircraft is climbing or descending. When the card opens, adsbdb adds the manufacturer/model, registered owner, country and a database route when available. Database routes are labeled unconfirmed for the observed flight. “More info…” opens FlightAware in your default browser using the callsign or registration; aircraft with only an ICAO hex open on Planespotters instead. Sample flight shows a flight without waiting. Check now refreshes the data.

## Privacy

Aircraft positions come from [adsb.lol](https://adsb.lol), with [adsb.fi](https://adsb.fi) as the fallback. These nearby-aircraft requests send your latitude and longitude to the provider, normally every five seconds. Distance is calculated locally.

Card enrichment sends aircraft hex/registration and callsign to [adsbdb](https://www.adsbdb.com/); it does not send your coordinates. Optional FlightAware requests send registration or callsign and your API key to FlightAware. Providers can see your public IP address. Enrichment is cached only in memory, bounded to 128 entries, for up to ten minutes (five minutes for successful FlightAware lookups); failures can retry after a minute while a card is visible. No enrichment database or photos are downloaded. Opening “More info…” visits a third-party website in your browser.

adsbdb route data has explicit reuse restrictions. Review its terms and obtain permission before publishing or incorporating those routes into another database.

## Optional FlightAware enrichment

Choose **FlightAware API key…** in the menu to save your own [AeroAPI](https://www.flightaware.com/commercial/aeroapi/) key in macOS Keychain. The key is never written to preferences or the repo. Remove it from the same dialog to disable FlightAware requests. adsbdb enrichment and “More info…” work without a key.

FlightAware may charge for API usage; personal and commercial plans have different terms. Flightbar uses at most one request per seven seconds, one page per lookup, and only shows an airborne flight matching the known registration. No matching flight or an unavailable service leaves the original card usable. Configure usage controls with FlightAware; the app does not impose a monthly spending cap.

## Build

Open `Flightbar.xcodeproj` in Xcode, or run:

```sh
./build.sh
```

The built app is `build/Flightbar.app`. The script uses local ad-hoc signing by default, so it does not require the original developer’s certificate. To use your own certificate, set `FLIGHTBAR_SIGN_IDENTITY`. For Xcode builds, select your own development team in Signing & Capabilities. The site in `site/` is what is published at [kaanuluer.com/flightbar](https://kaanuluer.com/flightbar).

## Verify enrichment

```sh
mkdir -p tmp
swiftc -parse-as-library Sources/Aircraft.swift Sources/Catalog.swift Sources/AircraftDetails.swift Tests/AircraftDetailsTests.swift -o tmp/aircraft-details-tests
./tmp/aircraft-details-tests
# Optional public API check, without an API key or user coordinates:
./tmp/aircraft-details-tests --live
```
