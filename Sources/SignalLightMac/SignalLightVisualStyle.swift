import AppKit
import SignalLightShared

/// Signal Light 各显示入口共用的黑色扁平绘制规则。
///
/// 外壳与灯杯保持静态，状态动画只改变灯泡和辉光亮度，确保悬浮窗、
/// 状态中心、菜单栏、Touch Bar 与规则预览不会出现不同的视觉语义。
enum SignalLightVisualStyle {
    /// 交通灯的固定视觉顺序：竖向从上到下、横向从左到右均为红、黄、绿。
    static func orderedLamps(for frameState: SignalFrame) -> [(color: NSColor, brightness: CGFloat)] {
        [
            (.systemRed, frameState.red),
            (.systemYellow, frameState.yellow),
            (.systemGreen, frameState.green),
        ]
    }

    /// 绘制无渐变、无高光的深黑灯体。
    static func drawBody(in rect: NSRect, cornerRadius: CGFloat, borderWidth: CGFloat = 1) {
        let body = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(calibratedWhite: 0.035, alpha: 0.98).setFill()
        body.fill()

        NSColor.white.withAlphaComponent(0.10).setStroke()
        body.lineWidth = borderWidth
        body.stroke()
    }

    /// 绘制一颗扁平灯泡。brightness 为 0 时完全熄灭，为 1 时使用完整状态色。
    /// 中间值不设置额外亮度下限，慢呼吸才能呈现清晰的暗到亮变化。
    static func drawLamp(
        center: CGPoint,
        radius: CGFloat,
        color: NSColor,
        brightness: CGFloat,
        cupExpansion: CGFloat,
        glowExpansion: CGFloat
    ) {
        let intensity = max(0, min(1, brightness))
        let lampRect = NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        let cupRect = lampRect.insetBy(dx: -cupExpansion, dy: -cupExpansion)
        let cupPath = NSBezierPath(ovalIn: cupRect)
        NSColor(calibratedWhite: 0.015, alpha: 0.96).setFill()
        cupPath.fill()
        NSColor.white.withAlphaComponent(0.07).setStroke()
        cupPath.lineWidth = max(0.5, radius * 0.05)
        cupPath.stroke()

        if intensity > 0, glowExpansion > 0 {
            let glowPath = NSBezierPath(
                ovalIn: lampRect.insetBy(dx: -glowExpansion, dy: -glowExpansion)
            )
            color.withAlphaComponent(0.20 * intensity).setFill()
            glowPath.fill()
        }

        let bulbPath = NSBezierPath(ovalIn: lampRect)
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        bulbPath.fill()

        if intensity > 0 {
            color.withAlphaComponent(intensity).setFill()
            bulbPath.fill()
            color.withAlphaComponent(0.22 * intensity).setStroke()
            bulbPath.lineWidth = max(0.5, radius * 0.08)
            bulbPath.stroke()
        }
    }
}
