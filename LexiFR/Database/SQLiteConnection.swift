import Foundation
import SQLite3

enum SQLiteValue: Sendable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case null

    var string: String? {
        if case let .text(value) = self { return value }
        return nil
    }

    var int: Int? {
        if case let .integer(value) = self { return Int(value) }
        return nil
    }

    var int64: Int64? {
        if case let .integer(value) = self { return value }
        return nil
    }

    var double: Double? {
        switch self {
        case let .real(value): value
        case let .integer(value): Double(value)
        default: nil
        }
    }
}

enum DatabaseError: LocalizedError {
    case open(String)
    case prepare(String)
    case bind(String)
    case step(String)

    var errorDescription: String? {
        switch self {
        case let .open(message): "Ouverture de la base impossible : \(message)"
        case let .prepare(message): "Requête SQLite invalide : \(message)"
        case let .bind(message): "Paramètre SQLite invalide : \(message)"
        case let .step(message): "Lecture SQLite impossible : \(message)"
        }
    }
}

final class SQLiteConnection: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private(set) var preparedStatementCount = 0

    init(url: URL, readOnly: Bool) throws {
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "erreur inconnue"
            sqlite3_close(handle)
            handle = nil
            throw DatabaseError.open(message)
        }
        sqlite3_busy_timeout(handle, 2_000)
        if readOnly {
            try execute("PRAGMA query_only = ON")
        } else {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
        }
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        
        while true {
            let status = sqlite3_step(statement)

            if status == SQLITE_DONE {
                return
            }

            if status == SQLITE_ROW {
                continue
            }

            throw DatabaseError.step(errorMessage)
        }
    }

    func rows(_ sql: String, bindings: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        var result: [[String: SQLiteValue]] = []
        while true {
            if result.count.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw DatabaseError.step(errorMessage) }
            var row: [String: SQLiteValue] = [:]
            for index in 0 ..< sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    row[name] = .real(sqlite3_column_double(statement, index))
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, index) {
                        row[name] = .text(String(cString: text))
                    } else {
                        row[name] = .null
                    }
                default:
                    row[name] = .null
                }
            }
            result.append(row)
        }
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    private func prepare(_ sql: String, bindings: [SQLiteValue]) throws -> OpaquePointer {
        guard handle != nil else { throw DatabaseError.prepare("base fermée") }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw DatabaseError.prepare(errorMessage)
        }
        do {
            let expectedBindings = Int(sqlite3_bind_parameter_count(statement))
            guard expectedBindings == bindings.count else {
                throw DatabaseError.bind("\(expectedBindings) paramètre(s) attendu(s), \(bindings.count) reçu(s)")
            }
            for (offset, value) in bindings.enumerated() {
                let index = Int32(offset + 1)
                let status: Int32
                switch value {
                case let .integer(value): status = sqlite3_bind_int64(statement, index, value)
                case let .real(value): status = sqlite3_bind_double(statement, index, value)
                case let .text(value): status = sqlite3_bind_text(statement, index, value, -1, transient)
                case .null: status = sqlite3_bind_null(statement, index)
                }
                guard status == SQLITE_OK else { throw DatabaseError.bind(errorMessage) }
            }
            preparedStatementCount += 1
            return statement
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
    }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "base fermée"
    }
}
