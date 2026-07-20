//
//  GraphSearchSQLite.swift
//  BrainMesh
//
//  Minimal prepared-statement wrapper around the system SQLite3 API.
//

import Foundation
import SQLite3

nonisolated struct GraphSearchSQLiteError: Error, Sendable {
    let code: Int32
    let extendedCode: Int32
    let message: String
    let operation: String

    var primaryCode: Int32 {
        code & 0xFF
    }

    var isCorruption: Bool {
        primaryCode == SQLITE_CORRUPT || primaryCode == SQLITE_NOTADB
    }

    var isFTS5Unavailable: Bool {
        message.localizedCaseInsensitiveContains("no such module: fts5")
    }

    var isFTSTokenizerUnavailable: Bool {
        message.localizedCaseInsensitiveContains("no such tokenizer:")
            || message.localizedCaseInsensitiveContains("error in tokenizer constructor")
            || message.localizedCaseInsensitiveContains("parse error in tokenize directive")
    }

    var isSearchSchemaUnavailable: Bool {
        let foldedMessage = message.lowercased()
        return foldedMessage.contains("no such table: graph_search_")
            || foldedMessage.contains("no such column:")
            || foldedMessage.contains("malformed database schema")
    }
}

nonisolated enum GraphSearchSQLiteBinding {
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

nonisolated final class GraphSearchSQLiteConnection {
    private(set) var handle: OpaquePointer?

    init(databaseURL: URL) throws {
        var openedHandle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &openedHandle, flags, nil)

        guard result == SQLITE_OK, let openedHandle else {
            let error = Self.makeError(
                handle: openedHandle,
                fallbackCode: result,
                operation: "open"
            )
            if let openedHandle {
                sqlite3_close_v2(openedHandle)
            }
            throw error
        }

        handle = openedHandle
        sqlite3_extended_result_codes(openedHandle, 1)
    }

    deinit {
        if let handle {
            sqlite3_close_v2(handle)
        }
    }

    func close() throws {
        guard let handle else { return }
        let result = sqlite3_close(handle)
        guard result == SQLITE_OK else {
            throw Self.makeError(
                handle: handle,
                fallbackCode: result,
                operation: "close"
            )
        }
        self.handle = nil
    }

    func closeForReplacement() throws {
        guard let handle else { return }
        let result = sqlite3_close_v2(handle)
        guard result == SQLITE_OK else {
            throw Self.makeError(
                handle: handle,
                fallbackCode: result,
                operation: "close-for-replacement"
            )
        }
        self.handle = nil
    }

    func prepare(
        _ sql: String,
        operation: String
    ) throws -> GraphSearchSQLiteStatement {
        guard let handle else {
            throw GraphSearchSQLiteError(
                code: SQLITE_MISUSE,
                extendedCode: SQLITE_MISUSE,
                message: "SQLite connection is closed.",
                operation: operation
            )
        }
        return try GraphSearchSQLiteStatement(
            connection: handle,
            sql: sql,
            operation: operation
        )
    }

    func execute(
        _ sql: String,
        operation: String
    ) throws {
        let statement = try prepare(sql, operation: operation)
        try statement.stepExpectingDone()
    }

    func setBusyTimeout(milliseconds: Int32) throws {
        guard let handle else {
            throw GraphSearchSQLiteError(
                code: SQLITE_MISUSE,
                extendedCode: SQLITE_MISUSE,
                message: "SQLite connection is closed.",
                operation: "set-busy-timeout"
            )
        }
        let result = sqlite3_busy_timeout(handle, milliseconds)
        guard result == SQLITE_OK else {
            throw Self.makeError(
                handle: handle,
                fallbackCode: result,
                operation: "set-busy-timeout"
            )
        }
    }

    func changes() throws -> Int {
        guard let handle else {
            throw GraphSearchSQLiteError(
                code: SQLITE_MISUSE,
                extendedCode: SQLITE_MISUSE,
                message: "SQLite connection is closed.",
                operation: "changes"
            )
        }
        return Int(sqlite3_changes(handle))
    }

    static func makeError(
        handle: OpaquePointer?,
        fallbackCode: Int32,
        operation: String
    ) -> GraphSearchSQLiteError {
        let code: Int32
        let extendedCode: Int32
        let message: String

        if let handle {
            code = sqlite3_errcode(handle)
            extendedCode = sqlite3_extended_errcode(handle)
            message = String(cString: sqlite3_errmsg(handle))
        } else {
            code = fallbackCode
            extendedCode = fallbackCode
            message = String(cString: sqlite3_errstr(fallbackCode))
        }

        return GraphSearchSQLiteError(
            code: code,
            extendedCode: extendedCode,
            message: message,
            operation: operation
        )
    }
}

