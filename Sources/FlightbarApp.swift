import AppKit
import SwiftUI

@main
struct FlightbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            StatusMenu()
        } label: {
            Image(systemName: model.menuSymbol)
                .accessibilityLabel("Flightbar")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.uluersolutions.flightbar")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                MenuBarGeometry.shared.refresh()
            }
        }
        AppModel.shared.start()
    }
}

struct StatusMenu: View {
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        Text("Flightbar")
        Text(model.statusLine)
        Text(model.detailLine)
        Text("Flies from the clock to the Apple logo. Stops when the pointer touches it.")

        Divider()
        Menu("Range: \(Radar.label(model.radiusKm))") {
            ForEach(Radar.radiusChoices, id: \.self) { kilometers in
                Toggle(Radar.label(kilometers), isOn: Binding(
                    get: { model.radiusKm == kilometers },
                    set: { isSelected in
                        if isSelected { model.radiusKm = kilometers }
                    }
                ))
            }
        }
        Menu("Aircraft color: \(model.planeColor.title)") {
            ForEach(PlaneTint.allCases) { tint in
                Toggle(isOn: Binding(
                    get: { model.planeColor == tint },
                    set: { isSelected in
                        if isSelected { model.planeColor = tint }
                    }
                )) {
                    Label {
                        Text(tint.title)
                    } icon: {
                        Image(nsImage: tint.menuImage)
                    }
                }
            }
        }

        if !model.overhead.isEmpty {
            Divider()
            Text("Overhead now")
            ForEach(model.overhead) { aircraft in
                Text(aircraft.menuLine)
            }
        }

        let passed = model.recent.filter { recent in
            !model.overhead.contains(where: { $0.hex == recent.hex })
        }
        if !passed.isEmpty {
            Divider()
            Text("Just entered")
            ForEach(passed) { aircraft in
                Text(aircraft.menuLine)
            }
        }

        Divider()
        Button("FlightAware API key…") { FlightAwareKeychain.configure() }
        Button("Sample flight") { model.preview() }
        Button("Check now") { model.pollNow() }
        if model.showsLocationSettings {
            Button("Open Location Settings") { model.openLocationSettings() }
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
