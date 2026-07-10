import AppKit
import ServiceManagement
import SignalLightShared

final class AgentSettingsViewController: NSViewController {
    private let onUpdate: (AgentConfig) throws -> Void
    private var agentConfig: AgentConfig
    private var directoryField: NSTextField!
    private var sourcePopup: NSPopUpButton!

    init(config: AgentConfig, onUpdate: @escaping (AgentConfig) throws -> Void) {
        self.agentConfig = config
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

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeSectionTitle("状态来源"))

        let sourceLabel = NSTextField(labelWithString: "优先展示:")
        stack.addArrangedSubview(sourceLabel)

        sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        sourcePopup.controlSize = .small
        for source in PreferredAgentSource.allCases {
            sourcePopup.addItem(withTitle: source.displayName)
        }
        if let index = PreferredAgentSource.allCases.firstIndex(of: agentConfig.preferredAgentSource) {
            sourcePopup.selectItem(at: index)
        }
        sourcePopup.target = self
        sourcePopup.action = #selector(preferredSourceChanged(_:))
        stack.addArrangedSubview(sourcePopup)

        let sourceHint = NSTextField(
            labelWithString: "多个 Agent 同时运行时，只展示所选来源的会话状态。OpenCode 使用独立筛选项，不再与 iTerm 等终端混在一起。"
        )
        sourceHint.font = NSFont.systemFont(ofSize: 11)
        sourceHint.textColor = .secondaryLabelColor
        sourceHint.lineBreakMode = .byWordWrapping
        sourceHint.preferredMaxLayoutWidth = 500
        stack.addArrangedSubview(sourceHint)

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

        let resetButton = NSButton(title: "恢复默认 Agent 设置", target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        actionRow.addArrangedSubview(resetButton)
        stack.addArrangedSubview(actionRow)

        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: 512),
        ])
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

    @objc private func preferredSourceChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < PreferredAgentSource.allCases.count else {
            return
        }
        agentConfig.preferredAgentSource = PreferredAgentSource.allCases[index]
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
        // 通过分布式通知请求 AppDelegate 清空会话
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.vibecoding.signal-light.clear-sessions"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    @objc private func resetToDefaults() {
        agentConfig = AgentConfig.default
        directoryField.stringValue = agentConfig.stateDirectory
        if let index = PreferredAgentSource.allCases.firstIndex(of: agentConfig.preferredAgentSource) {
            sourcePopup.selectItem(at: index)
        }
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
