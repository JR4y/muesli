import Foundation
import SQLite3

public enum LocalSyncRepositoryError: Error, LocalizedError {
    case databaseError(message: String, code: Int32)
    case unknownEntity(remoteID: String, entityType: SyncEntityType)
    case missingFolderForRemoteParent(parentRemoteID: String)

    public var errorDescription: String? {
        switch self {
        case .databaseError(let message, let code):
            return "Sync DB error (\(code)): \(message)"
        case .unknownEntity(let remoteID, let entityType):
            return "Cannot apply remote \(entityType.rawValue): no local mapping for \(remoteID)"
        case .missingFolderForRemoteParent(let parentRemoteID):
            return "Cannot resolve remote folder parent \(parentRemoteID) to local id"
        }
    }
}

/// Repository for sync metadata, tombstones, cursors, and reconciliation. It
/// shares the same SQLite database as `DictationStore` and creates a small set
/// of auxiliary tables plus triggers that mark domain rows as dirty whenever
/// they change. Apply-remote calls always re-clean the metadata after the
/// triggers have fired, so remote-driven writes never appear as local edits.
public final class LocalSyncRepository {
    private let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public var resolvedDatabaseURL: URL { databaseURL }

    // MARK: - Migration

    public func migrateIfNeeded() throws {
        try withDB { db in
            try exec(
                """
                CREATE TABLE IF NOT EXISTS sync_metadata (
                    entity_type TEXT NOT NULL,
                    local_id INTEGER NOT NULL,
                    remote_id TEXT,
                    client_updated_at TEXT NOT NULL,
                    remote_version INTEGER NOT NULL DEFAULT 0,
                    last_seen_server_updated_at TEXT,
                    last_payload_hash TEXT,
                    dirty INTEGER NOT NULL DEFAULT 1,
                    last_writer_device_id TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                    PRIMARY KEY (entity_type, local_id),
                    UNIQUE (entity_type, remote_id)
                );
                CREATE INDEX IF NOT EXISTS idx_sync_metadata_dirty
                    ON sync_metadata(entity_type, dirty, client_updated_at);

                CREATE TABLE IF NOT EXISTS sync_tombstones (
                    entity_type TEXT NOT NULL,
                    local_id INTEGER NOT NULL,
                    remote_id TEXT,
                    client_deleted_at TEXT NOT NULL,
                    last_known_remote_version INTEGER NOT NULL DEFAULT 0,
                    dirty INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                    PRIMARY KEY (entity_type, local_id)
                );
                CREATE INDEX IF NOT EXISTS idx_sync_tombstones_dirty
                    ON sync_tombstones(entity_type, dirty, client_deleted_at);

                CREATE TABLE IF NOT EXISTS sync_state (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
                );
                """,
                db: db
            )

            for entity in SyncEntityType.allCases {
                try installTriggers(for: entity, db: db)
            }

            try backfillExistingRowsAsDirty(db: db)
        }
    }

    private func backfillExistingRowsAsDirty(db: OpaquePointer?) throws {
        let nowExpr = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"
        let statements = [
            """
            INSERT INTO sync_metadata (
                entity_type, local_id, client_updated_at, dirty, updated_at
            )
            SELECT 'dictation', d.id, \(nowExpr), 1, datetime('now')
            FROM dictations d
            LEFT JOIN sync_metadata m
                ON m.entity_type = 'dictation' AND m.local_id = d.id
            WHERE m.local_id IS NULL
            """,
            """
            INSERT INTO sync_metadata (
                entity_type, local_id, client_updated_at, dirty, updated_at
            )
            SELECT 'meeting', me.id, \(nowExpr), 1, datetime('now')
            FROM meetings me
            LEFT JOIN sync_metadata m
                ON m.entity_type = 'meeting' AND m.local_id = me.id
            WHERE m.local_id IS NULL
            """,
            """
            INSERT INTO sync_metadata (
                entity_type, local_id, client_updated_at, dirty, updated_at
            )
            SELECT 'folder', f.id, \(nowExpr), 1, datetime('now')
            FROM meeting_folders f
            LEFT JOIN sync_metadata m
                ON m.entity_type = 'folder' AND m.local_id = f.id
            WHERE m.local_id IS NULL
            """
        ]
        for statement in statements {
            try exec(statement, db: db)
        }
    }

    private func installTriggers(for entity: SyncEntityType, db: OpaquePointer?) throws {
        let entityKey = entity.rawValue
        let table = entity.domainTableName
        let nowExpr = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"

        let upsertTrigger: (String) -> String = { kind in
            """
            CREATE TRIGGER IF NOT EXISTS trg_\(table)_sync_\(kind)
            AFTER \(kind.uppercased()) ON \(table)
            FOR EACH ROW
            BEGIN
                INSERT INTO sync_metadata (
                    entity_type, local_id, client_updated_at, dirty, updated_at
                ) VALUES (
                    '\(entityKey)', NEW.id, \(nowExpr), 1, datetime('now')
                )
                ON CONFLICT(entity_type, local_id) DO UPDATE SET
                    client_updated_at = excluded.client_updated_at,
                    dirty = 1,
                    updated_at = datetime('now');
            END;
            """
        }

        let beforeDelete = """
        CREATE TRIGGER IF NOT EXISTS trg_\(table)_sync_before_delete
        BEFORE DELETE ON \(table)
        FOR EACH ROW
        BEGIN
            INSERT OR REPLACE INTO sync_tombstones (
                entity_type, local_id, remote_id, client_deleted_at,
                last_known_remote_version, dirty, updated_at
            ) VALUES (
                '\(entityKey)',
                OLD.id,
                (SELECT remote_id FROM sync_metadata
                    WHERE entity_type = '\(entityKey)' AND local_id = OLD.id),
                \(nowExpr),
                COALESCE(
                    (SELECT remote_version FROM sync_metadata
                        WHERE entity_type = '\(entityKey)' AND local_id = OLD.id),
                    0
                ),
                1,
                datetime('now')
            );
        END;
        """

        let afterDelete = """
        CREATE TRIGGER IF NOT EXISTS trg_\(table)_sync_after_delete
        AFTER DELETE ON \(table)
        FOR EACH ROW
        BEGIN
            DELETE FROM sync_metadata
            WHERE entity_type = '\(entityKey)' AND local_id = OLD.id;
        END;
        """

        try exec(upsertTrigger("insert"), db: db)
        try exec(upsertTrigger("update"), db: db)
        try exec(beforeDelete, db: db)
        try exec(afterDelete, db: db)
    }

    // MARK: - Device ID

    public func ensureDeviceID() throws -> String {
        if let existing = try loadStateValue(.deviceID), !existing.isEmpty {
            return existing
        }
        let newID = UUID().uuidString
        try writeStateValue(.deviceID, value: newID)
        return newID
    }

    // MARK: - Cursors

    public func loadCursor(for entity: SyncEntityType) throws -> SyncCursor? {
        try loadCursor(stateKey: cursorKey(for: entity))
    }

    public func loadPreferencesCursor() throws -> SyncCursor? {
        try loadCursor(stateKey: .pullCursorUserPreferences)
    }

    public func saveCursor(_ cursor: SyncCursor, for entity: SyncEntityType) throws {
        try saveCursor(cursor, stateKey: cursorKey(for: entity))
    }

