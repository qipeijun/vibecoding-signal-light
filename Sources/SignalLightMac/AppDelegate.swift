import AppKit
import CoreFoundation
import Darwin
import Dispatch
import ServiceManagement
import SignalLightShared

private let statusChangedNotificationName = "com.vibecoding.signal-light.status-changed"
private let statusChangedCFNotificationName = statusChangedNotificationName as CFString
private let statusChangedNotification = Notification.Name(statusChangedNotificationName)

private let statusChangedCallback: CFNotificationCallback = { _, observer, _, _, _ in
    guard let observer else {
        return
    }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
    DispatchQueue.main.async {
        delegate.refreshStateAndViews()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = SignalLightConfigStore()
    private var config: SignalLightConfig!
    private var stateStore: SignalStateStore!
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let viewController = SignalViewController()
    private var panel: NSPanel?
    private var animationTimer: DispatchSourceTimer?
    private var stateDirectorySource: DispatchSourceFileSystemObject?
    private var lastFallbackRefresh = Date.distantPast
    private var tick = 0
    private var shouldShowPanel = true
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
        buildPanel()
        applyDisplayConfig()
        syncLaunchAtLogin()
        viewController.showTouchBar = config.display.showTouchBar
        _ = stateStore.refresh()
        updateViews()
        startDarwinStatusNotification()
        startStateDirectoryWatcher()

        startAnimationTimer()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(signalStatusDidChange),
            name: statusChangedNotification,
            object: nil
        )

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

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidActivateApplication),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        animationTimer?.cancel()
        stateDirectorySource?.cancel()
        stopDarwinStatusNotification()
        savePanelFrame()
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
            config: config
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
            stateDirectorySource?.cancel()
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
        let sessionFile = stateDir.appendingPathComponent("sessions.json")
        let currentStatusFile = stateDir.appendingPathComponent("current_status.json")

        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

        let emptyState = SessionState(sessions: [:])
        if let data = try? JSONEncoder().encode(emptyState) {
            try? data.write(to: sessionFile, options: .atomic)
        }

        let idleStatus = CurrentStatus(aggregate: "idle", updatedAt: Date().timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(idleStatus) {
            try? data.write(to: currentStatusFile, options: .atomic)
        }

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

    private func buildPanel() {
        let frame = savedPanelFrame() ?? defaultPanelFrame()
        let panel = SignalPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = viewController
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = config.display.alwaysOnTop ? .screenSaver : .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove),
            name: NSWindow.didMoveNotification,
            object: panel
        )

        self.panel = panel
        shouldShowPanel = config.display.showFloatingWindowAtStartup
        if shouldShowPanel {
            keepPanelFloating(force: true)
        }
    }

    private func applyDisplayConfig() {
        guard let panel else { return }
        panel.level = config.display.alwaysOnTop ? .screenSaver : .floating
        panel.alphaValue = config.display.opacity

        let size = SignalLightView.preferredSize
        let scaled = NSSize(width: size.width * config.display.windowScale, height: size.height * config.display.windowScale)
        panel.setContentSize(scaled)
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
    }

    @objc private func togglePanel() {
        guard let panel else {
            return
        }
        if panel.isVisible {
            shouldShowPanel = false
            savePanelFrame()
            panel.orderOut(nil)
        } else {
            shouldShowPanel = true
            keepPanelFloating(force: true)
        }
    }

    @objc private func quit() {
        savePanelFrame()
        NSApp.terminate(nil)
    }

    @objc private func panelDidMove() {
        savePanelFrame()
    }

    @objc private func workspaceDidActivateApplication() {
        keepPanelFloating()
    }

    @objc private func signalStatusDidChange() {
        refreshStateAndViews()
    }

    private func startDarwinStatusNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterAddObserver(
            center,
            observer,
            statusChangedCallback,
            statusChangedCFNotificationName,
            nil,
            .deliverImmediately
        )
    }

    private func stopDarwinStatusNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(statusChangedCFNotificationName), nil)
    }

    private func startStateDirectoryWatcher() {
        try? FileManager.default.createDirectory(
            at: stateStore.stateDirectoryURL,
            withIntermediateDirectories: true
        )

        let descriptor = open(stateStore.stateDirectoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.refreshStateAndViews()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        stateDirectorySource = source
    }

    func refreshStateAndViews() {
        if stateStore.refresh() {
            tick = 0
        }
        lastFallbackRefresh = Date()
        updateViews()
        keepPanelFloating()
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
        guard let panel, shouldShowPanel, force || panel.isVisible else {
            return
        }
        panel.level = config.display.alwaysOnTop ? .screenSaver : .floating
        panel.orderFrontRegardless()
    }

    private func savePanelFrame() {
        guard let frame = panel?.frame else {
            return
        }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "SignalLightPanelFrame")
    }

    private func savedPanelFrame() -> NSRect? {
        guard let value = UserDefaults.standard.string(forKey: "SignalLightPanelFrame") else {
            return nil
        }
        var frame = NSRectFromString(value)
        frame.size = panelSize
        return frame.isEmpty ? nil : frame
    }

    private func defaultPanelFrame() -> NSRect {
        let size = panelSize
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        return NSRect(
            x: screenFrame.maxX - size.width - 18,
            y: screenFrame.maxY - size.height - 42,
            width: size.width,
            height: size.height
        )
    }

    private var panelSize: NSSize {
        SignalLightView.preferredSize
    }
}
