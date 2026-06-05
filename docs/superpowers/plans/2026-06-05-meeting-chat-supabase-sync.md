# Meeting Chat Supabase Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync Meeting Chat threads and messages through Supabase using the normal sync cycle, including existing local chats and global clear-chat deletes.

**Architecture:** Add chat-specific sync metadata and tombstones beside the existing local chat tables, then integrate a dedicated `MeetingChatSyncRepository` into `SupabaseSyncManager`. Remote chat rows live in new Supabase tables and are accessed through `SupabaseRESTClient`; the existing `LocalSyncRepository` remains unchanged for dictations, meetings, folders, and preferences.

**Tech Stack:** Swift 5.9, Swift Testing, SQLite3, URLSession/PostgREST, Supabase SQL migrations, existing `MuesliMeetingChat` and `MuesliNativeApp` modules.

---

## File Structure

- Create `supabase/migrations/20260605000000_add_meeting_chat_sync.sql`
  - Remote schema, indexes, version triggers, and RLS policies for chat threads/messages.
- Create `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncModels.swift`
  - Local dirty metadata, tombstone, remote payload, cursor key, and hash helpers for chat sync.
- Create `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift`
  - SQLite metadata/tombstone migration, backfill, dirty-row loading, apply-remote, mark-synced, tombstone helpers, and local/remote ID resolution for chat.
- Modify `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/SQLiteMeetingChatStore.swift`
  - Add hooks so local thread/message inserts and clear-thread operations mark chat sync metadata/tombstones.
- Modify `native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseRESTClient.swift`
  - Add remote payload parsing and select/upsert/update/fetch methods for chat threads/messages.
- Modify `native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseSyncManager.swift`
  - Own and run chat sync after meetings/folders are synced and before existing tombstone purge finishes.
- Modify `native/MuesliNative/Sources/MuesliNativeApp/AppDelegate.swift`
  - Wire `MeetingChatSyncRepository` into `SupabaseSyncManager`.
- Modify `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift`
  - Construct the chat sync repository using the same SQLite database URL as `DictationStore`.
- Modify `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`
  - Clarify clear-chat copy if the existing panel uses a confirmation.
- Test `native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift`
  - Local metadata/backfill/tombstone/apply behavior.
- Test `native/MuesliNative/Tests/MuesliTests/SupabaseRESTClientTests.swift`
  - Existing file; extend for chat REST methods.
- Test `native/MuesliNative/Tests/MuesliTests/MeetingChatSyncManagerTests.swift`
  - Focused sync ordering through source-order tests plus repository and REST boundary tests.

---

### Task 1: Supabase Migration For Chat Sync

**Files:**
- Create: `supabase/migrations/20260605000000_add_meeting_chat_sync.sql`
- Test: `native/MuesliNative/Tests/MuesliTests/SupabaseRESTClientTests.swift`

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/20260605000000_add_meeting_chat_sync.sql`:

```sql
-- Muesli Meeting Chat sync schema
-- Adds remote chat threads/messages for normal Supabase sync.

set check_function_bodies = off;

create table if not exists public.meeting_chat_threads (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    scope_kind text not null check (scope_kind in ('meeting', 'folder')),
    scope_id uuid not null,
    title text not null,
    summary text not null default '',
    client_updated_at timestamptz not null,
    server_updated_at timestamptz not null default now(),
    remote_version bigint not null default 1,
    last_writer_device_id text not null,
    deleted_at timestamptz
);

create index if not exists idx_meeting_chat_threads_user_cursor
    on public.meeting_chat_threads (user_id, server_updated_at, id);

create index if not exists idx_meeting_chat_threads_scope
    on public.meeting_chat_threads (user_id, scope_kind, scope_id);

create table if not exists public.meeting_chat_messages (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    thread_id uuid not null references public.meeting_chat_threads(id) on delete cascade,
    role text not null check (role in ('user', 'assistant', 'error')),
    content text not null,
    sources_json jsonb not null default '[]'::jsonb,
    created_at timestamptz not null,
    client_updated_at timestamptz not null,
    server_updated_at timestamptz not null default now(),
    remote_version bigint not null default 1,
    last_writer_device_id text not null,
    deleted_at timestamptz
);

create index if not exists idx_meeting_chat_messages_user_cursor
    on public.meeting_chat_messages (user_id, server_updated_at, id);

create index if not exists idx_meeting_chat_messages_thread_created
    on public.meeting_chat_messages (user_id, thread_id, created_at);

drop trigger if exists trg_meeting_chat_threads_version on public.meeting_chat_threads;
create trigger trg_meeting_chat_threads_version
    before update on public.meeting_chat_threads
    for each row execute function public.bump_remote_version();

drop trigger if exists trg_meeting_chat_messages_version on public.meeting_chat_messages;
create trigger trg_meeting_chat_messages_version
    before update on public.meeting_chat_messages
    for each row execute function public.bump_remote_version();

alter table public.meeting_chat_threads enable row level security;
alter table public.meeting_chat_messages enable row level security;

drop policy if exists meeting_chat_threads_own on public.meeting_chat_threads;
create policy meeting_chat_threads_own on public.meeting_chat_threads
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists meeting_chat_messages_own on public.meeting_chat_messages;
create policy meeting_chat_messages_own on public.meeting_chat_messages
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

- [ ] **Step 2: Run migration syntax check**

Run:

```bash
rg -n "meeting_chat_threads|meeting_chat_messages|meeting_chat_threads_own|meeting_chat_messages_own" supabase/migrations/20260605000000_add_meeting_chat_sync.sql
```

Expected: output includes both table names, both trigger names, and both RLS policy names.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260605000000_add_meeting_chat_sync.sql
git commit -m "db: add meeting chat sync schema"
```

---

### Task 2: Chat Sync Models And Hashing

**Files:**
- Create: `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncModels.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift`

- [ ] **Step 1: Write failing model/hash tests**

Create `native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift`:

```swift
import Foundation
import MuesliCore
import MuesliMeetingChat
import Testing
@testable import MuesliNativeApp

@Suite("Meeting chat sync repository", .serialized)
struct MeetingChatSyncRepositoryTests {
    @Test("thread hash changes when sync-visible fields change")
    func threadHashChangesForVisibleFields() {
        let original = MeetingChatSyncHasher.threadHash(
            scopeKind: "meeting",
            scopeRemoteID: "meeting-remote-1",
            title: "Customer Review",
            summary: "Renewal risk"
        )
        let renamed = MeetingChatSyncHasher.threadHash(
            scopeKind: "meeting",
            scopeRemoteID: "meeting-remote-1",
            title: "Customer Review Updated",
            summary: "Renewal risk"
        )

        #expect(original != renamed)
    }