nonisolated final class GraphSearchSQLiteStatement {
    private let connection: OpaquePointer
    private let operation: String
    private var handle: OpaquePointer?

    init(
        connection: OpaquePointer,
        sql: String,
        operation: String
    ) throws {
        self.connection = connection
        self.operation = operation

        var preparedHandle: OpaquePointer?
        let result = sqlite3_prepare_v2(
            connection,
            sql,
            -1,
            &preparedHandle,
            nil
        )
        guard result == SQLITE_OK, let preparedHandle else {
            throw GraphSearchSQLiteConnection.makeError(
                handle: connection,
                fallbackCode: result,
                operation: operation
            )
        }
        handle = preparedHandle
    }

    deinit {
        if let handle {
            sqlite3_finalize(handle)
        }
    }

    func bind(_ value: String?, at index: Int32) throws {
        guard let value else {
            try bindNull(at: index)
            return
        }
        guard let handle else {
            throw closedStatementError()
        }

        let utf8 = value.utf8CString
        let byteCount = max(0, utf8.count - 1)
        guard let sqliteByteCount = Int32(exactly: byteCount) else {
            throw GraphSearchSQLiteError(
                code: SQLITE_TOOBIG,
                extendedCode: SQLITE_TOOBIG,
                message: "Bound text exceeds SQLite's supported byte count.",
                operation: "\(operation)-bind-text"
            )
        }
        let result = utf8.withUnsafeBufferPointer { buffer in
            sqlite3_bind_text(
                handle,
                index,
                buffer.baseAddress,
                sqliteByteCount,
                GraphSearchSQLiteBinding.transient
            )
        }
        try check(result, operation: "\(operation)-bind-text")
    }

    func bind(_ value: Int?, at index: Int32) throws {
        guard let value else {
            try bindNull(at: index)
            return
        }
        try bind(value, at: index)
    }

    func bind(_ value: Int, at index: Int32) throws {
        try bind(Int64(value), at: index)
    }

    func bind(_ value: Int64, at index: Int32) throws {
        guard let handle else {
            throw closedStatementError()
        }
        let result = sqlite3_bind_int64(handle, index, value)
        try check(result, operation: "\(operation)-bind-int64")
    }

    func bind(_ value: Double, at index: Int32) throws {
        guard let handle else {
            throw closedStatementError()
        }
        let result = sqlite3_bind_double(handle, index, value)
        try check(result, operation: "\(operation)-bind-double")
    }

    func bindNull(at index: Int32) throws {
        guard let handle else {
            throw closedStatementError()
        }
        let result = sqlite3_bind_null(handle, index)
        try check(result, operation: "\(operation)-bind-null")
    }

    func step() throws -> Bool {
        guard let handle else {
            throw closedStatementError()
        }
        let result = sqlite3_step(handle)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw GraphSearchSQLiteConnection.makeError(
                handle: connection,
                fallbackCode: result,
                operation: operation
            )
        }
    }

    func stepExpectingDone() throws {
        let hasRow = try step()
        guard hasRow == false else {
            throw GraphSearchSQLiteError(
                code: SQLITE_MISMATCH,
                extendedCode: SQLITE_MISMATCH,
                message: "Statement unexpectedly returned a row.",
                operation: operation
            )
        }
    }

    func reset() throws {
        guard let handle else {
            throw closedStatementError()
        }
        let resetResult = sqlite3_reset(handle)
        try check(resetResult, operation: "\(operation)-reset")
        let clearResult = sqlite3_clear_bindings(handle)
        try check(clearResult, operation: "\(operation)-clear-bindings")
    }

    func columnText(at index: Int32) -> String? {
        guard let handle else { return nil }
        guard sqlite3_column_type(handle, index) != SQLITE_NULL else { return nil }
        guard let bytes = sqlite3_column_text(handle, index) else { return "" }
        let count = Int(sqlite3_column_bytes(handle, index))
        let buffer = UnsafeBufferPointer(start: bytes, count: count)
        return String(bytes: buffer, encoding: .utf8)
    }

    func columnInt(at index: Int32) -> Int {
        Int(columnInt64(at: index))
    }

    func columnInt64(at index: Int32) -> Int64 {
        guard let handle else { return 0 }
        return sqlite3_column_int64(handle, index)
    }

    func columnNullableInt(at index: Int32) -> Int? {
        guard let handle else { return nil }
        guard sqlite3_column_type(handle, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(handle, index))
    }

    func columnDouble(at index: Int32) -> Double {
        guard let handle else { return 0 }
        return sqlite3_column_double(handle, index)
    }

    private func check(
        _ result: Int32,
        operation: String
    ) throws {
        guard result == SQLITE_OK else {
            throw GraphSearchSQLiteConnection.makeError(
                handle: connection,
                fallbackCode: result,
                operation: operation
            )
        }
    }

    private func closedStatementError() -> GraphSearchSQLiteError {
        GraphSearchSQLiteError(
            code: SQLITE_MISUSE,
            extendedCode: SQLITE_MISUSE,
            message: "SQLite statement is finalized.",
            operation: operation
        )
    }
}
