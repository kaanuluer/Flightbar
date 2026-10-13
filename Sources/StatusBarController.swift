import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private var rescueWindow: NSWindow?
    private var didCheckVisibility = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.isVisible = true
        if let button = statusItem.button {
            let mark = MenuBarMark.image()
            button.image = mark
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.toolTip = "Flightbar"
            button.setAccessibilityLabel("Flightbar")
        }
    }

    func confirmVisible() {
        guard !didCheckVisibility else { return }
        didCheckVisibility = true
        if buttonScreenRect == nil {
            showRescue()
        }
    }

    /// The status item counts as shown only when its button occupies a real
    /// rectangle on a menu bar. A visible status-bar window is not enough:
    /// macOS can keep that window up while the item itself is overflowed or missing.
    private var buttonScreenRect: NSRect? {
        guard statusItem.isVisible, let button = statusItem.button, let window = button.window else {
            return nil
        }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard rect.width >= 10, rect.height >= 10 else { return nil }
        let onBar = NSScreen.screens.contains { screen in
            let height = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
            let bar = NSRect(
                x: screen.frame.minX,
                y: screen.frame.maxY - height - 4,
                width: screen.frame.width,
                height: height + 8
            )
            return bar.intersects(rect)
        }
        return onBar ? rect : nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let model = AppModel.shared

        menu.addItem(disabled(model.statusLine))
        menu.addItem(disabled(model.detailLine))
        menu.addItem(disabled("Flies from the clock toward the Apple logo. The pointer stops it."))
        menu.addItem(.separator())

        let range = NSMenuItem(title: "Range: \(Radar.label(model.radiusKm))", action: nil, keyEquivalent: "")
        let rangeMenu = NSMenu()
        for kilometers in Radar.radiusChoices {
            let item = NSMenuItem(
                title: Radar.label(kilometers),
                action: #selector(chooseRange(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.state = model.radiusKm == kilometers ? .on : .off
            item.representedObject = NSNumber(value: kilometers)
            rangeMenu.addItem(item)
        }
        range.submenu = rangeMenu
        menu.addItem(range)

        let color = NSMenuItem(title: "Aircraft color: \(model.planeColor.title)", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for tint in PlaneTint.allCases {
            let item = NSMenuItem(title: tint.title, action: #selector(chooseColor(_:)), keyEquivalent: "")
            item.target = self
            item.state = model.planeColor == tint ? .on : .off
            item.image = tint.menuImage
            item.representedObject = tint.rawValue
            colorMenu.addItem(item)
        }
        color.submenu = colorMenu
        menu.addItem(color)

        if !model.overhead.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled("Overhead now"))
            for aircraft in model.overhead {
                menu.addItem(disabled(aircraft.menuLine))
            }
        }

        let passed = model.recent.filter { recent in
            !model.overhead.contains(where: { $0.hex == recent.hex })
        }
        if !passed.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled("Just entered"))
            for aircraft in passed {
                menu.addItem(disabled(aircraft.menuLine))
            }
        }

        menu.addItem(.separator())
        menu.addItem(action("Sample flight", #selector(sampleFlight)))
        menu.addItem(action("Check now", #selector(checkNow)))
        if model.showsLocationSettings {
            menu.addItem(action("Open Location Settings", #selector(openLocationSettings)))
        }
        menu.addItem(.separator())
        let quit = action("Quit", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func chooseRange(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        AppModel.shared.radiusKm = number.doubleValue
    }

    @objc private func chooseColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tint = PlaneTint(rawValue: raw) else { return }
        AppModel.shared.planeColor = tint
    }

    @objc private func sampleFlight() {
        AppModel.shared.preview()
    }

    @objc private func checkNow() {
        AppModel.shared.pollNow()
    }

    @objc private func openLocationSettings() {
        AppModel.shared.openLocationSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showRescue() {
        if rescueWindow == nil {
            let host = NSHostingView(rootView: RescueView())
            let size = host.fittingSize
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Flightbar"
            window.contentView = host
            window.setContentSize(size == .zero ? NSSize(width: 440, height: 210) : size)
            window.isReleasedWhenClosed = false
            window.center()
            rescueWindow = window
        }
        guard let rescueWindow else { return }
        rescueWindow.level = .floating
        rescueWindow.collectionBehavior = [.canJoinAllSpaces, .moveToActiveSpace]
        rescueWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private struct RescueView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Flightbar is running")
                .font(.title2.weight(.semibold))
            Text("The menu-bar icon isn’t visible. macOS can hide it when the menu bar is full. This window is here so the app is not only a background process.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Flightbar asks for your location while it is open, to measure distance. It does not need Device Control and Data Access.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Sample flight") { AppModel.shared.preview() }
                Button("Check now") { AppModel.shared.pollNow() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
