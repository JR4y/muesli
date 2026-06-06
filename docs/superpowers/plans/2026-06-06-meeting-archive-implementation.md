# Meeting Archive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a synced Archive area for meeting folders and meetings while preserving folder structure and keeping archive separate from delete/purge.

**Architecture:** Archive is modeled as nullable `archived_at` on local SQLite and Supabase `meetings` / `meeting_folders`. The active Meetings area queries only non-archived rows; the Archive tab queries archived rows and exposes restore actions. Supabase sync treats `archived_at` as a normal payload field, included in REST bodies, remote parsing, payload hashes, and conflict resolution.

**Tech Stack:** Swift, SwiftUI, SQLite3, Swift Testing, Supabase PostgREST, Supabase SQL migrations.

---

## File Map

- Modify: `native/MuesliNative/Sources/MuesliCore/StorageModels.swift`
  - Add `archivedAt` to `MeetingRecord` and `MeetingFolder`.
- Modify: `native/MuesliNative/Sources/MuesliCore/DictationStore.swift`
  - Add local schema columns, active/archive query filters, archive/restore APIs.
- Modify: `native/MuesliNative/Sources/MuesliCore/Sync/LocalSyncModels.swift`
  - Add `archivedAt` to remote folder/meeting payloads.
- Modify: `native/MuesliNative/Sources/MuesliCore/Sync/LocalSyncRepository.swift`
  - Read/write `archived_at` in dirty rows and remote apply helpers.
- Modify: `native/MuesliNative/Sources/MuesliCore/Sync/SyncPayloadHasher.swift`
  - Include `archived_at` in folder and meeting hashes.
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseRESTClient.swift`
  - Send and parse `archived_at`.
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseSyncManager.swift`
  - Pass archive values through upload/conflict code paths.
- Create: `supabase/migrations/20260606000000_add_archive_state.sql`
  - Add remote archive columns and indexes.
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/AppState.swift`
  - Add `DashboardTab.archive` and archive view state/counts.
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift`
  - Load active vs archived rows, add archive navigation/actions.
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/SidebarView.swift`
  - Add Archive top-level nav and archive/restore context actions.
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingsView.swift`
  - Reuse browser for active Meetings and Archive modes.
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingListItemView.swift`
  - Replace delete-only affordance with configurable row action.
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`
  - Add Archive/Restore/localized copy.
- Modify tests:
  - `native/MuesliNative/Tests/MuesliTests/DictationStoreTests.swift`
  - `native/MuesliNative/Tests/MuesliTests/LocalSyncRepositoryTests.swift`
  - `native/MuesliNative/Tests/MuesliTests/SupabaseRESTClientTests.swift`
  - `native/MuesliNative/Tests/MuesliTests/MeetingsNavigationTests.swift`
  - `native/MuesliNative/Tests/MuesliTests/DashboardRootViewTests.swift`

---

## Task 1: Local Archive Schema And Store APIs

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliCore/StorageModels.swift`
- Modify: `native/MuesliNative/Sources/MuesliCore/DictationStore.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/DictationStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Append these tests inside `DictationStoreTests`:

```swift
@Test("migration adds archive columns to meetings and folders")
func migrationAddsArchiveColumns() throws {
    let store = try makeStore()
    let db = try openSQLiteDatabase(at: store.databasePath())
    defer { sqlite3_close(db) }

    #expect(try tableColumns("meetings", db: db).contains("archived_at"))
    #expect(try tableColumns("meeting_folders", db: db).contains("archived_at"))
}

@Test("archive meeting hides it from active meetings and restore returns it")
func archiveMeetingFiltersActiveRows() throws {
    let store = try makeStore()
    let start = Date()
    let id = try store.insertMeeting(
        title: "Archive Me",
        calendarEventID: nil,
        startTime: start,
        endTime: start.addingTimeInterval(60),
        rawTranscript: "Transcript",
        formattedNotes: "Notes",
        micAudioPath: nil,
        systemAudioPath: nil
    )

    try store.archiveMeeting(id: id, archivedAt: "2026-06-06T10:00:00.000Z")

    #expect(try store.recentMeetings(limit: 10).isEmpty)
    let archived = try store.recentMeetings(limit: 10, archiveFilter: .archived)
    #expect(archived.map(\.id) == [id])
    #expect(archived.first?.archivedAt == "2026-06-06T10:00:00.000Z")

    try store.restoreMeeting(id: id)

    #expect(try store.recentMeetings(limit: 10).map(\.id) == [id])
    #expect(try store.recentMeetings(limit: 10, archiveFilter: .archived).isEmpty)
}

@Test("archive folder archives descendants and subtree meetings")
func archiveFolderTreeArchivesDescendants() throws {
    let store = try makeStore()
    let root = try store.createFolder(name: "Root")
    let child = try store.createFolder(name: "Child", parentFolderID: root)
    let outsider = try store.createFolder(name: "Other")
    let start = Date()
    let rootMeeting = try insertMeeting(in: store, title: "Root Meeting", folderID: root, start: start)
    let childMeeting = try insertMeeting(in: store, title: "Child Meeting", folderID: child, start: start.addingTimeInterval(60))
    let outsideMeeting = try insertMeeting(in: store, title: "Outside", folderID: outsider, start: start.addingTimeInterval(120))

    try store.archiveFolderTree(id: root, archivedAt: "2026-06-06T11:00:00.000Z")

    #expect(try store.listFolders().map(\.id) == [outsider])
    #expect(try store.listFolders(archiveFilter: .archived).map(\.id) == [root, child])
    #expect(try store.recentMeetings(limit: 10).map(\.id) == [outsideMeeting])
    #expect(Set(try store.recentMeetings(limit: 10, archiveFilter: .archived).map(\.id)) == Set([rootMeeting, childMeeting]))
}

@Test("restore folder tree clears archived rows")
func restoreFolderTreeClearsArchiveState() throws {
    let store = try makeStore()
    let root = try store.createFolder(name: "Root")
    let child = try store.createFolder(name: "Child", parentFolderID: root)
    let start = Date()
    let meeting = try insertMeeting(in: store, title: "Child Meeting", folderID: child, start: start)

    try store.archiveFolderTree(id: root, archivedAt: "2026-06-06T11:00:00.000Z")
    try store.restoreFolderTree(id: root)

    #expect(try store.listFolders().map(\.id) == [root, child])
    #expect(try store.listFolders(archiveFilter: .archived).isEmpty)
    #expect(try store.recentMeetings(limit: 10).map(\.id) == [meeting])
}
```

