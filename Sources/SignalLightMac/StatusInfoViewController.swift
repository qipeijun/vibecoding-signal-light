import AppKit
import QuartzCore
import SignalLightShared

final class StatusInfoViewController: NSViewController {
    private struct SessionCandidate {
        let key: String
        let record: SessionRecord
        let signal: String
        let priority: Int
    }

    private let configStore: SignalLightConfigStore
    private let quotaReader = CodexRateLimitReader()
    private var stateStore: SignalStateStore
    private var config: SignalLightConfig
    private let threadCatalog: CodexThreadCatalog
    private let onOpenDiagnostics: () -> Void
    private let onOpenSession: (String?, SessionSource?) -> Void
    private var currentSessionKey: String?
    private var currentSessionSource: SessionSource?
    private var threadSummaries: [String: CodexThreadSummary] = [:]
    private var lastSessionSignature: String?
    private var lastRecentThreadSignature: String?
    private var sessionTimestampFields: [String: NSTextField] = [:]
    private var recentThreadTimestampFields: [String: NSTextField] = [:]

    private let signalView = DashboardSignalView()
    private let stateValue = NSTextField(labelWithString: "")
    private let stateSummaryValue = NSTextField(labelWithString: "")
    private let actionValue = NSTextField(labelWithString: "")
    private let sourceValue = NSTextField(labelWithString: "")
    private let modelValue = NSTextField(labelWithString: "")
    private let updatedValue = NSTextField(labelWithString: "")
    private let sessionsSummaryValue = NSTextField(labelWithString: "")
    private let sessionsStack = NSStackView()
    private let recentThreadsStack = NSStackView()
    private let quotaValue = NSTextField(labelWithString: "")
    private let refreshQuotaButton = NSButton()
    private let openDiagnosticsButton = NSButton()
    private let returnToCodexButton = NSButton()

