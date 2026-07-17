import AppKit
import SignalLightShared

final class SettingsTabViewController: NSViewController {
    static let statusCenterContentSize = NSSize(width: 680, height: 570)
    private static let settingsContentSize = NSSize(width: 680, height: 540)

    private enum SettingsSection: Int, CaseIterable {
        case display
        case agent
        case rules
        case diagnostics
        case about

        var title: String {
            switch self {
            case .display: return "显示"
            case .agent: return "Codex"
            case .rules: return "规则"
            case .diagnostics: return "诊断"
            case .about: return "关于"
            }
        }

        var heading: String {
            switch self {
            case .display: return "悬浮窗与状态栏"
            case .agent: return "Codex 集成"
            case .rules: return "状态灯规则"
            case .diagnostics: return "配置诊断"
            case .about: return "关于 Signal Light"
            }
        }

        var subtitle: String {
            switch self {
            case .display:
                return "控制悬浮窗、透明度、动画速度、Dock 和 Touch Bar。"
            case .agent:
                return "配置状态目录、分级租约、登录启动和会话清理。"
            case .rules:
                return "12 个状态使用固定颜色语义，可调整动画方式。"
            case .diagnostics:
                return "检查配置文件、状态目录和 Codex Hook。"
            case .about:
                return "版本、项目主页和应用说明。"
            }
        }
    }

    private let configStore: SignalLightConfigStore
    private var currentConfig: SignalLightConfig
    private var stateStore: SignalStateStore
    private let threadCatalog: CodexThreadCatalog
    private let onOpenSession: (String?, SessionSource?) -> Void
    private let titleLabel = NSTextField(labelWithString: "Signal Light")
    private let backButton = NSButton()
    private let settingsButton = NSButton()
    private let segmentedControl = NSSegmentedControl(
        labels: SettingsSection.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let headingLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let contentContainer = NSView()
    private var currentChild: NSViewController?
    private var currentFrameState = SignalFrame(green: 1, yellow: 0, red: 0)

    init(
        configStore: SignalLightConfigStore,
        config: SignalLightConfig,
        stateStore: SignalStateStore,
        threadCatalog: CodexThreadCatalog = CodexThreadCatalog(),
        onOpenSession: @escaping (String?, SessionSource?) -> Void = { _, _ in }
    ) {
        self.configStore = configStore
        self.currentConfig = config
        self.stateStore = stateStore
        self.threadCatalog = threadCatalog
        self.onOpenSession = onOpenSession
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.statusCenterContentSize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        showStatusCenter()
    }

    func refreshRuntimeStatus(config: SignalLightConfig, stateStore: SignalStateStore, frameState: SignalFrame) {
        currentConfig = config
        self.stateStore = stateStore
        currentFrameState = frameState
        (currentChild as? StatusInfoViewController)?.update(
            config: config,
            stateStore: stateStore,
            frameState: frameState
        )
    }

    /// 高频动画刷新只更新灯泡帧，避免重复计算会话、历史和状态文案。
    func updateAnimationFrame(_ frameState: SignalFrame) {
        currentFrameState = frameState
        (currentChild as? StatusInfoViewController)?.updateAnimationFrame(frameState)
    }

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 10
        topRow.alignment = .centerY

        configureIconButton(
            backButton,
            symbolName: "chevron.left",
            toolTip: "返回状态中心",
            action: #selector(showStatusCenterAction)
        )
        backButton.isHidden = true

        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        segmentedControl.segmentStyle = .rounded
        segmentedControl.selectedSegment = SettingsSection.display.rawValue
        segmentedControl.target = self
        segmentedControl.action = #selector(sectionChanged(_:))
        segmentedControl.isHidden = true
        for section in SettingsSection.allCases {
            segmentedControl.setWidth(84, forSegment: section.rawValue)
        }

        configureIconButton(
            settingsButton,
            symbolName: "gearshape",
            toolTip: "打开设置",
            action: #selector(showSettingsAction)
        )

        topRow.addArrangedSubview(backButton)
        topRow.addArrangedSubview(titleLabel)
        topRow.addArrangedSubview(NSView())
        topRow.addArrangedSubview(segmentedControl)
        topRow.addArrangedSubview(settingsButton)
        root.addArrangedSubview(topRow)

        headingLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        headingLabel.isHidden = true
        root.addArrangedSubview(headingLabel)

        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.isHidden = true
        root.addArrangedSubview(subtitleLabel)
        root.addArrangedSubview(makeSeparator())

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(contentContainer)

        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 390),
        ])
    }

    private func configureIconButton(
        _ button: NSButton,
        symbolName: String,
        toolTip: String,
        action: Selector
    ) {
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.toolTip = toolTip
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.setAccessibilityLabel(toolTip)
    }

    @objc private func showStatusCenterAction() {
        showStatusCenter()
    }

    @objc private func showSettingsAction() {
        showSettings(.display)
    }

    @objc private func sectionChanged(_ sender: NSSegmentedControl) {
        guard let section = SettingsSection(rawValue: sender.selectedSegment) else {
            return
        }
        showSettings(section)
    }

    private func showStatusCenter() {
        preferredContentSize = Self.statusCenterContentSize
        backButton.isHidden = true
        settingsButton.isHidden = false
        segmentedControl.isHidden = true
        headingLabel.isHidden = true
        subtitleLabel.isHidden = true

        let statusController = StatusInfoViewController(
            configStore: configStore,
            config: currentConfig,
            stateStore: stateStore,
            threadCatalog: threadCatalog,
            onOpenDiagnostics: { [weak self] in self?.showSettings(.diagnostics) },
            onOpenSession: onOpenSession
        )
        replaceContent(with: statusController)
        statusController.update(config: currentConfig, stateStore: stateStore, frameState: currentFrameState)
    }

    private func showSettings(_ section: SettingsSection) {
        preferredContentSize = Self.settingsContentSize
        backButton.isHidden = false
        settingsButton.isHidden = true
        segmentedControl.isHidden = false
        segmentedControl.selectedSegment = section.rawValue
        headingLabel.stringValue = section.heading
        subtitleLabel.stringValue = section.subtitle
        headingLabel.isHidden = false
        subtitleLabel.isHidden = false

        let child: NSViewController
        switch section {
        case .display:
            child = DisplaySettingsViewController(
                config: currentConfig.display,
                onUpdate: { [weak self] updated in
                    guard let self else { return }
                    currentConfig.display = updated
                    try saveAndNotify()
                }
            )
        case .agent:
            child = AgentSettingsViewController(
                config: currentConfig.agent,
                onUpdate: { [weak self] updated in
                    guard let self else { return }
                    currentConfig.agent = updated
                    try saveAndNotify()
                }
            )
        case .rules:
            child = StatusRulesSettingsViewController(
                config: currentConfig.statusRules,
                onUpdate: { [weak self] updated in
                    guard let self else { return }
                    currentConfig.statusRules = updated
                    try saveAndNotify()
                }
            )
        case .diagnostics:
            child = DiagnosticsViewController(
                configStore: configStore,
                config: currentConfig
            )
        case .about:
            child = AboutViewController()
        }

        replaceContent(with: child)
    }

    private func replaceContent(with child: NSViewController) {
        currentChild?.view.removeFromSuperview()
        currentChild?.removeFromParent()

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        currentChild = child
    }

    private func saveAndNotify() throws {
        try configStore.saveConfig(currentConfig)
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