Add these helpers near the existing test helpers:

```swift
private func openSQLiteDatabase(at url: URL) throws -> OpaquePointer? {
    var db: OpaquePointer?
    #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
    return db
}

private func tableColumns(_ table: String, db: OpaquePointer?) throws -> Set<String> {
    var stmt: OpaquePointer?
    #expect(sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK)
    defer { sqlite3_finalize(stmt) }
    var columns = Set<String>()
    while sqlite3_step(stmt) == SQLITE_ROW {
        if let raw = sqlite3_column_text(stmt, 1) {
            columns.insert(String(cString: raw))
        }
    }
    return columns
}

private func insertMeeting(
    in store: DictationStore,
    title: String,
    folderID: Int64,
    start: Date
) throws -> Int64 {
    let id = try store.insertMeeting(
        title: title,
        calendarEventID: nil,
        startTime: start,
        endTime: start.addingTimeInterval(30),
        rawTranscript: "Transcript",
        formattedNotes: "Notes",
        micAudioPath: nil,
        systemAudioPath: nil
    )
    try store.moveMeeting(id: id, toFolder: folderID)
    return id
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter "archive|migrationAddsArchive"
```

Expected: compile failures for missing `archiveFilter`, `.archived`, `archiveMeeting`, `restoreMeeting`, `archiveFolderTree`, `restoreFolderTree`, and `archivedAt`.

- [ ] **Step 3: Implement storage model fields**

In `StorageModels.swift`, add `archivedAt` to `MeetingRecord`:

```swift
public let archivedAt: String?
```

Add an initializer parameter after `source`:

```swift
source: MeetingSource = .meeting,
archivedAt: String? = nil
```

Assign it:

```swift
self.archivedAt = archivedAt
```

Add it to `CodingKeys`:

```swift
case archivedAt
```

Decode with default nil:

```swift
archivedAt: try c.decodeIfPresent(String.self, forKey: .archivedAt)
```

Add `archivedAt` to `MeetingFolder`:

```swift
public let archivedAt: String?
```

Add initializer parameter:

```swift
archivedAt: String? = nil
```

Assign it:

```swift
self.archivedAt = archivedAt
```

- [ ] **Step 4: Implement local archive filter and schema**

In `DictationStore.swift`, add:

```swift
public enum MeetingArchiveFilter: Sendable {
    case active
    case archived
    case all

    var sqlPredicate: String {
        switch self {
        case .active:
            return "archived_at IS NULL"
        case .archived:
            return "archived_at IS NOT NULL"
        case .all:
            return "1 = 1"
        }
    }
}
```

Update `meetingColumns` to append `archived_at`:

```swift
private static let meetingColumns = """
id, title, start_time, duration_seconds, raw_transcript, formatted_notes, word_count, folder_id, calendar_event_id, mic_audio_path, system_audio_path, saved_recording_path, merged_into_meeting_id, meeting_status, manual_notes, selected_template_id, selected_template_name, selected_template_kind, selected_template_prompt, source, calendar_event_snapshot, archived_at
"""
```

Add `archived_at TEXT` to fresh `meetings` and `meeting_folders` table definitions. Add idempotent alters and indexes:

```swift
if sqlite3_exec(db, "ALTER TABLE meetings ADD COLUMN archived_at TEXT", nil, nil, nil) != SQLITE_OK {
    // Column may already exist.
}
if sqlite3_exec(db, "ALTER TABLE meeting_folders ADD COLUMN archived_at TEXT", nil, nil, nil) != SQLITE_OK {
    // Column may already exist.
}
let _ = sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_meetings_archived_at ON meetings(archived_at)", nil, nil, nil)
let _ = sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_meeting_folders_archived_at ON meeting_folders(archived_at)", nil, nil, nil)
```

- [ ] **Step 5: Implement archive-aware queries and APIs**

Change signatures:

```swift
public func meetingCounts(archiveFilter: MeetingArchiveFilter = .active) throws -> (total: Int, byFolder: [Int64: Int])
public func recentMeetings(limit: Int? = nil, folderID: Int64? = nil, archiveFilter: MeetingArchiveFilter = .active) throws -> [MeetingRecord]
public func listFolders(archiveFilter: MeetingArchiveFilter = .active) throws -> [MeetingFolder]
```