    init(
        configStore: SignalLightConfigStore,
        config: SignalLightConfig,
        stateStore: SignalStateStore,
        threadCatalog: CodexThreadCatalog = CodexThreadCatalog(),
        onOpenDiagnostics: @escaping () -> Void = {},
        onOpenSession: @escaping (String?, SessionSource?) -> Void = { _, _ in }
    ) {
        self.configStore = configStore
        self.config = config
        self.stateStore = stateStore
        self.threadCatalog = threadCatalog
        self.onOpenDiagnostics = onOpenDiagnostics
        self.onOpenSession = onOpenSession
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 644, height: 540))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        update(config: config, stateStore: stateStore, frameState: nil)
        refreshQuota()
    }

    func update(config: SignalLightConfig, stateStore: SignalStateStore, frameState: SignalFrame? = nil) {
        self.config = config
        self.stateStore = stateStore

        let lifecycleThreadIDs = Set(stateStore.sessionState.sessions.compactMap { key, record in
            // 已收口记录只进入最近对话，不再扫描 rollout 生命周期。
            ["done", "session_end", "off"].contains(record.signal) ? nil : key
        })
        threadSummaries = threadCatalog.summaries(for: lifecycleThreadIDs)
        let candidates = sessionCandidates()
        let activeThreadIDs = Set(candidates.map(\.key))
        let recentThreads = threadCatalog.recentSummaries(limit: 5, excluding: activeThreadIDs)
        let candidate = preferredCandidate(in: candidates)
        let record = candidate?.record
        currentSessionKey = candidate?.key
        currentSessionSource = candidate?.record.source
        let state = stateStore.effectiveState
        let summary = signalSummaries[state.rawValue]

        signalView.frameState = frameState ?? frame(for: state, tick: 0, rules: config.statusRules)
        signalView.stateName = state.displayName
        updateText(stateValue, value: state.displayName)
        updateText(stateSummaryValue, value: summary?.summary ?? "当前状态没有可用说明。")
        let actionText = stateStore.connectionIssue ?? attentionText(for: state, summary: summary)
        updateText(actionValue, value: actionText)
        actionValue.isHidden = actionText.isEmpty
        actionValue.textColor = actionColor(for: state)
        openDiagnosticsButton.isHidden = stateStore.connectionIssue == nil

        let recentHistory = flowHistory(sessionKey: candidate?.key)
        let latestHistory = recentHistory.last
        let source = sourceName(from: record) ?? sourceName(from: latestHistory)
        sourceValue.stringValue = source ?? "未提供"
        modelValue.stringValue = cleanText(record?.model) ?? cleanText(latestHistory?.model) ?? "未提供"
        updatedValue.stringValue = formattedTimestamp(stateStore.updatedAt ?? record?.updatedAt)
        let threadName = candidate.flatMap { threadSummaries[$0.key]?.name }
        let canOpenThread = candidate.flatMap { codexThreadURL(threadID: $0.key) } != nil
        returnToCodexButton.isHidden = !canOpenThread && record?.source == nil
        let sourceButtonTitle = canOpenThread ? "打开当前会话" : source.map { "打开 \($0)" } ?? "打开来源应用"
        returnToCodexButton.title = sourceButtonTitle
        returnToCodexButton.toolTip = threadName.map { "打开会话「\($0)」" } ?? sourceButtonTitle
        returnToCodexButton.setAccessibilityLabel(sourceButtonTitle)

        // 连接异常会覆盖普通会话状态，此时没有任何单一会话可以声称自己驱动主灯。
        let preferredKey = stateStore.connectionIssue == nil ? candidate?.key : nil
        updateSessions(candidates: candidates, preferredKey: preferredKey)
        updateRecentThreads(recentThreads)
    }

    /// 仅更新灯泡亮度，供主动画时钟高频调用。
    func updateAnimationFrame(_ frameState: SignalFrame) {
        signalView.frameState = frameState
    }

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 6, right: 4)
        root.alignment = .leading

        root.addArrangedSubview(makeHero())
        root.addArrangedSubview(makeSeparator())
        root.addArrangedSubview(makeConversationSections())
        root.addArrangedSubview(makeSeparator())
        root.addArrangedSubview(makeQuotaRow())

        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeHero() -> NSView {
        let hero = NSStackView()
        hero.orientation = .horizontal
        hero.spacing = 16
        hero.alignment = .centerY
        hero.widthAnchor.constraint(equalToConstant: 636).isActive = true
        hero.heightAnchor.constraint(equalToConstant: 150).isActive = true

        signalView.translatesAutoresizingMaskIntoConstraints = false
        signalView.widthAnchor.constraint(equalToConstant: 84).isActive = true
        signalView.heightAnchor.constraint(equalToConstant: 144).isActive = true
        hero.addArrangedSubview(signalView)

        let details = NSStackView()
        details.orientation = .vertical
        details.spacing = 6
        details.alignment = .leading
        details.widthAnchor.constraint(equalToConstant: 536).isActive = true

        details.addArrangedSubview(makeEyebrow("当前状态"))

        stateValue.font = NSFont.systemFont(ofSize: 25, weight: .bold)
        stateValue.textColor = .labelColor
        details.addArrangedSubview(stateValue)

        stateSummaryValue.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        stateSummaryValue.textColor = .labelColor
        stateSummaryValue.lineBreakMode = .byWordWrapping
        stateSummaryValue.maximumNumberOfLines = 2
        stateSummaryValue.widthAnchor.constraint(equalToConstant: 536).isActive = true
        details.addArrangedSubview(stateSummaryValue)

        actionValue.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        actionValue.lineBreakMode = .byWordWrapping
        actionValue.maximumNumberOfLines = 2
        actionValue.widthAnchor.constraint(equalToConstant: 536).isActive = true
        details.addArrangedSubview(actionValue)

        details.addArrangedSubview(makeMetadataRow())
        details.addArrangedSubview(makeActionRow())

        hero.addArrangedSubview(details)
        return hero
    }

    private func makeMetadataRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .top
        row.addArrangedSubview(makeMetadataItem(title: "最近来源", value: sourceValue, width: 164))
        row.addArrangedSubview(makeMetadataItem(title: "最近模型", value: modelValue, width: 164))
        row.addArrangedSubview(makeMetadataItem(title: "更新时间", value: updatedValue, width: 164))
        return row
    }

    private func makeMetadataItem(title: String, value: NSTextField, width: CGFloat) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 3
        stack.alignment = .leading
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .tertiaryLabelColor

        value.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        value.textColor = .secondaryLabelColor
        value.lineBreakMode = .byTruncatingMiddle
        value.widthAnchor.constraint(equalToConstant: width).isActive = true

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(value)
        return stack
    }

    private func makeActionRow() -> NSView {
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 8

        configureActionButton(
            returnToCodexButton,
            title: "打开来源应用",
            symbolName: "arrow.up.forward.app",
            action: #selector(returnToCodex)
        )
        configureActionButton(
            openDiagnosticsButton,
            title: "检查连接",
            symbolName: "stethoscope",
            action: #selector(openDiagnostics)
        )
        actions.addArrangedSubview(returnToCodexButton)
        actions.addArrangedSubview(openDiagnosticsButton)
        return actions
    }

    private func makeSessionsSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.widthAnchor.constraint(equalToConstant: 636).isActive = true

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.widthAnchor.constraint(equalToConstant: 636).isActive = true

        let title = NSTextField(labelWithString: "活跃会话")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        sessionsSummaryValue.font = NSFont.systemFont(ofSize: 11)
        sessionsSummaryValue.textColor = .secondaryLabelColor

        header.addArrangedSubview(title)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(sessionsSummaryValue)

        sessionsStack.orientation = .vertical
        sessionsStack.spacing = 2
        sessionsStack.alignment = .leading
        sessionsStack.widthAnchor.constraint(equalToConstant: 636).isActive = true

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(sessionsStack)
        return stack
    }

    private func makeConversationSections() -> NSView {
        let content = ConversationSectionsStackView()
        content.orientation = .vertical
        content.spacing = 10
        content.alignment = .leading
        content.setContentHuggingPriority(.required, for: .vertical)
        content.addArrangedSubview(makeSessionsSection())
        content.addArrangedSubview(makeRecentThreadsSection())
        content.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = content
        scrollView.widthAnchor.constraint(equalToConstant: 636).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 278).isActive = true

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.contentView.bottomAnchor),
        ])
        return scrollView
    }

    private func makeRecentThreadsSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.widthAnchor.constraint(equalToConstant: 636).isActive = true

        let title = NSTextField(labelWithString: "最近对话")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor

        recentThreadsStack.orientation = .vertical
        recentThreadsStack.spacing = 2
        recentThreadsStack.alignment = .leading
        recentThreadsStack.widthAnchor.constraint(equalToConstant: 636).isActive = true

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(recentThreadsStack)
        return stack
    }

    private func configureActionButton(
        _ button: NSButton,
        title: String,
        symbolName: String,
        action: Selector
    ) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = self
        button.action = action
        button.setAccessibilityLabel(title)
    }

    @objc private func openDiagnostics() {
        onOpenDiagnostics()
    }

    @objc private func returnToCodex() {
        onOpenSession(currentSessionKey, currentSessionSource)
    }

    private func makeQuotaRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: 636).isActive = true

        quotaValue.font = NSFont.systemFont(ofSize: 11)
        quotaValue.textColor = .secondaryLabelColor
        quotaValue.lineBreakMode = .byTruncatingTail
        quotaValue.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        refreshQuotaButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "刷新 Codex 额度"
        )
        refreshQuotaButton.imagePosition = .imageOnly
        refreshQuotaButton.bezelStyle = .texturedRounded
        refreshQuotaButton.controlSize = .small
        refreshQuotaButton.toolTip = "刷新 Codex 额度"
        refreshQuotaButton.target = self
        refreshQuotaButton.action = #selector(refreshQuota)
        refreshQuotaButton.setAccessibilityLabel("刷新 Codex 额度")

        row.addArrangedSubview(quotaValue)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(refreshQuotaButton)
        return row
    }

    private func preferredCandidate(in candidates: [SessionCandidate]) -> SessionCandidate? {
        candidates.max {
            $0.priority == $1.priority
                ? $0.record.updatedAt < $1.record.updatedAt
                : $0.priority < $1.priority
        }
    }

    private func sessionCandidates() -> [SessionCandidate] {
        let agent = configStore.effectiveAgentConfig(from: config)
        let now = Date().timeIntervalSince1970
        return stateStore.sessionState.sessions.compactMap { key, record in
            guard !sessionEndSignals.contains(record.signal) else {
                return nil
            }
            let activity = stateStore.threadActivities[key] ?? threadSummaries[key]?.activity
            guard let signal = activeSessionSignal(
                for: record,
                activity: activity,
                now: now,
                policy: agent.leasePolicy
            ), let priority = signalRiskPriority(signal) else {
                return nil
            }
            return SessionCandidate(key: key, record: record, signal: signal, priority: priority)
        }
    }

    private func updateSessions(candidates unsortedCandidates: [SessionCandidate], preferredKey: String?) {
        let candidates = unsortedCandidates.sorted {
            $0.priority == $1.priority
                ? $0.record.updatedAt > $1.record.updatedAt
                : $0.priority > $1.priority
        }
        let signature = candidates.map { candidate in
            let threadName = threadSummaries[candidate.key]?.name ?? ""
            let source = sourceName(from: candidate.record) ?? ""
            let model = cleanText(candidate.record.model) ?? ""
            return "\(candidate.key):\(candidate.signal):\(candidate.key == preferredKey):\(threadName):\(source):\(model)"
        }.joined(separator: "|")
        if signature == lastSessionSignature {
            for candidate in candidates.prefix(3) {
                sessionTimestampFields[candidate.key]?.stringValue = relativeTimestamp(candidate.record.updatedAt)
            }
            return
        }
        let shouldAnimate = lastSessionSignature != nil
        lastSessionSignature = signature
        defer { animateSessionChangeIfNeeded(shouldAnimate) }

        sessionTimestampFields = [:]
        for view in sessionsStack.arrangedSubviews {
            sessionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !candidates.isEmpty else {
            sessionsSummaryValue.stringValue = "0 个"
            let empty = NSTextField(labelWithString: "暂无正在运行的会话")
            empty.font = NSFont.systemFont(ofSize: 11)
            empty.textColor = .secondaryLabelColor
            empty.widthAnchor.constraint(equalToConstant: 636).isActive = true
            empty.heightAnchor.constraint(equalToConstant: 36).isActive = true
            sessionsStack.addArrangedSubview(empty)
            return
        }

        let urgentCount = candidates.filter { redSignals.contains($0.signal) }.count
        let attentionCount = candidates.filter { $0.signal == "attention" }.count
        var summary = "\(candidates.count) 个"
        if urgentCount > 0 {
            summary += " · \(urgentCount) 个需立即处理"
        } else if attentionCount > 0 {
            summary += " · \(attentionCount) 个需查看"
        }
        sessionsSummaryValue.stringValue = summary

        for candidate in candidates.prefix(3) {
            sessionsStack.addArrangedSubview(
                makeSessionRow(candidate, isPreferred: candidate.key == preferredKey)
            )
        }
        if candidates.count > 3 {
            let remaining = NSTextField(labelWithString: "另有 \(candidates.count - 3) 个活跃会话")
            remaining.font = NSFont.systemFont(ofSize: 10)
            remaining.textColor = .tertiaryLabelColor
            remaining.alignment = .right
            remaining.widthAnchor.constraint(equalToConstant: 636).isActive = true
            sessionsStack.addArrangedSubview(remaining)
        }
    }

    private func makeSessionRow(_ candidate: SessionCandidate, isPreferred: Bool) -> NSView {
        let row = ConversationRowView()
        row.threadID = candidate.key
        row.source = candidate.record.source
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        row.hoverColor = sessionColor(for: candidate.signal)
        if isPreferred {
            let color = sessionColor(for: candidate.signal)
            row.baseBackgroundColor = color.withAlphaComponent(0.055)
            row.baseBorderColor = color.withAlphaComponent(0.22)
        }
        row.widthAnchor.constraint(equalToConstant: 636).isActive = true
        row.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = sessionColor(for: candidate.signal).cgColor
        dot.layer?.cornerRadius = 4.5
        dot.widthAnchor.constraint(equalToConstant: 9).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 9).isActive = true
        if isPreferred {
            dot.layer?.shadowColor = sessionColor(for: candidate.signal).cgColor
            dot.layer?.shadowOpacity = 0.28
            dot.layer?.shadowRadius = 3
            dot.layer?.shadowOffset = .zero
        }

        let identity = NSStackView()
        identity.orientation = .vertical
        identity.spacing = 1
        identity.alignment = .leading
        identity.widthAnchor.constraint(equalToConstant: 292).isActive = true

        let sourceName = sourceName(from: candidate.record) ?? "未知来源"
        let threadName = threadSummaries[candidate.key]?.name
        let primaryText = threadName ?? "\(sourceName) · 会话 \(shortSessionIdentifier(candidate.key))"
        let source = NSTextField(labelWithString: primaryText)
        source.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        source.lineBreakMode = .byTruncatingTail
        source.widthAnchor.constraint(equalToConstant: 292).isActive = true
        source.toolTip = threadName.map { "\($0)\n会话 \(candidate.key)" } ?? "会话 \(candidate.key)"

        let modelParts = [sourceName, cleanText(candidate.record.model)].compactMap { $0 }
        let model = NSTextField(labelWithString: modelParts.joined(separator: " · "))
        model.font = NSFont.systemFont(ofSize: 10)
        model.textColor = .secondaryLabelColor
        model.lineBreakMode = .byTruncatingTail
        model.widthAnchor.constraint(equalToConstant: 292).isActive = true
        identity.addArrangedSubview(source)
        identity.addArrangedSubview(model)

        let statePrefix = isPreferred ? "主灯 · " : ""
        let state = NSTextField(labelWithString: statePrefix + localizedSignalName(candidate.signal))
        state.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        state.textColor = sessionColor(for: candidate.signal)
        state.alignment = .right
        state.widthAnchor.constraint(equalToConstant: 116).isActive = true

        let updated = NSTextField(labelWithString: relativeTimestamp(candidate.record.updatedAt))
        updated.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        updated.textColor = .tertiaryLabelColor
        updated.alignment = .right
        updated.widthAnchor.constraint(equalToConstant: 76).isActive = true
        sessionTimestampFields[candidate.key] = updated

        let canOpen = codexThreadURL(threadID: candidate.key) != nil || candidate.record.source != nil
        row.isEnabled = canOpen
        row.target = self
        row.action = #selector(openSession(_:))
        row.toolTip = canOpen
            ? threadName.map { "打开会话「\($0)」" } ?? "打开这个会话"
            : "当前会话没有可用的打开入口"
        row.setAccessibilityLabel(threadName.map { "打开会话 \($0)" } ?? "打开会话")

        let openIcon = NSImageView()
        openIcon.image = NSImage(
            systemSymbolName: "arrow.up.forward.square",
            accessibilityDescription: "打开会话"
        )
        openIcon.contentTintColor = .secondaryLabelColor
        openIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        openIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        openIcon.isHidden = !canOpen

        row.addArrangedSubview(dot)
        row.addArrangedSubview(identity)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(state)
        row.addArrangedSubview(updated)
        row.addArrangedSubview(openIcon)
        return row
    }

    private func updateRecentThreads(_ summaries: [CodexThreadSummary]) {
        let signature = summaries.map { "\($0.id):\($0.name)" }.joined(separator: "|")
        if signature == lastRecentThreadSignature {
            for summary in summaries {
                recentThreadTimestampFields[summary.id]?.stringValue = summary.updatedAt.map(relativeTimestamp) ?? ""
            }
            return
        }
        lastRecentThreadSignature = signature
        recentThreadTimestampFields = [:]
        for view in recentThreadsStack.arrangedSubviews {
            recentThreadsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !summaries.isEmpty else {
            let empty = NSTextField(labelWithString: "暂无可打开的最近对话")
            empty.font = NSFont.systemFont(ofSize: 11)
            empty.textColor = .secondaryLabelColor
            empty.widthAnchor.constraint(equalToConstant: 636).isActive = true
            empty.heightAnchor.constraint(equalToConstant: 30).isActive = true
            recentThreadsStack.addArrangedSubview(empty)
            return
        }

        for summary in summaries {
            recentThreadsStack.addArrangedSubview(makeRecentThreadRow(summary))
        }
    }

    private func makeRecentThreadRow(_ summary: CodexThreadSummary) -> NSView {
        let row = ConversationRowView()
        row.threadID = summary.id
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        row.widthAnchor.constraint(equalToConstant: 636).isActive = true
        row.heightAnchor.constraint(equalToConstant: 34).isActive = true
        row.target = self
        row.action = #selector(openSession(_:))
        row.toolTip = "打开对话「\(summary.name)」"
        row.setAccessibilityLabel("打开对话 \(summary.name)")

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let name = NSTextField(labelWithString: summary.name)
        name.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        name.toolTip = summary.name
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let updated = NSTextField(labelWithString: summary.updatedAt.map(relativeTimestamp) ?? "")
        updated.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        updated.textColor = .tertiaryLabelColor
        updated.alignment = .right
        updated.widthAnchor.constraint(equalToConstant: 92).isActive = true
        recentThreadTimestampFields[summary.id] = updated

        let openIcon = NSImageView()
        openIcon.image = NSImage(
            systemSymbolName: "arrow.up.forward.square",
            accessibilityDescription: "打开最近对话"
        )
        openIcon.contentTintColor = .secondaryLabelColor
        openIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        openIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        row.addArrangedSubview(icon)
        row.addArrangedSubview(name)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(updated)
        row.addArrangedSubview(openIcon)
        return row
    }

    @objc private func openSession(_ sender: ConversationRowView) {
        onOpenSession(sender.threadID, sender.source)
    }

    private func sessionColor(for signal: String) -> NSColor {
        if redSignals.contains(signal) {
            return .systemRed
        }
        if ["attention", "stale"].contains(signal) {
            return .systemOrange
        }
        if workingSignals.contains(signal) || signal == "working" {
            return .systemGreen
        }
        return .secondaryLabelColor
    }

    private func relativeTimestamp(_ value: Double) -> String {
        let elapsed = max(0, Date().timeIntervalSince1970 - value)
        if elapsed < 60 {
            return "刚刚"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60)) 分钟前"
        }
        return StatusInfoFormatters.timestamp.string(from: Date(timeIntervalSince1970: value))
    }

    private func shortSessionIdentifier(_ key: String) -> String {
        String(key.suffix(6)).uppercased()
    }

    private func flowHistory(sessionKey: String?) -> [SignalHistoryEntry] {
        guard let sessionKey else {
            return []
        }
        let cutoff = Date().timeIntervalSince1970 - historyRetentionSeconds
        return stateStore.history.entries.filter { entry in
            entry.recordedAt >= cutoff && entry.sessionKey == sessionKey
        }
    }

    private func sourceName(from record: SessionRecord?) -> String? {
        guard let source = record?.source else {
            return nil
        }
        return cleanText(source.localizedName) ?? cleanText(source.bundleIdentifier)
    }

    private func sourceName(from entry: SignalHistoryEntry?) -> String? {
        cleanText(entry?.source?.localizedName) ?? cleanText(entry?.source?.bundleIdentifier)
    }

    private func actionColor(for state: SignalState) -> NSColor {
        switch state {
        case .permission, .blocked:
            return .systemRed
        case .attention, .stale:
            return .systemOrange
        default:
            return .secondaryLabelColor
        }
    }

    private func attentionText(
        for state: SignalState,
        summary: (summary: String, attention: String)?
    ) -> String {
        switch state {
        case .attention, .permission, .blocked, .stale:
            return summary?.attention ?? ""
        default:
            return ""
        }
    }

    /// 状态文字变化使用轻微上移加淡入，避免轮询刷新时生硬跳字。
    private func updateText(_ field: NSTextField, value: String) {
        guard field.stringValue != value else {
            return
        }
        let shouldAnimate = !field.stringValue.isEmpty
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if shouldAnimate {
            field.wantsLayer = true
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.45
            fade.toValue = 1
            let move = CABasicAnimation(keyPath: "transform.translation.y")
            move.fromValue = -2
            move.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [fade, move]
            group.duration = 0.22
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            field.layer?.add(group, forKey: "status-text-change")
        }
        field.stringValue = value
    }

    /// 只在会话结构或状态真的变化时播放，单纯更新时间不会反复闪动。
    private func animateSessionChangeIfNeeded(_ shouldAnimate: Bool) {
        guard shouldAnimate, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }
        sessionsStack.wantsLayer = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.4
        fade.toValue = 1
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = -4
        move.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [fade, move]
        group.duration = 0.22
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        sessionsStack.layer?.add(group, forKey: "session-state-change")
    }

    private func formattedTimestamp(_ value: Double?) -> String {
        guard let value else {
            return "暂无"
        }
        return StatusInfoFormatters.timestamp.string(from: Date(timeIntervalSince1970: value))
    }

    private func localizedSignalName(_ signal: String) -> String {
        switch signal {
        case "tool_done": return "工具完成"
        case "session_start": return "会话开始"
        case "session_end": return "会话结束"
        default: return SignalState(rawValue: signal)?.displayName ?? signal
        }
    }

    @objc private func refreshQuota() {
        refreshQuotaButton.isEnabled = false
        quotaValue.stringValue = "Codex 额度 · 正在读取..."
        quotaReader.fetch { [weak self] state in
            DispatchQueue.main.async {
                self?.refreshQuotaButton.isEnabled = true
                self?.applyQuotaState(state)
            }
        }
    }

    private func applyQuotaState(_ state: CodexQuotaState) {
        switch state {
        case .loading:
            quotaValue.stringValue = "Codex 额度 · 正在读取..."
        case .unavailable(let reason):
            quotaValue.stringValue = "Codex 额度不可用 · \(reason)"
        case .loaded(let snapshot):
            quotaValue.stringValue = "Codex 额度 · \(snapshot.primary.displayTitle(defaultTitle: "5 小时"))剩余 \(snapshot.primary.remainingPercent)% · \(snapshot.secondary.displayTitle(defaultTitle: "7 天"))剩余 \(snapshot.secondary.remainingPercent)%"
        }
    }

    private func makeEyebrow(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 636).isActive = true
        return box
    }

}

