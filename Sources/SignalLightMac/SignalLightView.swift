import AppKit
import SignalLightShared

final class SignalLightView: NSView {
    static let preferredSize = NSSize(width: 56, height: 122)

    var frameState = SignalFrame(green: 1, yellow: 0, red: 0) {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSignalBody(in: bounds)
    }

    private func drawSignalBody(in rect: NSRect) {
        let bodyRect = rect.insetBy(dx: 5, dy: 5)
        drawDeepGlassBody(in: bodyRect)

        let centerX = bodyRect.midX
        let radius = min(bodyRect.width * 0.30, 10)
        let spacing = max(8, floor((bodyRect.width - radius * 2) / 2))
        let centerGap = radius * 2 + spacing
        let firstY = bodyRect.minY + spacing + radius

        drawLamp(center: CGPoint(x: centerX, y: firstY), radius: radius, color: .systemGreen, brightness: frameState.green)
        drawLamp(center: CGPoint(x: centerX, y: firstY + centerGap), radius: radius, color: .systemYellow, brightness: frameState.yellow)
        drawLamp(center: CGPoint(x: centerX, y: firstY + centerGap * 2), radius: radius, color: .systemRed, brightness: frameState.red)
    }

    private func drawDeepGlassBody(in rect: NSRect) {
        let shadow = NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: 1), xRadius: 11, yRadius: 11)
        NSColor.black.withAlphaComponent(0.18).setFill()
        shadow.fill()

        let body = NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11)
        let gradient = NSGradient(colors: [
            NSColor(calibratedWhite: 0.06, alpha: 0.70),
            NSColor(calibratedWhite: 0.01, alpha: 0.82),
        ])
        gradient?.draw(in: body, angle: 90)

    }

    private func drawLamp(center: CGPoint, radius: CGFloat, color: NSColor, brightness: CGFloat) {
        let active = max(0, min(1, brightness))
        let lampRect = NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let cupRect = lampRect.insetBy(dx: -3, dy: -3)

        NSColor.black.withAlphaComponent(0.30).setFill()
        NSBezierPath(ovalIn: cupRect).fill()

        if active > 0 {
            let visual = 0.24 + active * 0.76
            color.withAlphaComponent(0.14 * visual).setFill()
            NSBezierPath(ovalIn: cupRect).fill()
        }

        if active > 0 {
            let visual = 0.24 + active * 0.76
            color.withAlphaComponent(0.30 + visual * 0.66).setFill()
        } else {
            NSColor(calibratedWhite: 0.015, alpha: 0.58).setFill()
        }
        NSBezierPath(ovalIn: lampRect).fill()
    }
}