Use `archiveFilter.sqlPredicate` in SQL. For folder recursive queries, make the CTE select only folders matching the same archive filter:

```swift
WITH RECURSIVE folder_tree(id) AS (
    SELECT id FROM meeting_folders WHERE id = ? AND \(archiveFilter.sqlPredicate)
    UNION ALL
    SELECT child.id
    FROM meeting_folders child
    JOIN folder_tree parent ON child.parent_folder_id = parent.id
    WHERE child.\(archiveFilter.sqlPredicate)
)
```

In the meetings WHERE clause add:

```swift
AND \(archiveFilter.sqlPredicate)
```

For folders, select:

```swift
SELECT id, name, parent_folder_id, color_hex, icon_name, created_at, archived_at
FROM meeting_folders
WHERE \(archiveFilter.sqlPredicate)
ORDER BY created_at ASC, id ASC
```

Add archive APIs:

```swift
public func archiveMeeting(id: Int64, archivedAt: String = SyncTimestamp.now()) throws {
    try setMeetingArchivedAt(id: id, archivedAt: archivedAt)
}

public func restoreMeeting(id: Int64) throws {
    try setMeetingArchivedAt(id: id, archivedAt: nil)
}

public func archiveFolderTree(id: Int64, archivedAt: String = SyncTimestamp.now()) throws {
    try setFolderTreeArchivedAt(id: id, archivedAt: archivedAt)
}

public func restoreFolderTree(id: Int64) throws {
    try setFolderTreeArchivedAt(id: id, archivedAt: nil)
}
```

Add private helpers:

```swift
private func setMeetingArchivedAt(id: Int64, archivedAt: String?) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    let sql = "UPDATE meetings SET archived_at = ? WHERE id = ?"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw lastError(db)
    }
    defer { sqlite3_finalize(statement) }
    bindOptionalText(archivedAt, at: 1, statement: statement)
    sqlite3_bind_int64(statement, 2, id)
    guard sqlite3_step(statement) == SQLITE_DONE else {
        throw lastError(db)
    }
}

private func setFolderTreeArchivedAt(id: Int64, archivedAt: String?) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil) == SQLITE_OK else {
        throw lastError(db)
    }
    do {
        let folderSQL = """
        WITH RECURSIVE folder_tree(id) AS (
            SELECT id FROM meeting_folders WHERE id = ?
            UNION ALL
            SELECT child.id
            FROM meeting_folders child
            JOIN folder_tree parent ON child.parent_folder_id = parent.id
        )
        UPDATE meeting_folders
        SET archived_at = ?
        WHERE id IN (SELECT id FROM folder_tree)
        """
        try execArchiveTreeUpdate(sql: folderSQL, rootID: id, archivedAt: archivedAt, db: db)

        let meetingSQL = """
        WITH RECURSIVE folder_tree(id) AS (
            SELECT id FROM meeting_folders WHERE id = ?
            UNION ALL
            SELECT child.id
            FROM meeting_folders child
            JOIN folder_tree parent ON child.parent_folder_id = parent.id
        )
        UPDATE meetings
        SET archived_at = ?
        WHERE folder_id IN (SELECT id FROM folder_tree)
        """
        try execArchiveTreeUpdate(sql: meetingSQL, rootID: id, archivedAt: archivedAt, db: db)

        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            throw lastError(db)
        }
    } catch {
        sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
        throw error
    }
}

private func execArchiveTreeUpdate(sql: String, rootID: Int64, archivedAt: String?, db: OpaquePointer?) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw lastError(db)
    }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_int64(statement, 1, rootID)
    bindOptionalText(archivedAt, at: 2, statement: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
        throw lastError(db)
    }
}
```

Update `makeMeetingRecord` and folder row creation to read `archived_at`.

- [ ] **Step 6: Run focused store tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter "archive|migrationAddsArchive"
```

Expected: all added archive store tests pass.

- [ ] **Step 7: Commit Task 1**

```bash
git add native/MuesliNative/Sources/MuesliCore/StorageModels.swift native/MuesliNative/Sources/MuesliCore/DictationStore.swift native/MuesliNative/Tests/MuesliTests/DictationStoreTests.swift
git commit -m "feat: add local archive state"
```

---

## Task 2: Supabase Archive Schema

**Files:**
- Create: `supabase/migrations/20260606000000_add_archive_state.sql`

- [ ] **Step 1: Add migration file**

Create:

```sql
-- Muesli Archive state
-- Adds reversible archive state for folders and meetings.

alter table public.meeting_folders
    add column if not exists archived_at timestamptz;

alter table public.meetings
    add column if not exists archived_at timestamptz;

create index if not exists idx_meeting_folders_user_archived
    on public.meeting_folders (user_id, archived_at);

create index if not exists idx_meetings_user_archived
    on public.meetings (user_id, archived_at);
```

- [ ] **Step 2: Verify migration syntax locally**

Run:

```bash
supabase migration list
```

Expected: the new local migration appears as unapplied remotely.

- [ ] **Step 3: Commit Task 2**

```bash
git add supabase/migrations/20260606000000_add_archive_state.sql
git commit -m "db: add archive state columns"
```

---

## Task 3: Sync Payloads And REST Archive Fields

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliCore/Sync/LocalSyncModels.swift`
- Modify: `native/MuesliNative/Sources/MuesliCore/Sync/SyncPayloadHasher.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseRESTClient.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/SupabaseRESTClientTests.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/LocalSyncRepositoryTests.swift`

