import Foundation

/// 安装、升级和卸载时的文件所有权规则。
///
/// 可配置状态目录可能与用户的其他文件共存，因此这里只允许删除 Signal Light
/// 明确定义的状态文件，绝不递归删除整个目录。
public enum SignalLightInstallLifecycle {
    public static let appBundleIdentifier = "com.vibecoding.signal-light"
    public static let stateFileNames = [
        "current_status.json",
        "sessions.json",
        "history.json",
        "codex_hook_activity.json",
        "state.lock",
    ]

    /// 删除状态目录中的已知文件并保留目录本身以及所有未知文件。
    @discardableResult
    public static func removeOwnedStateFiles(
        in stateDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        var removed: [URL] = []
        for name in stateFileNames {
            let url = stateDirectory.appendingPathComponent(name, isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }
            try fileManager.removeItem(at: url)
            removed.append(url)
        }
        return removed
    }

    /// 仅识别由 Signal Light 安装器生成的命令 wrapper 或指向 App bundle 的符号链接。
    public static func ownsInstalledCommand(at url: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        let ownedTargets = [
            "/Applications/Signal Light.app/Contents/Resources/bin/signal-light",
            "/Applications/Signal Light.app/Contents/Resources/bin/codex-signal-hook",
            "/Applications/Signal Light.app/Contents/Resources/bin/claude-code-signal-hook",
        ]

        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path),
           ownedTargets.contains(destination) {
            return true
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue <= 64 * 1024,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              text.hasPrefix("#!")
        else {
            return false
        }

        return ownedTargets.contains { target in
            text.contains("exec \"\(target)\"") || text.contains("exec '\(target)'")
        }
    }

    /// 旧 Claude wrapper 只有在归属明确时才允许迁移删除。
    @discardableResult
    public static func removeOwnedLegacyClaudeCommand(
        at url: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard ownsInstalledCommand(at: url, fileManager: fileManager) else {
            return false
        }
        try fileManager.removeItem(at: url)
        return true
    }

    /// 校验指定 App bundle 确实属于 Signal Light，避免仅凭路径删除其他应用。
    public static func ownsInstalledApp(at url: URL, fileManager: FileManager = .default) -> Bool {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let identifier = info["CFBundleIdentifier"] as? String
        else {
            return false
        }
        return identifier == appBundleIdentifier
    }
}
