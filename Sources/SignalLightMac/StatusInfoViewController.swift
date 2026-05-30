import AppKit
import SignalLightShared

final class StatusInfoViewController: NSViewController {
    private let configStore: SignalLightConfigStore
    private var stateStore: SignalStateStore
    private var config: SignalLightConfig

    private let stateValue = NSTextField(labelWithString: "")
    private let sourceValue = NSTextField(labelWithString: "")
    private let modelValue = NSTextField(labelWithString: "")
    private let updatedValue = NSTextField(labelWithString: "")
    private let directoryValue = NSTextField(labelWithString: "")

    init(configStore: SignalLightConfigStore, config: SignalLightConfig, stateStore: SignalStateStore) {
        self.configStore = configStore
        self.config = config
        self.stateStore = stateStore
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
        update(config: config, stateStore: stateStore)
    }

    func update(config: SignalLightConfig, stateStore: SignalStateStore) {
        self.config = config
        self.stateStore = stateStore

        let record = preferredRecord()
        stateValue.stringValue = stateStore.state.displayName
        sourceValue.stringValue = sourceName(from: record) ?? "当前状态未提供来源"
        modelValue.stringValue = cleanText(record?.model) ?? "当前状态未提供模型"
        updatedValue.stringValue = formattedTimestamp(stateStore.updatedAt ?? record?.updatedAt)
        directoryValue.stringValue = stateStore.stateDirectoryURL.path
    }

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 8, right: 4)
        stack.alignment = .leading

        stack.addArrangedSubview(makeSectionTitle("状态详情"))
        stack.addArrangedSubview(makeRow(title: "状态", value: stateValue, emphasize: true))
        stack.addArrangedSubview(makeRow(title: "来源程序", value: sourceValue))
        stack.addArrangedSubview(makeRow(title: "模型", value: modelValue))
        stack.addArrangedSubview(makeRow(title: "最后更新", value: updatedValue))

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeSectionTitle("状态数据"))
        stack.addArrangedSubview(makeRow(title: "状态目录", value: directoryValue, selectable: true))

        let hint = NSTextField(labelWithString: "状态由本机 Agent hook 写入，菜单栏和悬浮灯会实时读取这里的数据。")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = 500
        stack.addArrangedSubview(hint)

        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: 512),
        ])
    }

    private func preferredRecord() -> SessionRecord? {
        let agent = configStore.effectiveAgentConfig(from: config)
        let now = Date().timeIntervalSince1970
        return stateStore.sessionState.sessions.values.filter { record in
            !sessionEndSignals.contains(record.signal)
                && now - record.updatedAt <= agent.sessionTTLSeconds
        }.max(by: { $0.updatedAt < $1.updatedAt })
    }

    private func sourceName(from record: SessionRecord?) -> String? {
        guard let source = record?.source else {
            return nil
        }
        return cleanText(source.localizedName) ?? cleanText(source.bundleIdentifier)
    }

    private func formattedTimestamp(_ value: Double?) -> String {
        guard let value else {
            return "暂无更新时间"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: Date(timeIntervalSince1970: value))
    }

    private func makeRow(
        title: String,
        value: NSTextField,
        emphasize: Bool = false,
        selectable: Bool = false
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .firstBaseline

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 12)
        titleField.textColor = .secondaryLabelColor
        titleField.alignment = .right
        titleField.widthAnchor.constraint(equalToConstant: 74).isActive = true

        value.font = emphasize ? NSFont.boldSystemFont(ofSize: 18) : NSFont.systemFont(ofSize: 13)
        value.textColor = emphasize ? .labelColor : .controlTextColor
        value.lineBreakMode = .byTruncatingMiddle
        value.isSelectable = selectable
        value.widthAnchor.constraint(equalToConstant: 410).isActive = true

        row.addArrangedSubview(titleField)
        row.addArrangedSubview(value)
        return row
    }

    private func makeSectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}

private func cleanText(_ value: String?) -> String? {
    guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
        return nil
    }
    return text
}
