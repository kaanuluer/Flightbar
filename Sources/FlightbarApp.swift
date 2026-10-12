import AppKit
import Combine
import SwiftUI

@main
struct FlightbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // SwiftUI requires a scene. The menu bar icon is an NSStatusItem owned by
        // AppDelegate. MenuBarExtra is not used: on macOS 26 and 27 it is dropped
        // when the app is an agent, which left Flightbar running with no icon.
        Settings {
            PreferencesView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var launchWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private var screenObserver: NSObjectProtocol?
    private var modelWatch: AnyCancellable?
    private var userConfirmedVisible = false

    private enum Keys {
        static let resetStatusItemVisibility = "didResetStatusItemVisibility"
        static let dismissedLaunchWindow = "didDismissLaunchWindow"
    }

    func applicationDidFinishLaunching(_: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.uluersolutions.flightbar")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        // LSUIElement already launches Flightbar as an agent. Calling
        // setActivationPolicy(.accessory) here used to run after SwiftUI created
        // its MenuBarExtra, and on macOS 27 that removed the status item while
        // the process kept running.
        NSApp.disableAutomaticTermination("Flightbar keeps a menu bar item")
        installMainMenu()
        installStatusItem()
        AppModel.shared.start()
        modelWatch = AppModel.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let item = self.statusItem {
                        self.applyIcon(to: item)
                    }
                    self.returnToMenuBarIfSettled()
                }
            }
        }
        if AppModel.shared.needsPlaceChoice {
            showPreferences()
        }
        scheduleVisibilityChecks()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resolveVisibility(final: false)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, placement() != .onScreen {
            showLaunchWindow()
        }
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        populate(menu)
    }

    func windowWillClose(_ notification: Notification) {
        let window = notification.object as? NSWindow
        let current = placement()
        if window == launchWindow {
            launchWindow = nil
            if userConfirmedVisible || current == .onScreen {
                UserDefaults.standard.set(true, forKey: Keys.dismissedLaunchWindow)
            }
        }
        if window == preferencesWindow {
            preferencesWindow = nil
        }
        userConfirmedVisible = false
        if current == .onScreen {
            DispatchQueue.main.async { [weak self] in
                self?.returnToMenuBarIfSettled()
            }
        }
    }

    /// A menu-bar app stays an agent once its windows are gone and the icon is on screen.
    /// While a location prompt is still unanswered, Flightbar stays in front so macOS can show it.
    private func returnToMenuBarIfSettled() {
        let waitingForLocationPrompt = AppModel.shared.placeSource == .device
            && AppModel.shared.authorization == .notDetermined
        guard launchWindow == nil, preferencesWindow == nil, !waitingForLocationPrompt else { return }
        guard placement() == .onScreen else { return }
        guard NSApp.activationPolicy() != .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    private func showPreferences() {
        if let preferencesWindow {
            NSApp.setActivationPolicy(.regular)
            preferencesWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let host = NSHostingView(rootView: PreferencesView())
        let width: CGFloat = 460
        host.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        host.layoutSubtreeIfNeeded()
        let height = max(360, host.fittingSize.height)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        preferencesWindow = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let quit = NSMenuItem(title: "Quit Flightbar", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    private func installStatusItem() {
        resetStaleStatusItemVisibilityIfNeeded()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyIcon(to: item)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        item.isVisible = true
        statusItem = item
    }

    /// MenuBarExtra wrote a hidden visibility flag that Control Center keeps honoring.
    /// Clear it once so the replacement status item can appear. A later hide is kept.
    private func resetStaleStatusItemVisibilityIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Keys.resetStatusItemVisibility) else { return }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSStatusItem Visible") {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: Keys.resetStatusItemVisibility)
    }

    private func applyIcon(to item: NSStatusItem) {
        guard let button = item.button else { return }
        let image = MenuBarMark.templateImage
        button.image = image
        let model = AppModel.shared
        if model.showsPlaneCount {
            button.title = "\(model.overhead.count)"
            button.imagePosition = .imageLeft
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
        (button.cell as? NSButtonCell)?.imageScaling = .scaleProportionallyDown
        button.toolTip = "Flightbar"
        button.setAccessibilityLabel("Flightbar")
    }

    private func scheduleVisibilityChecks() {
        for delay in [0.5, 1.2, 2.5] {
            let isFinal = delay == 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    self?.resolveVisibility(final: isFinal)
                }
            }
        }
    }

    private enum Placement {
        case unknown
        case onScreen
        /// Still allowed in the menu bar, but the item's window is off the menu bar strip.
        case offScreen
        /// System Settings, or a stale visibility flag, turned the item off.
        case removed
    }

    private func placement() -> Placement {
        guard let statusItem else { return .removed }
        if !statusItem.isVisible { return .removed }
        guard let button = statusItem.button else { return .unknown }
        if button.image == nil { applyIcon(to: statusItem) }
        guard let frame = button.window?.frame else { return .unknown }
        if frame.width < 2 || frame.height < 2 { return .unknown }
        if frame.maxY < 0 { return .offScreen }
        let onScreen = NSScreen.screens.contains { screen in
            let thickness = max(NSStatusBar.system.thickness, 24)
            let strip = NSRect(
                x: screen.frame.minX - 20,
                y: screen.frame.maxY - thickness - 8,
                width: screen.frame.width + 40,
                height: thickness + 16
            )
            return strip.intersects(frame)
        }
        return onScreen ? .onScreen : .offScreen
    }

    private func resolveVisibility(final: Bool) {
        let dismissed = UserDefaults.standard.bool(forKey: Keys.dismissedLaunchWindow)
        switch placement() {
        case .onScreen:
            if launchWindow != nil {
                launchWindow?.close()
            }
        case .removed:
            showLaunchWindow()
        case .offScreen:
            if !dismissed { showLaunchWindow() }
        case .unknown:
            if final, !dismissed { showLaunchWindow() }
        }
    }

    private func showLaunchWindow() {
        if let launchWindow {
            if launchWindow.isVisible { return }
            NSApp.setActivationPolicy(.regular)
            launchWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let root = LaunchPrompt(
            onShowIcon: { [weak self] in self?.revealStatusItem() },
            onOpenSettings: { [weak self] in self?.openMenuBarSettings() },
            onAlreadyVisible: { [weak self] in self?.confirmIconVisible() },
            onQuit: { NSApp.terminate(nil) }
        )
        let host = NSHostingView(rootView: root)
        let width: CGFloat = 480
        host.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        host.layoutSubtreeIfNeeded()
        let height = max(220, host.fittingSize.height)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Flightbar"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        launchWindow = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func revealStatusItem() {
        guard let statusItem else { return }
        statusItem.isVisible = true
        applyIcon(to: statusItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.placement() == .onScreen {
                    self.launchWindow?.close()
                }
            }
        }
    }

    private func confirmIconVisible() {
        userConfirmedVisible = true
        UserDefaults.standard.set(true, forKey: Keys.dismissedLaunchWindow)
        launchWindow?.close()
    }

    private func openMenuBarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func populate(_ menu: NSMenu) {
        let model = AppModel.shared
        menu.removeAllItems()
        addLabel("Flightbar", to: menu, style: .title)
        addLabel(model.statusLine, to: menu, style: .primary)
        addLabel(model.detailLine, to: menu, style: .primary)
        addLabel("Select an aircraft for its details. The flight across the menu bar is off unless you turn it on.", to: menu, style: .caption)
        menu.addItem(.separator())

        let range = NSMenuItem(title: "Range: \(Radar.label(model.radiusKm))", action: nil, keyEquivalent: "")
        let rangeMenu = NSMenu()
        rangeMenu.autoenablesItems = false
        for kilometers in Radar.radiusChoices {
            let item = NSMenuItem(title: Radar.label(kilometers), action: #selector(selectRadius(_:)), keyEquivalent: "")
            item.target = self
            item.state = model.radiusKm == kilometers ? .on : .off
            item.representedObject = NSNumber(value: kilometers)
            rangeMenu.addItem(item)
        }
        range.submenu = rangeMenu
        menu.addItem(range)

        let color = NSMenuItem(title: "Aircraft color: \(model.planeColor.title)", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        colorMenu.autoenablesItems = false
        for tint in PlaneTint.allCases {
            let item = NSMenuItem(title: tint.title, action: #selector(selectColor(_:)), keyEquivalent: "")
            item.target = self
            item.state = model.planeColor == tint ? .on : .off
            item.image = tint.menuImage
            item.representedObject = tint.rawValue
            colorMenu.addItem(item)
        }
        color.submenu = colorMenu
        menu.addItem(color)

        let flags = NSMenuItem(title: "Flags: \(model.flagFilter.menuTitle)", action: nil, keyEquivalent: "")
        let flagsMenu = NSMenu()
        flagsMenu.autoenablesItems = false
        for filter in DbFlagFilter.allCases {
            let item = NSMenuItem(title: filter.menuTitle, action: #selector(selectFlag(_:)), keyEquivalent: "")
            item.target = self
            item.state = model.flagFilter == filter ? .on : .off
            item.representedObject = filter.rawValue
            item.toolTip = filter.explanation
            flagsMenu.addItem(item)
        }
        flags.submenu = flagsMenu
        menu.addItem(flags)

        addToggle(
            model.showsPlaneCount ? "Hide aircraft count" : "Show aircraft count",
            on: model.showsPlaneCount,
            action: #selector(toggleCount(_:)),
            to: menu
        )
        addToggle(
            "Fly across the menu bar",
            on: model.fliesAcrossMenuBar,
            action: #selector(toggleFly(_:)),
            to: menu
        )
        addToggle(
            "Notify when an aircraft enters",
            on: model.notificationsEnabled,
            action: #selector(toggleNotify(_:)),
            to: menu
        )
        addAction("Preferences…", action: #selector(openPreferences(_:)), to: menu)

        if !model.overhead.isEmpty {
            menu.addItem(.separator())
            addLabel("Overhead now", to: menu, style: .heading)
            for aircraft in model.overhead {
                addAircraft(aircraft, to: menu)
            }
        }
        let passed = model.recent.filter { recent in
            !model.overhead.contains(where: { $0.hex == recent.hex })
        }
        if !passed.isEmpty {
            menu.addItem(.separator())
            addLabel("Just entered", to: menu, style: .heading)
            for aircraft in passed {
                addAircraft(aircraft, to: menu)
            }
        }

        menu.addItem(.separator())
        addAction("Show sample aircraft", action: #selector(sampleFlight(_:)), to: menu)
        addAction("Check now", action: #selector(checkNow(_:)), to: menu)
        if model.showsLocationSettings {
            addAction("Open Location Settings", action: #selector(openLocationSettings(_:)), to: menu)
        }
        menu.addItem(.separator())
        let quit = addAction("Quit", action: #selector(quit(_:)), to: menu)
        quit.keyEquivalent = "q"
    }

    private enum LabelStyle {
        case title
        case heading
        case primary
        case caption
    }

    private func addLabel(_ title: String, to menu: NSMenu, style: LabelStyle) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let font: NSFont
        let color: NSColor
        switch style {
        case .title:
            font = NSFont.menuFont(ofSize: 0)
            color = .labelColor
        case .heading:
            font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            color = .labelColor
        case .primary:
            font = NSFont.menuFont(ofSize: 0)
            color = .labelColor
        case .caption:
            font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
            color = .secondaryLabelColor
        }
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: font
        ])
        item.isEnabled = true
        menu.addItem(item)
    }

    private func addAircraft(_ aircraft: Aircraft, to menu: NSMenu) {
        let item = NSMenuItem(title: aircraft.menuLine, action: #selector(showAircraft(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = aircraft.hex
        item.attributedTitle = NSAttributedString(string: aircraft.menuLine, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.menuFont(ofSize: 0)
        ])
        menu.addItem(item)
    }

    private func addToggle(_ title: String, on: Bool, action: Selector, to menu: NSMenu) {
        let item = addAction(title, action: action, to: menu)
        item.state = on ? .on : .off
    }

    @discardableResult
    private func addAction(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func selectRadius(_ sender: NSMenuItem) {
        guard let kilometers = (sender.representedObject as? NSNumber)?.doubleValue else { return }
        AppModel.shared.radiusKm = kilometers
    }

    @objc private func selectColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let tint = PlaneTint(rawValue: raw) else { return }
        AppModel.shared.planeColor = tint
    }

    @objc private func selectFlag(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let filter = DbFlagFilter(rawValue: raw) else { return }
        AppModel.shared.flagFilter = filter
    }

    @objc private func toggleCount(_: NSMenuItem) {
        AppModel.shared.showsPlaneCount.toggle()
    }

    @objc private func toggleFly(_: NSMenuItem) {
        AppModel.shared.fliesAcrossMenuBar.toggle()
    }

    @objc private func toggleNotify(_: NSMenuItem) {
        AppModel.shared.notificationsEnabled.toggle()
    }

    @objc private func openPreferences(_: NSMenuItem) {
        showPreferences()
    }

    @objc private func showAircraft(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String,
              let aircraft = AppModel.shared.aircraft(hex: hex) else { return }
        let anchor = statusItem?.button?.window?.frame
        let point = anchor.map { NSPoint(x: $0.midX, y: $0.minY) }
        FlightLane.shared.showDetails(aircraft, under: point)
    }

    @objc private func sampleFlight(_: NSMenuItem) {
        AppModel.shared.preview()
    }

    @objc private func checkNow(_: NSMenuItem) {
        AppModel.shared.pollNow()
    }

    @objc private func openLocationSettings(_: NSMenuItem) {
        AppModel.shared.openLocationSettings()
    }

    @objc private func quit(_: Any?) {
        NSApp.terminate(nil)
    }
}

private struct LaunchPrompt: View {
    var onShowIcon: () -> Void
    var onOpenSettings: () -> Void
    var onAlreadyVisible: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                MenuBarMarkShape()
                    .fill(Color.primary)
                    .frame(width: 36, height: 36)
                    .accessibilityLabel("Flightbar")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flightbar is running")
                        .font(.title3.weight(.semibold))
                    Text("The menu bar icon isn’t on screen.")
                        .foregroundStyle(.secondary)
                }
            }
            Text("Look along the top of the screen for a top-down aircraft. It follows the light and dark menu bar. It is not the Location Services arrow.")
                .fixedSize(horizontal: false, vertical: true)
            Text("If macOS hid the icon, turn Flightbar on in System Settings → Menu Bar. Show Menu Bar Icon asks macOS to display it again.")
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Show Menu Bar Icon", action: onShowIcon)
                    .keyboardShortcut(.defaultAction)
                Button("Menu Bar Settings…", action: onOpenSettings)
            }
            HStack {
                Button("The icon is already visible", action: onAlreadyVisible)
                    .buttonStyle(.borderless)
                Spacer(minLength: 0)
                Button("Quit", action: onQuit)
            }
        }
        .padding(20)
        .frame(width: 480, alignment: .leading)
    }
}
