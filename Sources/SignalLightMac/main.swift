import AppKit

if CommandLine.arguments.contains("--capture-readme-screenshots") {
    let outputPath = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "docs/images"
    do {
        try ReadmeScreenshotCapture.run(outputPath: outputPath)
        exit(0)
    } catch {
        fputs("生成 README 截图失败: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
