import Foundation

public enum SignalLightPaths {
    public static let codexHookCommand = "/usr/local/bin/codex-signal-hook"
    public static let claudeHookCommand = "/usr/local/bin/claude-code-signal-hook"
    public static let cursorHookCommand = "/usr/local/bin/cursor-signal-hook"

    public static let commonExecutableDirectories = [
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/Applications/Codex.app/Contents/Resources",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
        "/usr/libexec",
    ]

    public static let bundledCodexExecutable = "/Applications/Codex.app/Contents/Resources/codex"
    public static let npmCodexExecutable = "/usr/local/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"

    public static func mergePath(_ path: String?) -> String {
        var entries: [String] = []
        var seen = Set<String>()

        for entry in pathEntries(from: path) + commonExecutableDirectories {
            if seen.insert(entry).inserted {
                entries.append(entry)
            }
        }
        return entries.joined(separator: ":")
    }

    public static func pathEntries(from path: String?) -> [String] {
        guard let path, !path.isEmpty else {
            return []
        }
        return path
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
