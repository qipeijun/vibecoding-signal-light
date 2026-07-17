import AppKit
import ServiceManagement
import SignalLightShared

final class AgentSettingsViewController: NSViewController {
    private let onUpdate: (AgentConfig) throws -> Void
    private var agentConfig: AgentConfig
    private var directoryField: NSTextField!
    private weak var settingsDocumentView: NSView?
    private let advancedLeaseStack = NSStackView()
    private var workingLeaseField: NSTextField!
    private var attentionLeaseField: NSTextField!
    private var criticalLeaseField: NSTextField!
    private var doneDisplayField: NSTextField!

    init(config: AgentConfig, onUpdate: @escaping (AgentConfig) throws -> Void) {
        self.agentConfig = config
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

        let documentView = AgentSettingsDocumentView(frame: NSRect(x: 0, y: 0, width: 636, height: 390))
        scrollView.documentView = documentView
        settingsDocumentView = documentView
        view = scrollView
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

        stack.addArrangedSubview(makeSectionTitle("状态文件"))

        let dirLabel = NSTextField(labelWithString: "状态文件目录:")
        stack.addArrangedSubview(dirLabel)

        let dirRow = NSStackView()
        dirRow.orientation = .horizontal
        dirRow.spacing = 8

        directoryField = NSTextField(string: agentConfig.stateDirectory)
        directoryField.isEditable = false
        directoryField.isSelectable = true
        directoryField.controlSize = .small
        directoryField.frame.size.width = 380
        dirRow.addArrangedSubview(directoryField)

        let chooseButton = NSButton(title: "选择...", target: self, action: #selector(chooseDirectory))
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .small
        dirRow.addArrangedSubview(chooseButton)

        stack.addArrangedSubview(dirRow)

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeSectionTitle("会话"))

        let ttlLabel = NSTextField(labelWithString: "会话超时 (秒):")
        stack.addArrangedSubview(ttlLabel)

        let ttlField = NSTextField(string: String(Int(agentConfig.sessionTTLSeconds)))
        ttlField.controlSize = .small
        ttlField.frame.size = NSMakeSize(120, 22)
        ttlField.formatter = {
            let f = NumberFormatter()
            f.minimum = 60
            f.maximum = 604800
            f.allowsFloats = false
            return f
        }()

        let ttlRow = NSStackView()
        ttlRow.orientation = .horizontal
        ttlRow.spacing = 8
        ttlRow.addArrangedSubview(ttlField)
        let ttlHint = NSTextField(labelWithString: "(60 - 604800，默认 86400)")
        ttlHint.font = NSFont.systemFont(ofSize: 11)
        ttlHint.textColor = .secondaryLabelColor
        ttlRow.addArrangedSubview(ttlHint)
        stack.addArrangedSubview(ttlRow)

        ttlField.target = self
        ttlField.action = #selector(ttlChanged(_:))

        let advancedButton = NSButton(title: "高级状态租约", target: self, action: #selector(toggleAdvancedLeases(_:)))
        advancedButton.bezelStyle = .disclosure
        advancedButton.setButtonType(.pushOnPushOff)
        advancedButton.controlSize = .small
        stack.addArrangedSubview(advancedButton)

        configureAdvancedLeaseStack()
        advancedLeaseStack.isHidden = true
        stack.addArrangedSubview(advancedLeaseStack)

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeSectionTitle("启动"))

        let launchCheck = NSButton(checkboxWithTitle: "登录时启动", target: self, action: #selector(launchAtLoginChanged(_:)))
        if #available(macOS 13.0, *) {
            launchCheck.state = agentConfig.launchAtLogin ? .on : .off
        } else {
            agentConfig.launchAtLogin = false
            launchCheck.state = .off
            launchCheck.isEnabled = false
        }
        stack.addArrangedSubview(launchCheck)
        if #available(macOS 13.0, *) {
        } else {
            let launchHint = NSTextField(labelWithString: "当前 macOS 版本不支持自动设置登录启动")
            launchHint.font = NSFont.systemFont(ofSize: 11)
            launchHint.textColor = .secondaryLabelColor
            stack.addArrangedSubview(launchHint)
        }

        stack.addArrangedSubview(makeSeparator())

        let actionsTitle = makeSectionTitle("操作")
        stack.addArrangedSubview(actionsTitle)

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.spacing = 10
        actionRow.alignment = .centerY

        let clearButton = NSButton(title: "清除所有会话", target: self, action: #selector(clearSessions))
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        actionRow.addArrangedSubview(clearButton)

        let clearHistoryButton = NSButton(title: "清空状态历史", target: self, action: #selector(clearHistory))
        clearHistoryButton.bezelStyle = .rounded
        clearHistoryButton.controlSize = .small
        actionRow.addArrangedSubview(clearHistoryButton)

        let resetButton = NSButton(title: "恢复默认 Codex 设置", target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        actionRow.addArrangedSubview(resetButton)
        stack.addArrangedSubview(actionRow)

        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let documentView = settingsDocumentView else {
            return
        }
        documentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.widthAnchor.constraint(equalToConstant: 512),
        ])
    }

