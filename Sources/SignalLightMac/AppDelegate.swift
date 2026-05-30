import AppKit
import Dispatch
import ServiceManagement
import SignalLightShared

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = SignalLightConfigStore()
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
    private var tick = 0
    private var settingsPopover: NSPopover?
    private var contextMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = configStore.loadOrRepairConfig()
        let agent = configStore.effectiveAgentConfig(from: config)
        stateStore = SignalStateStore(stateDirectory: agent.stateDirectory)

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
        updateViews()
        startStatusChangeObserver()
        startStateDirectoryWatcher()

        startAnimationTimer()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(configDidChange),
            name: NSNotification.Name("com.vibecoding.signal-light.config-changed"),
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleClearSessions),
            name: NSNotification.Name("com.vibecoding.signal-light.clear-sessions"),
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        animationTimer?.cancel()
        stateDirectoryWatcher.stop()
        statusChangeObserver?.stop()
        floatingPanelCoordinator?.stop()
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
        popover.contentSize = NSSize(width: 680, height: 540)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = SettingsTabViewController(
            configStore: configStore,
            config: config,
            stateStore: stateStore
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
            stateStore = SignalStateStore(stateDirectory: newStateDir)
            startStateDirectoryWatcher()
            _ = stateStore.refresh()
        }

        // 重新应用显示配置
        applyDisplayConfig()
        syncLaunchAtLogin()

        // 动画速度变更
        animationTimer?.cancel()
        startAnimationTimer()

        viewController.showTouchBar = newConfig.display.showTouchBar

        updateViews()
    }

    @objc private func handleClearSessions() {
        let agent = configStore.effectiveAgentConfig(from: config)
        let stateDir = URL(fileURLWithPath: agent.stateDirectory)
        try? SignalLightStateFiles.clearSessionsAndWriteIdle(in: stateDir)

        _ = stateStore.refresh()
        tick = 0
        updateViews()
    }

    private func startAnimationTimer() {
        let interval = 0.18 / config.display.animationSpeed
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            self.tick += 1
            self.refreshStateIfFallbackIntervalElapsed()
            self.updateViews()
            if self.tick.isMultiple(of: 10) {
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

    private func updateViews() {
        let currentFrame = frame(for: stateStore.state, tick: tick, rules: config.statusRules)
        statusItem.button?.image = makeStatusIcon(frameState: currentFrame)
        viewController.update(frameState: currentFrame)
        (settingsPopover?.contentViewController as? SettingsTabViewController)?
            .refreshRuntimeStatus(config: config, stateStore: stateStore)
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

    private func startStatusChangeObserver() {
        let observer = StatusChangeObserver { [weak self] in
            self?.refreshStateAndViews()
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
            tick = 0
        }
        lastFallbackRefresh = Date()
        updateViews()
        keepPanelFloating()
    }

    private func recoverAfterWake() {
        let now = Date()
        guard now.timeIntervalSince(lastWakeRefresh) >= 1 else {
            return
        }
        lastWakeRefresh = now

        animationTimer?.cancel()
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
            sessionTTL: agent.sessionTTLSeconds
        ) else {
            return
        }
        SessionSourceActivation.activate(source)
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

    private func refreshStateIfFallbackIntervalElapsed() {
        let now = Date()
        guard now.timeIntervalSince(lastFallbackRefresh) >= 3 else {
            return
        }
        lastFallbackRefresh = now
        if stateStore.refresh() {
            tick = 0
        }
    }

    private func keepPanelFloating(force: Bool = false) {
        floatingPanelCoordinator?.keepFloating(display: config.display, force: force)
    }
}