/// 滚动列表使用顶部原点，保证会话区域始终从“活跃会话”标题开始显示。
private final class ConversationSectionsStackView: NSStackView {
    override var isFlipped: Bool {
        true
    }
}

/// 状态中心的可交互会话行，统一提供 hover、手型光标、整行点击和键盘激活。
private final class ConversationRowView: NSStackView {
    var threadID: String?
    var source: SessionSource?
    weak var target: AnyObject?
    var action: Selector?
    var baseBackgroundColor: NSColor? { didSet { applyInteractionAppearance() } }
    var baseBorderColor: NSColor? { didSet { applyInteractionAppearance() } }
    var hoverColor: NSColor = .controlAccentColor { didSet { applyInteractionAppearance() } }

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    var isEnabled = true {
        didSet {
            applyInteractionAppearance()
            window?.invalidateCursorRects(for: self)
        }
    }

    override var acceptsFirstResponder: Bool {
        isEnabled
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.5
        setAccessibilityRole(.button)
        applyInteractionAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isEnabled else {
            return
        }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else {
            return
        }
        isHovered = true
        applyInteractionAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        applyInteractionAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }
        window?.makeFirstResponder(self)
        isPressed = true
        applyInteractionAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else {
            return
        }
        let shouldActivate = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        applyInteractionAppearance()
        if shouldActivate, let action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, [36, 49, 76].contains(event.keyCode), let action else {
            super.keyDown(with: event)
            return
        }
        NSApp.sendAction(action, to: target, from: self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyInteractionAppearance()
    }