- [ ] **Step 1: Write failing hash and REST tests**

Add to `LocalSyncRepositoryTests`:

```swift
@Test("meeting hash changes when archive state changes")
func meetingHashDiffersForArchiveState() {
    let active = SyncPayloadHasher.meetingHash(
        title: "Planning",
        calendarEventID: nil,
        calendarEventSnapshotJSON: nil,
        startTime: "2026-06-06T10:00:00Z",
        endTime: nil,
        durationSeconds: 60,
        rawTranscript: "Transcript",
        formattedNotes: "Notes",
        meetingStatus: "completed",
        manualNotes: "",
        wordCount: 2,
        selectedTemplateID: nil,
        selectedTemplateName: nil,
        selectedTemplateKind: nil,
        selectedTemplatePrompt: nil,
        folderRemoteID: nil,
        mergedIntoMeetingRemoteID: nil,
        archivedAt: nil
    )
    let archived = SyncPayloadHasher.meetingHash(
        title: "Planning",
        calendarEventID: nil,
        calendarEventSnapshotJSON: nil,
        startTime: "2026-06-06T10:00:00Z",
        endTime: nil,
        durationSeconds: 60,
        rawTranscript: "Transcript",
        formattedNotes: "Notes",
        meetingStatus: "completed",
        manualNotes: "",
        wordCount: 2,
        selectedTemplateID: nil,
        selectedTemplateName: nil,
        selectedTemplateKind: nil,
        selectedTemplatePrompt: nil,
        folderRemoteID: nil,
        mergedIntoMeetingRemoteID: nil,
        archivedAt: "2026-06-06T11:00:00.000Z"
    )
    #expect(active != archived)
}

@Test("folder hash changes when archive state changes")
func folderHashDiffersForArchiveState() {
    let active = SyncPayloadHasher.folderHash(
        name: "Customers",
        parentRemoteID: nil,
        colorHex: nil,
        iconName: nil,
        sortOrder: 0,
        archivedAt: nil
    )
    let archived = SyncPayloadHasher.folderHash(
        name: "Customers",
        parentRemoteID: nil,
        colorHex: nil,
        iconName: nil,
        sortOrder: 0,
        archivedAt: "2026-06-06T11:00:00.000Z"
    )
    #expect(active != archived)
}
```

Add or update REST tests so captured JSON body contains:

```swift
#expect(body["archived_at"] as? String == "2026-06-06T11:00:00.000Z")
```

And parse tests expect:

```swift
#expect(payload.archivedAt == "2026-06-06T11:00:00.000Z")
```

- [ ] **Step 2: Run failing sync/REST tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter "archive state|archived_at|ArchiveState"
```

Expected: compile failures for missing `archivedAt` parameters and properties.

- [ ] **Step 3: Add archived fields to remote models**

In `RemoteFolderPayload`, add:

```swift
public let archivedAt: String?
```

Add initializer parameter after `deletedAt`:

```swift
archivedAt: String?
```

Assign it:

```swift
self.archivedAt = archivedAt
```

In `RemoteMeetingPayload`, add the same property and initializer parameter.

- [ ] **Step 4: Add archive to hashes**

Change hash signatures:

```swift
archivedAt: String?
```

Add payload keys:

```swift
"archived_at": archivedAt as Any? ?? NSNull(),
```

Update every call site to pass local or remote archive state.

- [ ] **Step 5: Add archive to REST client**

Add `archivedAt: String?` parameter to `upsertFolder`, `updateFolder`, `upsertMeeting`, and `updateMeeting`.

Add to request bodies:

```swift
"archived_at": archivedAt as Any? ?? NSNull(),
```

In `parseFolder`, read:

```swift
let archivedAt = row["archived_at"] as? String
```

Pass `archivedAt` to `RemoteFolderPayload`.

In `parseMeeting`, read and pass the same field.

- [ ] **Step 6: Run focused sync/REST tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter "meeting hash changes when archive state changes|folder hash changes when archive state changes|SupabaseRESTClient"
```

Expected: hash and REST tests pass.

- [ ] **Step 7: Commit Task 3**

```bash
git add native/MuesliNative/Sources/MuesliCore/Sync/LocalSyncModels.swift native/MuesliNative/Sources/MuesliCore/Sync/SyncPayloadHasher.swift native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseRESTClient.swift native/MuesliNative/Tests/MuesliTests/SupabaseRESTClientTests.swift native/MuesliNative/Tests/MuesliTests/LocalSyncRepositoryTests.swift
git commit -m "feat: sync archive payload fields"
```

---

## Task 4: Local Sync Repository Archive Apply/Dirty Rows

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliCore/Sync/LocalSyncRepository.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/LocalSyncRepositoryTests.swift`

- [ ] **Step 1: Write failing local sync tests**

Add tests:

```swift
@Test("dirty meeting exposes archivedAt")
func dirtyMeetingExposesArchiveState() throws {
    let fx = try SyncFixture()
    let meetingID = try fx.store.insertMeeting(
        title: "Archived",
        calendarEventID: nil,
        startTime: Date(),
        endTime: Date().addingTimeInterval(60),
        rawTranscript: "Transcript",
        formattedNotes: "Notes",
        micAudioPath: nil,
        systemAudioPath: nil
    )
    try fx.store.archiveMeeting(id: meetingID, archivedAt: "2026-06-06T12:00:00.000Z")

    let dirty = try #require(try fx.repo.dirtyMeetings(limit: 10).first { $0.record.id == meetingID })
    #expect(dirty.record.archivedAt == "2026-06-06T12:00:00.000Z")
}

