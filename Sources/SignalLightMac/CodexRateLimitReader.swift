import Foundation
import SignalLightShared

final class CodexRateLimitReader {
    private let timeout: TimeInterval
    private let environment: [String: String]

    init(timeout: TimeInterval = 12, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.timeout = timeout
        self.environment = environment
    }

    func fetch(completion: @escaping (CodexQuotaState) -> Void) {
        DispatchQueue.global(qos: .utility).async { [timeout, environment] in
            do {
                let snapshot = try Self.readSnapshot(timeout: timeout, environment: environment)
                completion(.loaded(snapshot))
            } catch {
                completion(.unavailable(Self.userFacingReason(for: error)))
            }
        }
    }

    private static func readSnapshot(timeout: TimeInterval, environment: [String: String]) throws -> CodexRateLimitSnapshot {
        guard let codexURL = findCodexExecutable(environment: environment) else {
            throw CodexRateLimitReaderError.codexNotInstalled
        }

        let process = Process()
        process.executableURL = codexURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = processEnvironment(from: environment)

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        let client = JSONRPCLineClient(
            output: outputPipe.fileHandleForReading,
            input: inputPipe.fileHandleForWriting
        )

        do {
            try process.run()
        } catch {
            throw CodexRateLimitReaderError.launchFailed(error.localizedDescription)
        }

        defer {
            client.stop()
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? errorPipe.fileHandleForReading.close()
            if process.isRunning {
                process.terminate()
            }
        }

        try client.send([
            "id": "initialize",
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "signal-light",
                    "title": "Signal Light",
                    "version": SignalLightVersion.displayString,
                ],
                "capabilities": [
                    "experimentalApi": true,
                    "requestAttestation": false,
                    "optOutNotificationMethods": [
                        "thread/started",
                        "thread/status/changed",
                        "thread/tokenUsage/updated",
                    ],
                ],
            ],
        ])
        _ = try client.waitForResponse(id: "initialize", timeout: timeout)

        try client.send([
            "method": "initialized",
        ])

        try client.send([
            "id": "codex-rate-limits",
            "method": "account/rateLimits/read",
        ])
        let result = try client.waitForResponse(id: "codex-rate-limits", timeout: timeout)
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return try CodexRateLimitPayload.decodeSnapshot(from: resultData)
    }

    private static func findCodexExecutable(environment: [String: String]) -> URL? {
        let fileManager = FileManager.default
        let pathCandidates = SignalLightPaths.pathEntries(from: environment["PATH"]).map { "\($0)/codex" }
        let fallbackCandidates = [
            SignalLightPaths.bundledCodexExecutable,
            SignalLightPaths.npmCodexExecutable,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        let candidates = pathCandidates + fallbackCandidates

        for candidate in candidates {
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    private static func processEnvironment(from environment: [String: String]) -> [String: String] {
        var next = environment
        next["PATH"] = SignalLightPaths.mergePath(next["PATH"])
        return next
    }

    private static func userFacingReason(for error: Error) -> String {
        if let readerError = error as? CodexRateLimitReaderError {
            return readerError.localizedDescription
        }
        if let decodingError = error as? CodexRateLimitDecodingError {
            return decodingError.localizedDescription
        }
        let message = error.localizedDescription
        let lowercased = message.lowercased()
        if lowercased.contains("auth") || lowercased.contains("login") || lowercased.contains("credential") {
            return "Codex 未登录或认证已失效"
        }
        if lowercased.contains("network")
            || lowercased.contains("dns")
            || lowercased.contains("timed out")
            || lowercased.contains("operation not permitted")
            || lowercased.contains("unreachable")
        {
            return "Codex 网络不可达，暂时无法读取额度"
        }
        return "读取 Codex 额度失败: \(message)"
    }
}

private enum CodexRateLimitReaderError: Error, LocalizedError {
    case codexNotInstalled
    case launchFailed(String)
    case writeFailed
    case timeout(String)
    case serverError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .codexNotInstalled:
            return "未找到 Codex CLI"
        case .launchFailed(let message):
            return "启动 Codex app-server 失败: \(message)"
        case .writeFailed:
            return "无法向 Codex app-server 发送请求"
        case .timeout(let id):
            return "读取 Codex 额度超时: \(id)"
        case .serverError(let message):
            return message
        case .invalidResponse:
            return "Codex app-server 返回了无法识别的响应"
        }
    }
}

private final class JSONRPCLineClient {
    private let output: FileHandle
    private let input: FileHandle
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var responses: [String: Result<[String: Any], Error>] = [:]

    init(output: FileHandle, input: FileHandle) {
        self.output = output
        self.input = input
        output.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData)
        }
    }

    deinit {
        stop()
    }

    func stop() {
        output.readabilityHandler = nil
        try? input.close()
        try? output.close()
    }

    func send(_ message: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(message),
              var data = try? JSONSerialization.data(withJSONObject: message)
        else {
            throw CodexRateLimitReaderError.writeFailed
        }
        data.append(0x0A)
        do {
            try input.write(contentsOf: data)
        } catch {
            throw CodexRateLimitReaderError.writeFailed
        }
    }

    func waitForResponse(id: String, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let response = responses.removeValue(forKey: id)
            lock.unlock()
            if let response {
                return try response.get()
            }

            let remaining = max(0.05, min(0.25, deadline.timeIntervalSinceNow))
            _ = semaphore.wait(timeout: .now() + remaining)
        }
        throw CodexRateLimitReaderError.timeout(id)
    }

    private func append(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)
            parseLine(Data(line))
        }
        lock.unlock()
        semaphore.signal()
    }

    private func parseLine(_ data: Data) {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idValue = object["id"]
        else {
            return
        }

        let id = String(describing: idValue)
        if let error = object["error"] as? [String: Any] {
            responses[id] = .failure(CodexRateLimitReaderError.serverError(serverErrorMessage(from: error)))
            return
        }
        guard let result = object["result"] as? [String: Any] else {
            responses[id] = .failure(CodexRateLimitReaderError.invalidResponse)
            return
        }
        responses[id] = .success(result)
    }

    private func serverErrorMessage(from error: [String: Any]) -> String {
        if let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        return "Codex app-server 返回错误"
    }
}
