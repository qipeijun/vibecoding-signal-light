import AppKit
import SignalLightShared

func makeStatusIcon(frameState: SignalFrame) -> NSImage {
    let size = NSSize(width: 36, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
        let bodyRect = NSRect(x: 2.5, y: 2, width: rect.width - 5, height: rect.height - 4)
        let body = NSBezierPath(roundedRect: bodyRect, xRadius: 6, yRadius: 6)
        let bodyGradient = NSGradient(colors: [
            NSColor(calibratedWhite: 0.07, alpha: 0.98),
            NSColor(calibratedWhite: 0.01, alpha: 0.99),
        ])
        bodyGradient?.draw(in: body, angle: 90)

        let radius: CGFloat = 3.7
        let centerY = rect.midY
        let centers: [CGFloat] = [10, 18, 26]
        drawStatusLamp(
            center: CGPoint(x: centers[0], y: centerY),
            radius: radius,
            color: NSColor.systemGreen,
            brightness: frameState.green
        )
        drawStatusLamp(
            center: CGPoint(x: centers[1], y: centerY),
            radius: radius,
            color: NSColor.systemYellow,
            brightness: frameState.yellow
        )
        drawStatusLamp(
            center: CGPoint(x: centers[2], y: centerY),
            radius: radius,
            color: NSColor.systemRed,
            brightness: frameState.red
        )
        return true
    }
    image.isTemplate = false
    return image
}

private func drawStatusLamp(center: CGPoint, radius: CGFloat, color: NSColor, brightness: CGFloat) {
    let active = max(0, min(1, brightness))
    let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

    if active > 0 {
        let glowRect = rect.insetBy(dx: -radius * 0.44, dy: -radius * 0.44)
        let glowPath = NSBezierPath(ovalIn: glowRect)
        let visual = 0.24 + active * 0.76
        color.withAlphaComponent(0.24 * visual).setFill()
        glowPath.fill()
    }

    if active > 0 {
        let visual = 0.24 + active * 0.76
        color.withAlphaComponent(0.36 + visual * 0.62).setFill()
    } else {
        NSColor(calibratedWhite: 0.018, alpha: 0.70).setFill()
    }
    NSBezierPath(ovalIn: rect).fill()
}
