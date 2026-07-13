import Foundation
import SQLite3

struct CursorAuthCredentials: Equatable {
    var accessToken: String
    var email: String?
    var planType: String?
}

enum CursorAuthStore {
    static let defaultDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb", isDirectory: false)

    static func loadCredentials(databaseURL: URL = defaultDatabaseURL) -> CursorAuthCredentials? {
        guard FileManager.default.isReadableFile(atPath: databaseURL.path) else {
            return nil
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            return nil
        }
        defer {
            sqlite3_close(database)
        }

        guard let accessToken = queryValue(key: "cursorAuth/accessToken", database: database),
              !accessToken.isEmpty
        else {
            return nil
        }

        return CursorAuthCredentials(
            accessToken: accessToken,
            email: queryValue(key: "cursorAuth/cachedEmail", database: database),
            planType: queryValue(key: "cursorAuth/stripeMembershipType", database: database)
        )
    }

    private static func queryValue(key: String, database: OpaquePointer) -> String? {
        let sql = "SELECT value FROM ItemTable WHERE key = ?1 LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else {
            return nil
        }

        let value = String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
