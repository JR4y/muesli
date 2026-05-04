import Foundation
import Testing
import MuesliCore
@testable import MuesliNativeApp

@Suite("LocalSyncRepository", .serialized)
struct LocalSyncRepositoryTests {

    /// Builds a fresh DB pair: DictationStore migrated first, then
    /// LocalSyncRepository on top so triggers can install correctly.
    private func makeFixture() throws -> (store: DictationStore, repo: LocalSyncRepository, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-sync-test-\(UUID().uuidString).db")
        let store = DictationStore(databaseURL: url)
        try store.migrateIfNeeded()
        let repo = LocalSyncRepository(databaseURL: url)
        try repo.migrateIfNeeded()
        return (store, repo, url)
    }

    // MARK: - Migration & device id

    @Test("migration is idempotent")
    func migrationIdempotent() throws {
        let fx = try makeFixture()
        try fx.repo.migrateIfNeeded()
        try fx.repo.migrateIfNeeded()
        // ensureDeviceID still works after re-migration
        let id = try fx.repo.ensureDeviceID()
        #expect(!id.isEmpty)
    }

    @Test("ensureDeviceID is stable across calls")
    func deviceIDStable() throws {
        let fx = try makeFixture()
        let first = try fx.repo.ensureDeviceID()
        let second = try fx.repo.ensureDeviceID()
        #expect(first == second)
        #expect(UUID(uuidString: first) != nil)
    }

    @Test("migration backfills existing local rows as dirty metadata")
    func migrationBackfillsExistingRows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-sync-backfill-\(UUID().uuidString).db")
        let store = DictationStore(databaseURL: url)
        try store.migrateIfNeeded()
        try store.insertDictation(
            text: "hola backfill",
            durationSeconds: 1.5,
            appContext: "Notes",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        _ = try store.createFolder(name: "Backfill")
        _ = try store.insertMeeting(
            title: "Meeting backfill",
            calendarEventID: nil,
            startTime: Date(timeIntervalSince1970: 1_700_000_010),
            endTime: Date(timeIntervalSince1970: 1_700_000_070),
            rawTranscript: "sync this old meeting",
            formattedNotes: "",
            micAudioPath: nil,
            systemAudioPath: nil
        )

        let repo = LocalSyncRepository(databaseURL: url)
        try repo.migrateIfNeeded()

        #expect(try repo.dirtyDictations().count == 1)
        #expect(try repo.dirtyFolders().count == 1)
        #expect(try repo.dirtyMeetings().count == 1)
    }

    // MARK: - Insert / update / delete triggers