    public func savePreferencesCursor(_ cursor: SyncCursor) throws {
        try saveCursor(cursor, stateKey: .pullCursorUserPreferences)
    }

    private func cursorKey(for entity: SyncEntityType) -> SyncStateKey {
        switch entity {
        case .dictation: return .pullCursorDictations
        case .meeting: return .pullCursorMeetings
        case .folder: return .pullCursorMeetingFolders
        }
    }

    private func loadCursor(stateKey: SyncStateKey) throws -> SyncCursor? {
        guard let raw = try loadStateValue(stateKey),
              let data = raw.data(using: .utf8),
              let cursor = try? JSONDecoder().decode(SyncCursor.self, from: data) else {
            return nil
        }
        return cursor
    }

    private func saveCursor(_ cursor: SyncCursor, stateKey: SyncStateKey) throws {
        let data = try JSONEncoder().encode(cursor)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try writeStateValue(stateKey, value: json)
    }

    // MARK: - Preferences state

    public func loadPreferencesState() throws -> SyncPreferencesState {
        let dirty = (try loadStateValue(.preferencesDirty)) == "true"
        let remoteVersion = Int64(try loadStateValue(.preferencesRemoteVersion) ?? "0") ?? 0
        let clientUpdatedAt = try loadStateValue(.preferencesClientUpdatedAt)
        let lastSeenServer = try loadStateValue(.preferencesLastSeenServerUpdatedAt)
        let lastHash = try loadStateValue(.preferencesLastPayloadHash)
        let lastWriter = try loadStateValue(.preferencesLastWriterDeviceID)
        return SyncPreferencesState(
            dirty: dirty,
            remoteVersion: remoteVersion,
            clientUpdatedAt: clientUpdatedAt,
            lastSeenServerUpdatedAt: lastSeenServer,
            lastPayloadHash: lastHash,
            lastWriterDeviceID: lastWriter
        )
    }

    public func markPreferencesDirty(clientUpdatedAt: String = SyncTimestamp.now()) throws {
        try withDB { db in
            try writeStateValue(.preferencesDirty, value: "true", db: db)
            try writeStateValue(.preferencesClientUpdatedAt, value: clientUpdatedAt, db: db)
        }
    }

    public func markPreferencesSynced(
        remoteVersion: Int64,
        clientUpdatedAt: String,
        serverUpdatedAt: String,
        payloadHash: String,
        lastWriterDeviceID: String
    ) throws {
        try withDB { db in
            try writeStateValue(.preferencesDirty, value: "false", db: db)
            try writeStateValue(.preferencesRemoteVersion, value: String(remoteVersion), db: db)
            try writeStateValue(.preferencesClientUpdatedAt, value: clientUpdatedAt, db: db)
            try writeStateValue(.preferencesLastSeenServerUpdatedAt, value: serverUpdatedAt, db: db)
            try writeStateValue(.preferencesLastPayloadHash, value: payloadHash, db: db)
            try writeStateValue(.preferencesLastWriterDeviceID, value: lastWriterDeviceID, db: db)
        }
    }

    // MARK: - Dirty queries

