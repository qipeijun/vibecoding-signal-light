import AppKit
import Foundation
import SignalLightShared

enum ReadmeScreenshotCapture {
    static func run(outputPath: String) throws {
        let outputDir = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.accessory)

        let store = SignalLightConfigStore()
        let demoConfig = SignalLightConfig(
            schemaVersion: configSchemaVersion,
            display: DisplayConfig(
                showFloatingWindowAtStartup: true,
                alwaysOnTop: true,
                windowScale: 1.0,
                opacity: 0.92,
                animationSpeed: 1.0,
                showDockIcon: true,
                showTouchBar: true
            ),
            agent: .default,
            statusRules: StatusRulesConfig(rules: [
                "attention": SignalRuleConfig(color: "yellow", mode: "flash"),
                "permission": SignalRuleConfig(color: "red", mode: "flash"),
                "working": SignalRuleConfig(color: "green", mode: "workPulse"),
            ])
        )

        try saveFloatingLight(to: outputDir.appendingPathComponent("screenshot-floating-light.png"))
        try savePanel(
            title: "显示设置",
            subtitle: "控制悬浮窗、透明度、动画速度和系统显示入口。",
            content: DisplaySettingsViewController(config: demoConfig.display, onUpdate: { _ in }),
            size: NSSize(width: 680, height: 540),
            to: outputDir.appendingPathComponent("screenshot-settings-display.png")
        )
        try savePanel(
            title: "状态灯规则",
            subtitle: "按状态配置颜色、动画和恢复默认行为。",
            content: StatusRulesSettingsViewController(config: demoConfig.statusRules, onUpdate: { _ in }),
            size: NSSize(width: 680, height: 540),
            to: outputDir.appendingPathComponent("screenshot-rules-panel.png")
        )
        try savePanel(
            title: "配置诊断",
            subtitle: "检查配置文件、状态目录和修复写入问题。",
            content: DiagnosticsViewController(configStore: store, config: demoConfig),
            size: NSSize(width: 680, height: 500),
            to: outputDir.appendingPathComponent("screenshot-diagnostics.png")
        )
    }

    private static func saveFloatingLight(to url: URL) throws {
        let size = NSSize(width: 520, height: 320)
        let canvas = ScreenshotCanvas(frame: NSRect(origin: .zero, size: size))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "桌面悬浮状态灯")
        title.font = NSFont.boldSystemFont(ofSize: 24)
        title.frame = NSRect(x: 46, y: 52, width: 260, height: 32)
        canvas.addSubview(title)

        let subtitle = NSTextField(labelWithString: "不用切回终端，也能看到 Agent 正在工作、等待授权或已经完成。")
        subtitle.font = NSFont.systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 46, y: 92, width: 330, height: 44)
        subtitle.cell?.wraps = true
        canvas.addSubview(subtitle)

        let signalView = SignalLightView(frame: NSRect(x: 382, y: 52, width: 84, height: 183))
        signalView.frameState = SignalFrame(green: 1, yellow: 0, red: 0)
        canvas.addSubview(signalView)

        let caption = NSTextField(labelWithString: "working / green pulse")
        caption.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        caption.frame = NSRect(x: 330, y: 246, width: 188, height: 20)
        canvas.addSubview(caption)

        try render(canvas, size: size, to: url)
    }

    private static func savePanel(
        title: String,
        subtitle: String,
        content: NSViewController,
        size: NSSize,
        to url: URL
    ) throws {
        let root = ScreenshotCanvas(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.boldSystemFont(ofSize: 20)
        titleField.alignment = .center
        titleField.frame = NSRect(x: 24, y: 24, width: size.width - 48, height: 28)
        root.addSubview(titleField)

        let subtitleField = NSTextField(labelWithString: subtitle)
        subtitleField.font = NSFont.systemFont(ofSize: 12)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.alignment = .center
        subtitleField.frame = NSRect(x: 24, y: 58, width: size.width - 48, height: 20)
        root.addSubview(subtitleField)

        let separator = NSBox(frame: NSRect(x: 24, y: 92, width: size.width - 48, height: 1))
        separator.boxType = .separator
        root.addSubview(separator)

        content.view.frame = NSRect(x: 22, y: 108, width: size.width - 44, height: size.height - 126)
        root.addSubview(content.view)
        scrollToTopIfNeeded(content.view)

        try render(root, size: size, to: url)
    }

    private static func scrollToTopIfNeeded(_ view: NSView) {
        if let scrollView = view as? NSScrollView {
            let maxY = max(0, (scrollView.documentView?.bounds.height ?? 0) - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }
        for subview in view.subviews {
            scrollToTopIfNeeded(subview)
        }
    }

    private static func render(_ view: NSView, size: NSSize, to url: URL) throws {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()

        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建截图 bitmap"])
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "capture", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法编码 PNG"])
        }
        try data.write(to: url, options: .atomic)
    }
}

private final class ScreenshotCanvas: NSView {
    override var isFlipped: Bool {
        true
    }
}
