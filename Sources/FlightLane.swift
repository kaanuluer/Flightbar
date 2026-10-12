import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class FlightLane {
    static let shared = FlightLane()

    func present(_ aircraft: Aircraft) {
        guard !sprites.contains(where: { $0.aircraft.hex == aircraft.hex }),
              !pending.contains(where: { $0.hex == aircraft.hex }) else { return }
        pending.append(aircraft)
        drain()
    }

    func presentPinned(_ aircraft: Aircraft) {
        launch(aircraft, pinned: true)
    }

    func applyTint(_ tint: PlaneTint) {
        for sprite in sprites {
            let pointingLeft = sprite.endX <= sprite.startX
            sprite.view.image = PlaneArtwork.image(pointingLeft: pointingLeft, tint: tint)
        }
    }

    func refresh(_ aircraft: Aircraft) {
        guard let index = sprites.firstIndex(where: { $0.aircraft.hex == aircraft.hex }) else { return }
        sprites[index].aircraft = aircraft
    }

    private struct Sprite {
        let id = UUID()
        var aircraft: Aircraft
        let view: NSImageView
        let displayID: CGDirectDisplayID
        var startX: CGFloat
        var endX: CGFloat
        var progress: CGFloat
        let progressPerSecond: CGFloat
        var pinned: Bool
    }

    private final class LaneWindow: NSWindow {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private var windows: [CGDirectDisplayID: LaneWindow] = [:]
    private var sprites: [Sprite] = []
    private var pending: [Aircraft] = []
    private var drainScheduled = false
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var hoveredID: UUID?
    private var hoverLostAt: CFTimeInterval?
    private var card: NSPanel?
    private var cardEffect: NSVisualEffectView?
    private var cardHost: NSHostingView<FlightCardView>?
    private var forcedHoverID: UUID?

    private func drain() {
        guard !drainScheduled, !pending.isEmpty else { return }
        let next = pending.removeFirst()
        launch(next, pinned: false)
        guard !pending.isEmpty else { return }
        drainScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) { [weak self] in
            MainActor.assumeIsolated {
                self?.drainScheduled = false
                self?.drain()
            }
        }
    }

    private func launch(_ aircraft: Aircraft, pinned: Bool) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
                ?? NSScreen.screens.first else { return }
        var anchor = MenuBarGeometry.shared.anchors(for: screen)
        if abs(anchor.startX - anchor.endX) < 80 {
            anchor.startX = screen.frame.maxX - 88
            anchor.endX = screen.frame.minX + 27
        }
        if CommandLine.arguments.contains("--preview") || CommandLine.arguments.contains("--preview-card") {
            NSLog(
                "Flightbar %@ start %.0f end %.0f bar %@",
                screen.localizedName,
                anchor.startX,
                anchor.endX,
                NSStringFromRect(anchor.bar)
            )
        }
        let pointingLeft = anchor.endX <= anchor.startX
        let image = PlaneArtwork.image(pointingLeft: pointingLeft, tint: AppModel.shared.planeColor)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.alphaValue = 0
        let distance = abs(anchor.endX - anchor.startX)
        let duration = min(24, max(9, Double(distance) / 100))
        let sprite = Sprite(
            aircraft: aircraft,
            view: imageView,
            displayID: screen.displayID,
            startX: anchor.startX,
            endX: anchor.endX,
            progress: pinned ? 0.42 : 0,
            progressPerSecond: CGFloat(1 / duration),
            pinned: pinned
        )
        let window = laneWindow(for: screen, bar: anchor.bar)
        window.contentView?.addSubview(imageView)
        if pinned { forcedHoverID = sprite.id }
        sprites.append(sprite)
        startTicking()
        if pinned { tick() }
    }

    private func laneWindow(for screen: NSScreen, bar: NSRect) -> LaneWindow {
        let identifier = screen.displayID
        let window: LaneWindow
        if let existing = windows[identifier] {
            window = existing
        } else {
            let created = LaneWindow(contentRect: bar, styleMask: [.borderless], backing: .buffered, defer: false)
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = false
            created.ignoresMouseEvents = true
            created.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
            created.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            created.hidesOnDeactivate = false
            created.isReleasedWhenClosed = false
            created.animationBehavior = .none
            let content = NSView(frame: NSRect(origin: .zero, size: bar.size))
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.clear.cgColor
            created.contentView = content
            windows[identifier] = created
            window = created
        }
        if window.frame != bar {
            window.setFrame(bar, display: true)
        }
        if !window.isVisible {
            window.orderFrontRegardless()
        }
        return window
    }

    private func startTicking() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastTick)
        lastTick = now
        let mouse = NSEvent.mouseLocation
        var finished: [UUID] = []

        for index in sprites.indices {
            let sprite = sprites[index]
            guard let window = windows[sprite.displayID] else { continue }
            let globalX = sprite.startX + (sprite.endX - sprite.startX) * sprite.progress
            let nearVertically = abs(mouse.y - window.frame.midY) < window.frame.height + 36
            let nearHorizontally = abs(mouse.x - globalX) < 110
            let slowed = !sprite.pinned && nearVertically && nearHorizontally
            if !sprite.pinned && hoveredID != sprite.id {
                let multiplier: CGFloat = slowed ? 0.32 : 1
                sprites[index].progress = min(1, sprite.progress + sprite.progressPerSecond * CGFloat(dt) * multiplier)
            }
            let current = sprites[index]
            let traveled = current.startX + (current.endX - current.startX) * current.progress
            let imageSize = current.view.image?.size ?? NSSize(width: 22, height: 22)
            let fit = min(1, max(0.65, (window.frame.height - 6) / max(imageSize.height, 1)))
            let emphasis: CGFloat = hoveredID == current.id ? 1.12 : 1
            let width = imageSize.width * fit * emphasis
            let height = imageSize.height * fit * emphasis
            let localX = traveled - window.frame.minX
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            current.view.frame = NSRect(
                x: localX - width / 2,
                y: (window.frame.height - height) / 2,
                width: width,
                height: height
            )
            let hovering = hoveredID == current.id
            if hovering || current.pinned {
                current.view.alphaValue = 1
            } else if current.progress < 0.035 {
                current.view.alphaValue = current.progress / 0.035
            } else if current.progress > 0.95 {
                current.view.alphaValue = max(0, (1 - current.progress) / 0.05)
            } else {
                current.view.alphaValue = 1
            }
            CATransaction.commit()
            if current.progress >= 1, hoveredID != current.id, !current.pinned {
                finished.append(current.id)
            }
        }

        let hitID = spriteUnderMouse(mouse)
        if let forced = forcedHoverID, sprites.contains(where: { $0.id == forced }) {
            hoveredID = forced
            hoverLostAt = nil
        } else if let hitID {
            hoveredID = hitID
            hoverLostAt = nil
        } else if hoveredID != nil {
            if hoverLostAt == nil { hoverLostAt = now }
            if let hoverLostAt, now - hoverLostAt > 0.16 {
                hoveredID = nil
                self.hoverLostAt = nil
            }
        }

        if let hoveredID, let sprite = sprites.first(where: { $0.id == hoveredID }) {
            showCard(for: sprite)
        } else {
            card?.orderOut(nil)
        }

        if !finished.isEmpty {
            for id in finished {
                if let index = sprites.firstIndex(where: { $0.id == id }) {
                    sprites[index].view.removeFromSuperview()
                    sprites.remove(at: index)
                }
            }
        }
        if sprites.isEmpty {
            timer?.invalidate()
            timer = nil
            card?.orderOut(nil)
            hoveredID = nil
            for window in windows.values { window.orderOut(nil) }
        }
    }

    private func spriteUnderMouse(_ mouse: NSPoint) -> UUID? {
        var best: (UUID, CGFloat)?
        for sprite in sprites {
            guard let window = windows[sprite.displayID] else { continue }
            let viewRect = window.convertToScreen(sprite.view.frame).insetBy(dx: -12, dy: 0)
            var hit = viewRect
            hit.origin.y = window.frame.minY
            hit.size.height = window.frame.height
            var contains = hit.contains(mouse)
            if hoveredID == sprite.id, let card, card.isVisible {
                let grown = card.frame.insetBy(dx: -10, dy: -16)
                if grown.contains(mouse) { contains = true }
            }
            if contains {
                let center = hit.midX
                let distance = abs(center - mouse.x)
                if best == nil || distance < best!.1 {
                    best = (sprite.id, distance)
                }
            }
        }
        return best?.0
    }

    private func showCard(for sprite: Sprite) {
        let host = cardHost ?? makeCard()
        if host.rootView.aircraft != sprite.aircraft {
            host.rootView = FlightCardView(aircraft: sprite.aircraft)
            host.layoutSubtreeIfNeeded()
            var size = host.fittingSize
            if size.width < 220 { size.width = 286 }
            if size.height < 90 { size.height = 188 }
            card?.setContentSize(size)
            host.frame = NSRect(origin: .zero, size: size)
            cardEffect?.frame = NSRect(origin: .zero, size: size)
        }
        guard let panel = card, let screen = screen(for: sprite.displayID) else { return }
        let window = windows[sprite.displayID]
        let bar = window?.frame ?? MenuBarProbe.menuBarRect(for: screen)
        let size = panel.frame.size
        let globalX = sprite.startX + (sprite.endX - sprite.startX) * sprite.progress
        var x = globalX - size.width / 2
        x = min(max(screen.frame.minX + 8, x), screen.frame.maxX - size.width - 8)
        let y = max(screen.frame.minY + 8, bar.minY - size.height - 2)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func makeCard() -> NSHostingView<FlightCardView> {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 286, height: 188),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        let effect = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        let seed = Aircraft(
            hex: "seed",
            callsign: "—",
            registration: nil,
            typeCode: nil,
            altitudeFeet: nil,
            groundSpeedKnots: nil,
            trackDegrees: nil,
            verticalRateFPM: nil,
            latitude: 0,
            longitude: 0,
            distanceKm: 0,
            emergency: nil
        )
        let host = NSHostingView(rootView: FlightCardView(aircraft: seed))
        host.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = effect
        effect.addSubview(host)
        card = panel
        cardEffect = effect
        cardHost = host
        return host
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
