import AppKit
import SignalLightShared

final class StatusInfoViewController: NSViewController {
    private enum QuotaProvider {
        case cursor
        case codex
    }

    private let configStore: SignalLightConfigStore
    private let codexQuotaReader = CodexRateLimitReader()
    private let cursorQuotaReader = CursorUsageReader()
    private var stateStore: SignalStateStore
    private var config: SignalLightConfig
    private var quotaProvider: QuotaProvider = .cursor

    private let stateValue = NSTextField(labelWithString: "")
    private let sourceValue = NSTextField(labelWithString: "")
    private let modelValue = NSTextField(labelWithString: "")
    private let updatedValue = NSTextField(labelWithString: "")
    private let directoryValue = NSTextField(labelWithString: "")
    private let quotaTitleValue = NSTextField(labelWithString: "Cursor 额度")
    private let quotaStatusValue = NSTextField(labelWithString: "")
    private let quotaSummaryValue = NSTextField(labelWithString: "")
    private let quotaSummaryLabel = NSTextField(labelWithString: "")
    private let quotaPrimaryRow = QuotaWindowRowView(title: "Auto")
    private let quotaSecondaryRow = QuotaWindowRowView(title: "API")
    private let onPreferredSourceUpdate: (PreferredAgentSource) throws -> Void
    private var sourceRadioButtons: [NSButton] = []
    private let contentWidth: CGFloat = 512
    private let contentStack = NSStackView()