    public func dirtyDictations(limit: Int = 100) throws -> [DirtyDictation] {
        var result: [DirtyDictation] = []
        try withDB { db in
            let sql = """
            SELECT
                d.id, d.timestamp, d.duration_seconds, d.raw_text,
                d.app_context, d.word_count, d.source, d.started_at, d.ended_at,
                m.remote_id, m.client_updated_at, m.remote_version,
                m.last_seen_server_updated_at, m.last_payload_hash,
                m.dirty, m.last_writer_device_id
            FROM dictations d
            JOIN sync_metadata m
                ON m.entity_type = 'dictation' AND m.local_id = d.id
            WHERE m.dirty = 1
            ORDER BY m.client_updated_at ASC, d.id ASC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let timestamp = stringColumn(stmt, 1)
                let duration = sqlite3_column_double(stmt, 2)
                let rawText = stringColumn(stmt, 3)
                let appContext = stringColumn(stmt, 4)
                let wordCount = Int(sqlite3_column_int(stmt, 5))
                let source = stringColumn(stmt, 6)
                let _ = stringColumn(stmt, 7) // started_at — unused for the DictationRecord
                let _ = stringColumn(stmt, 8) // ended_at — unused for the DictationRecord
                let remoteID = optionalStringColumn(stmt, 9)
                let clientUpdatedAt = stringColumn(stmt, 10)
                let remoteVersion = sqlite3_column_int64(stmt, 11)
                let lastSeenServer = optionalStringColumn(stmt, 12)
                let lastHash = optionalStringColumn(stmt, 13)
                let dirty = sqlite3_column_int(stmt, 14) != 0
                let lastWriter = optionalStringColumn(stmt, 15)

                let record = DictationRecord(
                    id: id,
                    timestamp: timestamp,
                    durationSeconds: duration,
                    rawText: rawText,
                    appContext: appContext,
                    wordCount: wordCount
                )
                _ = source // source is enforced via INSERT default; included here in case it diverges later
                let metadata = SyncMetadataRecord(
                    entityType: .dictation,
                    localID: id,
                    remoteID: remoteID,
                    clientUpdatedAt: clientUpdatedAt,
                    remoteVersion: remoteVersion,
                    lastSeenServerUpdatedAt: lastSeenServer,
                    lastPayloadHash: lastHash,
                    dirty: dirty,
                    lastWriterDeviceID: lastWriter
                )
                result.append(DirtyDictation(metadata: metadata, record: record))
            }
        }
        return result
    }

    /// Returns dirty meetings excluding rows in `recording` or `processing`.
    /// `folderRemoteID` is resolved on-the-fly from `sync_metadata`.
    public func dirtyMeetings(limit: Int = 50) throws -> [DirtyMeeting] {
        var result: [DirtyMeeting] = []
        try withDB { db in
            let sql = """
            SELECT
                me.id, me.title, me.start_time, me.duration_seconds,
                me.raw_transcript, me.formatted_notes, me.word_count,
                me.folder_id, me.calendar_event_id, me.mic_audio_path,
                me.system_audio_path, me.saved_recording_path,
                me.merged_into_meeting_id, me.meeting_status, me.manual_notes,
                me.selected_template_id, me.selected_template_name,
                me.selected_template_kind, me.selected_template_prompt,
                me.calendar_event_snapshot,
                m.remote_id, m.client_updated_at, m.remote_version,
                m.last_seen_server_updated_at, m.last_payload_hash,
                m.dirty, m.last_writer_device_id,
                fm.remote_id AS folder_remote_id,
                mm.remote_id AS merged_into_meeting_remote_id
            FROM meetings me
            JOIN sync_metadata m
                ON m.entity_type = 'meeting' AND m.local_id = me.id
            LEFT JOIN sync_metadata fm
                ON fm.entity_type = 'folder' AND fm.local_id = me.folder_id
            LEFT JOIN sync_metadata mm
                ON mm.entity_type = 'meeting' AND mm.local_id = me.merged_into_meeting_id
            WHERE m.dirty = 1
              AND me.meeting_status NOT IN ('recording', 'processing')
            ORDER BY
                CASE WHEN me.merged_into_meeting_id IS NULL THEN 0 ELSE 1 END ASC,
                m.client_updated_at ASC,
                me.id ASC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let record = makeMeetingRecord(stmt: stmt, baseColumn: 0)
                let metadata = SyncMetadataRecord(
                    entityType: .meeting,
                    localID: record.id,
                    remoteID: optionalStringColumn(stmt, 20),
                    clientUpdatedAt: stringColumn(stmt, 21),
                    remoteVersion: sqlite3_column_int64(stmt, 22),
                    lastSeenServerUpdatedAt: optionalStringColumn(stmt, 23),
                    lastPayloadHash: optionalStringColumn(stmt, 24),
                    dirty: sqlite3_column_int(stmt, 25) != 0,
                    lastWriterDeviceID: optionalStringColumn(stmt, 26)
                )
                let folderRemoteID = optionalStringColumn(stmt, 27)
                let mergedIntoMeetingRemoteID = optionalStringColumn(stmt, 28)
                result.append(
                    DirtyMeeting(
                        metadata: metadata,
                        record: record,
                        folderRemoteID: folderRemoteID,
                        mergedIntoMeetingRemoteID: mergedIntoMeetingRemoteID
                    )
                )
            }
        }
        return result
    }

    public func dirtyFolders(limit: Int = 100) throws -> [DirtyFolder] {
        var result: [DirtyFolder] = []
        try withDB { db in
            let sql = """
            SELECT
                f.id, f.name, f.parent_folder_id, f.color_hex, f.icon_name, f.created_at,
                m.remote_id, m.client_updated_at, m.remote_version,
                m.last_seen_server_updated_at, m.last_payload_hash,
                m.dirty, m.last_writer_device_id,
                pm.remote_id AS parent_remote_id
            FROM meeting_folders f
            JOIN sync_metadata m
                ON m.entity_type = 'folder' AND m.local_id = f.id
            LEFT JOIN sync_metadata pm
                ON pm.entity_type = 'folder' AND pm.local_id = f.parent_folder_id
            WHERE m.dirty = 1
            ORDER BY m.client_updated_at ASC, f.id ASC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let name = stringColumn(stmt, 1)
                let parentLocalID = optionalInt64Column(stmt, 2)
                let colorHex = optionalStringColumn(stmt, 3)
                let iconName = optionalStringColumn(stmt, 4)
                let createdAt = stringColumn(stmt, 5)
                let folder = MeetingFolder(
                    id: id,
                    name: name,
                    parentFolderID: parentLocalID,
                    colorHex: colorHex,
                    iconName: iconName,
                    createdAt: createdAt
                )
                let metadata = SyncMetadataRecord(
                    entityType: .folder,
                    localID: id,
                    remoteID: optionalStringColumn(stmt, 6),
                    clientUpdatedAt: stringColumn(stmt, 7),
                    remoteVersion: sqlite3_column_int64(stmt, 8),
                    lastSeenServerUpdatedAt: optionalStringColumn(stmt, 9),
                    lastPayloadHash: optionalStringColumn(stmt, 10),
                    dirty: sqlite3_column_int(stmt, 11) != 0,
                    lastWriterDeviceID: optionalStringColumn(stmt, 12)
                )
                let parentRemoteID = optionalStringColumn(stmt, 13)
                result.append(DirtyFolder(metadata: metadata, record: folder, parentRemoteID: parentRemoteID))
            }
        }
        return result
    }

    public func dirtyTombstones(entityType: SyncEntityType, limit: Int = 100) throws -> [SyncTombstoneRecord] {
        var result: [SyncTombstoneRecord] = []
        try withDB { db in
            let sql = """
            SELECT entity_type, local_id, remote_id, client_deleted_at,
                   last_known_remote_version, dirty
            FROM sync_tombstones
            WHERE entity_type = ? AND dirty = 1
            ORDER BY client_deleted_at ASC, local_id ASC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, entityType.rawValue)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let parsedType = SyncEntityType(rawValue: stringColumn(stmt, 0)) else {
                    continue
                }
                result.append(
                    SyncTombstoneRecord(
                        entityType: parsedType,
                        localID: sqlite3_column_int64(stmt, 1),
                        remoteID: optionalStringColumn(stmt, 2),
                        clientDeletedAt: stringColumn(stmt, 3),
                        lastKnownRemoteVersion: sqlite3_column_int64(stmt, 4),
                        dirty: sqlite3_column_int(stmt, 5) != 0
                    )
                )
            }
        }
        return result
    }

    // MARK: - Mark synced (after successful upload)

    public func markDictationSynced(
        localID: Int64,
        remoteID: String,
        remoteVersion: Int64,
        clientUpdatedAt: String,
        serverUpdatedAt: String,
        payloadHash: String,
        lastWriterDeviceID: String
    ) throws {
        try writeMetadata(
            entityType: .dictation,
            localID: localID,
            remoteID: remoteID,
            remoteVersion: remoteVersion,
            clientUpdatedAt: clientUpdatedAt,
            serverUpdatedAt: serverUpdatedAt,
            payloadHash: payloadHash,
            lastWriterDeviceID: lastWriterDeviceID,
            dirty: false
        )
    }

    public func markMeetingSynced(
        localID: Int64,
        remoteID: String,
        remoteVersion: Int64,
        clientUpdatedAt: String,
        serverUpdatedAt: String,
        payloadHash: String,
        lastWriterDeviceID: String
    ) throws {
        try writeMetadata(
            entityType: .meeting,
            localID: localID,
            remoteID: remoteID,
            remoteVersion: remoteVersion,
            clientUpdatedAt: clientUpdatedAt,
            serverUpdatedAt: serverUpdatedAt,
            payloadHash: payloadHash,
            lastWriterDeviceID: lastWriterDeviceID,
            dirty: false
        )
    }

    public func markFolderSynced(
        localID: Int64,
        remoteID: String,
        remoteVersion: Int64,
        clientUpdatedAt: String,
        serverUpdatedAt: String,
        payloadHash: String,
        lastWriterDeviceID: String
    ) throws {
        try writeMetadata(
            entityType: .folder,
            localID: localID,
            remoteID: remoteID,
            remoteVersion: remoteVersion,
            clientUpdatedAt: clientUpdatedAt,
            serverUpdatedAt: serverUpdatedAt,
            payloadHash: payloadHash,
            lastWriterDeviceID: lastWriterDeviceID,
            dirty: false
        )
    }

    private func writeMetadata(
        entityType: SyncEntityType,
        localID: Int64,
        remoteID: String?,
        remoteVersion: Int64,
        clientUpdatedAt: String,
        serverUpdatedAt: String?,
        payloadHash: String?,
        lastWriterDeviceID: String?,
        dirty: Bool
    ) throws {
        try withDB { db in
            let sql = """
            INSERT INTO sync_metadata (
                entity_type, local_id, remote_id, client_updated_at,
                remote_version, last_seen_server_updated_at, last_payload_hash,
                dirty, last_writer_device_id, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
            ON CONFLICT(entity_type, local_id) DO UPDATE SET
                remote_id = excluded.remote_id,
                client_updated_at = excluded.client_updated_at,
                remote_version = excluded.remote_version,
                last_seen_server_updated_at = excluded.last_seen_server_updated_at,
                last_payload_hash = excluded.last_payload_hash,
                dirty = excluded.dirty,
                last_writer_device_id = excluded.last_writer_device_id,
                updated_at = datetime('now')
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, entityType.rawValue)
            sqlite3_bind_int64(stmt, 2, localID)
            bindOptionalText(stmt, 3, remoteID)
            bindText(stmt, 4, clientUpdatedAt)
            sqlite3_bind_int64(stmt, 5, remoteVersion)
            bindOptionalText(stmt, 6, serverUpdatedAt)
            bindOptionalText(stmt, 7, payloadHash)
            sqlite3_bind_int(stmt, 8, dirty ? 1 : 0)
            bindOptionalText(stmt, 9, lastWriterDeviceID)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw lastError(db)
            }
        }
    }

    // MARK: - Tombstones (post-upload cleanup)

    public func clearTombstone(entityType: SyncEntityType, localID: Int64) throws {
        try withDB { db in
            try exec(
                "DELETE FROM sync_tombstones WHERE entity_type = ? AND local_id = ?",
                params: [entityType.rawValue, String(localID)],
                db: db
            )
        }
    }

    /// Marks a tombstone clean (i.e. uploaded). Call this after a successful
    /// remote DELETE that you also want to retain locally (per §12.5).
    public func markTombstoneSynced(entityType: SyncEntityType, localID: Int64, lastKnownRemoteVersion: Int64) throws {
        try withDB { db in
            try exec(
                """
                UPDATE sync_tombstones
                SET dirty = 0, last_known_remote_version = ?, updated_at = datetime('now')
                WHERE entity_type = ? AND local_id = ?
                """,
                params: [String(lastKnownRemoteVersion), entityType.rawValue, String(localID)],
                db: db
            )
        }
    }

    public func purgeCleanTombstones(olderThanDays days: Int) throws {
        try withDB { db in
            let cutoff = SyncTimestamp.format(Date().addingTimeInterval(-Double(days) * 86_400))
            try exec(
                """
                DELETE FROM sync_tombstones
                WHERE dirty = 0 AND client_deleted_at < ?
                """,
                params: [cutoff],
                db: db
            )
        }
    }

    // MARK: - Apply remote changes

    public func applyRemoteFolder(_ payload: RemoteFolderPayload) throws {
        try withDB { db in
            try beginImmediateTransaction(db)
            do {
                let parentLocalID: Int64?
                if let parentRemoteID = payload.parentRemoteID {
                    if let id = try localID(forRemoteID: parentRemoteID, entityType: .folder, db: db) {
                        parentLocalID = id
                    } else {
                        // Parent has not been applied yet — leave NULL; it'll be
                        // reparented on a later cycle once the parent arrives.
                        parentLocalID = nil
                    }
                } else {
                    parentLocalID = nil
                }

                let existingLocalID = try localID(forRemoteID: payload.remoteID, entityType: .folder, db: db)

                if payload.deletedAt != nil {
                    if let existingLocalID {
                        try deleteFolder(localID: existingLocalID, db: db)
                        try clearTombstone(entityType: .folder, localID: existingLocalID, db: db)
                    }
                    try removeMetadata(entityType: .folder, remoteID: payload.remoteID, db: db)
                    try commit(db)
                    return
                }

                let localID: Int64
                if let existingLocalID {
                    try updateFolder(localID: existingLocalID, payload: payload, parentLocalID: parentLocalID, db: db)
                    localID = existingLocalID
                } else {
                    localID = try insertFolder(payload: payload, parentLocalID: parentLocalID, db: db)
                }

                let hash = SyncPayloadHasher.folderHash(
                    name: payload.name,
                    parentRemoteID: payload.parentRemoteID,
                    colorHex: payload.colorHex,
                    iconName: payload.iconName,
                    sortOrder: payload.sortOrder
                )
                try writeMetadata(
                    entityType: .folder,
                    localID: localID,
                    remoteID: payload.remoteID,
                    remoteVersion: payload.remoteVersion,
                    clientUpdatedAt: payload.clientUpdatedAt,
                    serverUpdatedAt: payload.serverUpdatedAt,
                    payloadHash: hash,
                    lastWriterDeviceID: payload.lastWriterDeviceID,
                    dirty: false,
                    db: db
                )
                try clearTombstone(entityType: .folder, localID: localID, db: db)
                try commit(db)
            } catch {
                rollback(db)
                throw error
            }
        }
    }

    public func applyRemoteDictation(_ payload: RemoteDictationPayload) throws {
        try withDB { db in
            try beginImmediateTransaction(db)
            do {
                let existingLocalID = try localID(forRemoteID: payload.remoteID, entityType: .dictation, db: db)

                if payload.deletedAt != nil {
                    if let existingLocalID {
                        try deleteDictation(localID: existingLocalID, db: db)
                        try clearTombstone(entityType: .dictation, localID: existingLocalID, db: db)
                    }
                    try removeMetadata(entityType: .dictation, remoteID: payload.remoteID, db: db)
                    try commit(db)
                    return
                }

                let localID: Int64
                if let existingLocalID {
                    try updateDictation(localID: existingLocalID, payload: payload, db: db)
                    localID = existingLocalID
                } else {
                    localID = try insertDictation(payload: payload, db: db)
                }

                let hash = SyncPayloadHasher.dictationHash(
                    timestamp: payload.timestamp,
                    durationSeconds: payload.durationSeconds,
                    rawText: payload.rawText,
                    appContext: payload.appContext,
                    wordCount: payload.wordCount,
                    source: payload.source,
                    startedAt: payload.startedAt,
                    endedAt: payload.endedAt
                )
                try writeMetadata(
                    entityType: .dictation,
                    localID: localID,
                    remoteID: payload.remoteID,
                    remoteVersion: payload.remoteVersion,
                    clientUpdatedAt: payload.clientUpdatedAt,
                    serverUpdatedAt: payload.serverUpdatedAt,
                    payloadHash: hash,
                    lastWriterDeviceID: payload.lastWriterDeviceID,
                    dirty: false,
                    db: db
                )
                try clearTombstone(entityType: .dictation, localID: localID, db: db)
                try commit(db)
            } catch {
                rollback(db)
                throw error
            }
        }
    }

    public func applyRemoteMeeting(_ payload: RemoteMeetingPayload) throws {
        try withDB { db in
            try beginImmediateTransaction(db)
            do {
                let folderLocalID: Int64?
                if let folderRemoteID = payload.folderRemoteID {
                    folderLocalID = try localID(forRemoteID: folderRemoteID, entityType: .folder, db: db)
                } else {
                    folderLocalID = nil
                }
                let mergedIntoMeetingLocalID: Int64?
                if let mergedIntoMeetingRemoteID = payload.mergedIntoMeetingRemoteID {
                    mergedIntoMeetingLocalID = try localID(
                        forRemoteID: mergedIntoMeetingRemoteID,
                        entityType: .meeting,
                        db: db
                    )
                } else {
                    mergedIntoMeetingLocalID = nil
                }

                let existingLocalID = try localID(forRemoteID: payload.remoteID, entityType: .meeting, db: db)

                if payload.deletedAt != nil {
                    if let existingLocalID {
                        try deleteMeeting(localID: existingLocalID, db: db)
                        try clearTombstone(entityType: .meeting, localID: existingLocalID, db: db)
                    }
                    try removeMetadata(entityType: .meeting, remoteID: payload.remoteID, db: db)
                    try commit(db)
                    return
                }

                let localID: Int64
                if let existingLocalID {
                    try updateMeeting(
                        localID: existingLocalID,
                        payload: payload,
                        folderLocalID: folderLocalID,
                        mergedIntoMeetingLocalID: mergedIntoMeetingLocalID,
                        db: db
                    )
                    localID = existingLocalID
                } else {
                    localID = try insertMeeting(
                        payload: payload,
                        folderLocalID: folderLocalID,
                        mergedIntoMeetingLocalID: mergedIntoMeetingLocalID,
                        db: db
                    )
                }

                let hash = SyncPayloadHasher.meetingHash(
                    title: payload.title,
                    calendarEventID: payload.calendarEventID,
                    calendarEventSnapshotJSON: payload.calendarEventSnapshotJSON,
                    startTime: payload.startTime,
                    endTime: payload.endTime,
                    durationSeconds: payload.durationSeconds,
                    rawTranscript: payload.rawTranscript,
                    formattedNotes: payload.formattedNotes,
                    meetingStatus: payload.meetingStatus,
                    manualNotes: payload.manualNotes,
                    wordCount: payload.wordCount,
                    selectedTemplateID: payload.selectedTemplateID,
                    selectedTemplateName: payload.selectedTemplateName,
                    selectedTemplateKind: payload.selectedTemplateKind,
                    selectedTemplatePrompt: payload.selectedTemplatePrompt,
                    folderRemoteID: payload.folderRemoteID,
                    mergedIntoMeetingRemoteID: payload.mergedIntoMeetingRemoteID
                )
                try writeMetadata(
                    entityType: .meeting,
                    localID: localID,
                    remoteID: payload.remoteID,
                    remoteVersion: payload.remoteVersion,
                    clientUpdatedAt: payload.clientUpdatedAt,
                    serverUpdatedAt: payload.serverUpdatedAt,
                    payloadHash: hash,
                    lastWriterDeviceID: payload.lastWriterDeviceID,
                    dirty: false,
                    db: db
                )
                try clearTombstone(entityType: .meeting, localID: localID, db: db)
                try commit(db)
            } catch {
                rollback(db)
                throw error
            }
        }
    }

    /// Applies remote preferences. The caller is responsible for actually
    /// writing the snapshot back to AppConfig — this method only updates
    /// `sync_state` so we know we're now in sync with the remote version.
    public func applyRemotePreferencesState(
        clientUpdatedAt: String,
        serverUpdatedAt: String,
        remoteVersion: Int64,
        payloadHash: String,
        lastWriterDeviceID: String
    ) throws {
        try withDB { db in
            try writeStateValue(.preferencesDirty, value: "false", db: db)
            try writeStateValue(.preferencesRemoteVersion, value: String(remoteVersion), db: db)
            try writeStateValue(.preferencesClientUpdatedAt, value: clientUpdatedAt, db: db)
            try writeStateValue(.preferencesLastSeenServerUpdatedAt, value: serverUpdatedAt, db: db)
            try writeStateValue(.preferencesLastPayloadHash, value: payloadHash, db: db)
            try writeStateValue(.preferencesLastWriterDeviceID, value: lastWriterDeviceID, db: db)
        }
    }

    // MARK: - Reconciliation helpers

    /// Returns dictations that have no `remote_id` yet, intended for first-sync
    /// fingerprint matching against the remote table.
    public func unsyncedDictations(limit: Int = 500) throws -> [DictationRecord] {
        var result: [DictationRecord] = []
        try withDB { db in
            let sql = """
            SELECT d.id, d.timestamp, d.duration_seconds, d.raw_text,
                   d.app_context, d.word_count
            FROM dictations d
            JOIN sync_metadata m
                ON m.entity_type = 'dictation' AND m.local_id = d.id
            WHERE m.remote_id IS NULL
            ORDER BY d.id ASC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(
                    DictationRecord(
                        id: sqlite3_column_int64(stmt, 0),
                        timestamp: stringColumn(stmt, 1),
                        durationSeconds: sqlite3_column_double(stmt, 2),
                        rawText: stringColumn(stmt, 3),
                        appContext: stringColumn(stmt, 4),
                        wordCount: Int(sqlite3_column_int(stmt, 5))
                    )
                )
            }
        }
        return result
    }

    public func unsyncedMeetings(limit: Int = 200) throws -> [MeetingRecord] {
        var result: [MeetingRecord] = []
        try withDB { db in
            let sql = """
            SELECT
                me.id, me.title, me.start_time, me.duration_seconds,
                me.raw_transcript, me.formatted_notes, me.word_count,
                me.folder_id, me.calendar_event_id, me.mic_audio_path,
                me.system_audio_path, me.saved_recording_path,
                me.merged_into_meeting_id, me.meeting_status, me.manual_notes,
                me.selected_template_id, me.selected_template_name,
                me.selected_template_kind, me.selected_template_prompt,
                me.calendar_event_snapshot
            FROM meetings me
            JOIN sync_metadata m
                ON m.entity_type = 'meeting' AND m.local_id = me.id
            WHERE m.remote_id IS NULL
              AND me.meeting_status NOT IN ('recording', 'processing')
            ORDER BY me.id ASC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(makeMeetingRecord(stmt: stmt, baseColumn: 0))
            }
        }
        return result
    }

    public func unsyncedFolders(limit: Int = 500) throws -> [MeetingFolder] {
        var result: [MeetingFolder] = []
        try withDB { db in
            let sql = """
            SELECT f.id, f.name, f.parent_folder_id, f.color_hex, f.icon_name, f.created_at
            FROM meeting_folders f
            JOIN sync_metadata m
                ON m.entity_type = 'folder' AND m.local_id = f.id
            WHERE m.remote_id IS NULL
            ORDER BY f.id ASC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(
                    MeetingFolder(
                        id: sqlite3_column_int64(stmt, 0),
                        name: stringColumn(stmt, 1),
                        parentFolderID: optionalInt64Column(stmt, 2),
                        colorHex: optionalStringColumn(stmt, 3),
                        iconName: optionalStringColumn(stmt, 4),
                        createdAt: stringColumn(stmt, 5)
                    )
                )
            }
        }
        return result
    }

    public func attachRemoteID(
        entityType: SyncEntityType,
        localID: Int64,
        remoteID: String,
        remoteVersion: Int64,
        clientUpdatedAt: String,
        serverUpdatedAt: String,
        payloadHash: String,
        lastWriterDeviceID: String
    ) throws {
        try writeMetadata(
            entityType: entityType,
            localID: localID,
            remoteID: remoteID,
            remoteVersion: remoteVersion,
            clientUpdatedAt: clientUpdatedAt,
            serverUpdatedAt: serverUpdatedAt,
            payloadHash: payloadHash,
            lastWriterDeviceID: lastWriterDeviceID,
            dirty: false
        )
    }

    public func localID(forRemoteID remoteID: String, entityType: SyncEntityType) throws -> Int64? {
        var found: Int64?
        try withDB { db in
            found = try localID(forRemoteID: remoteID, entityType: entityType, db: db)
        }
        return found
    }

    /// Finds an unmapped local dictation that matches the remote payload's
    /// fingerprint. Used during first-sync reconciliation.
    public func findUnmappedDictation(timestamp: String, rawText: String, appContext: String) throws -> Int64? {
        var found: Int64?
        try withDB { db in
            let sql = """
            SELECT d.id FROM dictations d
            LEFT JOIN sync_metadata m
                ON m.entity_type = 'dictation' AND m.local_id = d.id
            WHERE (m.remote_id IS NULL OR m.local_id IS NULL)
              AND d.timestamp = ? AND d.raw_text = ? AND d.app_context = ?
            ORDER BY d.id ASC
            LIMIT 1
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, timestamp)
            bindText(stmt, 2, rawText)
            bindText(stmt, 3, appContext)
            if sqlite3_step(stmt) == SQLITE_ROW {
                found = sqlite3_column_int64(stmt, 0)
            }
        }
        return found
    }

    /// Finds a local meeting matching the given calendar_event_id and start
    /// time that is not yet mapped to a remote_id.
    public func findUnmappedMeetingByCalendar(calendarEventID: String, startTime: String) throws -> Int64? {
        var found: Int64?
        try withDB { db in
            let sql = """
            SELECT me.id FROM meetings me
            LEFT JOIN sync_metadata m
                ON m.entity_type = 'meeting' AND m.local_id = me.id
            WHERE (m.remote_id IS NULL OR m.local_id IS NULL)
              AND me.calendar_event_id = ?
              AND me.start_time = ?
              AND me.meeting_status NOT IN ('recording', 'processing')
            ORDER BY me.id ASC
            LIMIT 1
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, calendarEventID)
            bindText(stmt, 2, startTime)
            if sqlite3_step(stmt) == SQLITE_ROW {
                found = sqlite3_column_int64(stmt, 0)
            }
        }
        return found
    }

    /// Finds an unmapped local meeting by transcript fingerprint when
    /// calendar_event_id is unavailable.
    public func findUnmappedMeetingByFingerprint(
        startTime: String,
        durationSeconds: Double,
        rawTranscript: String
    ) throws -> Int64? {
        var found: Int64?
        try withDB { db in
            let sql = """
            SELECT me.id FROM meetings me
            LEFT JOIN sync_metadata m
                ON m.entity_type = 'meeting' AND m.local_id = me.id
            WHERE (m.remote_id IS NULL OR m.local_id IS NULL)
              AND me.start_time = ?
              AND ABS(COALESCE(me.duration_seconds, 0) - ?) < 0.001
              AND me.raw_transcript = ?
              AND me.meeting_status NOT IN ('recording', 'processing')
            ORDER BY me.id ASC
            LIMIT 1
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, startTime)
            sqlite3_bind_double(stmt, 2, durationSeconds)
            bindText(stmt, 3, rawTranscript)
            if sqlite3_step(stmt) == SQLITE_ROW {
                found = sqlite3_column_int64(stmt, 0)
            }
        }
        return found
    }

    /// Finds an unmapped local folder by name + parent (resolved via
    /// sync_metadata). When `parentRemoteID` is nil the search restricts to
    /// folders without a parent.
    public func findUnmappedFolder(name: String, parentRemoteID: String?) throws -> Int64? {
        var found: Int64?
        try withDB { db in
            let parentLocalID: Int64?
            if let parentRemoteID {
                parentLocalID = try localID(forRemoteID: parentRemoteID, entityType: .folder, db: db)
                if parentLocalID == nil { return }
            } else {
                parentLocalID = nil
            }
            let parentClause = parentLocalID == nil
                ? "f.parent_folder_id IS NULL"
                : "f.parent_folder_id = ?"
            let sql = """
            SELECT f.id FROM meeting_folders f
            LEFT JOIN sync_metadata m
                ON m.entity_type = 'folder' AND m.local_id = f.id
            WHERE (m.remote_id IS NULL OR m.local_id IS NULL)
              AND f.name = ?
              AND \(parentClause)
            ORDER BY f.id ASC
            LIMIT 1
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, name)
            if let parentLocalID {
                sqlite3_bind_int64(stmt, 2, parentLocalID)
            }
            if sqlite3_step(stmt) == SQLITE_ROW {
                found = sqlite3_column_int64(stmt, 0)
            }
        }
        return found
    }

    /// Resolves a remote folder UUID from a local folder id. Returns nil when
    /// the folder is not yet synced.
    public func remoteID(forLocalID localID: Int64, entityType: SyncEntityType) throws -> String? {
        var remoteID: String?
        try withDB { db in
            let sql = """
            SELECT remote_id FROM sync_metadata
            WHERE entity_type = ? AND local_id = ?
            LIMIT 1
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, entityType.rawValue)
            sqlite3_bind_int64(stmt, 2, localID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                remoteID = optionalStringColumn(stmt, 0)
            }
        }
        return remoteID
    }

    public func metadata(entityType: SyncEntityType, localID: Int64) throws -> SyncMetadataRecord? {
        var result: SyncMetadataRecord?
        try withDB { db in
            let sql = """
            SELECT remote_id, client_updated_at, remote_version,
                   last_seen_server_updated_at, last_payload_hash, dirty,
                   last_writer_device_id
            FROM sync_metadata
            WHERE entity_type = ? AND local_id = ?
            LIMIT 1
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, entityType.rawValue)
            sqlite3_bind_int64(stmt, 2, localID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = SyncMetadataRecord(
                    entityType: entityType,
                    localID: localID,
                    remoteID: optionalStringColumn(stmt, 0),
                    clientUpdatedAt: stringColumn(stmt, 1),
                    remoteVersion: sqlite3_column_int64(stmt, 2),
                    lastSeenServerUpdatedAt: optionalStringColumn(stmt, 3),
                    lastPayloadHash: optionalStringColumn(stmt, 4),
                    dirty: sqlite3_column_int(stmt, 5) != 0,
                    lastWriterDeviceID: optionalStringColumn(stmt, 6)
                )
            }
        }
        return result
    }

    // MARK: - Domain row writers (used by applyRemote*)

    private func insertDictation(payload: RemoteDictationPayload, db: OpaquePointer?) throws -> Int64 {
        let sql = """
        INSERT INTO dictations
        (timestamp, duration_seconds, raw_text, app_context, word_count, source, started_at, ended_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, payload.timestamp)
        sqlite3_bind_double(stmt, 2, payload.durationSeconds)
        bindText(stmt, 3, payload.rawText)
        bindText(stmt, 4, payload.appContext)
        sqlite3_bind_int(stmt, 5, Int32(payload.wordCount))
        bindText(stmt, 6, payload.source)
        bindOptionalText(stmt, 7, payload.startedAt)
        bindOptionalText(stmt, 8, payload.endedAt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw lastError(db)
        }
        return sqlite3_last_insert_rowid(db)
    }

    private func updateDictation(localID: Int64, payload: RemoteDictationPayload, db: OpaquePointer?) throws {
        let sql = """
        UPDATE dictations
        SET timestamp = ?, duration_seconds = ?, raw_text = ?, app_context = ?,
            word_count = ?, source = ?, started_at = ?, ended_at = ?
        WHERE id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, payload.timestamp)
        sqlite3_bind_double(stmt, 2, payload.durationSeconds)
        bindText(stmt, 3, payload.rawText)
        bindText(stmt, 4, payload.appContext)
        sqlite3_bind_int(stmt, 5, Int32(payload.wordCount))
        bindText(stmt, 6, payload.source)
        bindOptionalText(stmt, 7, payload.startedAt)
        bindOptionalText(stmt, 8, payload.endedAt)
        sqlite3_bind_int64(stmt, 9, localID)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    private func deleteDictation(localID: Int64, db: OpaquePointer?) throws {
        try exec("DELETE FROM dictations WHERE id = ?", params: [String(localID)], db: db)
    }

    private func insertMeeting(
        payload: RemoteMeetingPayload,
        folderLocalID: Int64?,
        mergedIntoMeetingLocalID: Int64?,
        db: OpaquePointer?
    ) throws -> Int64 {
        let sql = """
        INSERT INTO meetings
        (title, calendar_event_id, calendar_event_snapshot, start_time, end_time,
         duration_seconds, raw_transcript, formatted_notes, mic_audio_path,
         system_audio_path, saved_recording_path, merged_into_meeting_id,
         meeting_status, manual_notes, word_count, selected_template_id,
         selected_template_name, selected_template_kind,
         selected_template_prompt, source, folder_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?, ?, ?, ?, ?, ?, ?, ?, 'meeting', ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, payload.title)
        bindOptionalText(stmt, 2, payload.calendarEventID)
        bindOptionalText(stmt, 3, payload.calendarEventSnapshotJSON)
        bindText(stmt, 4, payload.startTime)
        bindOptionalText(stmt, 5, payload.endTime)
        if let duration = payload.durationSeconds {
            sqlite3_bind_double(stmt, 6, duration)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        bindText(stmt, 7, payload.rawTranscript)
        bindText(stmt, 8, payload.formattedNotes)
        if let mergedIntoMeetingLocalID {
            sqlite3_bind_int64(stmt, 9, mergedIntoMeetingLocalID)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        bindText(stmt, 10, payload.meetingStatus)
        bindText(stmt, 11, payload.manualNotes)
        sqlite3_bind_int(stmt, 12, Int32(payload.wordCount))
        bindOptionalText(stmt, 13, payload.selectedTemplateID)
        bindOptionalText(stmt, 14, payload.selectedTemplateName)
        bindOptionalText(stmt, 15, payload.selectedTemplateKind)
        bindOptionalText(stmt, 16, payload.selectedTemplatePrompt)
        if let folderLocalID {
            sqlite3_bind_int64(stmt, 17, folderLocalID)
        } else {
            sqlite3_bind_null(stmt, 17)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw lastError(db)
        }
        return sqlite3_last_insert_rowid(db)
    }

    private func updateMeeting(
        localID: Int64,
        payload: RemoteMeetingPayload,
        folderLocalID: Int64?,
        mergedIntoMeetingLocalID: Int64?,
        db: OpaquePointer?
    ) throws {
        // Preserve audio paths (mic_audio_path, system_audio_path,
        // saved_recording_path) — these are local-only fields per §23.
        let sql = """
        UPDATE meetings
        SET title = ?, calendar_event_id = ?, calendar_event_snapshot = ?,
            start_time = ?, end_time = ?, duration_seconds = ?,
            raw_transcript = ?, formatted_notes = ?, meeting_status = ?,
            manual_notes = ?, word_count = ?, selected_template_id = ?,
            selected_template_name = ?, selected_template_kind = ?,
            selected_template_prompt = ?, folder_id = ?,
            merged_into_meeting_id = ?
        WHERE id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, payload.title)
        bindOptionalText(stmt, 2, payload.calendarEventID)
        bindOptionalText(stmt, 3, payload.calendarEventSnapshotJSON)
        bindText(stmt, 4, payload.startTime)
        bindOptionalText(stmt, 5, payload.endTime)
        if let duration = payload.durationSeconds {
            sqlite3_bind_double(stmt, 6, duration)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        bindText(stmt, 7, payload.rawTranscript)
        bindText(stmt, 8, payload.formattedNotes)
        bindText(stmt, 9, payload.meetingStatus)
        bindText(stmt, 10, payload.manualNotes)
        sqlite3_bind_int(stmt, 11, Int32(payload.wordCount))
        bindOptionalText(stmt, 12, payload.selectedTemplateID)
        bindOptionalText(stmt, 13, payload.selectedTemplateName)
        bindOptionalText(stmt, 14, payload.selectedTemplateKind)
        bindOptionalText(stmt, 15, payload.selectedTemplatePrompt)
        if let folderLocalID {
            sqlite3_bind_int64(stmt, 16, folderLocalID)
        } else {
            sqlite3_bind_null(stmt, 16)
        }
        if let mergedIntoMeetingLocalID {
            sqlite3_bind_int64(stmt, 17, mergedIntoMeetingLocalID)
        } else {
            sqlite3_bind_null(stmt, 17)
        }
        sqlite3_bind_int64(stmt, 18, localID)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    private func deleteMeeting(localID: Int64, db: OpaquePointer?) throws {
        try exec(
            "UPDATE meetings SET merged_into_meeting_id = NULL WHERE merged_into_meeting_id = ?",
            params: [String(localID)],
            db: db
        )
        try exec("DELETE FROM meetings WHERE id = ?", params: [String(localID)], db: db)
    }

    private func insertFolder(
        payload: RemoteFolderPayload,
        parentLocalID: Int64?,
        db: OpaquePointer?
    ) throws -> Int64 {
        let sql = """
        INSERT INTO meeting_folders
        (name, parent_folder_id, color_hex, icon_name, sort_order)
        VALUES (?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, payload.name)
        if let parentLocalID {
            sqlite3_bind_int64(stmt, 2, parentLocalID)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        bindOptionalText(stmt, 3, payload.colorHex)
        bindOptionalText(stmt, 4, payload.iconName)
        sqlite3_bind_int(stmt, 5, Int32(payload.sortOrder))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw lastError(db)
        }
        return sqlite3_last_insert_rowid(db)
    }

    private func updateFolder(
        localID: Int64,
        payload: RemoteFolderPayload,
        parentLocalID: Int64?,
        db: OpaquePointer?
    ) throws {
        let sql = """
        UPDATE meeting_folders
        SET name = ?, parent_folder_id = ?, color_hex = ?, icon_name = ?, sort_order = ?
        WHERE id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, payload.name)
        if let parentLocalID {
            sqlite3_bind_int64(stmt, 2, parentLocalID)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        bindOptionalText(stmt, 3, payload.colorHex)
        bindOptionalText(stmt, 4, payload.iconName)
        sqlite3_bind_int(stmt, 5, Int32(payload.sortOrder))
        sqlite3_bind_int64(stmt, 6, localID)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    private func deleteFolder(localID: Int64, db: OpaquePointer?) throws {
        // Mirror DictationStore.deleteFolder semantics minus the transaction
        // (we are already inside one): null out child meetings, reparent
        // grandchildren, then delete the folder.
        var parentID: Int64?
        let parentLookup = "SELECT parent_folder_id FROM meeting_folders WHERE id = ? LIMIT 1"
        var s0: OpaquePointer?
        guard sqlite3_prepare_v2(db, parentLookup, -1, &s0, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        sqlite3_bind_int64(s0, 1, localID)
        if sqlite3_step(s0) == SQLITE_ROW, sqlite3_column_type(s0, 0) != SQLITE_NULL {
            parentID = sqlite3_column_int64(s0, 0)
        }
        sqlite3_finalize(s0)

        try exec("UPDATE meetings SET folder_id = NULL WHERE folder_id = ?", params: [String(localID)], db: db)
        if let parentID {
            try exec(
                "UPDATE meeting_folders SET parent_folder_id = ? WHERE parent_folder_id = ?",
                params: [String(parentID), String(localID)],
                db: db
            )
        } else {
            try exec(
                "UPDATE meeting_folders SET parent_folder_id = NULL WHERE parent_folder_id = ?",
                params: [String(localID)],
                db: db
            )
        }
        try exec("DELETE FROM meeting_folders WHERE id = ?", params: [String(localID)], db: db)
    }

    private func clearTombstone(entityType: SyncEntityType, localID: Int64, db: OpaquePointer?) throws {
        try exec(
            "DELETE FROM sync_tombstones WHERE entity_type = ? AND local_id = ?",
            params: [entityType.rawValue, String(localID)],
            db: db
        )
    }

    private func removeMetadata(entityType: SyncEntityType, remoteID: String, db: OpaquePointer?) throws {
        try exec(
            "DELETE FROM sync_metadata WHERE entity_type = ? AND remote_id = ?",
            params: [entityType.rawValue, remoteID],
            db: db
        )
    }

    private func writeMetadata(
        entityType: SyncEntityType,
        localID: Int64,
        remoteID: String?,
        remoteVersion: Int64,
        clientUpdatedAt: String,
        serverUpdatedAt: String?,
        payloadHash: String?,
        lastWriterDeviceID: String?,
        dirty: Bool,
        db: OpaquePointer?
    ) throws {
        let sql = """
        INSERT INTO sync_metadata (
            entity_type, local_id, remote_id, client_updated_at,
            remote_version, last_seen_server_updated_at, last_payload_hash,
            dirty, last_writer_device_id, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(entity_type, local_id) DO UPDATE SET
            remote_id = excluded.remote_id,
            client_updated_at = excluded.client_updated_at,
            remote_version = excluded.remote_version,
            last_seen_server_updated_at = excluded.last_seen_server_updated_at,
            last_payload_hash = excluded.last_payload_hash,
            dirty = excluded.dirty,
            last_writer_device_id = excluded.last_writer_device_id,
            updated_at = datetime('now')
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, entityType.rawValue)
        sqlite3_bind_int64(stmt, 2, localID)
        bindOptionalText(stmt, 3, remoteID)
        bindText(stmt, 4, clientUpdatedAt)
        sqlite3_bind_int64(stmt, 5, remoteVersion)
        bindOptionalText(stmt, 6, serverUpdatedAt)
        bindOptionalText(stmt, 7, payloadHash)
        sqlite3_bind_int(stmt, 8, dirty ? 1 : 0)
        bindOptionalText(stmt, 9, lastWriterDeviceID)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    private func localID(forRemoteID remoteID: String, entityType: SyncEntityType, db: OpaquePointer?) throws -> Int64? {
        let sql = """
        SELECT local_id FROM sync_metadata
        WHERE entity_type = ? AND remote_id = ?
        LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, entityType.rawValue)
        bindText(stmt, 2, remoteID)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return nil
    }

    // MARK: - sync_state I/O

    private func loadStateValue(_ key: SyncStateKey) throws -> String? {
        var value: String?
        try withDB { db in
            value = try loadStateValue(key, db: db)
        }
        return value
    }

    private func loadStateValue(_ key: SyncStateKey, db: OpaquePointer?) throws -> String? {
        let sql = "SELECT value FROM sync_state WHERE key = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, key.rawValue)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return optionalStringColumn(stmt, 0)
        }
        return nil
    }

    private func writeStateValue(_ key: SyncStateKey, value: String) throws {
        try withDB { db in
            try writeStateValue(key, value: value, db: db)
        }
    }

    private func writeStateValue(_ key: SyncStateKey, value: String, db: OpaquePointer?) throws {
        let sql = """
        INSERT INTO sync_state (key, value, updated_at)
        VALUES (?, ?, datetime('now'))
        ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            updated_at = datetime('now')
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, key.rawValue)
        bindText(stmt, 2, value)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    // MARK: - DB helpers

    private func withDB(_ body: (OpaquePointer?) throws -> Void) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            let err = lastError(db)
            sqlite3_close(db)
            throw err
        }
        defer { sqlite3_close(db) }
        if sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
        if sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
        try body(db)
    }

    private func beginImmediateTransaction(_ db: OpaquePointer?) throws {
        if sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
    }

    private func commit(_ db: OpaquePointer?) throws {
        if sqlite3_exec(db, "COMMIT", nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
    }

    private func rollback(_ db: OpaquePointer?) {
        sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
    }

    private func exec(_ sql: String, db: OpaquePointer?) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
    }

    private func exec(_ sql: String, params: [String], db: OpaquePointer?) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(stmt) }
        for (index, value) in params.enumerated() {
            bindText(stmt, Int32(index + 1), value)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, nil)
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func stringColumn(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }

    private func optionalStringColumn(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func optionalInt64Column(_ stmt: OpaquePointer?, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(stmt, index)
    }

    private func makeMeetingRecord(stmt: OpaquePointer?, baseColumn: Int32) -> MeetingRecord {
        let folderID = optionalInt64Column(stmt, baseColumn + 7)
        let calendarEventID = optionalStringColumn(stmt, baseColumn + 8)
        let micAudio = optionalStringColumn(stmt, baseColumn + 9)
        let systemAudio = optionalStringColumn(stmt, baseColumn + 10)
        let savedRecording = optionalStringColumn(stmt, baseColumn + 11)
        let mergedIntoMeetingID = optionalInt64Column(stmt, baseColumn + 12)
        let status = MeetingStatus(rawValue: stringColumn(stmt, baseColumn + 13)) ?? .completed
        let manualNotes = stringColumn(stmt, baseColumn + 14)
        let templateID = optionalStringColumn(stmt, baseColumn + 15)
        let templateName = optionalStringColumn(stmt, baseColumn + 16)
        let templateKindRaw = optionalStringColumn(stmt, baseColumn + 17)
        let templateKind = templateKindRaw.flatMap(MeetingTemplateKind.init(rawValue:))
        let templatePrompt = optionalStringColumn(stmt, baseColumn + 18)
        let snapshotJSON = optionalStringColumn(stmt, baseColumn + 19)
        let snapshot: MeetingCalendarEventSnapshot? = {
            guard let json = snapshotJSON, let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(MeetingCalendarEventSnapshot.self, from: data)
        }()
        return MeetingRecord(
            id: sqlite3_column_int64(stmt, baseColumn + 0),
            title: stringColumn(stmt, baseColumn + 1),
            startTime: stringColumn(stmt, baseColumn + 2),
            durationSeconds: sqlite3_column_double(stmt, baseColumn + 3),
            rawTranscript: stringColumn(stmt, baseColumn + 4),
            formattedNotes: stringColumn(stmt, baseColumn + 5),
            wordCount: Int(sqlite3_column_int(stmt, baseColumn + 6)),
            folderID: folderID,
            calendarEventID: calendarEventID,
            calendarEventSnapshot: snapshot,
            micAudioPath: micAudio,
            systemAudioPath: systemAudio,
            savedRecordingPath: savedRecording,
            mergedIntoMeetingID: mergedIntoMeetingID,
            status: status,
            manualNotes: manualNotes,
            selectedTemplateID: templateID,
            selectedTemplateName: templateName,
            selectedTemplateKind: templateKind,
            selectedTemplatePrompt: templatePrompt
        )
    }

    private func lastError(_ db: OpaquePointer?) -> NSError {
        let code = sqlite3_errcode(db)
        let message = String(cString: sqlite3_errmsg(db))
        return NSError(
            domain: "MuesliSyncDB",
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