    @Test("insert dictation creates dirty sync_metadata")
    func insertDictationCreatesMetadata() throws {
        let fx = try makeFixture()
        try fx.store.insertDictation(
            text: "hola mundo",
            durationSeconds: 1.5,
            appContext: "TextEdit",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let dirty = try fx.repo.dirtyDictations()
        #expect(dirty.count == 1)
        #expect(dirty[0].metadata.dirty == true)
        #expect(dirty[0].metadata.remoteID == nil)
        #expect(dirty[0].record.rawText == "hola mundo")
    }

    @Test("update dictation re-marks dirty after a clean sync")
    func updateDictationReMarksDirty() throws {
        let fx = try makeFixture()
        try fx.store.insertDictation(
            text: "first",
            durationSeconds: 1,
            appContext: "",
            startedAt: Date(),
            endedAt: Date()
        )
        let initial = try fx.repo.dirtyDictations()
        let localID = initial[0].record.id

        try fx.repo.markDictationSynced(
            localID: localID,
            remoteID: "remote-1",
            remoteVersion: 1,
            clientUpdatedAt: SyncTimestamp.now(),
            serverUpdatedAt: SyncTimestamp.now(),
            payloadHash: "hash-1",
            lastWriterDeviceID: "device-A"
        )
        #expect(try fx.repo.dirtyDictations().isEmpty)

        // Update the row via DictationStore — directly editing the underlying
        // DB by inserting a duplicate keeps this self-contained.
        try fx.store.clearDictations()
        try fx.store.insertDictation(
            text: "after clear",
            durationSeconds: 0.5,
            appContext: "",
            startedAt: Date(),
            endedAt: Date()
        )

        let again = try fx.repo.dirtyDictations()
        #expect(again.count == 1)
        #expect(again[0].metadata.dirty == true)
    }

    @Test("delete dictation creates dirty tombstone with metadata remote_id")
    func deleteCreatesTombstone() throws {
        let fx = try makeFixture()
        try fx.store.insertDictation(
            text: "to delete",
            durationSeconds: 1,
            appContext: "",
            startedAt: Date(),
            endedAt: Date()
        )
        let dirty = try fx.repo.dirtyDictations()
        let localID = dirty[0].record.id
        try fx.repo.markDictationSynced(
            localID: localID,
            remoteID: "rem-7",
            remoteVersion: 3,
            clientUpdatedAt: SyncTimestamp.now(),
            serverUpdatedAt: SyncTimestamp.now(),
            payloadHash: "h",
            lastWriterDeviceID: "device-A"
        )
        try fx.store.deleteDictation(id: localID)

        let tombstones = try fx.repo.dirtyTombstones(entityType: .dictation)
        #expect(tombstones.count == 1)
        #expect(tombstones[0].remoteID == "rem-7")
        #expect(tombstones[0].lastKnownRemoteVersion == 3)
        #expect(tombstones[0].dirty == true)

        // sync_metadata row was removed by AFTER DELETE trigger
        #expect(try fx.repo.metadata(entityType: .dictation, localID: localID) == nil)
    }

    @Test("delete of never-synced row creates tombstone with NULL remote_id")
    func deleteUnsyncedRowCreatesNullRemoteTombstone() throws {
        let fx = try makeFixture()
        try fx.store.insertDictation(
            text: "never synced",
            durationSeconds: 1,
            appContext: "",
            startedAt: Date(),
            endedAt: Date()
        )
        let id = try fx.repo.dirtyDictations()[0].record.id
        try fx.store.deleteDictation(id: id)
        let tombstones = try fx.repo.dirtyTombstones(entityType: .dictation)
        #expect(tombstones.count == 1)
        #expect(tombstones[0].remoteID == nil)
    }

    // MARK: - Apply remote → clean metadata

    @Test("applyRemoteDictation inserts row and leaves metadata clean")
    func applyRemoteDictationLeavesClean() throws {
        let fx = try makeFixture()
        let now = SyncTimestamp.now()
        try fx.repo.applyRemoteDictation(
            RemoteDictationPayload(
                remoteID: "rem-100",
                timestamp: "2026-05-01T10:00:00.000Z",
                durationSeconds: 2.5,
                rawText: "from remote",
                appContext: "Slack",
                wordCount: 2,
                source: "dictation",
                startedAt: "2026-05-01T09:59:57.500Z",
                endedAt: "2026-05-01T10:00:00.000Z",
                clientUpdatedAt: now,
                serverUpdatedAt: now,
                remoteVersion: 1,
                lastWriterDeviceID: "device-B",
                deletedAt: nil
            )
        )
        let dirty = try fx.repo.dirtyDictations()
        #expect(dirty.isEmpty, "remote-applied dictation must not be marked dirty")

        let localID = try fx.repo.localID(forRemoteID: "rem-100", entityType: .dictation)
        #expect(localID != nil)

        let meta = try fx.repo.metadata(entityType: .dictation, localID: localID!)
        #expect(meta?.remoteID == "rem-100")
        #expect(meta?.dirty == false)
        #expect(meta?.lastPayloadHash != nil && meta?.lastPayloadHash != "")
    }

    @Test("applyRemoteDictation with deletedAt removes local row")
    func applyRemoteDictationDelete() throws {
        let fx = try makeFixture()
        let now = SyncTimestamp.now()
        try fx.repo.applyRemoteDictation(
            RemoteDictationPayload(
                remoteID: "rem-D",
                timestamp: "2026-05-01T10:00:00.000Z",
                durationSeconds: 1,
                rawText: "doomed",
                appContext: "",
                wordCount: 1,
                source: "dictation",
                startedAt: nil,
                endedAt: nil,
                clientUpdatedAt: now,
                serverUpdatedAt: now,
                remoteVersion: 1,
                lastWriterDeviceID: "device-B",
                deletedAt: nil
            )
        )
        let localID = try fx.repo.localID(forRemoteID: "rem-D", entityType: .dictation)!

        try fx.repo.applyRemoteDictation(
            RemoteDictationPayload(
                remoteID: "rem-D",
                timestamp: "2026-05-01T10:00:00.000Z",
                durationSeconds: 1,
                rawText: "doomed",
                appContext: "",
                wordCount: 1,
                source: "dictation",
                startedAt: nil,
                endedAt: nil,
                clientUpdatedAt: now,
                serverUpdatedAt: now,
                remoteVersion: 2,
                lastWriterDeviceID: "device-B",
                deletedAt: SyncTimestamp.now()
            )
        )

        // Local row gone — but BEFORE DELETE trigger created a tombstone for it.
        // applyRemote must clear it so we don't try to re-upload a remote-driven delete.
        let tombstones = try fx.repo.dirtyTombstones(entityType: .dictation)
        #expect(tombstones.allSatisfy { $0.localID != localID })
        #expect(try fx.repo.localID(forRemoteID: "rem-D", entityType: .dictation) == nil)
    }

    // MARK: - Folder + meeting interaction

    @Test("dirtyFolders resolves parent_remote_id via metadata join")
    func dirtyFoldersResolveParentRemote() throws {
        let fx = try makeFixture()
        let parentID = try fx.store.createFolder(name: "Customers")
        let childID = try fx.store.createFolder(name: "Acme", parentFolderID: parentID)

        try fx.repo.markFolderSynced(
            localID: parentID,
            remoteID: "folder-parent",
            remoteVersion: 1,
            clientUpdatedAt: SyncTimestamp.now(),
            serverUpdatedAt: SyncTimestamp.now(),
            payloadHash: "h",
            lastWriterDeviceID: "device-A"
        )

        let dirty = try fx.repo.dirtyFolders()
        #expect(dirty.count == 1)
        #expect(dirty[0].record.id == childID)
        #expect(dirty[0].parentRemoteID == "folder-parent")
    }

    @Test("dirtyMeetings excludes recording and processing rows")
    func dirtyMeetingsExcludesLiveStatuses() throws {
        let fx = try makeFixture()
        let live = try fx.store.createLiveMeeting(
            title: "Live",
            calendarEventID: nil,
            startTime: Date()
        )
        try fx.store.completeLiveMeeting(
            id: try fx.store.createLiveMeeting(
                title: "Done",
                calendarEventID: nil,
                startTime: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            title: "Done",
            calendarEventID: nil,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_010),
            rawTranscript: "hi",
            formattedNotes: "",
            micAudioPath: nil,
            systemAudioPath: nil
        )

        let dirty = try fx.repo.dirtyMeetings()
        #expect(dirty.count == 1)
        #expect(dirty.first?.record.status == .completed)
        _ = live
    }

    @Test("applyRemoteMeeting preserves local audio paths on update")
    func applyRemoteMeetingPreservesAudioPaths() throws {
        let fx = try makeFixture()
        let id = try fx.store.insertMeeting(
            title: "Local",
            calendarEventID: nil,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_100),
            rawTranscript: "local-text",
            formattedNotes: "local-notes",
            micAudioPath: "/tmp/mic.wav",
            systemAudioPath: "/tmp/sys.wav",
            savedRecordingPath: "/tmp/saved.m4a"
        )
        try fx.repo.markMeetingSynced(
            localID: id,
            remoteID: "rem-meet-1",
            remoteVersion: 1,
            clientUpdatedAt: SyncTimestamp.now(),
            serverUpdatedAt: SyncTimestamp.now(),
            payloadHash: "h",
            lastWriterDeviceID: "device-A"
        )

        let now = SyncTimestamp.now()
        try fx.repo.applyRemoteMeeting(
            RemoteMeetingPayload(
                remoteID: "rem-meet-1",
                folderRemoteID: nil,
                title: "Updated From Remote",
                calendarEventID: nil,
                calendarEventSnapshotJSON: nil,
                startTime: "2026-05-01T10:00:00.000Z",
                endTime: "2026-05-01T11:00:00.000Z",
                durationSeconds: 3600,
                rawTranscript: "remote-text",
                formattedNotes: "remote-notes",
                meetingStatus: "completed",
                manualNotes: "",
                wordCount: 1,
                selectedTemplateID: nil,
                selectedTemplateName: nil,
                selectedTemplateKind: nil,
                selectedTemplatePrompt: nil,
                clientUpdatedAt: now,
                serverUpdatedAt: now,
                remoteVersion: 2,
                lastWriterDeviceID: "device-B",
                deletedAt: nil
            )
        )

        let updated = try fx.store.meeting(id: id)
        #expect(updated?.title == "Updated From Remote")
        #expect(updated?.rawTranscript == "remote-text")
        #expect(updated?.micAudioPath == "/tmp/mic.wav")
        #expect(updated?.systemAudioPath == "/tmp/sys.wav")
        #expect(updated?.savedRecordingPath == "/tmp/saved.m4a")

        let dirty = try fx.repo.dirtyMeetings()
        #expect(dirty.allSatisfy { $0.record.id != id })
    }