    init(
        configStore: SignalLightConfigStore,
        config: SignalLightConfig,
        stateStore: SignalStateStore,
        onPreferredSourceUpdate: @escaping (PreferredAgentSource) throws -> Void
    ) {
        self.configStore = configStore
        self.config = config
        self.stateStore = stateStore
        self.onPreferredSourceUpdate = onPreferredSourceUpdate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 390))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)

        let docView = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 1))
        scrollView.documentView = docView
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        quotaProvider = resolveQuotaProvider(from: preferredRecord())
        update(config: config, stateStore: stateStore)
        refreshQuota()
    }

    func update(config: SignalLightConfig, stateStore: SignalStateStore) {
        self.config = config
        self.stateStore = stateStore

        let record = preferredRecord()
        let nextProvider = resolveQuotaProvider(from: record)
        if let record {
            let scopedSignal = aggregateSessions(["active": record])
            stateValue.stringValue = SignalState(rawValue: scopedSignal)?.displayName ?? scopedSignal
        } else {
            stateValue.stringValue = stateStore.state.displayName
        }
        sourceValue.stringValue = sourceName(from: record) ?? "当前状态未提供来源"
        modelValue.stringValue = cleanText(record?.model) ?? "当前状态未提供模型"
        updatedValue.stringValue = formattedTimestamp(stateStore.updatedAt ?? record?.updatedAt)
        directoryValue.stringValue = stateStore.stateDirectoryURL.path

        if nextProvider != quotaProvider {
            quotaProvider = nextProvider
            refreshQuota()
        }

        syncSourceRadioSelection()
        updateDocumentHeight()
    }

    private func buildUI() {
        guard let docView = (view as? NSScrollView)?.documentView else {
            return
        }

        let stack = contentStack
        stack.orientation = .vertical
        stack.spacing = 14
        stack.distribution = .gravityAreas
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 8, right: 4)
        stack.alignment = .leading

        stack.addArrangedSubview(makeSourceFilterSection())

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeSectionTitle("状态详情"))
        stack.addArrangedSubview(makeRow(title: "状态", value: stateValue, emphasize: true))
        stack.addArrangedSubview(makeRow(title: "来源程序", value: sourceValue))
        stack.addArrangedSubview(makeRow(title: "模型", value: modelValue))
        stack.addArrangedSubview(makeRow(title: "最后更新", value: updatedValue))

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeSectionTitle("状态数据"))
        stack.addArrangedSubview(makeRow(title: "状态目录", value: directoryValue, selectable: true))

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeQuotaCard())
        applyLoadingQuotaState()

        let hint = NSTextField(labelWithString: "状态由本机 Agent hook 写入，菜单栏和悬浮灯会实时读取这里的数据。")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = 500
        stack.addArrangedSubview(hint)

        stack.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: docView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: contentWidth),
        ])
        updateDocumentHeight()
    }

    private func updateDocumentHeight() {
        guard let scrollView = view as? NSScrollView,
              let docView = scrollView.documentView
        else {
            return
        }

        contentStack.layoutSubtreeIfNeeded()
        let fittingHeight = ceil(contentStack.fittingSize.height) + 8
        let viewportHeight = scrollView.contentView.bounds.height
        docView.setFrameSize(NSSize(width: contentWidth, height: max(fittingHeight, viewportHeight)))
    }

    private func makeSourceFilterSection() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 8
        container.alignment = .leading

        container.addArrangedSubview(makeSectionTitle("监听来源"))

        let filterHint = NSTextField(
            labelWithString: "只展示所选应用的状态；多个 Agent 同时运行时不会互相覆盖。"
        )
        filterHint.font = NSFont.systemFont(ofSize: 11)
        filterHint.textColor = .secondaryLabelColor
        filterHint.lineBreakMode = .byWordWrapping
        filterHint.preferredMaxLayoutWidth = 500
        container.addArrangedSubview(filterHint)

        sourceRadioButtons = []
        let sources = PreferredAgentSource.allCases
        let columnsPerRow = 3
        var index = 0
        while index < sources.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 16
            row.alignment = .centerY
            let end = min(index + columnsPerRow, sources.count)
            for sourceIndex in index..<end {
                let source = sources[sourceIndex]
                let button = NSButton(
                    radioButtonWithTitle: source.displayName,
                    target: self,
                    action: #selector(sourceRadioChanged(_:))
                )
                button.tag = sourceIndex
                sourceRadioButtons.append(button)
                row.addArrangedSubview(button)
            }
            container.addArrangedSubview(row)
            index += columnsPerRow
        }

        syncSourceRadioSelection()
        return container
    }

    private func syncSourceRadioSelection() {
        let preferred = configStore.effectiveAgentConfig(from: config).preferredAgentSource
        guard let selectedIndex = PreferredAgentSource.allCases.firstIndex(of: preferred) else {
            return
        }
        for (index, button) in sourceRadioButtons.enumerated() {
            button.state = index == selectedIndex ? .on : .off
        }
    }

    @objc private func sourceRadioChanged(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0, index < PreferredAgentSource.allCases.count else {
            return
        }
        for (buttonIndex, button) in sourceRadioButtons.enumerated() {
            button.state = buttonIndex == index ? .on : .off
        }
        do {
            try onPreferredSourceUpdate(PreferredAgentSource.allCases[index])
        } catch {
            showSettingsError(error)
        }
    }

    private func preferredRecord() -> SessionRecord? {
        let agent = configStore.effectiveAgentConfig(from: config)
        let now = Date().timeIntervalSince1970
        return preferredSessionRecord(
            in: stateStore.sessionState.sessions,
            preferred: agent.preferredAgentSource,
            now: now,
            sessionTTL: agent.sessionTTLSeconds,
            excludingEndSignals: true
        )
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
        return StatusInfoFormatters.timestamp.string(from: Date(timeIntervalSince1970: value))
    }

    private func formattedResetTime(_ value: Int64?) -> String {
        guard let value else {
            return "暂无重置时间"
        }
        return "重置 \(StatusInfoFormatters.resetTime.string(from: Date(timeIntervalSince1970: TimeInterval(value))))"
    }

    private func resolveQuotaProvider(from record: SessionRecord?) -> QuotaProvider {
        if isCursorSessionSource(record?.source) {
            return .cursor
        }
        if let bundleIdentifier = record?.source?.bundleIdentifier?.lowercased(),
           bundleIdentifier.contains("codex") || bundleIdentifier.contains("openai")
        {
            return .codex
        }
        if CursorAuthStore.loadCredentials() != nil {
            return .cursor
        }
        return .codex
    }

    @objc private func refreshQuota() {
        applyLoadingQuotaState()
        switch quotaProvider {
        case .cursor:
            cursorQuotaReader.fetch { [weak self] state in
                DispatchQueue.main.async {
                    self?.applyCursorQuotaState(state)
                }
            }
        case .codex:
            codexQuotaReader.fetch { [weak self] state in
                DispatchQueue.main.async {
                    self?.applyCodexQuotaState(state)
                }
            }
        }
    }

    private func applyLoadingQuotaState() {
        quotaTitleValue.stringValue = quotaProvider == .cursor ? "Cursor 额度" : "Codex 额度"
        quotaSummaryValue.stringValue = "--%"
        quotaSummaryValue.textColor = .secondaryLabelColor
        quotaSummaryLabel.stringValue = quotaProvider == .cursor ? "总用量剩余" : "短窗口剩余"
        quotaStatusValue.stringValue = quotaProvider == .cursor ? "正在读取 Cursor 额度..." : "正在读取 Codex 额度..."
        quotaPrimaryRow.isHidden = true
        quotaSecondaryRow.isHidden = true
        updateDocumentHeight()
    }

    private func applyCursorQuotaState(_ state: CursorQuotaState) {
        guard quotaProvider == .cursor else {
            return
        }

        switch state {
        case .loading:
            applyLoadingQuotaState()
        case .unavailable(let reason):
            quotaTitleValue.stringValue = "Cursor 额度"
            quotaSummaryValue.stringValue = "不可用"
            quotaSummaryValue.textColor = .systemRed
            quotaSummaryLabel.stringValue = "读取失败"
            quotaStatusValue.stringValue = reason
            quotaPrimaryRow.isHidden = true
            quotaSecondaryRow.isHidden = true
        case .loaded(let snapshot):
            let remaining = snapshot.totalRemainingPercent
            quotaTitleValue.stringValue = "Cursor 额度"
            quotaSummaryValue.stringValue = "\(remaining)%"
            quotaSummaryValue.textColor = quotaTextColor(forRemainingPercent: remaining)
            quotaSummaryLabel.stringValue = cursorSummaryLabel(from: snapshot)
            quotaStatusValue.stringValue = cursorQuotaStatus(from: snapshot)
            quotaPrimaryRow.isHidden = false
            quotaSecondaryRow.isHidden = false
            quotaPrimaryRow.update(
                window: snapshot.usageWindow(usedPercent: snapshot.autoUsedPercent, resetsAt: snapshot.billingCycleEnd),
                defaultTitle: "Auto",
                resetText: formattedResetDate(snapshot.billingCycleEnd)
            )
            quotaSecondaryRow.update(
                window: snapshot.usageWindow(usedPercent: snapshot.apiUsedPercent, resetsAt: snapshot.billingCycleEnd),
                defaultTitle: "API",
                resetText: formattedResetDate(snapshot.billingCycleEnd)
            )
        }
        updateDocumentHeight()
    }

    private func applyCodexQuotaState(_ state: CodexQuotaState) {
        guard quotaProvider == .codex else {
            return
        }

        switch state {
        case .loading:
            applyLoadingQuotaState()
        case .unavailable(let reason):
            quotaTitleValue.stringValue = "Codex 额度"
            quotaSummaryValue.stringValue = "不可用"
            quotaSummaryValue.textColor = .systemRed
            quotaSummaryLabel.stringValue = "读取失败"
            quotaStatusValue.stringValue = reason
            quotaPrimaryRow.isHidden = true
            quotaSecondaryRow.isHidden = true
        case .loaded(let snapshot):
            let primaryRemaining = snapshot.primary.remainingPercent
            quotaTitleValue.stringValue = "Codex 额度"
            quotaSummaryValue.stringValue = "\(primaryRemaining)%"
            quotaSummaryValue.textColor = quotaTextColor(forRemainingPercent: primaryRemaining)
            quotaSummaryLabel.stringValue = "\(snapshot.primary.displayTitle(defaultTitle: "5 小时"))剩余"
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
        updateDocumentHeight()
    }

    private func cursorQuotaStatus(from snapshot: CursorUsageSnapshot) -> String {
        var parts: [String] = []
        if let planType = snapshot.formattedPlanType {
            parts.append(planType)
        }
        if let email = cleanText(snapshot.email) {
            parts.append(email)
        }
        if let displayMessage = cleanText(snapshot.displayMessage) {
            parts.append(displayMessage)
        }
        return parts.isEmpty ? "Cursor" : parts.joined(separator: " · ")
    }

    private func cursorSummaryLabel(from snapshot: CursorUsageSnapshot) -> String {
        if let limitCents = snapshot.includedLimitCents, let spendCents = snapshot.totalSpendCents, limitCents > 0 {
            return "已用 \(formatUSD(cents: min(spendCents, limitCents))) / \(formatUSD(cents: limitCents))"
        }
        return "总用量剩余"
    }

    private func formattedResetDate(_ value: Date?) -> String {
        guard let value else {
            return "暂无重置时间"
        }
        return "重置 \(StatusInfoFormatters.resetTime.string(from: value))"
    }

    private func formatUSD(cents: Int) -> String {
        let amount = NSDecimalNumber(value: cents).dividing(by: 100)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: amount) ?? "$\(amount)"
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

    private func makeQuotaCard() -> NSView {
        let card = QuotaCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: 512).isActive = true

        let content = NSStackView()
        content.orientation = .vertical
        content.spacing = 12
        content.alignment = .leading
        content.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)

        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 14
        header.alignment = .top
        header.widthAnchor.constraint(equalToConstant: 480).isActive = true

        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.spacing = 4
        titleStack.alignment = .leading

        quotaTitleValue.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        quotaTitleValue.textColor = .labelColor
        titleStack.addArrangedSubview(quotaTitleValue)

        quotaStatusValue.font = NSFont.systemFont(ofSize: 11)
        quotaStatusValue.textColor = .secondaryLabelColor
        quotaStatusValue.lineBreakMode = .byTruncatingMiddle
        quotaStatusValue.widthAnchor.constraint(equalToConstant: 300).isActive = true
        titleStack.addArrangedSubview(quotaStatusValue)

        header.addArrangedSubview(titleStack)
        header.addArrangedSubview(NSView())

        let button = NSButton(title: "刷新", target: self, action: #selector(refreshQuota))
        button.bezelStyle = .rounded
        button.controlSize = .small
        header.addArrangedSubview(button)

        let summaryRow = NSStackView()
        summaryRow.orientation = .horizontal
        summaryRow.spacing = 18
        summaryRow.alignment = .bottom

        let summaryStack = NSStackView()
        summaryStack.orientation = .vertical
        summaryStack.spacing = 2
        summaryStack.alignment = .leading

        quotaSummaryValue.font = NSFont.monospacedDigitSystemFont(ofSize: 34, weight: .semibold)
        quotaSummaryValue.textColor = .labelColor
        quotaSummaryValue.lineBreakMode = .byClipping
        quotaSummaryValue.widthAnchor.constraint(equalToConstant: 132).isActive = true
        summaryStack.addArrangedSubview(quotaSummaryValue)

        quotaSummaryLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        quotaSummaryLabel.textColor = .secondaryLabelColor
        quotaSummaryLabel.lineBreakMode = .byTruncatingTail
        quotaSummaryLabel.widthAnchor.constraint(equalToConstant: 132).isActive = true
        summaryStack.addArrangedSubview(quotaSummaryLabel)

        let windowsStack = NSStackView()
        windowsStack.orientation = .vertical
        windowsStack.spacing = 8
        windowsStack.alignment = .leading
        windowsStack.addArrangedSubview(quotaPrimaryRow)
        windowsStack.addArrangedSubview(quotaSecondaryRow)

        summaryRow.addArrangedSubview(summaryStack)
        summaryRow.addArrangedSubview(windowsStack)

        content.addArrangedSubview(header)
        content.addArrangedSubview(summaryRow)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        return card
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

private func quotaTextColor(forRemainingPercent percent: Int) -> NSColor {
    if percent <= 10 {
        return .systemRed
    }
    if percent <= 25 {
        return .systemOrange
    }
    return .labelColor
}

private func cleanText(_ value: String?) -> String? {
    guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
        return nil
    }
    return text
}

