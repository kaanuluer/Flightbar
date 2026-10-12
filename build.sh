#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/Flightbar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -parse-as-library -O -target arm64-apple-macos14.0 \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreLocation \
  -framework ApplicationServices \
  -framework QuartzCore \
  -o "$APP/Contents/MacOS/Flightbar" \
  Sources/*.swift
mkdir -p "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/Flightbar.icns "$APP/Contents/Resources/Flightbar.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Flightbar" "$APP/Contents/Info.plist"
codesign --force --sign "Apple Development: Kaan Uluer (757A9ZKQKF)" --options runtime --entitlements Flightbar.entitlements "$APP"
echo "Built $APP"
