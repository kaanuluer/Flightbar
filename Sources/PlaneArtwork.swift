import AppKit
import SwiftUI

enum PlaneTint: String, CaseIterable, Identifiable {
    case white
    case yellow
    case orange
    case red
    case green
    case cyan
    case blue
    case purple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: return "White"
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        case .red: return "Red"
        case .green: return "Green"
        case .cyan: return "Cyan"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }

    var color: NSColor {
        switch self {
        case .white: return .white
        case .yellow: return NSColor(srgbRed: 1, green: 0.84, blue: 0.18, alpha: 1)
        case .orange: return NSColor(srgbRed: 1, green: 0.52, blue: 0.12, alpha: 1)
        case .red: return NSColor(srgbRed: 1, green: 0.27, blue: 0.27, alpha: 1)
        case .green: return NSColor(srgbRed: 0.30, green: 0.85, blue: 0.39, alpha: 1)
        case .cyan: return NSColor(srgbRed: 0.32, green: 0.90, blue: 0.95, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.36, green: 0.62, blue: 1, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.72, green: 0.45, blue: 1, alpha: 1)
        }
    }

    var menuImage: NSImage {
        if let cached = Self.swatches[self] { return cached }
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            self.color.setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.28).setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
        image.isTemplate = false
        Self.swatches[self] = image
        return image
    }

    private static var swatches: [PlaneTint: NSImage] = [:]
}

@MainActor
enum PlaneArtwork {
    static func image(pointingLeft: Bool, tint: PlaneTint) -> NSImage {
        let key = CacheKey(pointingLeft: pointingLeft, tint: tint)
        if let cached = cache[key] { return cached }
        let rendered = render(pointingLeft: pointingLeft, tint: tint)
        cache[key] = rendered
        return rendered
    }

    private struct CacheKey: Hashable {
        var pointingLeft: Bool
        var tint: PlaneTint
    }

    private static var cache: [CacheKey: NSImage] = [:]

    private static func render(pointingLeft: Bool, tint: PlaneTint) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        guard let symbol = NSImage(systemSymbolName: "airplane", accessibilityDescription: "Aircraft")?
            .withSymbolConfiguration(configuration) else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        let fill = Self.tint(symbol, tint.color)
        let outlineColor = contrastingOutline(for: tint.color)
        let black = Self.tint(symbol, outlineColor)
        // The symbol nose points east. 180° turns it west, toward the Apple logo.
        let radians = (pointingLeft ? 180.0 : 0) * CGFloat.pi / 180
        let pad: CGFloat = 3
        let side = ceil(max(symbol.size.width, symbol.size.height) + pad * 2)
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.interpolationQuality = .high
            func draw(_ source: NSImage, dx: CGFloat, dy: CGFloat) {
                context.saveGState()
                context.translateBy(x: rect.midX + dx, y: rect.midY + dy)
                context.rotate(by: radians)
                source.draw(in: NSRect(
                    x: -symbol.size.width / 2,
                    y: -symbol.size.height / 2,
                    width: symbol.size.width,
                    height: symbol.size.height
                ))
                context.restoreGState()
            }
            for dx in [-0.85, 0, 0.85] {
                for dy in [-0.85, 0, 0.85] where dx != 0 || dy != 0 {
                    draw(black, dx: dx, dy: dy)
                }
            }
            draw(fill, dx: 0, dy: 0)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func contrastingOutline(for color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        if luminance < 0.45 {
            return NSColor.white.withAlphaComponent(0.95)
        }
        return NSColor.black.withAlphaComponent(0.9)
    }

    private static func tint(_ image: NSImage, _ color: NSColor) -> NSImage {
        let copy = NSImage(size: image.size)
        copy.lockFocus()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        copy.unlockFocus()
        copy.isTemplate = false
        return copy
    }
}

/// Menu bar mark: a top-down aircraft, not the side-view SF Symbol and not the Location arrow.
/// Black fill with `isTemplate` so AppKit tints it for light and dark menu bars.
/// The same outline is `Resources/MenuBarIcon.svg`.
enum MenuBarMark {
    static let pointSize = CGSize(width: 18, height: 18)

    /// Outline in an 18×18 box, y increasing downward.
    static let outline: [CGPoint] = [
        CGPoint(x: 9.0, y: 1.0),
        CGPoint(x: 10.5, y: 5.4),
        CGPoint(x: 16.8, y: 8.0),
        CGPoint(x: 16.8, y: 10.1),
        CGPoint(x: 10.7, y: 9.2),
        CGPoint(x: 10.5, y: 13.2),
        CGPoint(x: 13.8, y: 16.3),
        CGPoint(x: 12.2, y: 17.2),
        CGPoint(x: 9.7, y: 14.7),
        CGPoint(x: 8.3, y: 14.7),
        CGPoint(x: 5.8, y: 17.2),
        CGPoint(x: 4.2, y: 16.3),
        CGPoint(x: 7.5, y: 13.2),
        CGPoint(x: 7.3, y: 9.2),
        CGPoint(x: 1.2, y: 10.1),
        CGPoint(x: 1.2, y: 8.0),
        CGPoint(x: 7.5, y: 5.4)
    ]

    static var templateImage: NSImage {
        if let cached = cache { return cached }
        let image = NSImage(size: pointSize, flipped: false) { rect in
            NSColor.black.setFill()
            let path = NSBezierPath()
            guard let first = outline.first else { return false }
            // Outline is y-down. AppKit images are y-up, so the nose stays at the top.
            path.move(to: CGPoint(x: first.x, y: rect.height - first.y))
            for point in outline.dropFirst() {
                path.line(to: CGPoint(x: point.x, y: rect.height - point.y))
            }
            path.close()
            path.fill()
            return true
        }
        image.isTemplate = true
        cache = image
        return image
    }

    private static var cache: NSImage?
}

struct MenuBarMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / MenuBarMark.pointSize.width
        let sy = rect.height / MenuBarMark.pointSize.height
        var path = Path()
        guard let first = MenuBarMark.outline.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * sx, y: rect.minY + first.y * sy))
        for point in MenuBarMark.outline.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * sx, y: rect.minY + point.y * sy))
        }
        path.closeSubpath()
        return path
    }
}