    @Test("message hash is stable for equivalent source JSON")
    func messageHashStableForSources() throws {
        let sources = [
            MeetingChatSource(meetingID: 10, title: "Sync", startTime: "2026-06-05T10:00:00Z")
        ]
        let first = try MeetingChatSyncHasher.messageHash(
            role: .assistant,
            content: "Answer",
            sources: sources,
            createdAt: "2026-06-05T10:01:00.000Z"
        )
        let second = try MeetingChatSyncHasher.messageHash(
            role: .assistant,
            content: "Answer",
            sources: sources,
            createdAt: "2026-06-05T10:01:00.000Z"
        )

        #expect(first == second)
        #expect(!first.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter 'threadHashChangesForVisibleFields|messageHashStableForSources'
```

Expected: FAIL because `MeetingChatSyncHasher` does not exist.

- [ ] **Step 3: Implement models and hash helper**

Create `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncModels.swift`:

```swift
import CryptoKit
import Foundation
import MuesliMeetingChat

enum MeetingChatSyncEntityKind: String, CaseIterable, Sendable {
    case thread
    case message
}

struct MeetingChatSyncMetadataRecord: Sendable, Equatable {
    let entityKind: MeetingChatSyncEntityKind
    let localID: String
    let remoteID: String?
    let clientUpdatedAt: String
    let remoteVersion: Int64
    let lastSeenServerUpdatedAt: String?
    let lastPayloadHash: String?
    let dirty: Bool
    let lastWriterDeviceID: String?
}

struct MeetingChatSyncTombstoneRecord: Sendable, Equatable {
    let entityKind: MeetingChatSyncEntityKind
    let localID: String
    let remoteID: String?
    let clientDeletedAt: String
    let lastKnownRemoteVersion: Int64
    let dirty: Bool
}

struct DirtyMeetingChatThread: Sendable {
    let metadata: MeetingChatSyncMetadataRecord
    let thread: MeetingChatThread
    let scopeKind: String
    let scopeRemoteID: String?
}

struct DirtyMeetingChatMessage: Sendable {
    let metadata: MeetingChatSyncMetadataRecord
    let message: MeetingChatMessage
    let threadLocalID: UUID
    let threadRemoteID: String?
}

struct RemoteMeetingChatThreadPayload: Sendable, Equatable {
    let remoteID: String
    let scopeKind: String
    let scopeRemoteID: String
    let title: String
    let summary: String
    let clientUpdatedAt: String
    let serverUpdatedAt: String
    let remoteVersion: Int64
    let lastWriterDeviceID: String
    let deletedAt: String?
}

struct RemoteMeetingChatMessagePayload: Sendable, Equatable {
    let remoteID: String
    let threadRemoteID: String
    let role: MeetingChatRole
    let content: String
    let sources: [MeetingChatSource]
    let createdAt: String
    let clientUpdatedAt: String
    let serverUpdatedAt: String
    let remoteVersion: Int64
    let lastWriterDeviceID: String
    let deletedAt: String?
}

enum MeetingChatSyncHasher {
    static func threadHash(
        scopeKind: String,
        scopeRemoteID: String,
        title: String,
        summary: String
    ) -> String {
        hash([
            "scope_kind": scopeKind,
            "scope_remote_id": scopeRemoteID,
            "title": title,
            "summary": summary,
        ])
    }

    static func messageHash(
        role: MeetingChatRole,
        content: String,
        sources: [MeetingChatSource],
        createdAt: String
    ) throws -> String {
        let sourcesData = try JSONEncoder().encode(sources)
        let sourcesJSON = String(data: sourcesData, encoding: .utf8) ?? "[]"
        return hash([
            "role": role.rawValue,
            "content": content,
            "sources_json": sourcesJSON,
            "created_at": createdAt,
        ])
    }

    private static func hash(_ object: [String: String]) -> String {
        let ordered = object.keys.sorted().map { "\($0)=\(object[$0] ?? "")" }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(ordered.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run the same focused command from Step 2.

Expected: PASS for 2 tests.

- [ ] **Step 5: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncModels.swift native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift
git commit -m "feat: add meeting chat sync models"
```

---

### Task 3: Local Chat Sync Metadata Migration And Backfill

**Files:**
- Create: `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift`
- Modify: `native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift`

- [ ] **Step 1: Add failing migration/backfill test**

Append to `MeetingChatSyncRepositoryTests`:

```swift
@Test("migration backfills existing chat threads and messages as dirty")
func migrationBackfillsExistingChat() throws {
    let fixture = try makeFixture()
    let snapshot = try fixture.chatStore.loadThread(scope: .meeting(42), title: "Backfill Meeting")
    try fixture.chatStore.appendMessage(
        MeetingChatMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
            role: .user,
            text: "Will this sync?",
            createdAt: Date(timeIntervalSince1970: 1_780_000_000)
        ),
        to: snapshot.thread
    )

    try fixture.syncRepo.migrateIfNeeded()

    let dirtyThreads = try fixture.syncRepo.dirtyThreads(limit: 10)
    let dirtyMessages = try fixture.syncRepo.dirtyMessages(limit: 10)
    #expect(dirtyThreads.count == 1)
    #expect(dirtyMessages.count == 1)
    #expect(dirtyThreads[0].thread.title == "Backfill Meeting")
    #expect(dirtyMessages[0].message.text == "Will this sync?")
}

private func makeFixture() throws -> (chatStore: SQLiteMeetingChatStore, syncRepo: MeetingChatSyncRepository, url: URL) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("muesli-chat-sync-\(UUID().uuidString).db")
    let chatStore = SQLiteMeetingChatStore(databaseURL: url)
    try chatStore.migrateIfNeeded()
    let syncRepo = MeetingChatSyncRepository(databaseURL: url)
    return (chatStore, syncRepo, url)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter 'migrationBackfillsExistingChat'
```

Expected: FAIL because `MeetingChatSyncRepository` does not exist.

- [ ] **Step 3: Implement minimal repository migration/backfill/read APIs**

Create `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift` with:

```swift
import Foundation
import SQLite3
import MuesliCore
import MuesliMeetingChat

final class MeetingChatSyncRepository {
    private let databaseURL: URL
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
            ORDER BY m.client_updated_at ASC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError(db) }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            var rows: [DirtyMeetingChatThread] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let thread = try threadFromStatement(stmt)
                let metadata = metadataFromStatement(stmt, entityKind: .thread, localIDColumn: 0, baseColumn: 7)
                rows.append(DirtyMeetingChatThread(
                    metadata: metadata,
                    thread: thread,
                    scopeKind: stringColumn(stmt, index: 1),
                    scopeRemoteID: nil
                ))
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
            ORDER BY m.client_updated_at ASC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError(db) }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            var rows: [DirtyMeetingChatMessage] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let threadID = UUID(uuidString: stringColumn(stmt, index: 1)) else {
                    throw MeetingChatStorageError.database("Invalid chat thread id.")
                }
                let metadata = metadataFromStatement(stmt, entityKind: .message, localIDColumn: 0, baseColumn: 6)
                rows.append(DirtyMeetingChatMessage(
                    metadata: metadata,
                    message: try messageFromStatement(stmt),
                    threadLocalID: threadID,
                    threadRemoteID: nil
                ))
            }
            return rows
        }
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

    private func threadFromStatement(_ stmt: OpaquePointer?) throws -> MeetingChatThread {
        guard let id = UUID(uuidString: stringColumn(stmt, index: 0)) else {
            throw MeetingChatStorageError.database("Invalid chat thread id.")
        }
        let kind = stringColumn(stmt, index: 1)
        let scopeID = sqlite3_column_int64(stmt, 2)
        let scope: MeetingChatScope = kind == "folder" ? .folder(scopeID) : .meeting(scopeID)
        return MeetingChatThread(
            id: id,
            scope: scope,
            title: stringColumn(stmt, index: 3),
            summary: stringColumn(stmt, index: 4),
            createdAt: dateFormatter.date(from: stringColumn(stmt, index: 5)) ?? Date(timeIntervalSince1970: 0),
            updatedAt: dateFormatter.date(from: stringColumn(stmt, index: 6)) ?? Date(timeIntervalSince1970: 0)
        )
    }

    private func messageFromStatement(_ stmt: OpaquePointer?) throws -> MeetingChatMessage {
        guard let id = UUID(uuidString: stringColumn(stmt, index: 0)) else {
            throw MeetingChatStorageError.database("Invalid chat message id.")
        }
        guard let role = MeetingChatRole(rawValue: stringColumn(stmt, index: 2)) else {
            throw MeetingChatStorageError.invalidMessageRole(stringColumn(stmt, index: 2))
        }
        let sourcesData = Data(stringColumn(stmt, index: 4).utf8)
        let sources = (try? decoder.decode([MeetingChatSource].self, from: sourcesData)) ?? []
        return MeetingChatMessage(
            id: id,
            role: role,
            text: stringColumn(stmt, index: 3),
            sources: sources,
            createdAt: dateFormatter.date(from: stringColumn(stmt, index: 5)) ?? Date(timeIntervalSince1970: 0)
        )
    }

    private func metadataFromStatement(
        _ stmt: OpaquePointer?,
        entityKind: MeetingChatSyncEntityKind,
        localIDColumn: Int32,
        baseColumn: Int32
    ) -> MeetingChatSyncMetadataRecord {
        MeetingChatSyncMetadataRecord(
            entityKind: entityKind,
            localID: stringColumn(stmt, index: localIDColumn),
            remoteID: optionalStringColumn(stmt, index: baseColumn),
            clientUpdatedAt: stringColumn(stmt, index: baseColumn + 1),
            remoteVersion: sqlite3_column_int64(stmt, baseColumn + 2),
            lastSeenServerUpdatedAt: optionalStringColumn(stmt, index: baseColumn + 3),
            lastPayloadHash: optionalStringColumn(stmt, index: baseColumn + 4),
            dirty: sqlite3_column_int(stmt, baseColumn + 5) != 0,
            lastWriterDeviceID: optionalStringColumn(stmt, index: baseColumn + 6)
        )
    }
}
```

- [ ] **Step 4: Add SQLite helper functions**

Add these helpers to the bottom of `MeetingChatSyncRepository.swift`:

```swift
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

