import AppKit

extension NSViewController {
    func showSettingsError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "设置操作失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        if let window = view.window ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }

    /// 对清空、重建和恢复默认等不可撤销操作进行统一确认。
    func confirmSettingsAction(title: String, message: String, actionTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: actionTitle)
        return alert.runModal() == .alertSecondButtonReturn
    }
}
