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

## Permissions

Flightbar asks for one thing: location while the app is open. That is how it measures which aircraft are inside the range you chose. If macOS has reduced accuracy on, it asks for precise location for that same measurement. The location prompt explains this.

It does not ask for Device Control and Data Access (the macOS 27 name for Accessibility), screen recording, input monitoring, or automation. Earlier builds read other apps' menu bars to find the clock and the Apple logo, and that is what produced the broad permission prompt. The flight path is now estimated from the screen edges, so that access is gone.

If the menu-bar icon cannot be shown, a small window opens so the app is not only a background process.

## Build

Open `Flightbar.xcodeproj` in Xcode, or run:

```sh
./build.sh
```

The built app is `build/Flightbar.app`. The site in `site/` is what is published at [kaanuluer.com/flightbar](https://kaanuluer.com/flightbar).