private func exec(_ sql: String, params: [String] = [], db: OpaquePointer?) throws {
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
    sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, transientDestructor)
}

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
```

- [ ] **Step 5: Run test to verify pass**

Run the same focused command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift
git commit -m "feat: backfill meeting chat sync metadata"
```

---

### Task 4: Mark Local Chat Changes Dirty And Clear Chat Tombstones

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/SQLiteMeetingChatStore.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift`
- Modify: `native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift`

- [ ] **Step 1: Add failing dirty/tombstone tests**

Append to `MeetingChatSyncRepositoryTests`:

```swift
@Test("append message marks message and thread dirty")
func appendMessageMarksChatDirty() throws {
    let fixture = try makeFixture()
    try fixture.syncRepo.migrateIfNeeded()
    let snapshot = try fixture.chatStore.loadThread(scope: .meeting(7), title: "Dirty Meeting")
    try fixture.syncRepo.markThreadSynced(
        localID: snapshot.thread.id,
        remoteID: "thread-remote",
        remoteVersion: 1,
        clientUpdatedAt: "2026-06-05T10:00:00.000Z",
        serverUpdatedAt: "2026-06-05T10:00:00.000Z",
        payloadHash: "thread-hash",
        lastWriterDeviceID: "device-a"
    )

    try fixture.chatStore.appendMessage(
        MeetingChatMessage(role: .user, text: "new local message"),
        to: snapshot.thread
    )

    #expect(try fixture.syncRepo.dirtyThreads(limit: 10).count == 1)
    #expect(try fixture.syncRepo.dirtyMessages(limit: 10).count == 1)
}

@Test("clear thread writes global synced tombstone")
func clearThreadWritesTombstone() throws {
    let fixture = try makeFixture()
    try fixture.syncRepo.migrateIfNeeded()
    let snapshot = try fixture.chatStore.loadThread(scope: .meeting(8), title: "Clear Meeting")
    try fixture.syncRepo.markThreadSynced(
        localID: snapshot.thread.id,
        remoteID: "thread-clear-remote",
        remoteVersion: 4,
        clientUpdatedAt: "2026-06-05T10:00:00.000Z",
        serverUpdatedAt: "2026-06-05T10:00:00.000Z",
        payloadHash: "thread-hash",
        lastWriterDeviceID: "device-a"
    )

    try fixture.chatStore.clearThread(scope: .meeting(8))

    let tombstones = try fixture.syncRepo.dirtyTombstones(entityKind: .thread, limit: 10)
    #expect(tombstones.count == 1)
    #expect(tombstones[0].remoteID == "thread-clear-remote")
    #expect(tombstones[0].lastKnownRemoteVersion == 4)
}
```

- [ ] **Step 2: Run tests to verify fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter 'appendMessageMarksChatDirty|clearThreadWritesTombstone'
```

Expected: FAIL because mark-synced/tombstone APIs and local dirty hooks do not exist.

- [ ] **Step 3: Implement repository write helpers**

Add to `MeetingChatSyncRepository`:

```swift
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

func dirtyTombstones(entityKind: MeetingChatSyncEntityKind, limit: Int = 100) throws -> [MeetingChatSyncTombstoneRecord] {
    try migrateIfNeeded()
    return try withDB { db in
        let sql = """
        SELECT entity_kind, local_id, remote_id, client_deleted_at, last_known_remote_version, dirty
        FROM meeting_chat_sync_tombstones
        WHERE entity_kind = ? AND dirty = 1
        ORDER BY client_deleted_at ASC
        LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError(db) }
        defer { sqlite3_finalize(stmt) }
        bindText(entityKind.rawValue, at: 1, statement: stmt)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        var rows: [MeetingChatSyncTombstoneRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(MeetingChatSyncTombstoneRecord(
                entityKind: entityKind,
                localID: stringColumn(stmt, index: 1),
                remoteID: optionalStringColumn(stmt, index: 2),
                clientDeletedAt: stringColumn(stmt, index: 3),
                lastKnownRemoteVersion: sqlite3_column_int64(stmt, 4),
                dirty: sqlite3_column_int(stmt, 5) != 0
            ))
        }
        return rows
    }
}

func recordThreadDelete(localID: UUID) throws {
    try recordDelete(entityKind: .thread, localID: localID.uuidString)
}
```

Also add private `markDirty`, `writeMetadata`, and `recordDelete` helpers:

```swift
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
                entityKind.rawValue, localID, remoteID, clientUpdatedAt, String(remoteVersion),
                serverUpdatedAt, payloadHash, dirty ? "1" : "0", lastWriterDeviceID
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
```

- [ ] **Step 4: Wire local store hooks**

Modify `SQLiteMeetingChatStore`:

```swift
private let syncRepository: MeetingChatSyncRepository?

init(databaseURL: URL, syncRepository: MeetingChatSyncRepository? = nil) {
    self.databaseURL = databaseURL
    self.syncRepository = syncRepository
}
```

In `loadThread`, after `insertThread(thread, db: db)`:

```swift
try syncRepository?.markThreadDirty(localID: thread.id)
```

In `appendMessage`, after `touchThread(thread.id, db: db)`:

```swift
try syncRepository?.markMessageDirty(localID: message.id)
try syncRepository?.markThreadDirty(localID: thread.id)
```

In `clearThread`, fetch the thread id before delete and record the tombstone:

```swift
if let thread = try selectThread(scope: scope, db: db) {
    try syncRepository?.recordThreadDelete(localID: thread.id)
}
```

- [ ] **Step 5: Update fixture to inject sync repo**

Change `makeFixture()` in `MeetingChatSyncRepositoryTests`:

```swift
let syncRepo = MeetingChatSyncRepository(databaseURL: url)
let chatStore = SQLiteMeetingChatStore(databaseURL: url, syncRepository: syncRepo)
try chatStore.migrateIfNeeded()
return (chatStore, syncRepo, url)
```

- [ ] **Step 6: Run tests to verify pass**

Run the focused command from Step 2.

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/SQLiteMeetingChatStore.swift native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift
git commit -m "feat: track meeting chat sync changes"
```

---

### Task 5: Chat REST Client

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseRESTClient.swift`
- Modify: `native/MuesliNative/Tests/MuesliTests/SupabaseRESTClientTests.swift`

- [ ] **Step 1: Add failing REST test for thread/message upload**

Append to `SupabaseRESTClientTests`:

```swift
@Test("upserts chat thread and message through PostgREST")
func upsertsChatThreadAndMessage() async throws {
    let recorder = RequestRecorder()
    let session = URLSession(configuration: recorder.configuration(responseBody: [
        [
            "id": "11111111-1111-1111-1111-111111111111",
            "scope_kind": "meeting",
            "scope_id": "22222222-2222-2222-2222-222222222222",
            "title": "Chat",
            "summary": "",
            "client_updated_at": "2026-06-05T10:00:00.000Z",
            "server_updated_at": "2026-06-05T10:00:01.000Z",
            "remote_version": 1,
            "last_writer_device_id": "device-a",
            "deleted_at": NSNull(),
        ],
        [
            "id": "33333333-3333-3333-3333-333333333333",
            "thread_id": "11111111-1111-1111-1111-111111111111",
            "role": "user",
            "content": "Hello",
            "sources_json": [],
            "created_at": "2026-06-05T10:00:02.000Z",
            "client_updated_at": "2026-06-05T10:00:02.000Z",
            "server_updated_at": "2026-06-05T10:00:03.000Z",
            "remote_version": 1,
            "last_writer_device_id": "device-a",
            "deleted_at": NSNull(),
        ],
    ]))
    let config = SupabaseConfig(baseURL: URL(string: "https://example.supabase.co")!, anonKey: "anon-key")
    let auth = try authenticatedManager(config: config)
    let client = SupabaseRESTClient(config: config, auth: auth, urlSession: session)

    _ = try await client.upsertMeetingChatThread(
        remoteID: nil,
        userID: "user-id",
        scopeKind: "meeting",
        scopeRemoteID: "22222222-2222-2222-2222-222222222222",
        title: "Chat",
        summary: "",
        clientUpdatedAt: "2026-06-05T10:00:00.000Z",
        deviceID: "device-a",
        deletedAt: nil
    )
    _ = try await client.upsertMeetingChatMessage(
        remoteID: nil,
        userID: "user-id",
        threadRemoteID: "11111111-1111-1111-1111-111111111111",
        role: .user,
        content: "Hello",
        sources: [],
        createdAt: "2026-06-05T10:00:02.000Z",
        clientUpdatedAt: "2026-06-05T10:00:02.000Z",
        deviceID: "device-a",
        deletedAt: nil
    )

    #expect(recorder.requests.map { $0.url?.path } == [
        "/rest/v1/meeting_chat_threads",
        "/rest/v1/meeting_chat_messages",
    ])
}
```

