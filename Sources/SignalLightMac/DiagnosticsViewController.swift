import AppKit
import SignalLightShared

final class DiagnosticsViewController: NSViewController {
    private enum IndicatorState {
        case pass
        case pending
        case fail

        var color: NSColor {
            switch self {
            case .pass: return .systemGreen
            case .pending: return .systemYellow
            case .fail: return .systemRed
            }
        }
    }

    private let configStore: SignalLightConfigStore
    private weak var statusStack: NSStackView?
    private weak var hookStatusStack: NSStackView?
    private weak var repairResultField: NSTextField?
    private weak var hookRepairResultField: NSTextField?
    private weak var repairHooksButton: NSButton?
    private var hookCheckGeneration = 0

    init(configStore: SignalLightConfigStore, config: SignalLightConfig) {
        self.configStore = configStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 430))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 8, right: 4)
        stack.alignment = .leading

        let pathLabel = NSTextField(labelWithString: "配置路径:")
        stack.addArrangedSubview(pathLabel)

        let pathField = NSTextField(string: configStore.configFileURL().path)
        pathField.isEditable = false
        pathField.isSelectable = true
        pathField.controlSize = .small
        pathField.frame.size.width = 500
        stack.addArrangedSubview(pathField)

        stack.addArrangedSubview(makeSeparator())

        let checkLabel = NSTextField(labelWithString: "状态检查:")
        checkLabel.font = NSFont.boldSystemFont(ofSize: 12)
        stack.addArrangedSubview(checkLabel)

        let statusStack = NSStackView()
        statusStack.orientation = .vertical
        statusStack.spacing = 4
        statusStack.alignment = .leading
        self.statusStack = statusStack
        stack.addArrangedSubview(statusStack)

        stack.addArrangedSubview(makeSeparator())

        let hookLabel = NSTextField(labelWithString: "Codex Hook:")
        hookLabel.font = NSFont.boldSystemFont(ofSize: 12)
        stack.addArrangedSubview(hookLabel)

        let hookStatusStack = NSStackView()
        hookStatusStack.orientation = .vertical
        hookStatusStack.spacing = 4
        hookStatusStack.alignment = .leading
        self.hookStatusStack = hookStatusStack
        stack.addArrangedSubview(hookStatusStack)

        let installResultURL = configStore.configDirectoryURL().appendingPathComponent("hook-install-result.txt")
        let installResult = (try? String(contentsOf: installResultURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hookRepairResultField = NSTextField(labelWithString: installResult.flatMap { $0.isEmpty ? nil : $0 } ?? "无")
        hookRepairResultField.lineBreakMode = .byTruncatingMiddle
        hookRepairResultField.preferredMaxLayoutWidth = 500
        hookRepairResultField.font = NSFont.systemFont(ofSize: 11)
        hookRepairResultField.textColor = .secondaryLabelColor
        self.hookRepairResultField = hookRepairResultField
        stack.addArrangedSubview(hookRepairResultField)

        stack.addArrangedSubview(makeSeparator())

        let repairLabel = NSTextField(labelWithString: "修复记录:")
        repairLabel.font = NSFont.boldSystemFont(ofSize: 12)
        stack.addArrangedSubview(repairLabel)

        let repairResultField = NSTextField(labelWithString: configStore.lastRepairResult ?? "无")
        repairResultField.lineBreakMode = .byWordWrapping
        repairResultField.preferredMaxLayoutWidth = 500
        self.repairResultField = repairResultField
        stack.addArrangedSubview(repairResultField)

        stack.addArrangedSubview(makeSeparator())

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 10
        buttonStack.alignment = .centerY

        let recheckBtn = NSButton(title: "重新检查", target: self, action: #selector(recheck))
        recheckBtn.bezelStyle = .rounded
        recheckBtn.controlSize = .small
        buttonStack.addArrangedSubview(recheckBtn)

        let repairBtn = NSButton(title: "重建默认配置", target: self, action: #selector(repair))
        repairBtn.bezelStyle = .rounded
        repairBtn.controlSize = .small
        buttonStack.addArrangedSubview(repairBtn)

        let repairHooksBtn = NSButton(title: "修复 Codex Hook", target: self, action: #selector(repairHooks))
        repairHooksBtn.bezelStyle = .rounded
        repairHooksBtn.controlSize = .small
        self.repairHooksButton = repairHooksBtn
        buttonStack.addArrangedSubview(repairHooksBtn)

        let openDirBtn = NSButton(title: "打开配置目录", target: self, action: #selector(openConfigDir))
        openDirBtn.bezelStyle = .rounded
        openDirBtn.controlSize = .small
        buttonStack.addArrangedSubview(openDirBtn)

        let resetAllBtn = NSButton(title: "恢复默认设置", target: self, action: #selector(resetAll))
        resetAllBtn.bezelStyle = .rounded
        resetAllBtn.controlSize = .small
        buttonStack.addArrangedSubview(resetAllBtn)

        stack.addArrangedSubview(buttonStack)

        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: 512),
        ])

        runDiagnostics()
    }

    private func runDiagnostics() {
        guard let statusStack else { return }
        // 清除旧结果
        statusStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        hookStatusStack?.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let configPath = configStore.configFileURL().path
        let configDirPath = configStore.configDirectoryURL().path
        let currentConfig = configStore.loadOrRepairConfig()
        let agent = configStore.effectiveAgentConfig(from: currentConfig)
        repairResultField?.stringValue = configStore.lastRepairResult ?? "无"

        let checks: [(String, Bool)] = [
            ("应用版本 \(SignalLightVersion.displayString)", true),
            ("配置文件存在", FileManager.default.fileExists(atPath: configPath)),
            ("配置文件可读", (try? Data(contentsOf: configStore.configFileURL())) != nil),
            ("配置目录可写", FileManager.default.isWritableFile(atPath: configDirPath)),
            ("状态目录 (\(agent.stateDirectory)) 可写", {
                let dir = URL(fileURLWithPath: agent.stateDirectory)
                // 检查目录是否存在且可写，如果不存在则检查父目录是否可写
                if FileManager.default.fileExists(atPath: dir.path) {
                    return FileManager.default.isWritableFile(atPath: dir.path)
                }
                return FileManager.default.isWritableFile(atPath: dir.deletingLastPathComponent().path)
            }()),
        ]

        for (label, pass) in checks {
            statusStack.addArrangedSubview(makeStatusRow(label: label, pass: pass))
        }

        runHookDiagnostics()
    }

    @objc private func recheck() {
        runDiagnostics()
    }

    @objc private func repair() {
        guard confirmSettingsAction(
            title: "重建默认配置？",
            message: "当前显示、Codex 和状态规则设置将被默认配置替换。Codex Hook 不受影响。",
            actionTitle: "重建配置"
        ) else { return }
        do {
            _ = try configStore.repairConfig()
            postConfigChanged()
            runDiagnostics()
        } catch {
            repairResultField?.stringValue = "修复配置失败: \(error.localizedDescription)"
            showSettingsError(error)
        }
    }

    @objc private func repairHooks() {
        let reports = checkSignalLightHooks()
        guard reports.contains(where: { !$0.ok }) else {
            hookRepairResultField?.stringValue = "Codex Hook 已连接，无需修复。"
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "修复 Codex Hook？"
        alert.informativeText = "将更新 ~/.codex/hooks.json 中的 Signal Light 事件，不会删除其他 Hook。"
        alert.addButton(withTitle: "修复")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        repairHooksButton?.isEnabled = false
        hookRepairResultField?.stringValue = "正在修复 Codex Hook..."

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try installSignalLightHooks() }
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.repairHooksButton?.isEnabled = true
                switch result {
                case .success(let reports):
                    self.hookRepairResultField?.stringValue = reports
                        .map { "\($0.title): \($0.message)" }
                        .joined(separator: "；")
                    DistributedNotificationCenter.default().postNotificationName(
                        NSNotification.Name("com.vibecoding.signal-light.hooks-changed"),
                        object: nil,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                    self.runDiagnostics()
                case .failure(let error):
                    self.hookRepairResultField?.stringValue = "修复 Codex Hook 失败: \(error.localizedDescription)"
                    self.showSettingsError(error)
                }
            }
        }
    }

    @objc private func openConfigDir() {
        NSWorkspace.shared.open(configStore.configDirectoryURL())
    }

    @objc private func resetAll() {
        guard confirmSettingsAction(
            title: "恢复全部默认设置？",
            message: "当前显示、Codex 和状态规则设置将恢复默认值。Codex Hook 不受影响。",
            actionTitle: "恢复默认"
        ) else { return }
        let defaultConfig = SignalLightConfig.default
        do {
            try configStore.saveConfig(defaultConfig)
        } catch {
            repairResultField?.stringValue = "恢复默认设置失败: \(error.localizedDescription)"
            showSettingsError(error)
            return
        }
        postConfigChanged()
        runDiagnostics()
    }

    private func postConfigChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.vibecoding.signal-light.config-changed"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func makeStatusRow(label: String, pass: Bool) -> NSView {
        makeStatusRow(label: label, state: pass ? .pass : .fail)
    }

    private func makeStatusRow(label: String, state: IndicatorState) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY

        let indicator = NSTextField(labelWithString: "●")
        indicator.textColor = state.color
        indicator.font = NSFont.systemFont(ofSize: 14)
        row.addArrangedSubview(indicator)

        let labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.systemFont(ofSize: 11)
        labelField.lineBreakMode = .byTruncatingMiddle
        labelField.widthAnchor.constraint(equalToConstant: 480).isActive = true
        row.addArrangedSubview(labelField)

        return row
    }

    private func runHookDiagnostics() {
        guard let hookStatusStack else {
            return
        }
        hookCheckGeneration += 1
        let generation = hookCheckGeneration
        hookStatusStack.addArrangedSubview(makeStatusRow(label: "Codex Hook 检查中...", state: .pending))

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let config = self.configStore.loadOrRepairConfig()
            let agent = self.configStore.effectiveAgentConfig(from: config)
            let connection = inspectCodexHookConnection(
                stateDirectory: URL(fileURLWithPath: agent.stateDirectory)
            )
            DispatchQueue.main.async {
                guard generation == self.hookCheckGeneration,
                      let hookStatusStack = self.hookStatusStack
                else {
                    return
                }
                hookStatusStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
                switch connection {
                case .missingConfiguration(let message):
                    hookStatusStack.addArrangedSubview(
                        self.makeStatusRow(label: "Codex Hook 未连接：\(message)", state: .fail)
                    )
                case .awaitingFirstEvent:
                    hookStatusStack.addArrangedSubview(
                        self.makeStatusRow(
                            label: "已配置，等待首次事件；请在 Codex /hooks 确认信任",
                            state: .pending
                        )
                    )
                case .active(let lastEventAt):
                    let time = DateFormatter.localizedString(
                        from: Date(timeIntervalSince1970: lastEventAt),
                        dateStyle: .none,
                        timeStyle: .medium
                    )
                    hookStatusStack.addArrangedSubview(
                        self.makeStatusRow(label: "已连接，最近事件 \(time)", state: .pass)
                    )
                }
            }
        }
    }
}
