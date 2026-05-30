import AppKit
import SignalLightShared

final class FloatingPanelCoordinator: NSObject {
    private let viewController: SignalViewController
    private let clickAction: () -> Void
    private var panel: SignalPanel?
    private var shouldShowPanel = true
    private let savedFrameKey = "SignalLightPanelFrame"

    init(viewController: SignalViewController, config: SignalLightConfig, clickAction: @escaping () -> Void) {
        self.viewController = viewController
        self.clickAction = clickAction
        super.init()
        buildPanel(config: config)
        applyDisplayConfig(config.display)
    }

    func applyDisplayConfig(_ display: DisplayConfig) {
        guard let panel else {
            return
        }
        panel.level = display.alwaysOnTop ? .screenSaver : .floating
        panel.alphaValue = display.opacity

        let size = SignalLightView.preferredSize
        let scaled = NSSize(width: size.width * display.windowScale, height: size.height * display.windowScale)
        panel.setContentSize(scaled)
    }

    func togglePanel(display: DisplayConfig) {
        guard let panel else {
            return
        }
        if panel.isVisible {
            shouldShowPanel = false
            savePanelFrame()
            panel.orderOut(nil)
        } else {
            shouldShowPanel = true
            keepFloating(display: display, force: true)
        }
    }

    func keepFloating(display: DisplayConfig, force: Bool = false) {
        guard let panel, shouldShowPanel, force || panel.isVisible else {
            return
        }
        panel.level = display.alwaysOnTop ? .screenSaver : .floating
        panel.orderFrontRegardless()
    }

    func savePanelFrame() {
        guard let frame = panel?.frame else {
            return
        }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: savedFrameKey)
    }

    func stop() {
        savePanelFrame()
        if let panel {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: panel)
        }
    }

    deinit {
        stop()
    }

    private func buildPanel(config: SignalLightConfig) {
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
        panel.clickAction = { [weak self] in
            self?.clickAction()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove),
            name: NSWindow.didMoveNotification,
            object: panel
        )

        self.panel = panel
        shouldShowPanel = config.display.showFloatingWindowAtStartup
        if shouldShowPanel {
            keepFloating(display: config.display, force: true)
        }
    }

    @objc private func panelDidMove() {
        savePanelFrame()
    }

    private func savedPanelFrame() -> NSRect? {
        guard let value = UserDefaults.standard.string(forKey: savedFrameKey) else {
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
