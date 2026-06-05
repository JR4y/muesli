import Foundation
import MuesliCore
import MuesliMeetingChat
import SQLite3

final class MeetingChatSyncRepository {
    private let databaseURL: URL
    private let localSyncRepository: LocalSyncRepository?
    private let decoder = JSONDecoder()
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(databaseURL: URL, localSyncRepository: LocalSyncRepository? = nil) {
        self.databaseURL = databaseURL
        self.localSyncRepository = localSyncRepository
    }

    func migrateIfNeeded() throws {
        try withDB { db in
            try exec(
                """
                CREATE TABLE IF NOT EXISTS meeting_chat_sync_metadata (
                    entity_kind TEXT NOT NULL,
                    local_id TEXT NOT NULL,
                    remote_id TEXT,
                    client_updated_at TEXT NOT NULL,
                    remote_version INTEGER NOT NULL DEFAULT 0,
                    last_seen_server_updated_at TEXT,
                    last_payload_hash TEXT,
                    dirty INTEGER NOT NULL DEFAULT 1,
                    last_writer_device_id TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                    PRIMARY KEY (entity_kind, local_id),
                    UNIQUE (entity_kind, remote_id)
                );
                CREATE INDEX IF NOT EXISTS idx_meeting_chat_sync_metadata_dirty
                    ON meeting_chat_sync_metadata(entity_kind, dirty, client_updated_at);

                CREATE TABLE IF NOT EXISTS meeting_chat_sync_tombstones (
                    entity_kind TEXT NOT NULL,
                    local_id TEXT NOT NULL,
                    remote_id TEXT,
                    client_deleted_at TEXT NOT NULL,
                    last_known_remote_version INTEGER NOT NULL DEFAULT 0,
                    dirty INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                    PRIMARY KEY (entity_kind, local_id)
                );
                CREATE INDEX IF NOT EXISTS idx_meeting_chat_sync_tombstones_dirty
                    ON meeting_chat_sync_tombstones(entity_kind, dirty, client_deleted_at);
                """,
                db: db
            )
            try backfillExistingRowsAsDirty(db: db)
        }
    }

