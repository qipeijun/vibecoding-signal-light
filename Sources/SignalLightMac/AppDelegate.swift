import AppKit
import Dispatch
import ServiceManagement
import SignalLightShared

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let configStore = SignalLightConfigStore()
    private let threadCatalog = CodexThreadCatalog()
    private var config: SignalLightConfig!
    private var stateStore: SignalStateStore!
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let viewController = SignalViewController()
    private var floatingPanelCoordinator: FloatingPanelCoordinator?
    private let stateDirectoryWatcher = StateDirectoryWatcher()
    private var statusChangeObserver: StatusChangeObserver?
    private var animationTimer: DispatchSourceTimer?
    private var lastFallbackRefresh = Date.distantPast
    private var lastWakeRefresh = Date.distantPast
    private var lastConnectionDiagnostics = Date.distantPast
    private var connectionDiagnosticsGeneration = 0
    private var tick = 0
    private var animationStartedAt = ProcessInfo.processInfo.systemUptime
    private var settingsPopover: NSPopover?
    private var contextMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = configStore.loadOrRepairConfig()
        let agent = configStore.effectiveAgentConfig(from: config)
        stateStore = SignalStateStore(
            stateDirectory: agent.stateDirectory,
            leasePolicy: agent.leasePolicy,
            sessionTTL: agent.sessionTTLSeconds,
            threadCatalog: threadCatalog
        )

        // 根据配置设置激活策略
        if !config.display.showDockIcon {
            NSApp.setActivationPolicy(.accessory)
        }

        buildStatusItem()
        buildFloatingPanel()
        applyDisplayConfig()
        syncLaunchAtLogin()
        viewController.showTouchBar = config.display.showTouchBar
        _ = stateStore.refresh()
        updateViews(refreshRuntimeStatus: true)
        startStatusChangeObserver()
        startStateDirectoryWatcher()
        runConnectionDiagnostics()

        startAnimationTimer()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(configDidChange),
            name: NSNotification.Name("com.vibecoding.signal-light.config-changed"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dismissStatusPopoverForScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dismissStatusPopoverForScreenChange),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleClearSessions),
            name: NSNotification.Name("com.vibecoding.signal-light.clear-sessions"),
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleHookConfigurationChanged),
            name: NSNotification.Name("com.vibecoding.signal-light.hooks-changed"),
            object: nil
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceDidActivateApplication),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(dismissStatusPopoverForScreenChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        animationTimer?.cancel()
        stateDirectoryWatcher.stop()
        statusChangeObserver?.stop()
        floatingPanelCoordinator?.stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func buildStatusItem() {
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusBarButtonClicked)
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])

        // 右键菜单（原 menu 项迁移至此）
        contextMenu = NSMenu()
        contextMenu?.addItem(NSMenuItem(title: "显示/隐藏悬浮窗", action: #selector(togglePanel), keyEquivalent: ""))
        contextMenu?.addItem(NSMenuItem.separator())
        contextMenu?.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        contextMenu?.items.forEach { $0.target = self }
    }

    // MARK: - Popover & Menu

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseDown {
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleSettingsPopover()
        }
    }

    private func toggleSettingsPopover() {
        if let popover = settingsPopover, popover.isShown {
            popover.close()
            return
        }

        let popover = NSPopover()
        popover.contentSize = SettingsTabViewController.statusCenterContentSize
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = SettingsTabViewController(
            configStore: configStore,
            config: config,
            stateStore: stateStore,
            threadCatalog: threadCatalog,
            onOpenSession: { [weak self] threadID, source in
                self?.openSession(threadID: threadID, source: source)
            }
        )
        popover.show(relativeTo: statusItem.button!.bounds, of: statusItem.button!, preferredEdge: .minY)
        settingsPopover = popover
    }

    // MARK: - Config Change Handling

    @objc private func configDidChange() {
        let newConfig = configStore.loadOrRepairConfig()
        let agent = configStore.effectiveAgentConfig(from: newConfig)
        config = newConfig

        // 如果状态目录变更，重建 watcher 和 stateStore
        let oldStateDir = stateStore.stateDirectoryURL.path
        let newStateDir = agent.stateDirectory
        if oldStateDir != newStateDir {
            stateStore = SignalStateStore(
                stateDirectory: newStateDir,
                leasePolicy: agent.leasePolicy,
                sessionTTL: agent.sessionTTLSeconds,
                threadCatalog: threadCatalog
            )
            startStateDirectoryWatcher()
            _ = stateStore.refresh()
        } else {
            stateStore.updateLeasePolicy(agent.leasePolicy, sessionTTL: agent.sessionTTLSeconds)
            _ = stateStore.refresh()
        }

        // 重新应用显示配置
        applyDisplayConfig()
        syncLaunchAtLogin()

        // 动画速度变更
        animationTimer?.cancel()
        resetAnimationPhase()
        startAnimationTimer()

        viewController.showTouchBar = newConfig.display.showTouchBar

        runConnectionDiagnostics()
        updateViews(refreshRuntimeStatus: true)
    }

    @objc private func handleClearSessions() {
        let agent = configStore.effectiveAgentConfig(from: config)
        let stateDir = URL(fileURLWithPath: agent.stateDirectory)
        try? SignalLightStateFiles.clearSessionsAndWriteIdle(in: stateDir)

        _ = stateStore.refresh()
        resetAnimationPhase()
        updateViews(refreshRuntimeStatus: true)
    }

    @objc private func handleHookConfigurationChanged() {
        runConnectionDiagnostics()
    }

    private func startAnimationTimer() {
        // 固定 30fps 刷新，速度设置只改变动画周期，不再通过降低帧率制造阶梯感。
        let interval = 1.0 / 30.0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            self.tick += 1
            let refreshedRuntime = self.refreshStateIfFallbackIntervalElapsed()
            self.updateViews(refreshRuntimeStatus: refreshedRuntime)
            if self.tick.isMultiple(of: 60) {
                self.keepPanelFloating()
            }
        }
        timer.resume()
        animationTimer = timer
    }

    private func buildFloatingPanel() {
        floatingPanelCoordinator = FloatingPanelCoordinator(
            viewController: viewController,
            config: config,
            clickAction: { [weak self] in
                self?.activateCurrentSourceApplication()
            }
        )
    }

    private func applyDisplayConfig() {
        floatingPanelCoordinator?.applyDisplayConfig(config.display)
    }

    private func syncLaunchAtLogin() {
        guard #available(macOS 13.0, *) else {
            return
        }

        do {
            if config.agent.launchAtLogin, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !config.agent.launchAtLogin, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Signal Light login item sync failed: \(error.localizedDescription)")
        }
    }

    private func updateViews(refreshRuntimeStatus: Bool = false) {
        let state = stateStore.effectiveState
        // 用户速度设置仅作用于长期驻留的环境状态，行动提示保持产品定义的固定节奏。
        let safeSpeed = state.allowsAnimationSpeedAdjustment
            ? min(max(config.display.animationSpeed, 0.25), 1.0)
            : 1.0
        let elapsedTime = max(0, ProcessInfo.processInfo.systemUptime - animationStartedAt) * safeSpeed
        let currentFrame = frame(
            for: state,
            elapsedTime: elapsedTime,
            rules: config.statusRules,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        statusItem.button?.image = makeStatusIcon(frameState: currentFrame)
        statusItem.button?.setAccessibilityLabel("Signal Light")
        statusItem.button?.setAccessibilityValue(state.displayName)
        statusItem.button?.toolTip = "Signal Light：\(state.displayName)"
        viewController.update(frameState: currentFrame, stateName: state.displayName)
        if let settings = settingsPopover?.contentViewController as? SettingsTabViewController {
            if refreshRuntimeStatus {
                settings.refreshRuntimeStatus(config: config, stateStore: stateStore, frameState: currentFrame)
            } else {
                settings.updateAnimationFrame(currentFrame)
            }
        }
    }

    @objc private func togglePanel() {
        floatingPanelCoordinator?.togglePanel(display: config.display)
    }

    @objc private func quit() {
        floatingPanelCoordinator?.savePanelFrame()
        NSApp.terminate(nil)
    }

    @objc private func workspaceDidActivateApplication() {
        keepPanelFloating()
    }

    @objc private func workspaceDidWake() {
        recoverAfterWake()
    }

    @objc private func accessibilityDisplayOptionsDidChange() {
        resetAnimationPhase()
        updateViews()
    }

    /// 显示器布局或 macOS Space 切换后，旧锚点已失效，主动关闭状态面板。
    @objc private func dismissStatusPopoverForScreenChange() {
        guard let popover = settingsPopover, popover.isShown else {
            return
        }
        popover.performClose(nil)
        settingsPopover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        if notification.object as? NSPopover === settingsPopover {
            settingsPopover = nil
        }
    }

    private func startStatusChangeObserver() {
        let observer = StatusChangeObserver { [weak self] in
            guard let self else { return }
            self.refreshStateAndViews()
            if self.stateStore.hookIssue != nil {
                self.runConnectionDiagnostics()
            }
        }
        observer.start()
        statusChangeObserver = observer
    }

    private func startStateDirectoryWatcher() {
        stateDirectoryWatcher.start(directoryURL: stateStore.stateDirectoryURL) { [weak self] in
            self?.refreshStateAndViews()
        }
    }

    func refreshStateAndViews() {
        if stateStore.refresh() {
            resetAnimationPhase()
        }
        lastFallbackRefresh = Date()
        updateViews(refreshRuntimeStatus: true)
        keepPanelFloating()
    }

    private func recoverAfterWake() {
        let now = Date()
        guard now.timeIntervalSince(lastWakeRefresh) >= 1 else {
            return
        }
        lastWakeRefresh = now

        animationTimer?.cancel()
        resetAnimationPhase()
        startAnimationTimer()
        startStateDirectoryWatcher()
        refreshStateAndViews()
    }

    private func activateCurrentSourceApplication() {
        _ = stateStore.refresh()
        let sessionState = readSessionState()
        let agent = configStore.effectiveAgentConfig(from: config)
        guard let source = SessionSourceActivation.preferredSource(
            in: sessionState.sessions,
            aggregate: stateStore.state,
            sessionTTL: agent.sessionTTLSeconds,
            leasePolicy: agent.leasePolicy
        ) else {
            return
        }
        SessionSourceActivation.activate(source)
    }

    /// Codex 会话优先走官方 URL Scheme 精确定位；不可导航的会话只激活来源应用。
    private func openSession(threadID: String?, source: SessionSource?) {
        if let threadID,
           let url = codexThreadURL(threadID: threadID),
           NSWorkspace.shared.open(url) {
            return
        }
        if let source {
            SessionSourceActivation.activate(source)
            return
        }
        activateCurrentSourceApplication()
    }

    private func readSessionState() -> SessionState {
        let sessionFile = stateStore.stateDirectoryURL.appendingPathComponent("sessions.json")
        guard let data = try? Data(contentsOf: sessionFile),
              let state = try? JSONDecoder().decode(SessionState.self, from: data)
        else {
            return SessionState(sessions: [:])
        }
        return state
    }

    @discardableResult
    private func refreshStateIfFallbackIntervalElapsed() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastFallbackRefresh) >= 1 else {
            return false
        }
        lastFallbackRefresh = now
        if stateStore.refresh() {
            resetAnimationPhase()
        }
        if now.timeIntervalSince(lastConnectionDiagnostics) >= 300 {
            runConnectionDiagnostics()
        }
        return true
    }

    /// 自动检查只读取本地健康状态；修复仍由诊断页中的显式操作触发。
    private func runConnectionDiagnostics() {
        lastConnectionDiagnostics = Date()
        connectionDiagnosticsGeneration += 1
        let generation = connectionDiagnosticsGeneration
        let configFileURL = configStore.configFileURL()
        let agent = configStore.effectiveAgentConfig(from: config)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var issues: [String] = []
            if (try? Data(contentsOf: configFileURL)) == nil {
                issues.append("配置文件无法读取")
            }

            let stateDirectory = URL(fileURLWithPath: agent.stateDirectory)
            let writablePath = FileManager.default.fileExists(atPath: stateDirectory.path)
                ? stateDirectory.path
                : stateDirectory.deletingLastPathComponent().path
            if !FileManager.default.isWritableFile(atPath: writablePath) {
                issues.append("状态目录不可写")
            }

            switch inspectCodexHookConnection(stateDirectory: stateDirectory) {
            case .missingConfiguration(let message):
                issues.append("Codex Hook 未连接：\(message)")
            case .awaitingFirstEvent:
                issues.append("Codex Hook 已配置，等待首次事件；请在 Codex /hooks 确认信任")
            case .active:
                break
            }

            DispatchQueue.main.async {
                guard let self, generation == self.connectionDiagnosticsGeneration else {
                    return
                }
                if self.stateStore.updateHookIssue(issues.isEmpty ? nil : issues.joined(separator: "；")) {
                    self.resetAnimationPhase()
                }
                self.updateViews(refreshRuntimeStatus: true)
            }
        }
    }

    private func keepPanelFloating(force: Bool = false) {
        floatingPanelCoordinator?.keepFloating(display: config.display, force: force)
    }

    private func resetAnimationPhase() {
        tick = 0
        animationStartedAt = ProcessInfo.processInfo.systemUptime
    }
}
