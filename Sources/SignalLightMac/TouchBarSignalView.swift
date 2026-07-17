import AppKit
import SignalLightShared

final class TouchBarSignalView: NSView {
    var frameState = SignalFrame(green: 1, yellow: 0, red: 0) {
        didSet {
            needsDisplay = true
        }
    }

    var stateName = SignalState.idle.displayName {
        didSet { setAccessibilityValue(stateName) }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 132, height: 30)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configureAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        configureAccessibility()
    }

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Signal Light Touch Bar 状态灯")
        setAccessibilityValue(stateName)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bodyRect = bounds.insetBy(dx: 4, dy: 3)
        SignalLightVisualStyle.drawBody(in: bodyRect, cornerRadius: 7, borderWidth: 0.5)

        let radius = min(bodyRect.height * 0.32, bodyRect.width / 9)
        let spacing = bodyRect.width / 4
        let centerY = bodyRect.midY

        for (index, lamp) in SignalLightVisualStyle.orderedLamps(for: frameState).enumerated() {
            drawLamp(
                center: CGPoint(x: bodyRect.minX + spacing * CGFloat(index + 1), y: centerY),
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
            glowExpansion: radius * 0.45
        )
    }
}