    private func applyInteractionAppearance() {
        guard let layer else {
            return
        }
        let backgroundColor: NSColor?
        let borderColor: NSColor
        if !isEnabled {
            backgroundColor = baseBackgroundColor
            borderColor = baseBorderColor ?? .separatorColor.withAlphaComponent(0.12)
            alphaValue = 0.72
        } else if isPressed {
            backgroundColor = hoverColor.withAlphaComponent(0.12)
            borderColor = hoverColor.withAlphaComponent(0.32)
            alphaValue = 1
        } else if isHovered {
            backgroundColor = hoverColor.withAlphaComponent(0.075)
            borderColor = hoverColor.withAlphaComponent(0.24)
            alphaValue = 1
        } else {
            backgroundColor = baseBackgroundColor
            borderColor = baseBorderColor ?? .separatorColor.withAlphaComponent(0.16)
            alphaValue = 1
        }
        layer.backgroundColor = backgroundColor?.cgColor ?? NSColor.clear.cgColor
        layer.borderColor = borderColor.cgColor
    }
}

private final class DashboardSignalView: NSView {
    var frameState = SignalFrame(green: 1, yellow: 0, red: 0) {
        didSet {
            needsDisplay = true
        }
    }

    var stateName = "空闲" {
        didSet {
            setAccessibilityValue(stateName)
        }
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAccessibility()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAccessibility()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bodyRect = bounds.insetBy(dx: 8, dy: 4)
        SignalLightVisualStyle.drawBody(in: bodyRect, cornerRadius: 12)

        let radius = min(bodyRect.width * 0.23, bodyRect.height * 0.105)
        let gap = max(8, (bodyRect.height - radius * 6) / 4)
        let lampStep = radius * 2 + gap
        let centerX = bodyRect.midX
        let firstCenterY = bodyRect.minY + gap + radius
        let centersY: [CGFloat] = [
            firstCenterY,
            firstCenterY + lampStep,
            firstCenterY + lampStep * 2,
        ]
        let lamps = SignalLightVisualStyle.orderedLamps(for: frameState)
        for (index, lamp) in lamps.enumerated() {
            SignalLightVisualStyle.drawLamp(
                center: CGPoint(x: centerX, y: centersY[index]),
                radius: radius,
                color: lamp.color,
                brightness: lamp.brightness,
                cupExpansion: radius * 0.24,
                glowExpansion: radius * 0.45
            )
        }
    }

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Agent 状态灯")
        setAccessibilityValue(stateName)
    }

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
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