Update `RequestRecorder.configuration` to accept response bodies:

```swift
func configuration(responseBody: [[String: Any]]? = nil) -> URLSessionConfiguration
```

Return one body per recorded request based on `storage.count`.

- [ ] **Step 2: Run test to verify fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter 'upsertsChatThreadAndMessage'
```

Expected: FAIL because chat REST methods do not exist.

- [ ] **Step 3: Add REST methods**

Add to `SupabaseRESTClient`:

```swift
func selectMeetingChatThreads(after cursor: SyncCursor?, limit: Int) async throws -> [RemoteMeetingChatThreadPayload] {
    let items = try await selectPage(table: "meeting_chat_threads", after: cursor, limit: limit)
    return items.compactMap { Self.parseMeetingChatThread($0) }
}

func selectMeetingChatMessages(after cursor: SyncCursor?, limit: Int) async throws -> [RemoteMeetingChatMessagePayload] {
    let items = try await selectPage(table: "meeting_chat_messages", after: cursor, limit: limit)
    return try items.compactMap { try Self.parseMeetingChatMessage($0) }
}

func upsertMeetingChatThread(
    remoteID: String?,
    userID: String,
    scopeKind: String,
    scopeRemoteID: String,
    title: String,
    summary: String,
    clientUpdatedAt: String,
    deviceID: String,
    deletedAt: String?
) async throws -> RemoteMeetingChatThreadPayload {
    var body: [String: Any] = [
        "user_id": userID,
        "scope_kind": scopeKind,
        "scope_id": scopeRemoteID,
        "title": title,
        "summary": summary,
        "client_updated_at": clientUpdatedAt,
        "last_writer_device_id": deviceID,
        "deleted_at": deletedAt as Any? ?? NSNull(),
    ]
    if let remoteID { body["id"] = remoteID }
    let data = try await sendUpsert(path: "meeting_chat_threads", body: body)
    guard let row = try Self.firstObject(from: data),
          let thread = Self.parseMeetingChatThread(row) else {
        throw SupabaseRESTError.decoding(message: "missing meeting chat thread row")
    }
    return thread
}

func upsertMeetingChatMessage(
    remoteID: String?,
    userID: String,
    threadRemoteID: String,
    role: MeetingChatRole,
    content: String,
    sources: [MeetingChatSource],
    createdAt: String,
    clientUpdatedAt: String,
    deviceID: String,
    deletedAt: String?
) async throws -> RemoteMeetingChatMessagePayload {
    let sourcesData = try JSONEncoder().encode(sources)
    let sourcesObject = (try? JSONSerialization.jsonObject(with: sourcesData)) ?? []
    var body: [String: Any] = [
        "user_id": userID,
        "thread_id": threadRemoteID,
        "role": role.rawValue,
        "content": content,
        "sources_json": sourcesObject,
        "created_at": createdAt,
        "client_updated_at": clientUpdatedAt,
        "last_writer_device_id": deviceID,
        "deleted_at": deletedAt as Any? ?? NSNull(),
    ]
    if let remoteID { body["id"] = remoteID }
    let data = try await sendUpsert(path: "meeting_chat_messages", body: body)
    guard let row = try Self.firstObject(from: data),
          let message = try Self.parseMeetingChatMessage(row) else {
        throw SupabaseRESTError.decoding(message: "missing meeting chat message row")
    }
    return message
}
```

Also add parse helpers:

```swift
private static func parseMeetingChatThread(_ row: [String: Any]) -> RemoteMeetingChatThreadPayload? {
    guard
        let id = row["id"] as? String,
        let scopeKind = row["scope_kind"] as? String,
        let scopeID = row["scope_id"] as? String,
        let title = row["title"] as? String,
        let summary = row["summary"] as? String,
        let clientUpdatedAt = row["client_updated_at"] as? String,
        let serverUpdatedAt = row["server_updated_at"] as? String,
        let remoteVersion = row["remote_version"] as? Int64 ?? (row["remote_version"] as? Int).map(Int64.init),
        let lastWriter = row["last_writer_device_id"] as? String
    else { return nil }
    return RemoteMeetingChatThreadPayload(
        remoteID: id,
        scopeKind: scopeKind,
        scopeRemoteID: scopeID,
        title: title,
        summary: summary,
        clientUpdatedAt: clientUpdatedAt,
        serverUpdatedAt: serverUpdatedAt,
        remoteVersion: remoteVersion,
        lastWriterDeviceID: lastWriter,
        deletedAt: row["deleted_at"] as? String
    )
}

private static func parseMeetingChatMessage(_ row: [String: Any]) throws -> RemoteMeetingChatMessagePayload? {
    guard
        let id = row["id"] as? String,
        let threadID = row["thread_id"] as? String,
        let roleRaw = row["role"] as? String,
        let role = MeetingChatRole(rawValue: roleRaw),
        let content = row["content"] as? String,
        let createdAt = row["created_at"] as? String,
        let clientUpdatedAt = row["client_updated_at"] as? String,
        let serverUpdatedAt = row["server_updated_at"] as? String,
        let remoteVersion = row["remote_version"] as? Int64 ?? (row["remote_version"] as? Int).map(Int64.init),
        let lastWriter = row["last_writer_device_id"] as? String
    else { return nil }
    let sources: [MeetingChatSource]
    if let sourceArray = row["sources_json"] {
        let data = try JSONSerialization.data(withJSONObject: sourceArray)
        sources = (try? JSONDecoder().decode([MeetingChatSource].self, from: data)) ?? []
    } else {
        sources = []
    }
    return RemoteMeetingChatMessagePayload(
        remoteID: id,
        threadRemoteID: threadID,
        role: role,
        content: content,
        sources: sources,
        createdAt: createdAt,
        clientUpdatedAt: clientUpdatedAt,
        serverUpdatedAt: serverUpdatedAt,
        remoteVersion: remoteVersion,
        lastWriterDeviceID: lastWriter,
        deletedAt: row["deleted_at"] as? String
    )
}
```

- [ ] **Step 4: Run test to verify pass**

Run the focused command from Step 2.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseRESTClient.swift native/MuesliNative/Tests/MuesliTests/SupabaseRESTClientTests.swift
git commit -m "feat: add meeting chat rest sync"
```

---

### Task 6: Resolve Meeting/Folder Scope Remote IDs

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift`
- Modify: `native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift`

- [ ] **Step 1: Add failing test for unsynced scope deferral**

Append to `MeetingChatSyncRepositoryTests`:

```swift
@Test("dirty thread exposes nil scope remote id until meeting is synced")
func dirtyThreadWaitsForScopeRemoteID() throws {
    let fixture = try makeFixtureWithDictationStore()
    let meetingID = try fixture.store.insertMeeting(
        title: "Unsynced Meeting",
        calendarEventID: nil,
        startTime: Date(timeIntervalSince1970: 1_780_000_000),
        endTime: Date(timeIntervalSince1970: 1_780_000_060),
        rawTranscript: "",
        formattedNotes: "",
        micAudioPath: nil,
        systemAudioPath: nil
    )
    _ = try fixture.chatStore.loadThread(scope: .meeting(meetingID), title: "Unsynced Meeting")

    let before = try fixture.chatSyncRepo.dirtyThreads(limit: 10)
    #expect(before.first?.scopeRemoteID == nil)

    try fixture.localSyncRepo.markMeetingSynced(
        localID: meetingID,
        remoteID: "meeting-remote",
        remoteVersion: 1,
        clientUpdatedAt: "2026-06-05T10:00:00.000Z",
        serverUpdatedAt: "2026-06-05T10:00:00.000Z",
        payloadHash: "meeting-hash",
        lastWriterDeviceID: "device-a"
    )

    let after = try fixture.chatSyncRepo.dirtyThreads(limit: 10)
    #expect(after.first?.scopeRemoteID == "meeting-remote")
}