@Test("apply remote archived meeting stores archive state")
func applyRemoteArchivedMeeting() throws {
    let fx = try SyncFixture()
    try fx.repo.applyRemoteMeeting(RemoteMeetingPayload(
        remoteID: UUID().uuidString,
        folderRemoteID: nil,
        title: "Remote Archived",
        calendarEventID: nil,
        calendarEventSnapshotJSON: nil,
        startTime: "2026-06-06T10:00:00Z",
        endTime: nil,
        durationSeconds: 60,
        rawTranscript: "Transcript",
        formattedNotes: "Notes",
        meetingStatus: "completed",
        manualNotes: "",
        wordCount: 2,
        selectedTemplateID: nil,
        selectedTemplateName: nil,
        selectedTemplateKind: nil,
        selectedTemplatePrompt: nil,
        clientUpdatedAt: "2026-06-06T12:00:00.000Z",
        serverUpdatedAt: "2026-06-06T12:00:00.000Z",
        remoteVersion: 1,
        lastWriterDeviceID: "remote",
        deletedAt: nil,
        archivedAt: "2026-06-06T12:00:00.000Z"
    ))

    let archived = try fx.store.recentMeetings(limit: 10, archiveFilter: .archived)
    #expect(archived.first?.title == "Remote Archived")
    #expect(archived.first?.archivedAt == "2026-06-06T12:00:00.000Z")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter "dirty meeting exposes archivedAt|apply remote archived meeting"
```

Expected: failures until sync repository selects, inserts, updates, and hashes archive state.

- [ ] **Step 3: Update dirty selects and row builders**

In `dirtyMeetings`, select `me.archived_at` after `me.calendar_event_snapshot`, and adjust metadata indexes by +1. Make `makeMeetingRecord(stmt:baseColumn:)` read archive state at the new base column.

In `dirtyFolders`, select `f.archived_at` after `f.created_at`, and create `MeetingFolder(... archivedAt: archivedAt)`. Adjust metadata indexes by +1.

In `unsyncedMeetings` and `unsyncedFolders`, include `archived_at` in SELECTs and row builders.

- [ ] **Step 4: Update apply remote insert/update helpers**

In `insertMeeting`, add `archived_at` column and bind `payload.archivedAt`.

In `updateMeeting`, set:

```swift
archived_at = ?
```

Bind `payload.archivedAt`.

In `insertFolder`, add `archived_at` and bind `payload.archivedAt`.

In `updateFolder`, set and bind `payload.archivedAt`.

- [ ] **Step 5: Update repository hashes**

Every `SyncPayloadHasher.meetingHash` call in `LocalSyncRepository` passes:

```swift
archivedAt: payload.archivedAt
```

or:

```swift
archivedAt: local.record.archivedAt
```

Every `folderHash` call passes:

```swift
archivedAt: payload.archivedAt
```

or:

```swift
archivedAt: local.record.archivedAt
```

- [ ] **Step 6: Run focused local sync tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter "dirty meeting exposes archivedAt|apply remote archived meeting|LocalSyncRepository"
```

Expected: local sync repository tests pass.

- [ ] **Step 7: Commit Task 4**

```bash
git add native/MuesliNative/Sources/MuesliCore/Sync/LocalSyncRepository.swift native/MuesliNative/Tests/MuesliTests/LocalSyncRepositoryTests.swift
git commit -m "feat: apply archive state in local sync"
```

---

## Task 5: Supabase Sync Manager Archive Upload/Conflict

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseSyncManager.swift`

- [ ] **Step 1: Update upload and conflict calls**

For folder uploads, pass:

```swift
archivedAt: local.record.archivedAt
```

For meeting uploads, pass:

```swift
archivedAt: local.record.archivedAt
```

For delete placeholder rows, pass:

```swift
archivedAt: nil
```

For remote hash comparisons, pass:

```swift
archivedAt: remote.archivedAt
```

For local hash comparisons, pass:

```swift
archivedAt: local.record.archivedAt
```

- [ ] **Step 2: Run sync manager tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter Supabase
```

Expected: Supabase sync tests compile and pass.

- [ ] **Step 3: Commit Task 5**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseSyncManager.swift
git commit -m "feat: upload archive state through sync"
```

---

## Task 6: Archive App State And Controller Actions

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/AppState.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/MeetingsNavigationTests.swift`

- [ ] **Step 1: Write failing controller tests**

Add tests:

```swift
@Test("showArchiveHome routes to archive tab")
func showArchiveHomeRoutesToArchive() {
    let controller = makeController()

    controller.showArchiveHome()

    #expect(controller.appState.selectedTab == .archive)
    #expect(controller.appState.meetingsNavigationState == .browser)
    #expect(controller.appState.selectedFolderID == nil)
}

@Test("archiveMeeting hides row from active controller state")
func archiveMeetingRefreshesActiveState() throws {
    let store = try makeStore()
    let id = try store.insertMeeting(
        title: "Archive Target",
        calendarEventID: nil,
        startTime: Date(),
        endTime: Date().addingTimeInterval(60),
        rawTranscript: "Transcript",
        formattedNotes: "Notes",
        micAudioPath: nil,
        systemAudioPath: nil
    )
    let controller = MuesliController(
        runtime: RuntimePaths(repoRoot: FileManager.default.temporaryDirectory, menuIcon: nil, appIcon: nil, bundlePath: nil),
        dictationStore: store
    )

    controller.archiveMeeting(id: id)

    #expect(controller.appState.meetingRows.isEmpty)
    #expect(try store.recentMeetings(limit: 10, archiveFilter: .archived).map(\.id) == [id])
}

@Test("restoreMeeting returns row from archive")
func restoreMeetingRefreshesArchiveState() throws {
    let store = try makeStore()
    let id = try store.insertMeeting(
        title: "Restore Target",
        calendarEventID: nil,
        startTime: Date(),
        endTime: Date().addingTimeInterval(60),
        rawTranscript: "Transcript",
        formattedNotes: "Notes",
        micAudioPath: nil,
        systemAudioPath: nil
    )
    try store.archiveMeeting(id: id, archivedAt: "2026-06-06T12:00:00.000Z")
    let controller = MuesliController(
        runtime: RuntimePaths(repoRoot: FileManager.default.temporaryDirectory, menuIcon: nil, appIcon: nil, bundlePath: nil),
        dictationStore: store
    )
    controller.showArchiveHome()

    controller.restoreMeeting(id: id)

    #expect(controller.appState.meetingRows.isEmpty)
    #expect(try store.recentMeetings(limit: 10).map(\.id) == [id])
}
```

- [ ] **Step 2: Run failing controller tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter "showArchiveHome|archiveMeetingRefreshesActiveState|restoreMeetingRefreshesArchiveState"
```

Expected: compile failures for missing `.archive`, `showArchiveHome`, `archiveMeeting`, and `restoreMeeting`.

- [ ] **Step 3: Add app state for archive**

In `DashboardTab`, add:

```swift
case archive
```

In `AppState`, add:

```swift
var archivedMeetingCount: Int = 0
var archivedMeetingCountsByFolder: [Int64: Int] = [:]
var archivedFolders: [MeetingFolder] = []
```

Add archive-aware folder helpers:

```swift
func folders(for tab: DashboardTab) -> [MeetingFolder] {
    tab == .archive ? archivedFolders : folders
}

func meetingCountsByFolder(for tab: DashboardTab) -> [Int64: Int] {
    tab == .archive ? archivedMeetingCountsByFolder : meetingCountsByFolder
}

func childFolders(of parentFolderID: Int64?, tab: DashboardTab) -> [MeetingFolder] {
    folders(for: tab).filter { $0.parentFolderID == parentFolderID }
}

func hasChildFolders(_ folderID: Int64, tab: DashboardTab) -> Bool {
    folders(for: tab).contains(where: { $0.parentFolderID == folderID })
}
```

- [ ] **Step 4: Update controller load and navigation**

In `syncAppState`, compute:

```swift
let archiveFilter: MeetingArchiveFilter = appState.selectedTab == .archive ? .archived : .active
appState.meetingRows = (try? dictationStore.recentMeetings(limit: 200, folderID: appState.selectedFolderID, archiveFilter: archiveFilter)) ?? []
let allFolders = (try? dictationStore.listFolders()) ?? []
let archivedFolders = (try? dictationStore.listFolders(archiveFilter: .archived)) ?? []
let counts = (try? dictationStore.meetingCounts()) ?? (total: 0, byFolder: [:])
let archivedCounts = (try? dictationStore.meetingCounts(archiveFilter: .archived)) ?? (total: 0, byFolder: [:])
appState.folders = allFolders
appState.archivedFolders = archivedFolders
appState.totalMeetingCount = counts.total
appState.archivedMeetingCount = archivedCounts.total
appState.meetingCountsByFolder = aggregatedFolderCounts(directCounts: counts.byFolder, folders: allFolders)
appState.archivedMeetingCountsByFolder = aggregatedFolderCounts(directCounts: archivedCounts.byFolder, folders: archivedFolders)
```

Add controller methods:

```swift
func showArchiveHome(folderID: Int64? = nil) {
    appState.selectedTab = .archive
    appState.selectedFolderID = folderID
    appState.meetingsNavigationState = .browser
    syncAppState()
}

func archiveMeeting(id: Int64) {
    try? dictationStore.archiveMeeting(id: id)
    if appState.selectedMeetingID == id {
        appState.selectedMeetingID = nil
        appState.selectedMeetingRecord = nil
        appState.meetingsNavigationState = .browser
    }
    syncAppState()
}

func restoreMeeting(id: Int64) {
    try? dictationStore.restoreMeeting(id: id)
    syncAppState()
}

func archiveFolder(id: Int64) {
    try? dictationStore.archiveFolderTree(id: id)
    if appState.selectedFolderID == id {
        appState.selectedFolderID = nil
    }
    syncAppState()
}

func restoreFolder(id: Int64) {
    try? dictationStore.restoreFolderTree(id: id)
    syncAppState()
}
```

- [ ] **Step 5: Run controller tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter "showArchiveHome|archiveMeetingRefreshesActiveState|restoreMeetingRefreshesArchiveState"
```

Expected: added controller tests pass.

- [ ] **Step 6: Commit Task 6**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/AppState.swift native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift native/MuesliNative/Tests/MuesliTests/MeetingsNavigationTests.swift
git commit -m "feat: add archive controller state"
```

---

## Task 7: Archive Navigation And Row Actions

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/DashboardRootView.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/SidebarView.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingsView.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingListItemView.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/DashboardRootViewTests.swift`

- [ ] **Step 1: Write failing UI logic tests**

Add:

```swift
@Test("archive tab is a dashboard tab")
func archiveTabExists() {
    #expect(DashboardTab.allCases.contains(.archive))
}

@Test("archive tab does not reserve titlebar inset")
func archiveTitlebarInset() {
    #expect(DashboardRootView.titlebarContentInset(isSearchActive: false, selectedTab: .archive) == 0)
}
```

- [ ] **Step 2: Run failing UI logic tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter "archive tab"
```

Expected: `.archive` compile failure until Task 6 is in place, then pass after UI switch handles it.

- [ ] **Step 3: Add localization keys**

Add keys:

```swift
case sidebarArchive
case meetingArchive
case meetingRestore
case meetingArchiveHelp
case meetingRestoreHelp
case folderArchiveTitle
case folderArchiveMessage
case archiveEmptyTitle
case archiveEmptyMessage
```

English:

```swift
"Archive"
"Restore"
"Archive meeting"
"Restore meeting"
"Archive this meeting"
"Restore this meeting"
"Archive folder?"
"This archives the folder, its subfolders, and all meetings inside them."
"Archive is empty"
"Archived folders and meetings will appear here."
```

Spanish:

```swift
"Archivo"
"Restaurar"
"Archivar nota"
"Restaurar nota"
"Archivar esta nota"
"Restaurar esta nota"
"Archivar carpeta?"
"Esto archiva la carpeta, sus subcarpetas y todas las notas dentro de ellas."
"El archivo esta vacio"
"Las carpetas y notas archivadas apareceran aqui."
```

- [ ] **Step 4: Add Archive routing**

In `DashboardRootView.detailContent`, add:

```swift
case .archive:
    MeetingsView(appState: appState, controller: controller)
```

In `SidebarView`, add a custom top-level Archive row before Settings so it can
load archived data through the controller:

```swift
Button {
    controller.showArchiveHome()
} label: {
    HStack(spacing: MuesliTheme.spacing12) {
        Image(systemName: "archivebox")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(appState.selectedTab == .archive ? MuesliTheme.accent : MuesliTheme.textSecondary)
            .frame(width: sidebarIconColumnWidth, height: sidebarIconColumnWidth, alignment: .center)
        Text(L10n.text(.sidebarArchive, config: appState.config))
            .font(MuesliTheme.headline())
            .foregroundStyle(appState.selectedTab == .archive ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
        Spacer()
        Text(formattedCount(appState.archivedMeetingCount))
            .font(MuesliTheme.caption())
            .monospacedDigit()
            .foregroundStyle(MuesliTheme.textTertiary)
    }
    .padding(.horizontal, sidebarRowHorizontalPadding)
    .padding(.vertical, MuesliTheme.spacing8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
            .fill(appState.selectedTab == .archive ? MuesliTheme.surfaceSelected : Color.clear)
    )
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
.padding(.horizontal, sidebarRowOuterPadding)
```

Use archive-aware folder sources:

```swift
private var rootFolders: [MeetingFolder] {
    appState.childFolders(of: nil, tab: appState.selectedTab)
}

private func folderChildren(of folderID: Int64) -> [MeetingFolder] {
    appState.childFolders(of: folderID, tab: appState.selectedTab)
}

private func folderHasChildren(_ folderID: Int64) -> Bool {
    appState.hasChildFolders(folderID, tab: appState.selectedTab)
}

private func folderMeetingCount(_ folderID: Int64) -> Int {
    appState.meetingCountsByFolder(for: appState.selectedTab)[folderID] ?? 0
}
```

Replace `appState.hasChildFolders(folder.id)`,
`appState.childFolders(of: folder.id)`, and
`appState.meetingCountsByFolder[folder.id]` in the folder tree with those
helpers.

Add context menu Archive on active folders only:

```swift
if appState.selectedTab == .meetings {
    Button(L10n.text(.meetingArchive, config: appState.config)) {
        folderToArchive = folder
        showArchiveConfirmation = true
    }
}
```

Add restore on archive folders only:

```swift
if appState.selectedTab == .archive {
    Button(L10n.text(.meetingRestore, config: appState.config)) {
        controller.restoreFolder(id: folder.id)
    }
}
```

- [ ] **Step 5: Make MeetingListItemView action configurable**

Replace `onDelete` with:

```swift
let primaryAction: MeetingListItemPrimaryAction?

struct MeetingListItemPrimaryAction {
    let systemImage: String
    let help: String
    let confirmationTitle: String?
    let confirmationMessage: String?
    let role: ButtonRole?
    let action: () -> Void
}
```

Use `primaryAction` for the hover button. If confirmation title/message exist, show alert; otherwise run `action()` directly.

In active Meetings, pass Archive:

```swift
primaryAction: MeetingListItemPrimaryAction(
    systemImage: "archivebox",
    help: L10n.text(.meetingArchiveHelp, config: appState.config),
    confirmationTitle: nil,
    confirmationMessage: nil,
    role: nil,
    action: { controller.archiveMeeting(id: meeting.id) }
)
```

Preserve delete in meeting detail where deletion still exists by creating a delete action with `systemImage: "trash"` and destructive confirmation.

In Archive, pass Restore for standalone archived meetings:

```swift
primaryAction: MeetingListItemPrimaryAction(
    systemImage: "arrow.uturn.backward",
    help: L10n.text(.meetingRestoreHelp, config: appState.config),
    confirmationTitle: nil,
    confirmationMessage: nil,
    role: nil,
    action: { controller.restoreMeeting(id: meeting.id) }
)
```

- [ ] **Step 6: Adapt MeetingsView for archive mode**

Add:

```swift
private var isArchiveMode: Bool {
    appState.selectedTab == .archive
}
```

Use `isArchiveMode` to hide:

- upcoming calendar section
- quick note button
- folder chat panel
- import audio drop target

Use archive title when no folder is selected:

```swift
return isArchiveMode
    ? L10n.text(.sidebarArchive, config: appState.config)
    : L10n.text(.sidebarAllMeetings, config: appState.config)
```

Use archive empty state copy when `isArchiveMode`.

- [ ] **Step 7: Run UI logic tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter "Dashboard root view|Meetings navigation"
```

Expected: dashboard/navigation tests pass.

- [ ] **Step 8: Commit Task 7**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/L10n.swift native/MuesliNative/Sources/MuesliNativeApp/DashboardRootView.swift native/MuesliNative/Sources/MuesliNativeApp/SidebarView.swift native/MuesliNative/Sources/MuesliNativeApp/MeetingsView.swift native/MuesliNative/Sources/MuesliNativeApp/MeetingListItemView.swift native/MuesliNative/Tests/MuesliTests/DashboardRootViewTests.swift
git commit -m "feat: add archive navigation"
```

---

## Task 8: Visible Notes Label Pass

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/MeetingsNavigationTests.swift`

- [ ] **Step 1: Write failing localization test**

Add:

```swift
@Test("primary meeting collection labels use notes language")
func primaryMeetingLabelsUseNotesLanguage() {
    var english = AppConfig()
    english.appLanguage = AppLanguage.english.rawValue
    var spanish = AppConfig()
    spanish.appLanguage = AppLanguage.spanish.rawValue

    #expect(L10n.text(.sidebarMeetings, config: english) == "Notes")
    #expect(L10n.text(.sidebarMeetings, config: spanish) == "Notas")
}
```

- [ ] **Step 2: Run failing localization test**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter primaryMeetingLabelsUseNotesLanguage
```

Expected: fails while labels still say Meetings/Reuniones.

- [ ] **Step 3: Update visible collection labels**

In `L10n.swift`, change primary collection labels:

```swift
case .sidebarMeetings:
    return "Notes"
case .sidebarAllMeetings:
    return "All Notes"
```

Spanish:

```swift
case .sidebarMeetings:
    return "Notas"
case .sidebarAllMeetings:
    return "Todas las notas"
```

Update empty-state/action labels that describe the collection as a whole. Keep specific calendar-related text as meeting language where it refers to actual meetings.

- [ ] **Step 4: Run localization test**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter primaryMeetingLabelsUseNotesLanguage
```

Expected: test passes.

- [ ] **Step 5: Commit Task 8**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/L10n.swift native/MuesliNative/Tests/MuesliTests/MeetingsNavigationTests.swift
git commit -m "feat: rename primary meetings labels to notes"
```

---

## Task 9: Remote Migration Push And Full Verification

**Files:**
- No code edits unless verification exposes a bug.

- [ ] **Step 1: Run focused archive test sweep**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter "archive|Archive|archived_at|archivedAt"
```

Expected: archive-focused tests pass.

- [ ] **Step 2: Run full native suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch
```

Expected: full native suite passes.

- [ ] **Step 3: Push Supabase migration**

Run:

```bash
supabase db push --yes
```

Expected: remote applies `20260606000000_add_archive_state.sql`.

- [ ] **Step 4: Install beta app**

Run:

```bash
MUESLI_SWIFTPM_SCRATCH_PATH="$HOME/Library/Caches/muesli-spm/dev" ./scripts/beta-test.sh
```

Expected: `/Applications/muesli-beta.app` is refreshed.

- [ ] **Step 5: Push beta branch**

Run:

```bash
git push origin beta
```

Expected: `origin/beta` includes all archive commits.

---

## Completion Note: 2026-06-06

Archive was implemented and pushed to `origin/beta`.

Delivered:

- Local archive schema and APIs for meetings and folders.
- Supabase archive schema through `20260606000000_add_archive_state.sql`.
- Remote migration pushed and verified with `supabase migration list`.
- Archive state included in REST bodies, remote parsing, sync payload hashes,
  local apply paths, upload, and conflict comparison.
- Archive browser mode added inside the existing Meetings sidebar section via
  `MeetingBrowserMode.archive`; no separate `DashboardTab.archive` was added.
- Archive/restore actions added for meetings and folders.
- Beta app installed through `scripts/beta-test.sh`.
- Branch `beta` pushed through commit
  `7b8e697 feat: sync and browse archived meetings`.

Verified:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter "DictationStore|LocalSyncRepository|SupabaseRESTClient"
```

Result: 89 tests passed.

Deferred to a later session:

- Visible terminology pass from Reuniones/Meetings to Notas/Notes.
- Final confirmation/wording for folder archive, since it archives a subtree.
- Any dedicated search path for archived content.
- Any deeper technical rename from Meeting to Note remains out of scope until
  product language is stable.
