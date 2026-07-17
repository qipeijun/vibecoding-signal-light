import AppKit
import SignalLightShared

final class SignalLightView: NSView {
    static let preferredSize = NSSize(width: 56, height: 122)

    var frameState = SignalFrame(green: 1, yellow: 0, red: 0) {
        didSet {
            needsDisplay = true
        }
    }

    var stateName = SignalState.idle.displayName {
        didSet { setAccessibilityValue(stateName) }
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        configureAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        configureAccessibility()
    }

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Signal Light 悬浮状态灯")
        setAccessibilityValue(stateName)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSignalBody(in: bounds)
    }

    private func drawSignalBody(in rect: NSRect) {
        let bodyRect = rect.insetBy(dx: 5, dy: 5)
        SignalLightVisualStyle.drawBody(in: bodyRect, cornerRadius: 11)

        let centerX = bodyRect.midX
        let radius = min(bodyRect.width * 0.30, 10)
        let spacing = max(8, floor((bodyRect.width - radius * 2) / 2))
        let centerGap = radius * 2 + spacing
        let firstY = bodyRect.minY + spacing + radius

        let lamps = SignalLightVisualStyle.orderedLamps(for: frameState)
        for (index, lamp) in lamps.enumerated() {
            SignalLightVisualStyle.drawLamp(
                center: CGPoint(x: centerX, y: firstY + centerGap * CGFloat(index)),
                radius: radius,
                color: lamp.color,
                brightness: lamp.brightness,
                cupExpansion: 3,
                glowExpansion: radius * 0.65
            )
        }
    }
}