private func makeFixtureWithDictationStore() throws -> (
    store: DictationStore,
    localSyncRepo: LocalSyncRepository,
    chatStore: SQLiteMeetingChatStore,
    chatSyncRepo: MeetingChatSyncRepository,
    url: URL
) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("muesli-chat-scope-sync-\(UUID().uuidString).db")
    let store = DictationStore(databaseURL: url)
    try store.migrateIfNeeded()
    let localSyncRepo = LocalSyncRepository(databaseURL: url)
    try localSyncRepo.migrateIfNeeded()
    let chatSyncRepo = MeetingChatSyncRepository(databaseURL: url, localSyncRepository: localSyncRepo)
    let chatStore = SQLiteMeetingChatStore(databaseURL: url, syncRepository: chatSyncRepo)
    try chatStore.migrateIfNeeded()
    try chatSyncRepo.migrateIfNeeded()
    return (store, localSyncRepo, chatStore, chatSyncRepo, url)
}
```

- [ ] **Step 2: Run test to verify fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter 'dirtyThreadWaitsForScopeRemoteID'
```

Expected: FAIL because repository does not resolve scope remote IDs.

- [ ] **Step 3: Inject LocalSyncRepository and resolve scope IDs**

Update `MeetingChatSyncRepository` initializer:

```swift
private let localSyncRepository: LocalSyncRepository?

init(databaseURL: URL, localSyncRepository: LocalSyncRepository? = nil) {
    self.databaseURL = databaseURL
    self.localSyncRepository = localSyncRepository
}
```

Add helper:

```swift
private func remoteID(for scope: MeetingChatScope) throws -> String? {
    guard let localSyncRepository else { return nil }
    switch scope {
    case .meeting(let id):
        return try localSyncRepository.remoteID(forLocalID: id, entityType: .meeting)
    case .folder(let id):
        return try localSyncRepository.remoteID(forLocalID: id, entityType: .folder)
    }
}
```

In `dirtyThreads`, replace `scopeRemoteID: nil` with:

```swift
scopeRemoteID: try remoteID(for: thread.scope)
```

- [ ] **Step 4: Run test to verify pass**

Run the focused command from Step 2.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift
git commit -m "feat: resolve chat sync scopes"
```

---

### Task 7: Apply Remote Chat Rows Locally

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/SQLiteMeetingChatStore.swift`
- Modify: `native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift`

- [ ] **Step 1: Add failing apply-remote test**

Append to `MeetingChatSyncRepositoryTests`:

```swift
@Test("apply remote thread and message writes local chat")
func applyRemoteThreadAndMessage() throws {
    let fixture = try makeFixtureWithDictationStore()
    let meetingID = try fixture.store.insertMeeting(
        title: "Remote Meeting",
        calendarEventID: nil,
        startTime: Date(timeIntervalSince1970: 1_780_000_000),
        endTime: Date(timeIntervalSince1970: 1_780_000_060),
        rawTranscript: "",
        formattedNotes: "",
        micAudioPath: nil,
        systemAudioPath: nil
    )
    try fixture.localSyncRepo.markMeetingSynced(
        localID: meetingID,
        remoteID: "meeting-remote-apply",
        remoteVersion: 1,
        clientUpdatedAt: "2026-06-05T10:00:00.000Z",
        serverUpdatedAt: "2026-06-05T10:00:00.000Z",
        payloadHash: "meeting-hash",
        lastWriterDeviceID: "device-a"
    )

    try fixture.chatSyncRepo.applyRemoteThread(RemoteMeetingChatThreadPayload(
        remoteID: "thread-remote-apply",
        scopeKind: "meeting",
        scopeRemoteID: "meeting-remote-apply",
        title: "Remote Chat",
        summary: "Older turns",
        clientUpdatedAt: "2026-06-05T10:01:00.000Z",
        serverUpdatedAt: "2026-06-05T10:01:01.000Z",
        remoteVersion: 1,
        lastWriterDeviceID: "device-b",
        deletedAt: nil
    ))
    try fixture.chatSyncRepo.applyRemoteMessage(RemoteMeetingChatMessagePayload(
        remoteID: "message-remote-apply",
        threadRemoteID: "thread-remote-apply",
        role: .assistant,
        content: "Remote answer",
        sources: [],
        createdAt: "2026-06-05T10:01:02.000Z",
        clientUpdatedAt: "2026-06-05T10:01:02.000Z",
        serverUpdatedAt: "2026-06-05T10:01:03.000Z",
        remoteVersion: 1,
        lastWriterDeviceID: "device-b",
        deletedAt: nil
    ))

    let snapshot = try fixture.chatStore.loadThread(scope: .meeting(meetingID), title: "Remote Meeting")
    #expect(snapshot.thread.title == "Remote Chat")
    #expect(snapshot.thread.summary == "Older turns")
    #expect(snapshot.messages.map(\.text) == ["Remote answer"])
}
```

- [ ] **Step 2: Run test to verify fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter 'applyRemoteThreadAndMessage'
```

Expected: FAIL because `applyRemoteThread` and `applyRemoteMessage` do not exist.

- [ ] **Step 3: Add local upsert APIs to SQLiteMeetingChatStore**

Add internal methods:

```swift
func upsertThreadFromSync(_ thread: MeetingChatThread) throws {
    try migrateIfNeeded()
    try withDB { db in
        try insertOrReplaceThread(thread, db: db)
    }
}

func upsertMessageFromSync(_ message: MeetingChatMessage, threadID: UUID) throws {
    try migrateIfNeeded()
    try withDB { db in
        try insertMessage(message, threadID: threadID, db: db)
    }
}
```

Extract `insertThread` into `insertOrReplaceThread` with `INSERT OR REPLACE`:

```swift
private func insertOrReplaceThread(_ thread: MeetingChatThread, db: OpaquePointer?) throws
```

Make `insertThread` call `insertOrReplaceThread` or replace call sites directly.

- [ ] **Step 4: Implement apply remote**

Add to `MeetingChatSyncRepository`:

```swift
func applyRemoteThread(_ payload: RemoteMeetingChatThreadPayload) throws {
    try migrateIfNeeded()
    try withDB { db in
        guard let scope = try localScope(kind: payload.scopeKind, remoteID: payload.scopeRemoteID) else { return }
        if payload.deletedAt != nil {
            if let localID = try localID(forRemoteID: payload.remoteID, entityKind: .thread, db: db) {
                try deleteLocalThread(localID: localID, db: db)
                try clearTombstone(entityKind: .thread, localID: localID, db: db)
            }
            try removeMetadata(entityKind: .thread, remoteID: payload.remoteID, db: db)
            return
        }
        let localID = (try localID(forRemoteID: payload.remoteID, entityKind: .thread, db: db))
            .flatMap(UUID.init(uuidString:)) ?? UUID()
        let thread = MeetingChatThread(
            id: localID,
            scope: scope,
            title: payload.title,
            summary: payload.summary,
            createdAt: Date(),
            updatedAt: dateFormatter.date(from: payload.clientUpdatedAt) ?? Date()
        )
        try upsertLocalThread(thread, db: db)
        let hash = MeetingChatSyncHasher.threadHash(
            scopeKind: payload.scopeKind,
            scopeRemoteID: payload.scopeRemoteID,
            title: payload.title,
            summary: payload.summary
        )
        try writeMetadata(
            entityKind: .thread,
            localID: localID.uuidString,
            remoteID: payload.remoteID,
            remoteVersion: payload.remoteVersion,
            clientUpdatedAt: payload.clientUpdatedAt,
            serverUpdatedAt: payload.serverUpdatedAt,
            payloadHash: hash,
            lastWriterDeviceID: payload.lastWriterDeviceID,
            dirty: false
        )
    }
}

