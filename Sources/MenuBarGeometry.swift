import AppKit
import ApplicationServices

struct MenuAnchor: Sendable {
    var startX: CGFloat
    var endX: CGFloat
    var bar: NSRect
}

struct MenuProbeItem: Sendable {
    var title: String
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var maxX: CGFloat { x + width }
}

enum MenuBarProbe {
    nonisolated static func scanItems() -> [MenuProbeItem] {
        var items: [MenuProbeItem] = []
        for app in NSWorkspace.shared.runningApplications {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.08)
            var menuBar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &menuBar) == .success,
                  let menuBar,
                  CFGetTypeID(menuBar) == AXUIElementGetTypeID() else { continue }
            let bar = menuBar as! AXUIElement
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &children) == .success,
                  let children else { continue }
            let array: [AXUIElement]
            if let typed = children as? [AXUIElement] {
                array = typed
            } else if let boxed = children as? NSArray {
                array = (0..<boxed.count).map { boxed[$0] as! AXUIElement }
            } else {
                continue
            }
            for child in array {
                guard let frame = frame(of: child),
                      frame.width > 8, frame.width < 320,
                      frame.height > 10, frame.height < 48 else { continue }
                let title = stringAttribute(child, kAXTitleAttribute) ?? ""
                items.append(MenuProbeItem(
                    title: title,
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: frame.width,
                    height: frame.height
                ))
            }
        }
        return items
    }

    nonisolated static func menuBarRect(for screen: NSScreen) -> NSRect {
        if let match = menuBarWindows().first(where: {
            abs($0.minX - screen.frame.minX) < 8 && abs($0.width - screen.frame.width) < 12
        }) {
            return match
        }
        let thickness = max(24, NSStatusBar.system.thickness)
        return NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - thickness,
            width: screen.frame.width,
            height: thickness
        )
    }

    nonisolated static func anchors(for screen: NSScreen, items: [MenuProbeItem]) -> MenuAnchor {
        let bar = menuBarRect(for: screen)
        let onScreen = items.filter { item in
            let mid = item.x + item.width / 2
            return mid >= screen.frame.minX + 2 && mid <= screen.frame.maxX - 2 && item.y > -30 && item.y < 80
        }
        let apples = onScreen.filter { $0.title == "Apple" && $0.width < 70 }
        let endX = apples.map { $0.x + $0.width / 2 }.min() ?? (screen.frame.minX + 27)

        let rightItems = onScreen.filter {
            $0.title != "Apple" && $0.x > screen.frame.midX && $0.maxX < screen.frame.maxX - 2
        }
        let startX: CGFloat
        if let rightmost = rightItems.max(by: { $0.maxX < $1.maxX }) {
            let gap = screen.frame.maxX - rightmost.maxX
            if gap > 40 && gap < 260 {
                startX = rightmost.maxX + gap / 2
            } else {
                startX = rightmost.x + rightmost.width / 2
            }
        } else {
            startX = screen.frame.maxX - 88
        }
        return MenuAnchor(startX: startX, endX: endX, bar: bar)
    }

    private nonisolated static func menuBarWindows() -> [NSRect] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let mainID = CGMainDisplayID()
        let mainScreen = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == mainID
        } ?? NSScreen.screens.first
        let mainTop = mainScreen?.frame.maxY ?? 0
        var rects: [NSRect] = []
        for dict in info {
            guard (dict[kCGWindowName as String] as? String) == "Menubar",
                  (dict[kCGWindowOwnerName as String] as? String) == "Window Server",
                  let bounds = dict[kCGWindowBounds as String] as? [String: Any],
                  let x = cgFloat(bounds["X"]),
                  let y = cgFloat(bounds["Y"]),
                  let width = cgFloat(bounds["Width"]),
                  let height = cgFloat(bounds["Height"]),
                  height > 16, height < 80 else { continue }
            let appKitY = mainTop - y - height
            rects.append(NSRect(x: x, y: appKitY, width: width, height: height))
        }
        return rects
    }

    private nonisolated static func cgFloat(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        return nil
    }

    private nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              let positionValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID() else { return nil }
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let sizeValue,
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private nonisolated static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

@MainActor
final class MenuBarGeometry {
    static let shared = MenuBarGeometry()
    private var items: [MenuProbeItem] = []

    func refresh() {
        Task.detached(priority: .utility) {
            let found = MenuBarProbe.scanItems()
            await MainActor.run {
                MenuBarGeometry.shared.items = found
            }
        }
    }

    func anchors(for screen: NSScreen) -> MenuAnchor {
        MenuBarProbe.anchors(for: screen, items: items)
    }
}
