import AppKit
import Foundation
import SignalLightShared

enum SessionSourceActivation {
    static func preferredSource(
        in sessions: [String: SessionRecord],
        aggregate: SignalState,
        sessionTTL: Double,
        now: Double = Date().timeIntervalSince1970
    ) -> SessionSource? {
        let candidates = sessions.values.filter { record in
            record.source != nil
                && !sessionEndSignals.contains(record.signal)
                && now - record.updatedAt <= sessionTTL
        }

        if let targetSignals = targetSignals(for: aggregate) {
            return latestRecord(in: candidates, matching: targetSignals)?.source
        }

        return candidates.max { $0.updatedAt < $1.updatedAt }?.source
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

    private static func targetSignals(for aggregate: SignalState) -> Set<String>? {
        switch aggregate {
        case .permission, .blocked:
            return redSignals
        case .attention:
            return yellowSignals
        case .thinking, .working, .toolDone:
            return workingSignals
        case .idle, .done, .sessionStart, .sessionEnd, .off:
            return nil
        }
    }

    private static func latestRecord(
        in records: [SessionRecord],
        matching signals: Set<String>
    ) -> SessionRecord? {
        records
            .filter { signals.contains($0.signal) }
            .max { $0.updatedAt < $1.updatedAt }
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
