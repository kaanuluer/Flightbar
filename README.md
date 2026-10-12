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

The flight card shows the callsign, airline, registration, aircraft type, distance, altitude, speed, heading, and whether the aircraft is climbing or descending. Sample flight shows a flight without waiting. Check now refreshes the data.

## Privacy

Your location stays on this Mac. Distance is calculated locally, between your position and the aircraft. Aircraft positions come from [adsb.lol](https://adsb.lol), with [adsb.fi](https://adsb.fi) as the fallback. There is no account.

## Build

Open `Flightbar.xcodeproj` in Xcode, or run:

```sh
./build.sh
```

The built app is `build/Flightbar.app`. The site in `site/` is what is published at [kaanuluer.com/flightbar](https://kaanuluer.com/flightbar).