    private func configureAdvancedLeaseStack() {
        advancedLeaseStack.orientation = .vertical
        advancedLeaseStack.spacing = 6
        advancedLeaseStack.alignment = .leading

        let hint = NSTextField(labelWithString: "超过租约仍无 Hook 更新时，状态会转为黄色失联。")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        advancedLeaseStack.addArrangedSubview(hint)

        workingLeaseField = makeLeaseField(value: agentConfig.workingLeaseSeconds, identifier: "working")
        attentionLeaseField = makeLeaseField(value: agentConfig.attentionLeaseSeconds, identifier: "attention")
        criticalLeaseField = makeLeaseField(value: agentConfig.criticalLeaseSeconds, identifier: "critical")
        doneDisplayField = makeLeaseField(value: agentConfig.doneDisplaySeconds, identifier: "done", minimum: 1, maximum: 30)

        advancedLeaseStack.addArrangedSubview(makeLeaseRow(
            leftTitle: "工作状态",
            leftField: workingLeaseField,
            rightTitle: "等待关注",
            rightField: attentionLeaseField
        ))
        advancedLeaseStack.addArrangedSubview(makeLeaseRow(
            leftTitle: "授权/阻塞",
            leftField: criticalLeaseField,
            rightTitle: "完成反馈",
            rightField: doneDisplayField
        ))
    }

    private func makeLeaseField(
        value: Double,
        identifier: String,
        minimum: Int = 60,
        maximum: Int = 604800
    ) -> NSTextField {
        let field = NSTextField(string: String(Int(value)))
        field.controlSize = .small
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.target = self
        field.action = #selector(leaseChanged(_:))
        field.widthAnchor.constraint(equalToConstant: 76).isActive = true

        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: minimum)
        formatter.maximum = NSNumber(value: maximum)
        formatter.allowsFloats = false
        field.formatter = formatter
        return field
    }

    private func makeLeaseRow(
        leftTitle: String,
        leftField: NSTextField,
        rightTitle: String,
        rightField: NSTextField
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let leftLabel = NSTextField(labelWithString: "\(leftTitle) (秒)")
        leftLabel.widthAnchor.constraint(equalToConstant: 92).isActive = true
        let rightLabel = NSTextField(labelWithString: "\(rightTitle) (秒)")
        rightLabel.widthAnchor.constraint(equalToConstant: 92).isActive = true

        row.addArrangedSubview(leftLabel)
        row.addArrangedSubview(leftField)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(rightLabel)
        row.addArrangedSubview(rightField)
        row.widthAnchor.constraint(equalToConstant: 500).isActive = true
        return row
    }

    @objc private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择状态目录"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.directoryField.stringValue = url.path
            self?.agentConfig.stateDirectory = url.path
            self?.notify()
        }
    }

    @objc private func ttlChanged(_ sender: NSTextField) {
        if let value = Double(sender.stringValue) {
            agentConfig.sessionTTLSeconds = value
            notify()
        }
    }

    @objc private func toggleAdvancedLeases(_ sender: NSButton) {
        let isExpanded = sender.state == .on
        advancedLeaseStack.isHidden = !isExpanded
        settingsDocumentView?.frame.size.height = isExpanded ? 500 : 390
    }

    @objc private func leaseChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue), let identifier = sender.identifier?.rawValue else {
            return
        }
        switch identifier {
        case "working":
            agentConfig.workingLeaseSeconds = value
        case "attention":
            agentConfig.attentionLeaseSeconds = value
        case "critical":
            agentConfig.criticalLeaseSeconds = value
        case "done":
            agentConfig.doneDisplaySeconds = value
        default:
            return
        }
        notify()
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        guard #available(macOS 13.0, *) else {
            sender.state = .off
            return
        }

        let enabled = sender.state == .on
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            sender.state = agentConfig.launchAtLogin ? .on : .off
            showSettingsError(error)
            return
        }

        agentConfig.launchAtLogin = sender.state == .on
        notify()
    }

    @objc private func clearSessions() {
        guard confirmSettingsAction(
            title: "清除所有会话？",
            message: "当前会话状态会立即清空，主灯回到空闲。状态历史不会被删除。",
            actionTitle: "清除会话"
        ) else { return }
        // 通过分布式通知请求 AppDelegate 清空会话
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.vibecoding.signal-light.clear-sessions"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    @objc private func clearHistory() {
        guard confirmSettingsAction(
            title: "清空状态历史？",
            message: "最近 24 小时的状态流记录会被删除，当前会话状态不受影响。",
            actionTitle: "清空历史"
        ) else { return }
        let stateDirectory = URL(fileURLWithPath: agentConfig.stateDirectory)
        do {
            try SignalLightStateFiles.clearHistory(in: stateDirectory)
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.vibecoding.signal-light.status-changed"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        } catch {
            showSettingsError(error)
        }
    }

    @objc private func resetToDefaults() {
        guard confirmSettingsAction(
            title: "恢复默认 Codex 设置？",
            message: "状态目录、会话租约和登录启动设置将恢复默认值。",
            actionTitle: "恢复默认"
        ) else { return }
        agentConfig = AgentConfig.default
        directoryField.stringValue = agentConfig.stateDirectory
        workingLeaseField.stringValue = String(Int(agentConfig.workingLeaseSeconds))
        attentionLeaseField.stringValue = String(Int(agentConfig.attentionLeaseSeconds))
        criticalLeaseField.stringValue = String(Int(agentConfig.criticalLeaseSeconds))
        doneDisplayField.stringValue = String(Int(agentConfig.doneDisplaySeconds))
        notify()
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

    private func notify() {
        do {
            try onUpdate(agentConfig)
        } catch {
            showSettingsError(error)
        }
    }
}

private final class AgentSettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
