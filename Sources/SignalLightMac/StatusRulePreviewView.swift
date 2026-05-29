import AppKit
import SignalLightShared

final class StatusRulePreviewView: NSView {
    var frameState = SignalFrame(green: 0, yellow: 0, red: 0) {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bodyRect = bounds.insetBy(dx: 4, dy: 3)
        let body = NSBezierPath(roundedRect: bodyRect, xRadius: 7, yRadius: 7)
        NSColor(calibratedWhite: 0.08, alpha: 0.82).setFill()
        body.fill()

        let radius = min(bodyRect.width * 0.28, 5.5)
        let centerX = bodyRect.midX
        let gap = (bodyRect.height - radius * 6) / 4
        let firstY = bodyRect.minY + gap + radius

        drawLamp(center: CGPoint(x: centerX, y: firstY), radius: radius, color: .systemGreen, brightness: frameState.green)
        drawLamp(center: CGPoint(x: centerX, y: firstY + radius * 2 + gap), radius: radius, color: .systemYellow, brightness: frameState.yellow)
        drawLamp(center: CGPoint(x: centerX, y: firstY + (radius * 2 + gap) * 2), radius: radius, color: .systemRed, brightness: frameState.red)
    }

    private func drawLamp(center: CGPoint, radius: CGFloat, color: NSColor, brightness: CGFloat) {
        let active = max(0, min(1, brightness))
        let lampRect = NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        NSColor.black.withAlphaComponent(0.38).setFill()
        NSBezierPath(ovalIn: lampRect.insetBy(dx: -1.5, dy: -1.5)).fill()

        if active > 0 {
            color.withAlphaComponent(0.95).setFill()
        } else {
            NSColor(calibratedWhite: 0.02, alpha: 0.62).setFill()
        }
        NSBezierPath(ovalIn: lampRect).fill()
    }
}
