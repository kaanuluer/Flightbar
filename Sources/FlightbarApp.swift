import AppKit
import SwiftUI

@main
struct FlightbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // A scene keeps the SwiftUI lifecycle alive. The menu bar item is an
        // NSStatusItem owned by the delegate, not a MenuBarExtra.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.uluersolutions.flightbar")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }
        // LSUIElement already keeps Flightbar out of the Dock. Changing the
        // activation policy here discards a SwiftUI menu-bar extra on newer macOS
        // and leaves the process running with nothing visible.
        let statusBar = StatusBarController()
        self.statusBar = statusBar
        AppModel.shared.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            statusBar.confirmVisible()
        }
    }
}
