import Foundation

public enum SignalLightVersion {
    public static var current: String {
        if let version = bundleVersion(from: Bundle.main) {
            return version
        }
        if let version = containingAppBundleVersion() {
            return version
        }
        return "development"
    }

    public static var displayString: String {
        "v\(current)"
    }

    private static func bundleVersion(from bundle: Bundle) -> String? {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return version
    }

    private static func containingAppBundleVersion() -> String? {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        guard let appURL = containingAppBundleURL(for: executableURL),
              let bundle = Bundle(url: appURL)
        else {
            return nil
        }
        return bundleVersion(from: bundle)
    }

    private static func containingAppBundleURL(for executableURL: URL) -> URL? {
        var url = executableURL.standardizedFileURL
        while url.path != "/" {
            if url.pathExtension == "app" {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
