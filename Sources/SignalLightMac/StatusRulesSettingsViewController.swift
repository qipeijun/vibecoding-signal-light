import AppKit
import SignalLightShared

final class StatusRulesSettingsViewController: NSViewController {
    private struct RuleRow {
        let signal: String
        let colorLabel: NSTextField
        let modePopup: NSPopUpButton
        let stateLabel: NSTextField
        let appearanceLabel: NSTextField
        let previewView: StatusRulePreviewView
        let resetButton: NSButton
    }

    private let onUpdate: (StatusRulesConfig) throws -> Void
    private var rulesConfig: StatusRulesConfig
    private var ruleRows: [RuleRow] = []
    private let summaryLabel = NSTextField(labelWithString: "")
    private let resetAllButton = NSButton(title: "全部恢复默认", target: nil, action: nil)

    private let contentWidth: CGFloat = 636
    private let groups: [(title: String, signals: [String])] = [
        ("日常状态", ["idle", "done", "off"]),
        ("工作流程", ["thinking", "working", "tool_done"]),
        ("需要关注", ["attention", "stale", "permission", "blocked"]),
        ("会话事件", ["session_start", "session_end"]),
    ]

    init(config: StatusRulesConfig, onUpdate: @escaping (StatusRulesConfig) throws -> Void) {
        self.rulesConfig = config
        self.onUpdate = onUpdate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 636, height: 390))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)

        let docView = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 720))
        scrollView.documentView = docView
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        refreshRuleRows()
    }

    private func buildUI() {
        guard let docView = (view as? NSScrollView)?.documentView else {
            return
        }

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        root.alignment = .leading

        root.addArrangedSubview(makeToolbar())
        for group in groups {
            root.addArrangedSubview(makeGroup(title: group.title, signals: group.signals))
        }

        root.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: docView.topAnchor),
            root.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            root.widthAnchor.constraint(equalToConstant: contentWidth),
        ])
    }

    private func makeToolbar() -> NSView {
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.alignment = .centerY
        toolbar.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        summaryLabel.font = NSFont.systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        resetAllButton.bezelStyle = .rounded
        resetAllButton.controlSize = .small
        resetAllButton.target = self
        resetAllButton.action = #selector(resetAllRules)

        toolbar.addArrangedSubview(summaryLabel)
        toolbar.addArrangedSubview(spacer)
        toolbar.addArrangedSubview(resetAllButton)
        return toolbar
    }

    private func makeGroup(title: String, signals: [String]) -> NSView {
        let groupStack = NSStackView()
        groupStack.orientation = .vertical
        groupStack.spacing = 0
        groupStack.alignment = .leading
        groupStack.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 11)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.frame.size.height = 20
        groupStack.addArrangedSubview(titleLabel)

        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.spacing = 0
        listStack.alignment = .leading
        listStack.wantsLayer = true
        listStack.layer?.cornerRadius = 8
        listStack.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.34).cgColor
        listStack.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        for (index, signal) in signals.enumerated() {
            listStack.addArrangedSubview(makeRuleRow(signal: signal, isAlternating: index.isMultiple(of: 2)))
            if index < signals.count - 1 {
                listStack.addArrangedSubview(makeSeparator())
            }
        }

        groupStack.addArrangedSubview(listStack)
        return groupStack
    }

    private func makeRuleRow(signal: String, isAlternating: Bool) -> NSView {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.backgroundColor = isAlternating ? NSColor.textBackgroundColor.withAlphaComponent(0.20).cgColor : NSColor.clear.cgColor

        let content = NSStackView()
        content.orientation = .horizontal
        content.spacing = 8
        content.alignment = .centerY
        content.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

        let previewView = StatusRulePreviewView(frame: NSRect(x: 0, y: 0, width: 24, height: 42))
        previewView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        previewView.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let textStack = makeSignalTextStack(signal: signal)
        let modePopup = makeModeControl(signal: signal)
        let colorLabel = makeLockedColorLabel(signal: signal)

        let stateLabel = makeMetaLabel(width: 50)
        let appearanceLabel = makeMetaLabel(width: 78)

        let resetButton = NSButton(title: "恢复", target: self, action: #selector(resetRule(_:)))
        resetButton.bezelStyle = .inline
        resetButton.controlSize = .small
        resetButton.identifier = NSUserInterfaceItemIdentifier(signal)
        resetButton.widthAnchor.constraint(equalToConstant: 40).isActive = true

        content.addArrangedSubview(previewView)
        content.addArrangedSubview(textStack)
        content.addArrangedSubview(stateLabel)
        content.addArrangedSubview(appearanceLabel)
        content.addArrangedSubview(colorLabel)
        content.addArrangedSubview(modePopup)
        content.addArrangedSubview(resetButton)

        content.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(content)
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: contentWidth),
            row.heightAnchor.constraint(equalToConstant: 54),
            content.topAnchor.constraint(equalTo: row.topAnchor),
            content.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])

        ruleRows.append(RuleRow(
            signal: signal,
            colorLabel: colorLabel,
            modePopup: modePopup,
            stateLabel: stateLabel,
            appearanceLabel: appearanceLabel,
            previewView: previewView,
            resetButton: resetButton
        ))
        return row
    }

    private func makeSignalTextStack(signal: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.widthAnchor.constraint(equalToConstant: 154).isActive = true

        let title = NSTextField(labelWithString: localizedSignalName(signal))
        title.font = NSFont.boldSystemFont(ofSize: 13)

        let detail = NSTextField(labelWithString: "\(signal) · \(signalSummaries[signal]?.attention ?? "")")
        detail.font = NSFont.systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(detail)
        return stack
    }

    private func makeModeControl(signal: String) -> NSPopUpButton {
        let modePopup = makePopup(width: 98)
        for title in modeTitles(for: signal) {
            modePopup.addItem(withTitle: title)
        }
        modePopup.target = self
        modePopup.action = #selector(ruleChanged(_:))

        let currentRule = rulesConfig.rules[signal]
        let values = modeValues(for: signal)
        modePopup.selectItem(at: values.firstIndex { $0 == currentRule?.mode } ?? 0)
        return modePopup
    }

    private func makeLockedColorLabel(signal: String) -> NSTextField {
        let label = NSTextField(labelWithString: semanticColorName(for: signal))
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = semanticColor(for: signal)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = "颜色由状态优先级锁定，避免高风险状态被误显示为低风险颜色。"
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        return label
    }

    private func makePopup(width: CGFloat) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: width, height: 24), pullsDown: false)
        popup.controlSize = .small
        popup.bezelStyle = .rounded
        popup.widthAnchor.constraint(equalToConstant: width).isActive = true
        return popup
    }

    @objc private func ruleChanged(_ sender: NSPopUpButton) {
        rebuildRulesFromUI()
    }

    @objc private func resetRule(_ sender: NSButton) {
        guard let signal = sender.identifier?.rawValue,
              let row = ruleRows.first(where: { $0.signal == signal }) else {
            return
        }
        row.modePopup.selectItem(at: 0)
        rebuildRulesFromUI()
    }

    @objc private func resetAllRules() {
        guard confirmSettingsAction(
            title: "恢复全部默认灯效？",
            message: "所有自定义动画模式将被清除，颜色语义不会改变。",
            actionTitle: "全部恢复"
        ) else { return }
        for row in ruleRows {
            row.modePopup.selectItem(at: 0)
        }
        rebuildRulesFromUI()
    }

    private func rebuildRulesFromUI() {
        var newRules: [String: SignalRuleConfig] = [:]
        for row in ruleRows {
            let values = modeValues(for: row.signal)
            let mode = values[row.modePopup.indexOfSelectedItem]
            if mode != nil {
                newRules[row.signal] = SignalRuleConfig(color: nil, mode: mode)
            }
        }

        rulesConfig = StatusRulesConfig(rules: newRules.filter { validSignals.contains($0.key) })
        notify()
        refreshRuleRows()
    }

    private func refreshRuleRows() {
        let customCount = rulesConfig.rules.count
        summaryLabel.stringValue = customCount == 0 ? "全部状态使用默认规则" : "已自定义 \(customCount) / \(signalOrder.count) 个状态"
        resetAllButton.isEnabled = customCount > 0

        for row in ruleRows {
            let rule = rulesConfig.rules[row.signal]
            row.stateLabel.stringValue = rule == nil ? "默认" : "自定义"
            row.stateLabel.textColor = rule == nil ? .secondaryLabelColor : .controlAccentColor
            row.resetButton.isEnabled = rule != nil
            row.appearanceLabel.stringValue = appearanceText(signal: row.signal, rule: rule)
            row.previewView.frameState = previewFrame(signal: row.signal, rule: rule)
        }
    }

    private func notify() {
        do {
            try onUpdate(rulesConfig)
        } catch {
            showSettingsError(error)
        }
    }

    private func modeTitles(for signal: String) -> [String] {
        let defaultText = defaultAppearance(signal: signal).mode
        return modeValues(for: signal).map { mode in
            switch mode {
            case nil: return "默认: \(defaultText)"
            case "off": return "关闭"
            case "steady": return "常亮"
            case "flash": return "闪烁"
            case "workPulse": return "工作脉冲"
            case "slowPulse": return "慢呼吸"
            case "doubleFlash": return "双闪"
            default: return mode ?? defaultText
            }
        }
    }

    private func modeValues(for signal: String) -> [String?] {
        let visibleModes: [String?] = [nil, "steady", "flash", "workPulse", "slowPulse", "doubleFlash"]
        return signal == "done" || signal == "off" ? [nil, "off"] + Array(visibleModes.dropFirst()) : visibleModes
    }

    private func appearanceText(signal: String, rule: SignalRuleConfig?) -> String {
        let appearance = effectiveAppearance(signal: signal, rule: rule)
        if appearance.mode == "关闭" {
            return "关闭"
        }
        return "\(appearance.color ?? "无灯") \(appearance.mode)"
    }

    private func previewFrame(signal: String, rule: SignalRuleConfig?) -> SignalFrame {
        guard let state = SignalState(rawValue: signal) else {
            return SignalFrame(green: 0, yellow: 0, red: 0)
        }
        let config = StatusRulesConfig(rules: rule.map { [signal: $0] } ?? [:])
        return frame(for: state, tick: 0, rules: config)
    }

    private func effectiveAppearance(signal: String, rule: SignalRuleConfig?) -> (color: String?, mode: String) {
        guard let state = SignalState(rawValue: signal) else {
            return (nil, "关闭")
        }
        let mode = rule.flatMap { SignalDisplayMode(rule: $0, defaultMode: state.displayMode) } ?? state.displayMode
        return describe(mode)
    }

    private func defaultAppearance(signal: String) -> (color: String?, mode: String) {
        guard let state = SignalState(rawValue: signal) else {
            return (nil, "关闭")
        }
        return describe(state.displayMode)
    }

    private func describe(_ mode: SignalDisplayMode) -> (color: String?, mode: String) {
        switch mode {
        case .off:
            return (nil, "关闭")
        case .steady(let color):
            return (describe(color), "常亮")
        case .flash(let color):
            return (describe(color), "闪烁")
        case .workPulse(let color):
            return (describe(color), "脉冲")
        case .slowPulse(let color):
            return (describe(color), "慢呼吸")
        case .doubleFlash(let color):
            return (describe(color), "双闪")
        }
    }

    private func describe(_ color: SignalColor) -> String {
        switch color {
        case .green:
            return "绿灯"
        case .yellow:
            return "黄灯"
        case .red:
            return "红灯"
        }
    }

    private func makeMetaLabel(width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .left
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return separator
    }

    private func localizedSignalName(_ signal: String) -> String {
        switch signal {
        case "idle":
            return "空闲"
        case "thinking":
            return "思考中"
        case "working":
            return "工作中"
        case "tool_done":
            return "工具完成"
        case "attention":
            return "等待查看"
        case "stale":
            return "状态失联"
        case "permission":
            return "请求授权"
        case "blocked":
            return "已阻塞"
        case "done":
            return "完成"
        case "session_start":
            return "会话开始"
        case "session_end":
            return "会话结束"
        case "off":
            return "关闭"
        default:
            return signal
        }
    }

    private func semanticColorName(for signal: String) -> String {
        switch signal {
        case "attention", "stale":
            return "黄灯锁定"
        case "permission", "blocked":
            return "红灯锁定"
        case "off":
            return "关闭"
        default:
            return "绿灯锁定"
        }
    }

    private func semanticColor(for signal: String) -> NSColor {
        switch signal {
        case "attention", "stale":
            return .systemYellow
        case "permission", "blocked":
            return .systemRed
        case "off":
            return .secondaryLabelColor
        default:
            return .systemGreen
        }
    }
}