func applyRemoteMessage(_ payload: RemoteMeetingChatMessagePayload) throws {
    try migrateIfNeeded()
    try withDB { db in
        guard let threadLocalIDString = try localID(forRemoteID: payload.threadRemoteID, entityKind: .thread, db: db),
              let threadLocalID = UUID(uuidString: threadLocalIDString) else { return }
        if payload.deletedAt != nil {
            if let localID = try localID(forRemoteID: payload.remoteID, entityKind: .message, db: db) {
                try deleteLocalMessage(localID: localID, db: db)
                try clearTombstone(entityKind: .message, localID: localID, db: db)
            }
            try removeMetadata(entityKind: .message, remoteID: payload.remoteID, db: db)
            return
        }
        let localID = (try localID(forRemoteID: payload.remoteID, entityKind: .message, db: db))
            .flatMap(UUID.init(uuidString:)) ?? UUID()
        let message = MeetingChatMessage(
            id: localID,
            role: payload.role,
            text: payload.content,
            sources: payload.sources,
            createdAt: dateFormatter.date(from: payload.createdAt) ?? Date()
        )
        try upsertLocalMessage(message, threadID: threadLocalID, db: db)
        let hash = try MeetingChatSyncHasher.messageHash(
            role: payload.role,
            content: payload.content,
            sources: payload.sources,
            createdAt: payload.createdAt
        )
        try writeMetadata(
            entityKind: .message,
            localID: localID.uuidString,
            remoteID: payload.remoteID,
            remoteVersion: payload.remoteVersion,
            clientUpdatedAt: payload.clientUpdatedAt,
            serverUpdatedAt: payload.serverUpdatedAt,
            payloadHash: hash,
            lastWriterDeviceID: payload.lastWriterDeviceID,
            dirty: false
        )
    }
}
```

Add these private helpers used above:

```swift
private func localScope(kind: String, remoteID: String) throws -> MeetingChatScope? {
    guard let localSyncRepository else { return nil }
    switch kind {
    case "meeting":
        guard let id = try localSyncRepository.localID(forRemoteID: remoteID, entityType: .meeting) else { return nil }
        return .meeting(id)
    case "folder":
        guard let id = try localSyncRepository.localID(forRemoteID: remoteID, entityType: .folder) else { return nil }
        return .folder(id)
    default:
        return nil
    }
}

private func localID(
    forRemoteID remoteID: String,
    entityKind: MeetingChatSyncEntityKind,
    db: OpaquePointer?
) throws -> String? {
    let sql = "SELECT local_id FROM meeting_chat_sync_metadata WHERE entity_kind = ? AND remote_id = ? LIMIT 1"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError(db) }
    defer { sqlite3_finalize(stmt) }
    bindText(entityKind.rawValue, at: 1, statement: stmt)
    bindText(remoteID, at: 2, statement: stmt)
    guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
    return stringColumn(stmt, index: 0)
}

