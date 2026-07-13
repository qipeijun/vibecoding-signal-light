import Foundation
import SignalLightShared

final class CursorUsageReader {
    private let timeout: TimeInterval
    private let session: URLSession
    private let databaseURL: URL

    init(
        timeout: TimeInterval = 12,
        session: URLSession = .shared,
        databaseURL: URL = CursorAuthStore.defaultDatabaseURL
    ) {
        self.timeout = timeout
        self.session = session
        self.databaseURL = databaseURL
    }

    func fetch(completion: @escaping (CursorQuotaState) -> Void) {
        DispatchQueue.global(qos: .utility).async { [timeout, session, databaseURL] in
            do {
                let snapshot = try Self.readSnapshot(
                    timeout: timeout,
                    session: session,
                    databaseURL: databaseURL
                )
                completion(.loaded(snapshot))
            } catch {
                completion(.unavailable(Self.userFacingReason(for: error)))
            }
        }
    }

    private static func readSnapshot(
        timeout: TimeInterval,
        session: URLSession,
        databaseURL: URL
    ) throws -> CursorUsageSnapshot {
        guard let credentials = CursorAuthStore.loadCredentials(databaseURL: databaseURL) else {
            throw CursorUsageReaderError.notLoggedIn
        }

        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("signal-light/\(SignalLightVersion.displayString)", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("{}".utf8)

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(CursorUsageReaderError.networkUnavailable)

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
                semaphore.signal()
                return
            }
            guard let http = response as? HTTPURLResponse else {
                result = .failure(CursorUsageReaderError.invalidResponse)
                semaphore.signal()
                return
            }
            guard (200..<300).contains(http.statusCode), let data else {
                result = .failure(CursorUsageReaderError.httpStatus(http.statusCode))
                semaphore.signal()
                return
            }
            result = .success(data)
            semaphore.signal()
        }
        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + timeout + 1)
        guard waitResult == .success else {
            task.cancel()
            throw CursorUsageReaderError.timeout
        }

        let data = try result.get()
        return try CursorUsagePayload.decodeSnapshot(
            from: data,
            planType: credentials.planType,
            email: credentials.email
        )
    }

    private static func userFacingReason(for error: Error) -> String {
        if let readerError = error as? CursorUsageReaderError {
            return readerError.localizedDescription
        }
        if let decodingError = error as? CursorUsageDecodingError {
            return decodingError.localizedDescription
        }
        let message = error.localizedDescription
        let lowercased = message.lowercased()
        if lowercased.contains("auth") || lowercased.contains("401") || lowercased.contains("403") {
            return "Cursor 登录已失效，请重新登录"
        }
        if lowercased.contains("network")
            || lowercased.contains("offline")
            || lowercased.contains("timed out")
            || lowercased.contains("could not connect")
        {
            return "Cursor 网络不可达，暂时无法读取额度"
        }
        return "读取 Cursor 额度失败: \(message)"
    }
}

private enum CursorUsageReaderError: Error, LocalizedError {
    case notLoggedIn
    case networkUnavailable
    case invalidResponse
    case httpStatus(Int)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "未找到 Cursor 登录信息"
        case .networkUnavailable:
            return "无法连接 Cursor 服务"
        case .invalidResponse:
            return "Cursor 返回了无法识别的响应"
        case .httpStatus(let status):
            if status == 401 || status == 403 {
                return "Cursor 登录已失效，请重新登录"
            }
            return "Cursor 服务返回 HTTP \(status)"
        case .timeout:
            return "读取 Cursor 额度超时"
        }
    }
}
