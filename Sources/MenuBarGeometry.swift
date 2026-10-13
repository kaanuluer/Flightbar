import AppKit

struct MenuAnchor: Sendable {
    var startX: CGFloat
    var endX: CGFloat
    var bar: NSRect
}

enum MenuBarProbe {
    /// The flight path is estimated from this screen's menu-bar edges.
    /// Reading other apps' menu bars goes through Accessibility, which macOS 27
    /// shows as Device Control and Data Access. The animation does not need that.
    static func anchors(for screen: NSScreen) -> MenuAnchor {
        let height = menuBarHeight(for: screen)
        let bar = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - height,
            width: screen.frame.width,
            height: height
        )
        let leftEdge = screen.auxiliaryTopLeftArea?.minX ?? screen.frame.minX
        let rightEdge = screen.auxiliaryTopRightArea?.maxX ?? screen.frame.maxX
        let endX = leftEdge + 20
        var startX = rightEdge - 74
        if startX < endX + 80 {
            startX = min(rightEdge - 16, endX + 80)
        }
        return MenuAnchor(startX: startX, endX: endX, bar: bar)
    }

    private static func menuBarHeight(for screen: NSScreen) -> CGFloat {
        let fromVisibleFrame = screen.frame.maxY - screen.visibleFrame.maxY
        return max(NSStatusBar.system.thickness, fromVisibleFrame)
    }
}

@MainActor
final class MenuBarGeometry {
    static let shared = MenuBarGeometry()

    func anchors(for screen: NSScreen) -> MenuAnchor {
        MenuBarProbe.anchors(for: screen)
    }
}