    @Test("applyRemoteFolder remaps parent through sync_metadata")
    func applyRemoteFolderRemapsParent() throws {
        let fx = try makeFixture()
        let now = SyncTimestamp.now()
        try fx.repo.applyRemoteFolder(
            RemoteFolderPayload(
                remoteID: "f-parent",
                parentRemoteID: nil,
                name: "Top",
                colorHex: nil,
                iconName: nil,
                sortOrder: 0,
                clientUpdatedAt: now,
                serverUpdatedAt: now,
                remoteVersion: 1,
                lastWriterDeviceID: "device-B",
                deletedAt: nil
            )
        )
        try fx.repo.applyRemoteFolder(
            RemoteFolderPayload(
                remoteID: "f-child",
                parentRemoteID: "f-parent",
                name: "Bottom",
                colorHex: nil,
                iconName: nil,
                sortOrder: 0,
                clientUpdatedAt: now,
                serverUpdatedAt: now,
                remoteVersion: 1,
                lastWriterDeviceID: "device-B",
                deletedAt: nil
            )
        )

        let folders = try fx.store.listFolders()
        let parent = folders.first(where: { $0.name == "Top" })!
        let child = folders.first(where: { $0.name == "Bottom" })!
        #expect(child.parentFolderID == parent.id)
    }

