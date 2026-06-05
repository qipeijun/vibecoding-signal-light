import AppKit
import SignalLightShared

final class StatusInfoViewController: NSViewController {
    private let configStore: SignalLightConfigStore
    private let quotaReader = CodexRateLimitReader()
    private var stateStore: SignalStateStore
    private var config: SignalLightConfig
    private var quotaState: CodexQuotaState = .loading

    private let stateValue = NSTextField(labelWithString: "")
    private let sourceValue = NSTextField(labelWithString: "")
    private let modelValue = NSTextField(labelWithString: "")
    private let updatedValue = NSTextField(labelWithString: "")
    private let directoryValue = NSTextField(labelWithString: "")
    private let quotaStatusValue = NSTextField(labelWithString: "")
    private let quotaPrimaryRow = QuotaWindowRowView(title: "5 小时")
    private let quotaSecondaryRow = QuotaWindowRowView(title: "7 天")

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
        refreshQuota()
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

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeQuotaHeader())
        stack.addArrangedSubview(makeRow(title: "状态", value: quotaStatusValue))
        stack.addArrangedSubview(quotaPrimaryRow)
        stack.addArrangedSubview(quotaSecondaryRow)
        applyQuotaState(.loading)

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

    private func formattedResetTime(_ value: Int64?) -> String {
        guard let value else {
            return "暂无重置时间"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "重置 \(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(value))))"
    }

    @objc private func refreshQuota() {
        applyQuotaState(.loading)
        quotaReader.fetch { [weak self] state in
            DispatchQueue.main.async {
                self?.applyQuotaState(state)
            }
        }
    }

    private func applyQuotaState(_ state: CodexQuotaState) {
        quotaState = state
        switch state {
        case .loading:
            quotaStatusValue.stringValue = "正在读取 Codex 额度..."
            quotaPrimaryRow.isHidden = true
            quotaSecondaryRow.isHidden = true
        case .unavailable(let reason):
            quotaStatusValue.stringValue = reason
            quotaPrimaryRow.isHidden = true
            quotaSecondaryRow.isHidden = true
        case .loaded(let snapshot):
            quotaStatusValue.stringValue = quotaStatus(from: snapshot)
            quotaPrimaryRow.isHidden = false
            quotaSecondaryRow.isHidden = false
            quotaPrimaryRow.update(
                window: snapshot.primary,
                defaultTitle: "5 小时",
                resetText: formattedResetTime(snapshot.primary.resetsAt)
            )
            quotaSecondaryRow.update(
                window: snapshot.secondary,
                defaultTitle: "7 天",
                resetText: formattedResetTime(snapshot.secondary.resetsAt)
            )
        }
    }

    private func quotaStatus(from snapshot: CodexRateLimitSnapshot) -> String {
        var parts: [String] = []
        if let limitName = cleanText(snapshot.limitName) {
            parts.append(limitName)
        } else if let limitId = cleanText(snapshot.limitId) {
            parts.append(limitId)
        } else {
            parts.append("Codex")
        }
        if let planType = cleanText(snapshot.planType) {
            parts.append(planType)
        }
        if let reachedType = cleanText(snapshot.rateLimitReachedType) {
            parts.append(reachedType)
        }
        if let credits = snapshot.credits, credits.hasCredits {
            if credits.unlimited {
                parts.append("credits unlimited")
            } else if let balance = cleanText(credits.balance) {
                parts.append("credits \(balance)")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func makeQuotaHeader() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let title = makeSectionTitle("Codex 额度")
        row.addArrangedSubview(title)
        row.addArrangedSubview(NSView())

        let button = NSButton(title: "刷新", target: self, action: #selector(refreshQuota))
        button.bezelStyle = .rounded
        button.controlSize = .small
        row.addArrangedSubview(button)
        row.widthAnchor.constraint(equalToConstant: 512).isActive = true
        return row
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

private final class QuotaWindowRowView: NSStackView {
    private let titleValue = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let percentValue = NSTextField(labelWithString: "")
    private let detailValue = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        orientation = .vertical
        spacing = 3
        alignment = .leading
        buildUI(title: title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(window: CodexRateLimitWindow, defaultTitle: String, resetText: String) {
        titleValue.stringValue = window.displayTitle(defaultTitle: defaultTitle)
        progress.doubleValue = min(100, max(0, Double(window.usedPercent)))
        percentValue.stringValue = "已用 \(window.usedPercent)%"
        detailValue.stringValue = "剩余 \(window.remainingPercent)% · \(resetText)"
    }

    private func buildUI(title: String) {
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 10
        topRow.alignment = .centerY

        titleValue.stringValue = title
        titleValue.font = NSFont.systemFont(ofSize: 12)
        titleValue.textColor = .secondaryLabelColor
        titleValue.alignment = .right
        titleValue.widthAnchor.constraint(equalToConstant: 74).isActive = true
        topRow.addArrangedSubview(titleValue)

        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 100
        progress.controlSize = .small
        progress.style = .bar
        progress.widthAnchor.constraint(equalToConstant: 220).isActive = true
        topRow.addArrangedSubview(progress)

        percentValue.font = NSFont.systemFont(ofSize: 12)
        percentValue.textColor = .controlTextColor
        percentValue.widthAnchor.constraint(equalToConstant: 92).isActive = true
        topRow.addArrangedSubview(percentValue)

        let detailRow = NSStackView()
        detailRow.orientation = .horizontal
        detailRow.spacing = 10
        detailRow.alignment = .firstBaseline

        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 74).isActive = true
        detailRow.addArrangedSubview(spacer)

        detailValue.font = NSFont.systemFont(ofSize: 11)
        detailValue.textColor = .secondaryLabelColor
        detailValue.lineBreakMode = .byTruncatingTail
        detailValue.widthAnchor.constraint(equalToConstant: 322).isActive = true
        detailRow.addArrangedSubview(detailValue)

        addArrangedSubview(topRow)
        addArrangedSubview(detailRow)
    }
}
