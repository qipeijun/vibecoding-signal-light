import AppKit

final class SignalViewController: NSViewController, NSTouchBarDelegate {
    let signalView = SignalLightView(frame: NSRect(origin: .zero, size: SignalLightView.preferredSize))
    private var touchBarView: TouchBarSignalView?

    override func loadView() {
        let rootView = NSView(frame: signalView.frame)
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 11
        rootView.layer?.cornerCurve = .continuous
        rootView.layer?.masksToBounds = true

        let visualEffect = NSVisualEffectView(frame: rootView.bounds.insetBy(dx: 5, dy: 5))
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 11
        visualEffect.layer?.cornerCurve = .continuous
        visualEffect.layer?.masksToBounds = true

        signalView.frame = rootView.bounds
        signalView.autoresizingMask = [.width, .height]

        rootView.addSubview(visualEffect)
        rootView.addSubview(signalView)
        view = rootView
    }

    func update(frameState: SignalFrame) {
        signalView.frameState = frameState
        touchBarView?.frameState = frameState
    }

    @available(macOS 10.12.2, *)
    override func makeTouchBar() -> NSTouchBar? {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [.signalLight]
        return touchBar
    }

    @available(macOS 10.12.2, *)
    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard identifier == .signalLight else {
            return nil
        }

        let item = NSCustomTouchBarItem(identifier: identifier)
        let touchView = TouchBarSignalView(frame: NSRect(x: 0, y: 0, width: 132, height: 30))
        touchBarView = touchView
        item.view = touchView
        return item
    }
}

@available(macOS 10.12.2, *)
private extension NSTouchBarItem.Identifier {
    static let signalLight = NSTouchBarItem.Identifier("com.vibecoding.signal-light.touchbar")
}
