import Foundation
import SQLite3

enum SQLiteDatabaseError: Error, Equatable {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

final class SQLiteDatabase {
    let handle: OpaquePointer

    init(url: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open(url.path, &database)

        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Unable to open database"
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteDatabaseError.openFailed(message)
        }

        handle = database
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }

        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(handle))
            throw SQLiteDatabaseError.executeFailed(message)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)

        guard result == SQLITE_OK, let statement else {
            throw SQLiteDatabaseError.prepareFailed(
                String(cString: sqlite3_errmsg(handle))
            )
        }

        return statement
    }
}
