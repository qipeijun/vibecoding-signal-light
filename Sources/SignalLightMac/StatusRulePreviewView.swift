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
        SignalLightVisualStyle.drawBody(in: bodyRect, cornerRadius: 7, borderWidth: 0.5)

        let radius = min(bodyRect.width * 0.28, 5.5)
        let centerX = bodyRect.midX
        let gap = (bodyRect.height - radius * 6) / 4
        let firstY = bodyRect.minY + gap + radius

        let lampStep = radius * 2 + gap
        for (index, lamp) in SignalLightVisualStyle.orderedLamps(for: frameState).enumerated() {
            drawLamp(
                center: CGPoint(x: centerX, y: firstY + lampStep * CGFloat(index)),
                radius: radius,
                color: lamp.color,
                brightness: lamp.brightness
            )
        }
    }

    private func drawLamp(center: CGPoint, radius: CGFloat, color: NSColor, brightness: CGFloat) {
        SignalLightVisualStyle.drawLamp(
            center: center,
            radius: radius,
            color: color,
            brightness: brightness,
            cupExpansion: 1.5,
            glowExpansion: radius * 0.4
        )
    }
}
