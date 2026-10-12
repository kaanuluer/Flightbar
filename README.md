# Flightbar

Flightbar puts the aircraft overhead in the macOS menu bar. When a plane enters the radius you chose, an icon flies from the clock to the Apple logo. The pointer stops it, and the flight card opens.

**Site and download:** [kaanuluer.com/flightbar](https://kaanuluer.com/flightbar)

Direct download: [Flightbar.zip](https://kaanuluer.com/flightbar/download/Flightbar.zip)

macOS 14 or later · Apple silicon. There is no Intel build.

## Install

1. Unzip the file and move Flightbar to the Applications folder.
2. If macOS cannot verify the app, right-click Flightbar and choose Open.
3. Allow location access when macOS asks. Flightbar uses it only while the app is open. Precise location is requested only if the system is currently limiting the app to an approximate location.

The menu bar icon is a top-down aircraft. It is a template image, so it turns dark or light with the menu bar. If that icon is not on screen, Flightbar opens a window. Show Menu Bar Icon asks macOS to display it, or turn Flightbar on in System Settings → Menu Bar.

## Permissions

Flightbar asks for one permission.

**Location, while the app is open.** The system location prompt appears when watching starts. The usage text is `NSLocationWhenInUseUsageDescription`. Precise location uses the purpose key `FlightbarPrecise` and is requested only when accuracy is already reduced. The position is not uploaded. Distance is calculated on this Mac.

Flightbar does not ask for these, and the binary does not call the APIs that trigger them:

- **Device Control and Data Access** (Accessibility). An earlier build walked other apps’ menu bars with `AXUIElement` to find the clock and the Apple logo. macOS 27 presents that access as Device Control and Data Access. The flight now starts near the clock and ends near the Apple logo using the screen frame.
- **Screen Recording.** That build also called `CGWindowListCopyWindowInfo` to measure the menu bar window. That call is gone.
- **Input Monitoring, Automation, or Apple Events.** While a flight is on screen, Flightbar reads `NSEvent.mouseLocation`. It does not install an event tap or send Apple Events.
- **Always-on location.** There is no `NSLocationAlwaysAndWhenInUseUsageDescription`, and the app does not call `requestAlwaysAuthorization`.

`Flightbar.entitlements` is empty. Hardened runtime is on, and no privacy entitlement is requested.

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

The built app is `build/Flightbar.app`. The site in `site/` is what is published at [kaanuluer.com/flightbar](https://kaanuluer.com/flightbar). Replace `site/download` with that build before publishing. The copy in the repo is a previous build.