    func dirtyThreads(limit: Int = 100) throws -> [DirtyMeetingChatThread] {
        try migrateIfNeeded()
        return try withDB { db in
            let sql = """
            SELECT t.id, t.scope_kind, t.scope_id, t.title, t.summary, t.created_at, t.updated_at,
                   m.remote_id, m.client_updated_at, m.remote_version, m.last_seen_server_updated_at,
                   m.last_payload_hash, m.dirty, m.last_writer_device_id
            FROM meeting_chat_threads t
            JOIN meeting_chat_sync_metadata m
              ON m.entity_kind = 'thread' AND m.local_id = t.id
            WHERE m.dirty = 1
            ORDER BY m.client_updated_at ASC, t.id ASC
            LIMIT ?
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(limit))

            var rows: [DirtyMeetingChatThread] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let thread = try thread(statement)
                let metadata = metadata(statement, entityKind: .thread, localIDColumn: 0, baseColumn: 7)
                rows.append(
                    DirtyMeetingChatThread(
                        metadata: metadata,
                        thread: thread,
                        scopeKind: stringColumn(statement, index: 1),
                        scopeRemoteID: try remoteID(for: thread.scope)
                    )
                )
            }
            return rows
        }
    }

    func dirtyMessages(limit: Int = 100) throws -> [DirtyMeetingChatMessage] {
        try migrateIfNeeded()
        return try withDB { db in
            let sql = """
            SELECT msg.id, msg.thread_id, msg.role, msg.content, msg.sources_json, msg.created_at,
                   m.remote_id, m.client_updated_at, m.remote_version, m.last_seen_server_updated_at,
                   m.last_payload_hash, m.dirty, m.last_writer_device_id
            FROM meeting_chat_messages msg
            JOIN meeting_chat_sync_metadata m
              ON m.entity_kind = 'message' AND m.local_id = msg.id
            WHERE m.dirty = 1
            ORDER BY m.client_updated_at ASC, msg.created_at ASC, msg.id ASC
            LIMIT ?
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(limit))

            var rows: [DirtyMeetingChatMessage] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let threadID = UUID(uuidString: stringColumn(statement, index: 1)) else {
                    throw MeetingChatStorageError.database("Invalid chat thread id.")
                }
                let metadata = metadata(statement, entityKind: .message, localIDColumn: 0, baseColumn: 6)
                rows.append(
                    DirtyMeetingChatMessage(
                        metadata: metadata,
                        message: try message(statement),
                        threadLocalID: threadID,
                        threadRemoteID: nil
                    )
                )
            }
            return rows
        }
    }

    func markThreadDirty(localID: UUID) throws {
        try markDirty(entityKind: .thread, localID: localID.uuidString)
    }

    func markMessageDirty(localID: UUID) throws {
        try markDirty(entityKind: .message, localID: localID.uuidString)
    }

    func markThreadSynced(
        localID: UUID,
        remoteID: String,
        remoteVersion: Int64,
        clientUpdatedAt: String,
        serverUpdatedAt: String,
        payloadHash: String,
        lastWriterDeviceID: String
    ) throws {
        try writeMetadata(
            entityKind: .thread,
            localID: localID.uuidString,
            remoteID: remoteID,
            remoteVersion: remoteVersion,
            clientUpdatedAt: clientUpdatedAt,
            serverUpdatedAt: serverUpdatedAt,
            payloadHash: payloadHash,
            lastWriterDeviceID: lastWriterDeviceID,
            dirty: false
        )
    }

    func dirtyTombstones(
        entityKind: MeetingChatSyncEntityKind,
        limit: Int = 100
    ) throws -> [MeetingChatSyncTombstoneRecord] {
        try migrateIfNeeded()
        return try withDB { db in
            let sql = """
            SELECT entity_kind, local_id, remote_id, client_deleted_at, last_known_remote_version, dirty
            FROM meeting_chat_sync_tombstones
            WHERE entity_kind = ? AND dirty = 1
            ORDER BY client_deleted_at ASC, local_id ASC
            LIMIT ?
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(statement) }
            bindText(entityKind.rawValue, at: 1, statement: statement)
            sqlite3_bind_int(statement, 2, Int32(limit))

            var rows: [MeetingChatSyncTombstoneRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let parsedKind = MeetingChatSyncEntityKind(rawValue: stringColumn(statement, index: 0)) else {
                    continue
                }
                rows.append(
                    MeetingChatSyncTombstoneRecord(
                        entityKind: parsedKind,
                        localID: stringColumn(statement, index: 1),
                        remoteID: optionalStringColumn(statement, index: 2),
                        clientDeletedAt: stringColumn(statement, index: 3),
                        lastKnownRemoteVersion: sqlite3_column_int64(statement, 4),
                        dirty: sqlite3_column_int(statement, 5) != 0
                    )
                )
            }
            return rows
        }
    }

    func recordThreadDelete(localID: UUID) throws {
        try recordDelete(entityKind: .thread, localID: localID.uuidString)
    }

    private func backfillExistingRowsAsDirty(db: OpaquePointer?) throws {
        let nowExpr = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"
        try exec(
            """
            INSERT INTO meeting_chat_sync_metadata (entity_kind, local_id, client_updated_at, dirty, updated_at)
            SELECT 'thread', t.id, \(nowExpr), 1, datetime('now')
            FROM meeting_chat_threads t
            LEFT JOIN meeting_chat_sync_metadata m
              ON m.entity_kind = 'thread' AND m.local_id = t.id
            WHERE m.local_id IS NULL
            """,
            db: db
        )
        try exec(
            """
            INSERT INTO meeting_chat_sync_metadata (entity_kind, local_id, client_updated_at, dirty, updated_at)
            SELECT 'message', msg.id, \(nowExpr), 1, datetime('now')
            FROM meeting_chat_messages msg
            LEFT JOIN meeting_chat_sync_metadata m
              ON m.entity_kind = 'message' AND m.local_id = msg.id
            WHERE m.local_id IS NULL
            """,
            db: db
        )
    }

    private func markDirty(entityKind: MeetingChatSyncEntityKind, localID: String) throws {
        try migrateIfNeeded()
        try withDB { db in
            try exec(
                """
                INSERT INTO meeting_chat_sync_metadata (entity_kind, local_id, client_updated_at, dirty, updated_at)
                VALUES (?, ?, ?, 1, datetime('now'))
                ON CONFLICT(entity_kind, local_id) DO UPDATE SET
                    client_updated_at = excluded.client_updated_at,
                    dirty = 1,
                    updated_at = datetime('now')
                """,
                params: [entityKind.rawValue, localID, SyncTimestamp.now()],
                db: db
            )
        }
    }

    private func writeMetadata(
        entityKind: MeetingChatSyncEntityKind,
        localID: String,
        remoteID: String,
        remoteVersion: Int64,
        clientUpdatedAt: String,
        serverUpdatedAt: String,
        payloadHash: String,
        lastWriterDeviceID: String,
        dirty: Bool
    ) throws {
        try migrateIfNeeded()
        try withDB { db in
            try exec(
                """
                INSERT INTO meeting_chat_sync_metadata (
                    entity_kind, local_id, remote_id, client_updated_at, remote_version,
                    last_seen_server_updated_at, last_payload_hash, dirty, last_writer_device_id, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                ON CONFLICT(entity_kind, local_id) DO UPDATE SET
                    remote_id = excluded.remote_id,
                    client_updated_at = excluded.client_updated_at,
                    remote_version = excluded.remote_version,
                    last_seen_server_updated_at = excluded.last_seen_server_updated_at,
                    last_payload_hash = excluded.last_payload_hash,
                    dirty = excluded.dirty,
                    last_writer_device_id = excluded.last_writer_device_id,
                    updated_at = datetime('now')
                """,
                params: [
                    entityKind.rawValue,
                    localID,
                    remoteID,
                    clientUpdatedAt,
                    String(remoteVersion),
                    serverUpdatedAt,
                    payloadHash,
                    dirty ? "1" : "0",
                    lastWriterDeviceID,
                ],
                db: db
            )
        }
    }

    private func recordDelete(entityKind: MeetingChatSyncEntityKind, localID: String) throws {
        try migrateIfNeeded()
        try withDB { db in
            try exec(
                """
                INSERT OR REPLACE INTO meeting_chat_sync_tombstones (
                    entity_kind, local_id, remote_id, client_deleted_at,
                    last_known_remote_version, dirty, updated_at
                )
                SELECT ?, ?, remote_id, ?, remote_version, 1, datetime('now')
                FROM meeting_chat_sync_metadata
                WHERE entity_kind = ? AND local_id = ?
                """,
                params: [entityKind.rawValue, localID, SyncTimestamp.now(), entityKind.rawValue, localID],
                db: db
            )
            try exec(
                "DELETE FROM meeting_chat_sync_metadata WHERE entity_kind = ? AND local_id = ?",
                params: [entityKind.rawValue, localID],
                db: db
            )
        }
    }

    private func thread(_ statement: OpaquePointer?) throws -> MeetingChatThread {
        guard let id = UUID(uuidString: stringColumn(statement, index: 0)) else {
            throw MeetingChatStorageError.database("Invalid chat thread id.")
        }
        let kind = stringColumn(statement, index: 1)
        let scopeID = sqlite3_column_int64(statement, 2)
        let scope: MeetingChatScope
        switch kind {
        case "meeting":
            scope = .meeting(scopeID)
        case "folder":
            scope = .folder(scopeID)
        default:
            throw MeetingChatStorageError.invalidScope(kind, scopeID)
        }
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
            throw MeetingChatStorageError.database("Invalid chat message id.")
        }
        let rawRole = stringColumn(statement, index: 2)
        guard let role = MeetingChatRole(rawValue: rawRole) else {
            throw MeetingChatStorageError.invalidMessageRole(rawRole)
        }
        let sourcesData = Data(stringColumn(statement, index: 4).utf8)
        let sources = (try? decoder.decode([MeetingChatSource].self, from: sourcesData)) ?? []
        return MeetingChatMessage(
            id: id,
            role: role,
            text: stringColumn(statement, index: 3),
            sources: sources,
            createdAt: dateFormatter.date(from: stringColumn(statement, index: 5)) ?? Date(timeIntervalSince1970: 0)
        )
    }

    private func metadata(
        _ statement: OpaquePointer?,
        entityKind: MeetingChatSyncEntityKind,
        localIDColumn: Int32,
        baseColumn: Int32
    ) -> MeetingChatSyncMetadataRecord {
        MeetingChatSyncMetadataRecord(
            entityKind: entityKind,
            localID: stringColumn(statement, index: localIDColumn),
            remoteID: optionalStringColumn(statement, index: baseColumn),
            clientUpdatedAt: stringColumn(statement, index: baseColumn + 1),
            remoteVersion: sqlite3_column_int64(statement, baseColumn + 2),
            lastSeenServerUpdatedAt: optionalStringColumn(statement, index: baseColumn + 3),
            lastPayloadHash: optionalStringColumn(statement, index: baseColumn + 4),
            dirty: sqlite3_column_int(statement, baseColumn + 5) != 0,
            lastWriterDeviceID: optionalStringColumn(statement, index: baseColumn + 6)
        )
    }

    private func remoteID(for scope: MeetingChatScope) throws -> String? {
        guard let localSyncRepository else { return nil }
        switch scope {
        case let .meeting(id):
            return try localSyncRepository.remoteID(forLocalID: id, entityType: .meeting)
        case let .folder(id):
            return try localSyncRepository.remoteID(forLocalID: id, entityType: .folder)
        }
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

    private func exec(_ sql: String, params: [String], db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in params.enumerated() {
            bindText(value, at: Int32(index + 1), statement: statement)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    private func lastError(_ db: OpaquePointer?) -> NSError {
        NSError(
            domain: "MuesliMeetingChatSyncDB",
            code: Int(sqlite3_errcode(db)),
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]
        )
    }

    private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func optionalStringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : stringColumn(statement, index: index)
    }

    private func bindText(_ value: String, at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, Self.transientDestructor)
    }

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
