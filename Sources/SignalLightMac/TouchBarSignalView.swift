import AppKit
import SignalLightShared

final class TouchBarSignalView: NSView {
    var frameState = SignalFrame(green: 1, yellow: 0, red: 0) {
        didSet {
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 132, height: 30)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bodyRect = bounds.insetBy(dx: 4, dy: 3)
        let body = NSBezierPath(roundedRect: bodyRect, xRadius: 7, yRadius: 7)
        NSColor(calibratedWhite: 0.02, alpha: 0.96).setFill()
        body.fill()

        let radius = min(bodyRect.height * 0.32, bodyRect.width / 9)
        let spacing = bodyRect.width / 4
        let centerY = bodyRect.midY

        drawLamp(
            center: CGPoint(x: bodyRect.minX + spacing, y: centerY),
            radius: radius,
            color: NSColor.systemGreen,
            brightness: frameState.green
        )
        drawLamp(
            center: CGPoint(x: bodyRect.minX + spacing * 2, y: centerY),
            radius: radius,
            color: NSColor.systemYellow,
            brightness: frameState.yellow
        )
        drawLamp(
            center: CGPoint(x: bodyRect.minX + spacing * 3, y: centerY),
            radius: radius,
            color: NSColor.systemRed,
            brightness: frameState.red
        )
    }

    private func drawLamp(center: CGPoint, radius: CGFloat, color: NSColor, brightness: CGFloat) {
        let active = max(0, min(1, brightness))
        let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let path = NSBezierPath(ovalIn: rect)

        if active > 0 {
            let visual = 0.24 + active * 0.76
            color.withAlphaComponent(0.32 + visual * 0.66).setFill()
        } else {
            NSColor(calibratedWhite: 0.018, alpha: 0.72).setFill()
        }
        path.fill()

        if active > 0 {
            color.withAlphaComponent(0.28 * active).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}
