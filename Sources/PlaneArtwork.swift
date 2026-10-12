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
