import AppKit
import CoreFoundation
import Darwin
import Dispatch

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
    private let stateStore = SignalStateStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let viewController = SignalViewController()
    private var panel: NSPanel?
    private var animationTimer: DispatchSourceTimer?
    private var stateDirectorySource: DispatchSourceFileSystemObject?
    private var lastFallbackRefresh = Date.distantPast
    private var tick = 0
    private var shouldShowPanel = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        buildPanel()
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
        statusItem.button?.action = #selector(togglePanel)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示/隐藏悬浮窗", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func startAnimationTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.18, repeating: 0.18)
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
        panel.level = .screenSaver
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
        keepPanelFloating(force: true)
    }

    private func updateViews() {
        let currentFrame = frame(for: stateStore.state, tick: tick)
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
        panel.level = .screenSaver
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