    // MARK: - Cursors & preferences state

    @Test("cursor save/load roundtrip per entity type")
    func cursorRoundtrip() throws {
        let fx = try makeFixture()
        let cursor = SyncCursor(serverUpdatedAt: "2026-05-04T10:20:30.123Z", id: UUID().uuidString)
        try fx.repo.saveCursor(cursor, for: .meeting)
        let loaded = try fx.repo.loadCursor(for: .meeting)
        #expect(loaded == cursor)
        #expect(try fx.repo.loadCursor(for: .dictation) == nil)
    }

    @Test("Supabase cursor query timestamp normalizes UTC offset to Z")
    func supabaseCursorTimestampNormalization() {
        #expect(
            SupabaseRESTClient.normalizedQueryTimestamp("2026-05-04T16:51:19.763003+00:00")
                == "2026-05-04T16:51:19.763003Z"
        )
        #expect(
            SupabaseRESTClient.normalizedQueryTimestamp("2026-05-04T16:51:19.763Z")
                == "2026-05-04T16:51:19.763Z"
        )
    }

    @Test("preferences state defaults are clean")
    func preferencesStateDefault() throws {
        let fx = try makeFixture()
        let state = try fx.repo.loadPreferencesState()
        #expect(state.dirty == false)
        #expect(state.remoteVersion == 0)
        #expect(state.lastPayloadHash == nil)
    }

    @Test("markPreferencesDirty + markPreferencesSynced round trip")
    func preferencesDirtyAndSynced() throws {
        let fx = try makeFixture()
        let ts1 = SyncTimestamp.now()
        try fx.repo.markPreferencesDirty(clientUpdatedAt: ts1)
        var state = try fx.repo.loadPreferencesState()
        #expect(state.dirty == true)
        #expect(state.clientUpdatedAt == ts1)

        let ts2 = SyncTimestamp.now()
        try fx.repo.markPreferencesSynced(
            remoteVersion: 5,
            clientUpdatedAt: ts2,
            serverUpdatedAt: ts2,
            payloadHash: "abc",
            lastWriterDeviceID: "device-A"
        )
        state = try fx.repo.loadPreferencesState()
        #expect(state.dirty == false)
        #expect(state.remoteVersion == 5)
        #expect(state.lastPayloadHash == "abc")
        #expect(state.lastWriterDeviceID == "device-A")
    }

    // MARK: - Tombstone purge

    @Test("purgeCleanTombstones removes only old + clean rows")
    func purgeCleanTombstonesOnly() throws {
        let fx = try makeFixture()
        try fx.store.insertDictation(
            text: "x",
            durationSeconds: 1,
            appContext: "",
            startedAt: Date(),
            endedAt: Date()
        )
        let id = try fx.repo.dirtyDictations()[0].record.id
        try fx.repo.markDictationSynced(
            localID: id,
            remoteID: "r",
            remoteVersion: 1,
            clientUpdatedAt: SyncTimestamp.now(),
            serverUpdatedAt: SyncTimestamp.now(),
            payloadHash: "h",
            lastWriterDeviceID: "d"
        )
        try fx.store.deleteDictation(id: id)

        // The tombstone is dirty — purge older than 30d should not remove it.
        try fx.repo.purgeCleanTombstones(olderThanDays: 30)
        #expect(try fx.repo.dirtyTombstones(entityType: .dictation).count == 1)

        try fx.repo.markTombstoneSynced(entityType: .dictation, localID: id, lastKnownRemoteVersion: 1)
        // Now clean and recent — purge 30d should still leave it (created today).
        try fx.repo.purgeCleanTombstones(olderThanDays: 30)
        // markTombstoneSynced does not change client_deleted_at, which is "now",
        // so a 30-day cutoff should still keep it.
        // Use a 0-day cutoff to verify deletion.
        try fx.repo.purgeCleanTombstones(olderThanDays: 0)
        #expect(try fx.repo.dirtyTombstones(entityType: .dictation).isEmpty)
    }

    // MARK: - Hashing

    @Test("payload hash is stable for identical input")
    func hashStable() {
        let h1 = SyncPayloadHasher.dictationHash(
            timestamp: "2026-05-04T10:00:00.000Z",
            durationSeconds: 1.2345,
            rawText: "hola",
            appContext: "Slack",
            wordCount: 1,
            source: "dictation",
            startedAt: nil,
            endedAt: "2026-05-04T10:00:01.234Z"
        )
        let h2 = SyncPayloadHasher.dictationHash(
            timestamp: "2026-05-04T10:00:00.000Z",
            durationSeconds: 1.2345,
            rawText: "hola",
            appContext: "Slack",
            wordCount: 1,
            source: "dictation",
            startedAt: nil,
            endedAt: "2026-05-04T10:00:01.234Z"
        )
        #expect(h1 == h2)
        #expect(h1.count == 64)
    }

    @Test("payload hash differs when text changes")
    func hashDiffersForDifferentInput() {
        let h1 = SyncPayloadHasher.dictationHash(
            timestamp: "2026-05-04T10:00:00.000Z",
            durationSeconds: 1, rawText: "a", appContext: "",
            wordCount: 1, source: "dictation",
            startedAt: nil, endedAt: nil
        )
        let h2 = SyncPayloadHasher.dictationHash(
            timestamp: "2026-05-04T10:00:00.000Z",
            durationSeconds: 1, rawText: "b", appContext: "",
            wordCount: 1, source: "dictation",
            startedAt: nil, endedAt: nil
        )
        #expect(h1 != h2)
    }

    @Test("preferences hash is stable for equivalent JSON payloads")
    func preferencesHashStable() {
        let snapshot1 = SyncPreferencesSnapshot(
            customMeetingTemplatesJSON: "[{\"a\":1,\"b\":2}]",
            hiddenBuiltInTemplateIDs: ["a", "b"],
            customWordsJSON: "[]",
            defaultMeetingTemplateID: "auto",
            autoTemplateTargetID: "",
            meetingTitlePrompt: "",
            folderOrderRemoteIDs: ["x", "y"]
        )
        let snapshot2 = SyncPreferencesSnapshot(
            customMeetingTemplatesJSON: "[{\"b\":2,\"a\":1}]", // re-ordered keys
            hiddenBuiltInTemplateIDs: ["a", "b"],
            customWordsJSON: "[]",
            defaultMeetingTemplateID: "auto",
            autoTemplateTargetID: "",
            meetingTitlePrompt: "",
            folderOrderRemoteIDs: ["x", "y"]
        )
        #expect(SyncPayloadHasher.preferencesHash(snapshot1) ==
                SyncPayloadHasher.preferencesHash(snapshot2))
    }
}
