import AppKit

final class SignalPanel: NSPanel {
    var clickAction: (() -> Void)?
    private var mouseDownLocation: CGPoint?
    private var didDragSinceMouseDown = false
    private let clickDragThreshold: CGFloat = 4

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownLocation = screenPoint(for: event)
            didDragSinceMouseDown = false
        case .leftMouseDragged:
            markDragIfNeeded(event)
        case .leftMouseUp:
            let shouldClick = mouseDownLocation != nil && !didDragSinceMouseDown
            super.sendEvent(event)
            mouseDownLocation = nil
            didDragSinceMouseDown = false
            if shouldClick {
                clickAction?()
            }
            return
        default:
            break
        }

        super.sendEvent(event)
    }

    private func markDragIfNeeded(_ event: NSEvent) {
        guard let start = mouseDownLocation else {
            return
        }
        let current = screenPoint(for: event)
        let distance = hypot(current.x - start.x, current.y - start.y)
        if distance > clickDragThreshold {
            didDragSinceMouseDown = true
        }
    }

    private func screenPoint(for event: NSEvent) -> CGPoint {
        convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
    }
}
