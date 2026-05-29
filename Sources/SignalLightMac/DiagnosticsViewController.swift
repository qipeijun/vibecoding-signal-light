import AppKit
import SignalLightShared

final class DiagnosticsViewController: NSViewController {
    private let configStore: SignalLightConfigStore
    private weak var statusStack: NSStackView?
    private weak var repairResultField: NSTextField?

    init(configStore: SignalLightConfigStore, config: SignalLightConfig) {
        self.configStore = configStore
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

        let repairBtn = NSButton(title: "修复配置", target: self, action: #selector(repair))
        repairBtn.bezelStyle = .rounded
        repairBtn.controlSize = .small
        buttonStack.addArrangedSubview(repairBtn)

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

        let configPath = configStore.configFileURL().path
        let configDirPath = configStore.configDirectoryURL().path
        let currentConfig = configStore.loadOrRepairConfig()
        let agent = configStore.effectiveAgentConfig(from: currentConfig)
        repairResultField?.stringValue = configStore.lastRepairResult ?? "无"

        let checks: [(String, Bool)] = [
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
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 6
            row.alignment = .centerY

            let indicator = NSTextField(labelWithString: pass ? "●" : "●")
            indicator.textColor = pass ? .systemGreen : .systemRed
            indicator.font = NSFont.systemFont(ofSize: 14)
            row.addArrangedSubview(indicator)

            let labelField = NSTextField(labelWithString: label)
            labelField.font = NSFont.systemFont(ofSize: 11)
            row.addArrangedSubview(labelField)

            statusStack.addArrangedSubview(row)
        }
    }

    @objc private func recheck() {
        runDiagnostics()
    }

    @objc private func repair() {
        do {
            _ = try configStore.repairConfig()
            postConfigChanged()
            runDiagnostics()
        } catch {
            repairResultField?.stringValue = "修复配置失败: \(error.localizedDescription)"
            showSettingsError(error)
        }
    }

    @objc private func openConfigDir() {
        NSWorkspace.shared.open(configStore.configDirectoryURL())
    }

    @objc private func resetAll() {
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
}
