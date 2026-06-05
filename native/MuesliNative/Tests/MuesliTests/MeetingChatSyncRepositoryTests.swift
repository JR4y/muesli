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
}