private enum StatusInfoFormatters {
    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    static let resetTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private final class QuotaCardView: NSView {
    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.withAlphaComponent(0.72).setFill()
        path.fill()

        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()

        let topGlow = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        NSColor.white.withAlphaComponent(effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.06 : 0.38).setStroke()
        topGlow.lineWidth = 1
        topGlow.stroke()
    }
}

private final class QuotaWindowRowView: NSStackView {
    private let titleValue = NSTextField(labelWithString: "")
    private let progress = QuotaProgressView()
    private let remainingValue = NSTextField(labelWithString: "")
    private let detailValue = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        orientation = .vertical
        spacing = 5
        alignment = .leading
        buildUI(title: title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(window: CodexRateLimitWindow, defaultTitle: String, resetText: String) {
        titleValue.stringValue = window.displayTitle(defaultTitle: defaultTitle)
        progress.percent = window.usedPercent
        let remaining = window.remainingPercent
        let used = max(0, window.usedPercent)
        progress.remainingPercent = remaining
        remainingValue.stringValue = "剩余 \(remaining)%"
        remainingValue.textColor = quotaTextColor(forRemainingPercent: remaining)
        detailValue.stringValue = resetText
        progress.toolTip = "已用 \(used)%"
    }

    private func buildUI(title: String) {
        widthAnchor.constraint(equalToConstant: 326).isActive = true

        let metaRow = NSStackView()
        metaRow.orientation = .horizontal
        metaRow.spacing = 10
        metaRow.alignment = .firstBaseline

        titleValue.stringValue = title
        titleValue.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleValue.textColor = .secondaryLabelColor
        titleValue.widthAnchor.constraint(equalToConstant: 48).isActive = true
        metaRow.addArrangedSubview(titleValue)

        remainingValue.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        remainingValue.textColor = .labelColor
        remainingValue.lineBreakMode = .byTruncatingTail
        remainingValue.widthAnchor.constraint(equalToConstant: 78).isActive = true
        metaRow.addArrangedSubview(remainingValue)

        detailValue.font = NSFont.systemFont(ofSize: 11)
        detailValue.textColor = .secondaryLabelColor
        detailValue.lineBreakMode = .byTruncatingTail
        detailValue.widthAnchor.constraint(equalToConstant: 178).isActive = true
        metaRow.addArrangedSubview(detailValue)

        progress.widthAnchor.constraint(equalToConstant: 326).isActive = true
        progress.heightAnchor.constraint(equalToConstant: 8).isActive = true

        addArrangedSubview(metaRow)
        addArrangedSubview(progress)
    }
}

private final class QuotaProgressView: NSView {
    private var clampedPercent = 0
    private var clampedRemainingPercent = 100

