import Foundation
import SQLite3
import MuesliMeetingChat

final class SQLiteMeetingChatStore: MeetingChatStoring {
    private let databaseURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func migrateIfNeeded() throws {
        try withDB { db in
            try exec(
                """
                CREATE TABLE IF NOT EXISTS meeting_chat_threads (
                    id TEXT PRIMARY KEY,
                    scope_kind TEXT NOT NULL,
                    scope_id INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    summary TEXT NOT NULL DEFAULT '',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(scope_kind, scope_id)
                );
                CREATE INDEX IF NOT EXISTS idx_meeting_chat_threads_scope
                    ON meeting_chat_threads(scope_kind, scope_id);

                CREATE TABLE IF NOT EXISTS meeting_chat_messages (
                    id TEXT PRIMARY KEY,
                    thread_id TEXT NOT NULL REFERENCES meeting_chat_threads(id) ON DELETE CASCADE,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    sources_json TEXT NOT NULL DEFAULT '[]',
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_meeting_chat_messages_thread_created
                    ON meeting_chat_messages(thread_id, created_at);
                """,
                db: db
            )
        }
    }

    func loadThread(scope: MeetingChatScope, title: String) throws -> MeetingChatThreadSnapshot {
        try migrateIfNeeded()
        return try withDB { db in
            if let existing = try selectThread(scope: scope, db: db) {
                if existing.title != title {
                    try updateThreadTitle(threadID: existing.id, title: title, db: db)
                }
                return MeetingChatThreadSnapshot(
                    thread: existing.title == title ? existing : MeetingChatThread(
                        id: existing.id,
                        scope: existing.scope,
                        title: title,
                        summary: existing.summary,
                        createdAt: existing.createdAt,
                        updatedAt: Date()
                    ),
                    messages: try selectMessages(threadID: existing.id, db: db)
                )
            }

            let now = Date()
            let thread = MeetingChatThread(
                scope: scope,
                title: title,
                createdAt: now,
                updatedAt: now
            )
            try insertThread(thread, db: db)
            return MeetingChatThreadSnapshot(thread: thread, messages: [])
        }
    }

    func appendMessage(_ message: MeetingChatMessage, to thread: MeetingChatThread) throws {
        try migrateIfNeeded()
        try withDB { db in
            try insertMessage(message, threadID: thread.id, db: db)
            try touchThread(thread.id, db: db)
        }
    }

