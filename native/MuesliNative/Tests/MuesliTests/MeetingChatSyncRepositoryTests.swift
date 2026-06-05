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
}
