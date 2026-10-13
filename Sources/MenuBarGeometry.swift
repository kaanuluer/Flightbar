import AppKit

struct MenuAnchor: Sendable {
    var startX: CGFloat
    var endX: CGFloat
    var bar: NSRect
}

enum MenuBarProbe {
    /// Clock-side and Apple-logo-side anchors from the screen frame.
    ///
    /// An earlier build found these by walking every app's menu bar with AXUIElement
    /// and by reading window names with CGWindowListCopyWindowInfo. On macOS 27 that
    /// Accessibility access is the "Device Control and Data Access" prompt. The flight
    /// only needs a start near the clock and an end near the Apple logo, which the
    /// screen frame already provides.
    nonisolated static func anchors(for screen: NSScreen) -> MenuAnchor {
        MenuAnchor(
            startX: screen.frame.maxX - 88,
            endX: screen.frame.minX + 27,
            bar: menuBarRect(for: screen)
        )
    }

    nonisolated static func menuBarRect(for screen: NSScreen) -> NSRect {
        let thickness = max(24, NSStatusBar.system.thickness)
        return NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - thickness,
            width: screen.frame.width,
            height: thickness
        )
    }
}

@MainActor
final class MenuBarGeometry {
    static let shared = MenuBarGeometry()

    func anchors(for screen: NSScreen) -> MenuAnchor {
        MenuBarProbe.anchors(for: screen)
    }
}