private func upsertLocalThread(_ thread: MeetingChatThread, db: OpaquePointer?) throws {
    let (kind, scopeID): (String, Int64)
    switch thread.scope {
    case .meeting(let id):
        kind = "meeting"
        scopeID = id
    case .folder(let id):
        kind = "folder"
        scopeID = id
    }
    try exec(
        """
        INSERT OR REPLACE INTO meeting_chat_threads
        (id, scope_kind, scope_id, title, summary, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        params: [
            thread.id.uuidString,
            kind,
            String(scopeID),
            thread.title,
            thread.summary,
            dateFormatter.string(from: thread.createdAt),
            dateFormatter.string(from: thread.updatedAt),
        ],
        db: db
    )
}

private func upsertLocalMessage(_ message: MeetingChatMessage, threadID: UUID, db: OpaquePointer?) throws {
    let sourcesData = try JSONEncoder().encode(message.sources)
    let sourcesJSON = String(data: sourcesData, encoding: .utf8) ?? "[]"
    try exec(
        """
        INSERT OR REPLACE INTO meeting_chat_messages
        (id, thread_id, role, content, sources_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        params: [
            message.id.uuidString,
            threadID.uuidString,
            message.role.rawValue,
            message.text,
            sourcesJSON,
            dateFormatter.string(from: message.createdAt),
        ],
        db: db
    )
}

private func deleteLocalThread(localID: String, db: OpaquePointer?) throws {
    try exec("DELETE FROM meeting_chat_threads WHERE id = ?", params: [localID], db: db)
}

private func deleteLocalMessage(localID: String, db: OpaquePointer?) throws {
    try exec("DELETE FROM meeting_chat_messages WHERE id = ?", params: [localID], db: db)
}

private func clearTombstone(entityKind: MeetingChatSyncEntityKind, localID: String, db: OpaquePointer?) throws {
    try exec(
        "DELETE FROM meeting_chat_sync_tombstones WHERE entity_kind = ? AND local_id = ?",
        params: [entityKind.rawValue, localID],
        db: db
    )
}

private func removeMetadata(entityKind: MeetingChatSyncEntityKind, remoteID: String, db: OpaquePointer?) throws {
    try exec(
        "DELETE FROM meeting_chat_sync_metadata WHERE entity_kind = ? AND remote_id = ?",
        params: [entityKind.rawValue, remoteID],
        db: db
    )
}
```

- [ ] **Step 5: Run test to verify pass**

Run the focused command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/SQLiteMeetingChatStore.swift native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift
git commit -m "feat: apply remote meeting chat sync"
```

---

### Task 8: Integrate Chat Sync Into SupabaseSyncManager

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseSyncManager.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/AppDelegate.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift`
- Modify: `native/MuesliNative/Tests/MuesliTests/SupabaseAuthPersistenceTests.swift`

- [ ] **Step 1: Add failing source-order test**

Append to `SupabaseAuthPersistenceTests`:

```swift
@Test("sync cycle downloads and uploads meeting chat after meetings")
func syncCycleOrdersMeetingChatAfterMeetings() throws {
    let sourceURL = URL(fileURLWithPath: "native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseSyncManager.swift")
    let source = try String(contentsOf: sourceURL)
    let downloadMeetings = try #require(source.range(of: "try await downloadMeetings(rest: rest)"))
    let downloadChatThreads = try #require(source.range(of: "try await downloadMeetingChatThreads(rest: rest)", range: downloadMeetings.upperBound..<source.endIndex))
    _ = try #require(source.range(of: "try await downloadMeetingChatMessages(rest: rest)", range: downloadChatThreads.upperBound..<source.endIndex))
    let uploadMeetings = try #require(source.range(of: "try await uploadMeetings(rest: rest, userID: userID)"))
    let uploadChatThreads = try #require(source.range(of: "try await uploadMeetingChatThreads(rest: rest, userID: userID)", range: uploadMeetings.upperBound..<source.endIndex))
    _ = try #require(source.range(of: "try await uploadMeetingChatMessages(rest: rest, userID: userID)", range: uploadChatThreads.upperBound..<source.endIndex))
}
```

- [ ] **Step 2: Run test to verify fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter 'syncCycleOrdersMeetingChatAfterMeetings'
```

Expected: FAIL because sync manager does not call chat sync.

- [ ] **Step 3: Inject chat repository**

Modify `SupabaseSyncManager` initializer:

```swift
private let chatRepo: MeetingChatSyncRepository

init(
    repo: LocalSyncRepository,
    chatRepo: MeetingChatSyncRepository,
    auth: SupabaseAuthManager,
    rest: SupabaseRESTClient?,
    preferencesBridge: SupabasePreferencesBridge,
    observer: SupabaseSyncStateObserver
) {
    self.repo = repo
    self.chatRepo = chatRepo
    self.auth = auth
    self.rest = rest
    self.preferencesBridge = preferencesBridge
    self.observer = observer
}
```

Update call sites in `AppDelegate` and tests to pass `chatRepo`.

In `MuesliController`, add property and initialization:

```swift
private let meetingChatSyncRepository: MeetingChatSyncRepository
```

After `dictationStore` initialization:

```swift
let localSyncRepository = LocalSyncRepository(databaseURL: self.dictationStore.resolvedDatabaseURL)
self.syncRepo = localSyncRepository
self.meetingChatSyncRepository = MeetingChatSyncRepository(
    databaseURL: self.dictationStore.resolvedDatabaseURL,
    localSyncRepository: localSyncRepository
)
self.meetingChatStore = SQLiteMeetingChatStore(
    databaseURL: self.dictationStore.resolvedDatabaseURL,
    syncRepository: self.meetingChatSyncRepository
)
```

Preserve one shared `LocalSyncRepository` instance: the object passed to `SupabaseSyncManager(repo:)` must also be passed into `MeetingChatSyncRepository(localSyncRepository:)`.

- [ ] **Step 4: Run build to catch initializer errors**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter 'syncCycleOrdersMeetingChatAfterMeetings'
```

Expected: still FAIL on missing sync methods, not compile errors.

- [ ] **Step 5: Add chat sync cycle methods**

Add to `runCycle`, after `downloadMeetings`:

```swift
try await downloadMeetingChatThreads(rest: rest)
try await downloadMeetingChatMessages(rest: rest)
```

Add to `runCycle`, after `uploadMeetings`:

```swift
try await uploadMeetingChatThreads(rest: rest, userID: userID)
try await uploadMeetingChatMessages(rest: rest, userID: userID)
```

Add methods:

```swift
private func downloadMeetingChatThreads(rest: SupabaseRESTClient) async throws {
    var current = try chatRepo.loadCursor(key: "pull_cursor:meeting_chat_threads")
    while true {
        let rows = try await rest.selectMeetingChatThreads(after: current, limit: pageSize)
        if rows.isEmpty { break }
        for row in rows {
            try chatRepo.applyRemoteThread(row)
        }
        current = SyncCursor(serverUpdatedAt: rows.last!.serverUpdatedAt, id: rows.last!.remoteID)
        try chatRepo.saveCursor(current!, key: "pull_cursor:meeting_chat_threads")
        if rows.count < pageSize { break }
    }
}

private func downloadMeetingChatMessages(rest: SupabaseRESTClient) async throws {
    var current = try chatRepo.loadCursor(key: "pull_cursor:meeting_chat_messages")
    while true {
        let rows = try await rest.selectMeetingChatMessages(after: current, limit: pageSize)
        if rows.isEmpty { break }
        for row in rows {
            try chatRepo.applyRemoteMessage(row)
        }
        current = SyncCursor(serverUpdatedAt: rows.last!.serverUpdatedAt, id: rows.last!.remoteID)
        try chatRepo.saveCursor(current!, key: "pull_cursor:meeting_chat_messages")
        if rows.count < pageSize { break }
    }
}

private func uploadMeetingChatThreads(rest: SupabaseRESTClient, userID: String) async throws {
    let deviceID = try repo.ensureDeviceID()
    let dirty = try chatRepo.dirtyThreads(limit: pageSize)
    for entry in dirty {
        guard let scopeRemoteID = entry.scopeRemoteID else { continue }
        let hash = MeetingChatSyncHasher.threadHash(
            scopeKind: entry.scopeKind,
            scopeRemoteID: scopeRemoteID,
            title: entry.thread.title,
            summary: entry.thread.summary
        )
        if entry.metadata.lastPayloadHash == hash, let remoteID = entry.metadata.remoteID {
            try chatRepo.markThreadSynced(
                localID: entry.thread.id,
                remoteID: remoteID,
                remoteVersion: entry.metadata.remoteVersion,
                clientUpdatedAt: entry.metadata.clientUpdatedAt,
                serverUpdatedAt: entry.metadata.lastSeenServerUpdatedAt ?? SyncTimestamp.now(),
                payloadHash: hash,
                lastWriterDeviceID: entry.metadata.lastWriterDeviceID ?? deviceID
            )
            continue
        }
        let remote = try await rest.upsertMeetingChatThread(
            remoteID: entry.metadata.remoteID,
            userID: userID,
            scopeKind: entry.scopeKind,
            scopeRemoteID: scopeRemoteID,
            title: entry.thread.title,
            summary: entry.thread.summary,
            clientUpdatedAt: entry.metadata.clientUpdatedAt,
            deviceID: deviceID,
            deletedAt: nil
        )
        try chatRepo.markThreadSynced(
            localID: entry.thread.id,
            remoteID: remote.remoteID,
            remoteVersion: remote.remoteVersion,
            clientUpdatedAt: remote.clientUpdatedAt,
            serverUpdatedAt: remote.serverUpdatedAt,
            payloadHash: hash,
            lastWriterDeviceID: deviceID
        )
    }
}

private func uploadMeetingChatMessages(rest: SupabaseRESTClient, userID: String) async throws {
    let deviceID = try repo.ensureDeviceID()
    let dirty = try chatRepo.dirtyMessages(limit: pageSize)
    for entry in dirty {
        guard let threadRemoteID = entry.threadRemoteID else { continue }
        let createdAt = SyncTimestamp.format(entry.message.createdAt)
        let hash = try MeetingChatSyncHasher.messageHash(
            role: entry.message.role,
            content: entry.message.text,
            sources: entry.message.sources,
            createdAt: createdAt
        )
        let remote = try await rest.upsertMeetingChatMessage(
            remoteID: entry.metadata.remoteID,
            userID: userID,
            threadRemoteID: threadRemoteID,
            role: entry.message.role,
            content: entry.message.text,
            sources: entry.message.sources,
            createdAt: createdAt,
            clientUpdatedAt: entry.metadata.clientUpdatedAt,
            deviceID: deviceID,
            deletedAt: nil
        )
        try chatRepo.markMessageSynced(
            localID: entry.message.id,
            remoteID: remote.remoteID,
            remoteVersion: remote.remoteVersion,
            clientUpdatedAt: remote.clientUpdatedAt,
            serverUpdatedAt: remote.serverUpdatedAt,
            payloadHash: hash,
            lastWriterDeviceID: deviceID
        )
    }
}
```

Add these repository APIs used above:

```swift
func loadCursor(key: String) throws -> SyncCursor? {
    try withDB { db in
        let sql = "SELECT value FROM sync_state WHERE key = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError(db) }
        defer { sqlite3_finalize(stmt) }
        bindText(key, at: 1, statement: stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let raw = stringColumn(stmt, index: 0)
        return try? JSONDecoder().decode(SyncCursor.self, from: Data(raw.utf8))
    }
}

func saveCursor(_ cursor: SyncCursor, key: String) throws {
    let data = try JSONEncoder().encode(cursor)
    guard let json = String(data: data, encoding: .utf8) else { return }
    try withDB { db in
        try exec(
            """
            INSERT INTO sync_state (key, value, updated_at)
            VALUES (?, ?, datetime('now'))
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')
            """,
            params: [key, json],
            db: db
        )
    }
}

func markMessageSynced(
    localID: UUID,
    remoteID: String,
    remoteVersion: Int64,
    clientUpdatedAt: String,
    serverUpdatedAt: String,
    payloadHash: String,
    lastWriterDeviceID: String
) throws {
    try writeMetadata(
        entityKind: .message,
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
```

Update `dirtyMessages` to set `threadRemoteID` by looking up the parent thread:

```swift
let threadRemoteID = try remoteID(forLocalID: threadID.uuidString, entityKind: .thread, db: db)
```

Add:

```swift
private func remoteID(forLocalID localID: String, entityKind: MeetingChatSyncEntityKind, db: OpaquePointer?) throws -> String? {
    let sql = "SELECT remote_id FROM meeting_chat_sync_metadata WHERE entity_kind = ? AND local_id = ? LIMIT 1"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError(db) }
    defer { sqlite3_finalize(stmt) }
    bindText(entityKind.rawValue, at: 1, statement: stmt)
    bindText(localID, at: 2, statement: stmt)
    guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
    return optionalStringColumn(stmt, index: 0)
}
```

- [ ] **Step 6: Run source-order test to verify pass**

Run the focused command from Step 2.

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseSyncManager.swift native/MuesliNative/Sources/MuesliNativeApp/AppDelegate.swift native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift native/MuesliNative/Tests/MuesliTests/SupabaseAuthPersistenceTests.swift
git commit -m "feat: sync meeting chat in supabase cycle"
```

---

### Task 9: Chat Tombstone Upload And Global Clear

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseSyncManager.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift`
- Modify: `native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift`

- [ ] **Step 1: Add failing tombstone clean test**

Append to `MeetingChatSyncRepositoryTests`:

```swift
@Test("mark thread tombstone synced clears dirty flag")
func markThreadTombstoneSynced() throws {
    let fixture = try makeFixture()
    let snapshot = try fixture.chatStore.loadThread(scope: .meeting(88), title: "Delete Sync")
    try fixture.syncRepo.markThreadSynced(
        localID: snapshot.thread.id,
        remoteID: "thread-delete-sync",
        remoteVersion: 2,
        clientUpdatedAt: "2026-06-05T10:00:00.000Z",
        serverUpdatedAt: "2026-06-05T10:00:00.000Z",
        payloadHash: "hash",
        lastWriterDeviceID: "device-a"
    )
    try fixture.chatStore.clearThread(scope: .meeting(88))
    let tombstone = try #require(fixture.syncRepo.dirtyTombstones(entityKind: .thread, limit: 10).first)

    try fixture.syncRepo.markTombstoneSynced(
        entityKind: .thread,
        localID: tombstone.localID,
        lastKnownRemoteVersion: 3
    )

    #expect(try fixture.syncRepo.dirtyTombstones(entityKind: .thread, limit: 10).isEmpty)
}
```

- [ ] **Step 2: Run test to verify fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter 'markThreadTombstoneSynced'
```

Expected: FAIL because `markTombstoneSynced` does not exist.

- [ ] **Step 3: Implement tombstone sync helpers**

Add to `MeetingChatSyncRepository`:

```swift
func markTombstoneSynced(
    entityKind: MeetingChatSyncEntityKind,
    localID: String,
    lastKnownRemoteVersion: Int64
) throws {
    try withDB { db in
        try exec(
            """
            UPDATE meeting_chat_sync_tombstones
            SET dirty = 0, last_known_remote_version = ?, updated_at = datetime('now')
            WHERE entity_kind = ? AND local_id = ?
            """,
            params: [String(lastKnownRemoteVersion), entityKind.rawValue, localID],
            db: db
        )
    }
}
```

- [ ] **Step 4: Upload tombstones from sync manager**

Add to `runCycle` after existing tombstones:

```swift
try await uploadMeetingChatTombstones(rest: rest, userID: userID, entityKind: .message)
try await uploadMeetingChatTombstones(rest: rest, userID: userID, entityKind: .thread)
```

Add method:

```swift
private func uploadMeetingChatTombstones(
    rest: SupabaseRESTClient,
    userID: String,
    entityKind: MeetingChatSyncEntityKind
) async throws {
    let tombstones = try chatRepo.dirtyTombstones(entityKind: entityKind, limit: pageSize)
    let deviceID = try repo.ensureDeviceID()
    for tombstone in tombstones {
        guard let remoteID = tombstone.remoteID, !remoteID.isEmpty else {
            try chatRepo.clearTombstone(entityKind: entityKind, localID: tombstone.localID)
            continue
        }
        switch entityKind {
        case .thread:
            _ = try await rest.upsertMeetingChatThread(
                remoteID: remoteID,
                userID: userID,
                scopeKind: "meeting",
                scopeRemoteID: "00000000-0000-0000-0000-000000000000",
                title: "(deleted)",
                summary: "",
                clientUpdatedAt: tombstone.clientDeletedAt,
                deviceID: deviceID,
                deletedAt: tombstone.clientDeletedAt
            )
        case .message:
            continue
        }
        try chatRepo.markTombstoneSynced(
            entityKind: entityKind,
            localID: tombstone.localID,
            lastKnownRemoteVersion: tombstone.lastKnownRemoteVersion + 1
        )
    }
}
```

Add `fetchMeetingChatThread(remoteID:)` to `SupabaseRESTClient` and use the remote row's existing scope fields when marking a thread deleted:

```swift
func fetchMeetingChatThread(remoteID: String) async throws -> RemoteMeetingChatThreadPayload? {
    let data = try await get(
        path: "meeting_chat_threads",
        query: [
            URLQueryItem(name: "id", value: "eq.\(remoteID)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "limit", value: "1"),
        ]
    )
    guard let row = try Self.firstObject(from: data) else { return nil }
    return Self.parseMeetingChatThread(row)
}
```

Update `uploadMeetingChatTombstones` thread branch:

```swift
guard let existing = try await rest.fetchMeetingChatThread(remoteID: remoteID) else {
    try chatRepo.markTombstoneSynced(
        entityKind: entityKind,
        localID: tombstone.localID,
        lastKnownRemoteVersion: tombstone.lastKnownRemoteVersion
    )
    continue
}
_ = try await rest.upsertMeetingChatThread(
    remoteID: remoteID,
    userID: userID,
    scopeKind: existing.scopeKind,
    scopeRemoteID: existing.scopeRemoteID,
    title: existing.title,
    summary: existing.summary,
    clientUpdatedAt: tombstone.clientDeletedAt,
    deviceID: deviceID,
    deletedAt: tombstone.clientDeletedAt
)
```

Then use `existing.scopeKind` and `existing.scopeRemoteID`.

- [ ] **Step 5: Run test to verify pass**

Run the focused command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseSyncManager.swift native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatSyncRepository.swift native/MuesliNative/Tests/MuesliTests/MeetingChatSyncRepositoryTests.swift
git commit -m "feat: sync meeting chat clears"
```

---

### Task 10: Clear Chat Copy

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatPanel.swift`
- Modify: `native/MuesliNative/Tests/MuesliTests/MeetingChatTests.swift`

- [ ] **Step 1: Check whether clear chat has confirmation**

Run:

```bash
rg -n "meetingChatClear|clearThread|Clear chat|Limpiar chat|confirmation|alert" native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatPanel.swift native/MuesliNative/Sources/MuesliNativeApp/L10n.swift
```

Expected: output shows the existing clear action and whether an alert is already present. Continue to Step 2 either way; Step 5 standardizes the confirmation.

- [ ] **Step 2: Add failing localization test**

Append to `MeetingChatTests`:

```swift
@Test("clear chat sync warning is localized")
func clearChatSyncWarningLocalized() {
    var english = AppConfig()
    english.appLanguage = AppLanguage.english.rawValue
    var spanish = AppConfig()
    spanish.appLanguage = AppLanguage.spanish.rawValue

    #expect(L10n.text(.meetingChatClearSyncedMessage, config: english).contains("all synced devices"))
    #expect(L10n.text(.meetingChatClearSyncedMessage, config: spanish).contains("todos los dispositivos"))
}
```

- [ ] **Step 3: Run test to verify fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter 'clearChatSyncWarningLocalized'
```

Expected: FAIL because `meetingChatClearSyncedMessage` does not exist.

- [ ] **Step 4: Add localization key**

In `L10nKey`, add:

```swift
case meetingChatClearSyncedMessage
```

In English switch:

```swift
case .meetingChatClearSyncedMessage:
    return "This clears this chat on all synced devices. This cannot be undone."
```

In Spanish switch:

```swift
case .meetingChatClearSyncedMessage:
    return "Esto limpia este chat en todos los dispositivos sincronizados. Esta accion no se puede deshacer."
```

- [ ] **Step 5: Wire confirmation**

Add:

```swift
@State private var isConfirmingClear = false
```

Change clear button action:

```swift
isConfirmingClear = true
```

Add `.alert`:

```swift
.alert(
    L10n.text(.meetingChatClear, config: config),
    isPresented: $isConfirmingClear
) {
    Button(L10n.text(.sidebarCancel, config: config), role: .cancel) {}
    Button(L10n.text(.meetingChatClear, config: config), role: .destructive) {
        clearChat()
    }
} message: {
    Text(L10n.text(.meetingChatClearSyncedMessage, config: config))
}
```

- [ ] **Step 6: Run test to verify pass**

Run the focused command from Step 3.

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/L10n.swift native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatPanel.swift native/MuesliNative/Tests/MuesliTests/MeetingChatTests.swift
git commit -m "feat: clarify synced chat clearing"
```

---

### Task 11: Final Verification

**Files:**
- All files changed by Tasks 1-10.

- [ ] **Step 1: Run focused chat/sync tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter 'Meeting chat sync repository|Supabase REST client|Meeting chat|syncCycleOrdersMeetingChatAfterMeetings'
```

Expected: all selected Swift Testing tests pass. The XCTest wrapper may report 0 tests, but Swift Testing output must show selected suites/tests passing.

- [ ] **Step 2: Run full native suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch
```

Expected: full suite passes.

- [ ] **Step 3: Review git status**

Run:

```bash
git status -sb
git log --oneline --decorate -8
```

Expected: only intentional Fase 2 commits are ahead of `origin/beta`; no unrelated `.superpowers/` files are staged.

- [ ] **Step 4: Report**

Report:

- migration file created
- local chat backfill behavior
- global clear-chat behavior
- focused and full test results
- whether Fase 1 local purge-button changes remain separate or have been committed separately
