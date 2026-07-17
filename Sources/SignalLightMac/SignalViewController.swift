import AppKit
import SignalLightShared

final class SignalViewController: NSViewController, NSTouchBarDelegate {
    let signalView = SignalLightView(frame: NSRect(origin: .zero, size: SignalLightView.preferredSize))
    private var touchBarView: TouchBarSignalView?
    var showTouchBar = true {
        didSet {
            if !showTouchBar {
                touchBarView = nil
                touchBar = nil
            }
        }
    }

    override func loadView() {
        let rootView = NSView(frame: signalView.frame)
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor

        signalView.frame = rootView.bounds
        signalView.autoresizingMask = [.width, .height]

        rootView.addSubview(signalView)
        view = rootView
    }

    func update(frameState: SignalFrame, stateName: String) {
        signalView.frameState = frameState
        signalView.stateName = stateName
        touchBarView?.frameState = frameState
        touchBarView?.stateName = stateName
    }

    @available(macOS 10.12.2, *)
    override func makeTouchBar() -> NSTouchBar? {
        guard showTouchBar else {
            return nil
        }
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
        touchView.stateName = signalView.stateName
        touchBarView = touchView
        item.view = touchView
        return item
    }
}

@available(macOS 10.12.2, *)
private extension NSTouchBarItem.Identifier {
    static let signalLight = NSTouchBarItem.Identifier("com.vibecoding.signal-light.touchbar")
}