    func clearThread(scope: MeetingChatScope) throws {
        try migrateIfNeeded()
        try withDB { db in
            let (kind, id) = Self.scopeColumns(scope)
            let sql = "DELETE FROM meeting_chat_threads WHERE scope_kind = ? AND scope_id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(statement) }
            bindText(kind, at: 1, statement: statement)
            sqlite3_bind_int64(statement, 2, id)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw lastError(db)
            }
        }
    }

    private func insertThread(_ thread: MeetingChatThread, db: OpaquePointer?) throws {
        let (kind, scopeID) = Self.scopeColumns(thread.scope)
        let sql = """
        INSERT INTO meeting_chat_threads
        (id, scope_kind, scope_id, title, summary, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }

        bindText(thread.id.uuidString, at: 1, statement: statement)
        bindText(kind, at: 2, statement: statement)
        sqlite3_bind_int64(statement, 3, scopeID)
        bindText(thread.title, at: 4, statement: statement)
        bindText(thread.summary, at: 5, statement: statement)
        bindText(dateFormatter.string(from: thread.createdAt), at: 6, statement: statement)
        bindText(dateFormatter.string(from: thread.updatedAt), at: 7, statement: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    private func updateThreadTitle(threadID: UUID, title: String, db: OpaquePointer?) throws {
        let sql = "UPDATE meeting_chat_threads SET title = ?, updated_at = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        bindText(title, at: 1, statement: statement)
        bindText(dateFormatter.string(from: Date()), at: 2, statement: statement)
        bindText(threadID.uuidString, at: 3, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    private func touchThread(_ threadID: UUID, db: OpaquePointer?) throws {
        let sql = "UPDATE meeting_chat_threads SET updated_at = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        bindText(dateFormatter.string(from: Date()), at: 1, statement: statement)
        bindText(threadID.uuidString, at: 2, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    private func selectThread(scope: MeetingChatScope, db: OpaquePointer?) throws -> MeetingChatThread? {
        let (kind, id) = Self.scopeColumns(scope)
        let sql = """
        SELECT id, scope_kind, scope_id, title, summary, created_at, updated_at
        FROM meeting_chat_threads
        WHERE scope_kind = ? AND scope_id = ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        bindText(kind, at: 1, statement: statement)
        sqlite3_bind_int64(statement, 2, id)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return try thread(statement)
    }

    private func selectMessages(threadID: UUID, db: OpaquePointer?) throws -> [MeetingChatMessage] {
        let sql = """
        SELECT id, role, content, sources_json, created_at
        FROM meeting_chat_messages
        WHERE thread_id = ?
        ORDER BY created_at ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        bindText(threadID.uuidString, at: 1, statement: statement)

        var messages: [MeetingChatMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            messages.append(try message(statement))
        }
        return messages
    }

    private func insertMessage(_ message: MeetingChatMessage, threadID: UUID, db: OpaquePointer?) throws {
        let sql = """
        INSERT OR REPLACE INTO meeting_chat_messages
        (id, thread_id, role, content, sources_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        let sourcesData = try encoder.encode(message.sources)
        guard let sourcesJSON = String(data: sourcesData, encoding: .utf8) else {
            throw MeetingChatStorageError.database("Unable to encode source references.")
        }

        bindText(message.id.uuidString, at: 1, statement: statement)
        bindText(threadID.uuidString, at: 2, statement: statement)
        bindText(message.role.rawValue, at: 3, statement: statement)
        bindText(message.text, at: 4, statement: statement)
        bindText(sourcesJSON, at: 5, statement: statement)
        bindText(dateFormatter.string(from: message.createdAt), at: 6, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    private func thread(_ statement: OpaquePointer?) throws -> MeetingChatThread {
        guard let id = UUID(uuidString: stringColumn(statement, index: 0)) else {
            throw MeetingChatStorageError.database("Invalid thread id.")
        }
        let kind = stringColumn(statement, index: 1)
        let scopeID = sqlite3_column_int64(statement, 2)
        let scope = try Self.scope(kind: kind, id: scopeID)
        return MeetingChatThread(
            id: id,
            scope: scope,
            title: stringColumn(statement, index: 3),
            summary: stringColumn(statement, index: 4),
            createdAt: dateFormatter.date(from: stringColumn(statement, index: 5)) ?? Date(timeIntervalSince1970: 0),
            updatedAt: dateFormatter.date(from: stringColumn(statement, index: 6)) ?? Date(timeIntervalSince1970: 0)
        )
    }

    private func message(_ statement: OpaquePointer?) throws -> MeetingChatMessage {
        guard let id = UUID(uuidString: stringColumn(statement, index: 0)) else {
            throw MeetingChatStorageError.database("Invalid message id.")
        }
        let rawRole = stringColumn(statement, index: 1)
        guard let role = MeetingChatRole(rawValue: rawRole) else {
            throw MeetingChatStorageError.invalidMessageRole(rawRole)
        }
        let sourcesData = Data(stringColumn(statement, index: 3).utf8)
        let sources = (try? decoder.decode([MeetingChatSource].self, from: sourcesData)) ?? []
        return MeetingChatMessage(
            id: id,
            role: role,
            text: stringColumn(statement, index: 2),
            sources: sources,
            createdAt: dateFormatter.date(from: stringColumn(statement, index: 4)) ?? Date(timeIntervalSince1970: 0)
        )
    }

    private func withDB<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var db: OpaquePointer?
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            throw lastError(db)
        }
        defer { sqlite3_close(db) }
        if sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
        if sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
        return try body(db)
    }

    private func exec(_ sql: String, db: OpaquePointer?) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
    }

    private func lastError(_ db: OpaquePointer?) -> NSError {
        NSError(
            domain: "MuesliMeetingChatDB",
            code: Int(sqlite3_errcode(db)),
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]
        )
    }

    private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func bindText(_ value: String, at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, Self.transientDestructor)
    }

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func scopeColumns(_ scope: MeetingChatScope) -> (String, Int64) {
        switch scope {
        case let .meeting(id):
            return ("meeting", id)
        case let .folder(id):
            return ("folder", id)
        }
    }

    private static func scope(kind: String, id: Int64) throws -> MeetingChatScope {
        switch kind {
        case "meeting":
            return .meeting(id)
        case "folder":
            return .folder(id)
        default:
            throw MeetingChatStorageError.invalidScope(kind, id)
        }
    }
}
