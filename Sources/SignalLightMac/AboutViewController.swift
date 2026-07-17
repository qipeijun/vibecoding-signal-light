import AppKit
import SignalLightShared

final class AboutViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 390))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 8, right: 4)
        stack.alignment = .leading

        let title = NSTextField(labelWithString: "Signal Light")
        title.font = NSFont.boldSystemFont(ofSize: 20)
        stack.addArrangedSubview(title)

        let version = NSTextField(labelWithString: "版本 \(SignalLightVersion.displayString)")
        version.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        version.textColor = .secondaryLabelColor
        stack.addArrangedSubview(version)

        stack.addArrangedSubview(makeSeparator())

        let summary = NSTextField(labelWithString: "给 Codex 一个看得见、能分清风险优先级的 macOS 状态灯。")
        summary.font = NSFont.systemFont(ofSize: 13)
        summary.lineBreakMode = .byWordWrapping
        summary.preferredMaxLayoutWidth = 500
        stack.addArrangedSubview(summary)

        let repoButton = NSButton(title: "打开项目主页", target: self, action: #selector(openRepository))
        repoButton.bezelStyle = .rounded
        repoButton.controlSize = .small
        stack.addArrangedSubview(repoButton)

        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: 512),
        ])
    }

    @objc private func openRepository() {
        guard let url = URL(string: "https://github.com/qipeijun/vibecoding-signal-light") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
