import AppKit

enum MenuBarMark {
    /// Black template artwork. The menu bar tints it for light and dark appearances.
    /// A radar arc plus a short jet, so it is not the system Location arrow or the system airplane.
    static func image() -> NSImage {
        let side: CGFloat = 18
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: NSPoint(x: 9, y: 8.2),
                radius: 6.7,
                startAngle: 210,
                endAngle: -30,
                clockwise: true
            )
            arc.lineWidth = 1.55
            arc.lineCapStyle = .round
            arc.stroke()

            let plane = NSBezierPath()
            plane.move(to: NSPoint(x: 9.0, y: 14.5))
            plane.line(to: NSPoint(x: 10.15, y: 10.3))
            plane.line(to: NSPoint(x: 15.5, y: 8.7))
            plane.line(to: NSPoint(x: 14.7, y: 7.35))
            plane.line(to: NSPoint(x: 10.1, y: 8.35))
            plane.line(to: NSPoint(x: 9.85, y: 5.5))
            plane.line(to: NSPoint(x: 12.15, y: 4.05))
            plane.line(to: NSPoint(x: 11.2, y: 3.35))
            plane.line(to: NSPoint(x: 9.45, y: 4.85))
            plane.line(to: NSPoint(x: 8.55, y: 4.85))
            plane.line(to: NSPoint(x: 6.8, y: 3.35))
            plane.line(to: NSPoint(x: 5.85, y: 4.05))
            plane.line(to: NSPoint(x: 8.15, y: 5.5))
            plane.line(to: NSPoint(x: 7.9, y: 8.35))
            plane.line(to: NSPoint(x: 3.3, y: 7.35))
            plane.line(to: NSPoint(x: 2.5, y: 8.7))
            plane.line(to: NSPoint(x: 7.85, y: 10.3))
            plane.close()
            plane.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
