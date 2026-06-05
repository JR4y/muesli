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
    func messageHashStableForSources() {
        let sources = [
            MeetingChatSource(meetingID: 10, title: "Sync", startTime: "2026-06-05T10:00:00Z")
        ]
        let first = MeetingChatSyncHasher.messageHash(
            role: .assistant,
            content: "Answer",
            sources: sources,
            createdAt: "2026-06-05T10:01:00.000Z"
        )
        let second = MeetingChatSyncHasher.messageHash(
            role: .assistant,
            content: "Answer",
            sources: sources,
            createdAt: "2026-06-05T10:01:00.000Z"
        )

        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test("migration backfills existing chat threads and messages as dirty")
    func migrationBackfillsExistingChat() throws {
        let fixture = try makeUnwiredFixture()
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
        #expect(snapshot.thread.title == "Remote Meeting")
        #expect(snapshot.thread.summary == "Older turns")
        #expect(snapshot.messages.map(\.text) == ["Remote answer"])
    }

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

    private func makeFixture() throws -> (chatStore: SQLiteMeetingChatStore, syncRepo: MeetingChatSyncRepository, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-chat-sync-\(UUID().uuidString).db")
        let syncRepo = MeetingChatSyncRepository(databaseURL: url)
        let chatStore = SQLiteMeetingChatStore(databaseURL: url, syncRepository: syncRepo)
        try chatStore.migrateIfNeeded()
        return (chatStore, syncRepo, url)
    }

    private func makeUnwiredFixture() throws -> (chatStore: SQLiteMeetingChatStore, syncRepo: MeetingChatSyncRepository, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-chat-sync-\(UUID().uuidString).db")
        let chatStore = SQLiteMeetingChatStore(databaseURL: url)
        try chatStore.migrateIfNeeded()
        let syncRepo = MeetingChatSyncRepository(databaseURL: url)
        return (chatStore, syncRepo, url)
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
}
