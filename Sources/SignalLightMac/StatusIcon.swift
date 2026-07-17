import AppKit
import SignalLightShared

func makeStatusIcon(frameState: SignalFrame) -> NSImage {
    let size = NSSize(width: 36, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
        let bodyRect = NSRect(x: 2, y: 1.5, width: rect.width - 4, height: rect.height - 3)
        SignalLightVisualStyle.drawBody(in: bodyRect, cornerRadius: 6, borderWidth: 0.5)

        let radius: CGFloat = 3.5
        let centerY = rect.midY
        let centers: [CGFloat] = [9, 18, 27]

        for (index, lamp) in SignalLightVisualStyle.orderedLamps(for: frameState).enumerated() {
            drawStatusLamp(
                center: CGPoint(x: centers[index], y: centerY),
                radius: radius,
                color: lamp.color,
                brightness: lamp.brightness
            )
        }
        return true
    }
    image.isTemplate = false
    return image
}

private func drawStatusLamp(center: CGPoint, radius: CGFloat, color: NSColor, brightness: CGFloat) {
    SignalLightVisualStyle.drawLamp(
        center: center,
        radius: radius,
        color: color,
        brightness: brightness,
        cupExpansion: 1,
        glowExpansion: 1.5
    )
}
