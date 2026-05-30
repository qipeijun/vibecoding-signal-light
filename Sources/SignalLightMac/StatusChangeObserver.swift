import AppKit
import CoreFoundation

private let statusChangedNotificationName = "com.vibecoding.signal-light.status-changed"
private let statusChangedCFNotificationName = statusChangedNotificationName as CFString
private let statusChangedNotification = Notification.Name(statusChangedNotificationName)

private let signalStatusChangedCallback: CFNotificationCallback = { _, observer, _, _, _ in
    guard let observer else {
        return
    }
    let statusObserver = Unmanaged<StatusChangeObserver>.fromOpaque(observer).takeUnretainedValue()
    DispatchQueue.main.async {
        statusObserver.handleStatusChanged()
    }
}

final class StatusChangeObserver: NSObject {
    private let onStatusChanged: () -> Void
    private var isStarted = false

    init(onStatusChanged: @escaping () -> Void) {
        self.onStatusChanged = onStatusChanged
    }

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterAddObserver(
            center,
            observer,
            signalStatusChangedCallback,
            statusChangedCFNotificationName,
            nil,
            .deliverImmediately
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(distributedStatusDidChange),
            name: statusChangedNotification,
            object: nil
        )
    }

    func stop() {
        guard isStarted else {
            return
        }
        isStarted = false

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(statusChangedCFNotificationName), nil)
        DistributedNotificationCenter.default().removeObserver(self, name: statusChangedNotification, object: nil)
    }

    deinit {
        stop()
    }

    fileprivate func handleStatusChanged() {
        onStatusChanged()
    }

    @objc private func distributedStatusDidChange() {
        handleStatusChanged()
    }
}
