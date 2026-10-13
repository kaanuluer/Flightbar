# Flightbar

Flightbar lists the aircraft overhead in the macOS menu bar. Select one for its details. A plane flying from the clock toward the Apple logo is optional and off unless you turn it on.

**Site and download:** [kaanuluer.com/flightbar](https://kaanuluer.com/flightbar)

Direct download: [Flightbar.zip](https://kaanuluer.com/flightbar/download/Flightbar.zip)

macOS 14 or later · Apple silicon. There is no Intel build.

## Install

1. Unzip the file and move Flightbar to the Applications folder.
2. If macOS cannot verify the app, right-click Flightbar and choose Open.
3. Choose Location Services, or enter a city, a postal code, or a latitude and longitude. Location Services is not required. The system prompt appears only if you choose it, and Flightbar comes forward first so macOS can show it.

The menu bar icon is a top-down aircraft. It is a template image, so it turns dark or light with the menu bar. It does not switch to the Location Services arrow. If that icon is not on screen, Flightbar opens a window. Show Menu Bar Icon asks macOS to display it, or turn Flightbar on in System Settings → Menu Bar.

## Language

Flightbar follows the language of the Mac. English and Turkish are included (`en.lproj` and `tr.lproj`). Numbers and the clock use that locale. Coordinates shown on the card, and the ones sent to the aircraft feed, stay in a fixed decimal form so they can be typed back in. The location permission text is translated in `InfoPlist.strings`.

## Permissions

Flightbar does not ask for a permission at launch.

**Location, while the app is open, only if you choose it.** The usage text is `NSLocationWhenInUseUsageDescription`. The prompt is not requested at launch. A menu-bar-only app that asks then never shows the dialog. Choosing Use Location Services brings Flightbar forward and then calls `requestWhenInUseAuthorization`. Precise location uses the purpose key `FlightbarPrecise` and is requested only when accuracy is already reduced. If you enter a place instead, `CLLocationManager` is not started.

**Notifications, only if you turn them on.** The default is off. Turning the setting on calls `UNUserNotificationCenter.requestAuthorization` for alerts and sounds. If you deny it, the setting turns back off.

Flightbar does not ask for these, and the binary does not call the APIs that trigger them:

- **Device Control and Data Access** (Accessibility). An earlier build walked other apps’ menu bars with `AXUIElement` to find the clock and the Apple logo. macOS 27 presents that access as Device Control and Data Access. The optional flight now starts near the clock and ends near the Apple logo using the screen frame.
- **Screen Recording.** That build also called `CGWindowListCopyWindowInfo` to measure the menu bar window. That call is gone.
- **Input Monitoring, Automation, or Apple Events.** While a flight is on screen, Flightbar reads `NSEvent.mouseLocation`. It does not install an event tap or send Apple Events.
- **Always-on location.** There is no `NSLocationAlwaysAndWhenInUseUsageDescription`, and the app does not call `requestAlwaysAuthorization`.

`Flightbar.entitlements` is empty. Hardened runtime is on, and no privacy entitlement is requested.

## What it shows

The menu remembers the range and the aircraft color. Range choices run from 1 km to 50 km. The default is 3 km.

Aircraft rows use the label color, so they stay readable in light and dark. Select a row to open the details card. The card shows the callsign, airline, registration, type code, type description when the feed sends one, distance, barometric altitude, geometric altitude (WGS84, `alt_geom`) when present, speed, track, true and magnetic heading when present, vertical rate, geometric rate, squawk, category, position, database flags, and emergency. **Show sample aircraft** opens a demo card. The card says it is a sample, not a live flight.

**Fly across the menu bar** is off by default. **Show aircraft count** puts the overhead count beside the icon and is off by default.

**Flags** filters the list after the feed returns. The labels match readsb’s `dbFlags` bitfield, which adsb.lol and adsb.fi forward:

| Menu | Meaning |
| --- | --- |
| All aircraft | No flag filter |
| Military (U) | `dbFlags & 1`. This is the aircraft tar1090 keeps when its U button is on (`onlyMilitary`). |
| Interesting | `dbFlags & 2`. Separate from U. |
| PIA | `dbFlags & 4`. Privacy ICAO address. |
| LADD | `dbFlags & 8`. Limiting Aircraft Data Displayed. |

**Notify when an aircraft enters** is off until you enable it. You can limit the alert to a callsign, registration, or type. The flag filter still applies. Alerts aimed at specific equipment and flight profiles are not in this version.

## Privacy

Distance is calculated on this Mac.

A city or postal code is sent to Apple’s geocoder (`CLGeocoder`) to become coordinates. Typing latitude and longitude skips the geocoder. After that, the position stays on this Mac.

The aircraft query still sends those coordinates to [adsb.lol](https://adsb.lol), with [adsb.fi](https://adsb.fi) as the fallback, so the feed knows which area to return. There is no account.

## Build

Open `Flightbar.xcodeproj` in Xcode, or run:

```sh
./build.sh
```

The built app is `build/Flightbar.app`. The site in `site/` is what is published at [kaanuluer.com/flightbar](https://kaanuluer.com/flightbar). Replace `site/download` with a Mac build before publishing. The copy in the repo is a previous build and still contains the old Accessibility calls.