    var percent: Int {
        get {
            clampedPercent
        }
        set {
            clampedPercent = min(100, max(0, newValue))
            needsDisplay = true
        }
    }

    var remainingPercent: Int {
        get {
            clampedRemainingPercent
        }
        set {
            clampedRemainingPercent = min(100, max(0, newValue))
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackHeight: CGFloat = 8
        let trackRect = bounds.insetBy(dx: 0, dy: max(0, (bounds.height - trackHeight) / 2))
        let radius = trackRect.height / 2
        Self.trackColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius).fill()

        Self.tickColor.setStroke()
        for tick in 1..<10 {
            let x = trackRect.minX + trackRect.width * CGFloat(tick) / 10
            let tickPath = NSBezierPath()
            tickPath.move(to: NSPoint(x: x, y: trackRect.minY + 1))
            tickPath.line(to: NSPoint(x: x, y: trackRect.maxY - 1))
            tickPath.lineWidth = 0.5
            tickPath.stroke()
        }

        guard clampedPercent > 0 else {
            return
        }

        let fillWidth = max(trackRect.height, trackRect.width * CGFloat(clampedPercent) / 100)
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: min(trackRect.width, fillWidth),
            height: trackRect.height
        )
        quotaProgressColor(forRemainingPercent: clampedRemainingPercent).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }

    private static let trackColor = NSColor.separatorColor.withAlphaComponent(0.28)
    private static let tickColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65)
}

private func quotaProgressColor(forRemainingPercent percent: Int) -> NSColor {
    if percent <= 10 {
        return NSColor.systemRed.withAlphaComponent(0.9)
    }
    if percent <= 25 {
        return NSColor.systemOrange.withAlphaComponent(0.88)
    }
    return NSColor.systemGreen.withAlphaComponent(0.82)
}
