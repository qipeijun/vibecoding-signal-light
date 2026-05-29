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
}
