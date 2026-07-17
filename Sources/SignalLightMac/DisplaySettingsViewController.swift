import AppKit
import SignalLightShared

final class DisplaySettingsViewController: NSViewController {
    private let onUpdate: (DisplayConfig) throws -> Void
    private var displayConfig: DisplayConfig

    init(config: DisplayConfig, onUpdate: @escaping (DisplayConfig) throws -> Void) {
        self.displayConfig = config
        self.onUpdate = onUpdate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 390))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 8, right: 4)
        stack.alignment = .leading

        stack.addArrangedSubview(makeSectionTitle("启动与层级"))

        let startupCheck = makeCheckbox(title: "启动时显示悬浮窗", isOn: displayConfig.showFloatingWindowAtStartup) { [weak self] on in
            self?.displayConfig.showFloatingWindowAtStartup = on
            self?.notify()
        }
        stack.addArrangedSubview(startupCheck)

        let topCheck = makeCheckbox(title: "始终置顶", isOn: displayConfig.alwaysOnTop) { [weak self] on in
            self?.displayConfig.alwaysOnTop = on
            self?.notify()
        }
        stack.addArrangedSubview(topCheck)

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeSectionTitle("外观"))

        let scaleLabel = NSTextField(labelWithString: "窗口大小: \(formatPercent(displayConfig.windowScale))")
        let scaleSlider = makeSlider(value: displayConfig.windowScale, min: 0.5, max: 2.0) { [weak self, weak scaleLabel] value in
            self?.displayConfig.windowScale = value
            scaleLabel?.stringValue = "窗口大小: \(formatPercent(value))"
            self?.notify()
        }
        stack.addArrangedSubview(scaleLabel)
        stack.addArrangedSubview(scaleSlider)

        let opacityLabel = NSTextField(labelWithString: "不透明度: \(formatPercent(displayConfig.opacity))")
        let opacitySlider = makeSlider(value: displayConfig.opacity, min: 0.1, max: 1.0) { [weak self, weak opacityLabel] value in
            self?.displayConfig.opacity = value
            opacityLabel?.stringValue = "不透明度: \(formatPercent(value))"
            self?.notify()
        }
        stack.addArrangedSubview(opacityLabel)
        stack.addArrangedSubview(opacitySlider)

        let speedLabel = NSTextField(labelWithString: "环境动画速度: \(String(format: "%.2fx", displayConfig.animationSpeed))")
        let speedSlider = makeSlider(value: min(displayConfig.animationSpeed, 1.0), min: 0.25, max: 1.0) { [weak self, weak speedLabel] value in
            self?.displayConfig.animationSpeed = value
            speedLabel?.stringValue = "环境动画速度: \(String(format: "%.2fx", value))"
            self?.notify()
        }
        stack.addArrangedSubview(speedLabel)
        stack.addArrangedSubview(speedSlider)

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeSectionTitle("系统显示"))

        let dockCheck = makeCheckbox(title: "显示 Dock 图标 (需重启生效)", isOn: displayConfig.showDockIcon) { [weak self] on in
            self?.displayConfig.showDockIcon = on
            self?.notify()
        }
        stack.addArrangedSubview(dockCheck)

        let touchBarCheck = makeCheckbox(title: "显示 Touch Bar", isOn: displayConfig.showTouchBar) { [weak self] on in
            self?.displayConfig.showTouchBar = on
            self?.notify()
        }
        stack.addArrangedSubview(touchBarCheck)

        let resetButton = NSButton(title: "恢复默认显示设置", target: self, action: #selector(resetDisplaySettings))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        stack.addArrangedSubview(resetButton)

        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: 512),
        ])
    }

    private func notify() {
        do {
            try onUpdate(displayConfig)
        } catch {
            showSettingsError(error)
        }
    }

    private func makeCheckbox(title: String, isOn: Bool, action: @escaping (Bool) -> Void) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = isOn ? .on : .off
        button.setButtonAction { action(button.state == .on) }
        return button
    }

    @objc private func resetDisplaySettings() {
        guard confirmSettingsAction(
            title: "恢复默认显示设置？",
            message: "悬浮窗显示、置顶、尺寸、透明度、动画速度、Dock 和 Touch Bar 设置将恢复默认值。",
            actionTitle: "恢复默认"
        ) else { return }
        displayConfig = .default
        notify()
        view.subviews.forEach { $0.removeFromSuperview() }
        buildUI()
    }

    private func makeSlider(value: Double, min: Double, max: Double, action: @escaping (Double) -> Void) -> NSSlider {
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: nil, action: nil)
        slider.sliderType = .linear
        slider.controlSize = .small
        slider.setSliderAction { action(slider.doubleValue) }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 20))
        slider.frame = NSRect(x: 0, y: 0, width: 500, height: 20)
        slider.autoresizingMask = [.width]
        container.addSubview(slider)
        return slider
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func makeSectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }
}

private func formatPercent(_ value: Double) -> String {
    String(format: "%.0f%%", value * 100)
}

// MARK: - Target-Action helpers

private class ActionTrampoline {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}

private var trampolineKey: UInt8 = 0

extension NSButton {
    func setButtonAction(_ action: @escaping () -> Void) {
        let trampoline = ActionTrampoline(action)
        objc_setAssociatedObject(self, &trampolineKey, trampoline, .OBJC_ASSOCIATION_RETAIN)
        self.target = trampoline
        self.action = #selector(ActionTrampoline.invoke)
    }
}

extension NSSlider {
    func setSliderAction(_ action: @escaping () -> Void) {
        let trampoline = ActionTrampoline(action)
        objc_setAssociatedObject(self, &trampolineKey, trampoline, .OBJC_ASSOCIATION_RETAIN)
        self.target = trampoline
        self.action = #selector(ActionTrampoline.invoke)
    }
}
