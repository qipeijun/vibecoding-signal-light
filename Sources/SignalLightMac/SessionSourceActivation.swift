import AppKit
import Foundation
import SignalLightShared

enum SessionSourceActivation {
    static func preferredSource(
        in sessions: [String: SessionRecord],
        preferred: PreferredAgentSource,
        sessionTTL: Double,
        now: Double = Date().timeIntervalSince1970
    ) -> SessionSource? {
        preferredSessionRecord(
            in: sessions,
            preferred: preferred,
            now: now,
            sessionTTL: sessionTTL,
            excludingEndSignals: true
        )?.source
    }

    static func activate(_ source: SessionSource) {
        if let app = runningApplication(byProcessIdentifier: source.processIdentifier, source: source) {
            if activate(app) {
                return
            }
        }

        guard let bundleIdentifier = source.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty
        else {
            return
        }

        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated }) {
            if activate(app) {
                return
            }
        }

        openBundleIdentifier(bundleIdentifier)
    }

    private static func runningApplication(
        byProcessIdentifier processIdentifier: Int?,
        source: SessionSource
    ) -> NSRunningApplication? {
        guard let processIdentifier,
              processIdentifier > 0,
              processIdentifier <= Int(Int32.max),
              let app = NSRunningApplication(processIdentifier: pid_t(processIdentifier)),
              !app.isTerminated
        else {
            return nil
        }

        if let bundleIdentifier = source.bundleIdentifier,
           !bundleIdentifier.isEmpty,
           app.bundleIdentifier != bundleIdentifier {
            return nil
        }
        return app
    }

    private static func activate(_ app: NSRunningApplication) -> Bool {
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private static func openBundleIdentifier(_ bundleIdentifier: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleIdentifier]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
