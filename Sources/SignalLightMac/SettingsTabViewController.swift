import AppKit
import SignalLightShared

final class SettingsTabViewController: NSViewController {
    private enum Section: Int, CaseIterable {
        case display
        case agent
        case rules
        case diagnostics

        var title: String {
            switch self {
            case .display: return "显示"
            case .agent: return "Agent"
            case .rules: return "规则"
            case .diagnostics: return "诊断"
            }
        }

        var heading: String {
            switch self {
            case .display: return "悬浮窗与状态栏"
            case .agent: return "Agent 集成"
            case .rules: return "状态灯规则"
            case .diagnostics: return "配置诊断"
            }
        }

        var subtitle: String {
            switch self {
            case .display:
                return "控制悬浮窗、透明度、动画速度、Dock 和 Touch Bar。"
            case .agent:
                return "配置状态目录、会话超时、登录启动和会话清理。"
            case .rules:
                return "为 11 个已知状态指定颜色与闪烁方式。"
            case .diagnostics:
                return "检查配置文件、状态目录和修复写入问题。"
            }
        }
    }

    private let configStore: SignalLightConfigStore
    private var currentConfig: SignalLightConfig
    private let segmentedControl = NSSegmentedControl(
        labels: Section.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let headingLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let contentContainer = NSView()
    private var currentChild: NSViewController?

    init(configStore: SignalLightConfigStore, config: SignalLightConfig) {
        self.configStore = configStore
        self.currentConfig = config
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 680, height: 540)
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
        selectSection(.display)
    }

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 14, right: 18)

        let header = NSStackView()
        header.orientation = .vertical
        header.spacing = 6

        headingLabel.font = NSFont.boldSystemFont(ofSize: 17)
        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2

        segmentedControl.segmentStyle = .rounded
        segmentedControl.selectedSegment = Section.display.rawValue
        segmentedControl.target = self
        segmentedControl.action = #selector(sectionChanged(_:))
        for section in Section.allCases {
            segmentedControl.setWidth(112, forSegment: section.rawValue)
        }

        header.addArrangedSubview(segmentedControl)
        header.addArrangedSubview(headingLabel)
        header.addArrangedSubview(subtitleLabel)
        root.addArrangedSubview(header)
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

    @objc private func sectionChanged(_ sender: NSSegmentedControl) {
        guard let section = Section(rawValue: sender.selectedSegment) else {
            return
        }
        selectSection(section)
    }

    private func selectSection(_ section: Section) {
        segmentedControl.selectedSegment = section.rawValue
        headingLabel.stringValue = section.heading
        subtitleLabel.stringValue = section.subtitle

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
