import Foundation
import MuesliCore
import Testing
@testable import MuesliNativeApp
@testable import MuesliMeetingChat

@Suite("Meeting chat context")
struct MeetingChatContextTests {
    @Test("meeting scope includes notes, manual notes, transcript, and source metadata")
    func meetingScopeBuildsContext() {
        let meeting = meetingRecord(
            id: 101,
            title: "Customer Review",
            notes: "## Summary\n- Renewal risk discussed.",
            transcript: "Customer asked about pricing details.",
            manualNotes: "- Follow up with Maya"
        )

        let bundle = MeetingChatContextBuilder.build(
            scope: .meeting(101),
            question: "What pricing details were mentioned?",
            meetings: [meeting],
            folders: []
        )

        #expect(!bundle.isEmpty)
        #expect(bundle.prompt.contains("Customer Review"))
        #expect(bundle.prompt.contains("Renewal risk discussed."))
        #expect(bundle.prompt.contains("Follow up with Maya"))
        #expect(bundle.prompt.contains("Customer asked about pricing details."))
        #expect(bundle.sources == [
            MeetingChatSource(meetingID: 101, title: "Customer Review", startTime: meeting.startTime)
        ])
    }

    @Test("folder scope includes descendant folder meetings and excludes merged meetings")
    func folderScopeUsesFolderTreeAndSkipsMergedMeetings() {
        let root = MeetingFolder(id: 10, name: "Sales", createdAt: "2026-06-01T00:00:00Z")
        let child = MeetingFolder(id: 11, name: "Enterprise", parentFolderID: 10, createdAt: "2026-06-01T00:00:00Z")
        let included = meetingRecord(id: 201, title: "Account Plan", folderID: 11, notes: "## Summary\n- Expansion path.")
        let direct = meetingRecord(id: 202, title: "Pipeline", folderID: 10, notes: "## Summary\n- Q3 forecast.")
        let other = meetingRecord(id: 203, title: "Engineering Sync", folderID: 99, notes: "## Summary\n- Infra work.")
        let merged = meetingRecord(
            id: 204,
            title: "Merged Source",
            folderID: 10,
            notes: "## Summary\n- Duplicate notes.",
            mergedIntoMeetingID: 202
        )

        let bundle = MeetingChatContextBuilder.build(
            scope: .folder(10),
            question: "What happened in this workspace?",
            meetings: [included, direct, other, merged],
            folders: [root, child]
        )

        #expect(bundle.prompt.contains("Folder: Sales"))
        #expect(bundle.prompt.contains("Account Plan"))
        #expect(bundle.prompt.contains("Pipeline"))
        #expect(!bundle.prompt.contains("Engineering Sync"))
        #expect(!bundle.prompt.contains("Merged Source"))
        #expect(bundle.sources.map(\.meetingID) == [202, 201])
    }

    @Test("empty scope returns no context")
    func emptyScopeReturnsNoContext() {
        let bundle = MeetingChatContextBuilder.build(
            scope: .meeting(999),
            question: "Anything here?",
            meetings: [],
            folders: []
        )

        #expect(bundle.isEmpty)
        #expect(bundle.prompt.isEmpty)
        #expect(bundle.sources.isEmpty)
    }

    @Test("memory policy uses summary plus only the most recent messages")
    func memoryPolicyLimitsPersistedMessages() {
        let messages = (1...12).map { index in
            MeetingChatMessage(
                role: index.isMultiple(of: 2) ? .assistant : .user,
                text: "message \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let memory = MeetingChatMemoryPolicy.memory(
            messages: messages,
            summary: "Earlier discussion: renewal risk and timeline drift.",
            recentLimit: 6
        )

        #expect(memory.summary == "Earlier discussion: renewal risk and timeline drift.")
        #expect(memory.recentMessages.map(\.text) == ["message 7", "message 8", "message 9", "message 10", "message 11", "message 12"])
        #expect(!memory.recentMessages.contains { $0.text == "message 1" })
    }

    @Test("memory policy omits summary when the full history fits in the recent window")
    func memoryPolicyOmitsSummaryForShortThreads() {
        let messages = [
            MeetingChatMessage(role: .user, text: "hello"),
            MeetingChatMessage(role: .assistant, text: "hi")
        ]

        let memory = MeetingChatMemoryPolicy.memory(
            messages: messages,
            summary: "Should not be sent yet.",
            recentLimit: 6
        )

        #expect(memory.summary == nil)
        #expect(memory.recentMessages.map(\.text) == ["hello", "hi"])
    }

    @Test("memory policy derives bounded local summary when no stored summary exists")
    func memoryPolicyDerivesBoundedSummary() {
        let messages = (1...9).map { index in
            MeetingChatMessage(
                role: .user,
                text: "older topic \(index) about project bias and risk",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let memory = MeetingChatMemoryPolicy.memory(
            messages: messages,
            summary: "",
            recentLimit: 3,
            maxDerivedSummaryCharacters: 90
        )

        let summary = memory.summary ?? ""
        #expect(summary.contains("user: older topic 1"))
        #expect(summary.contains("[truncated]"))
        #expect(summary.count <= 102)
        #expect(memory.recentMessages.map(\.text) == [
            "older topic 7 about project bias and risk",
            "older topic 8 about project bias and risk",
            "older topic 9 about project bias and risk"
        ])
    }

    @Test("explicit transcript lookup includes transcript for a meeting")
    func explicitTranscriptLookupIncludesTranscript() {
        let meeting = meetingRecord(
            id: 301,
            title: "Design Review",
            notes: "## Summary\n- There was a disagreement.",
            transcript: "Ana said the deadline was too optimistic."
        )

        let bundle = MeetingChatContextBuilder.build(
            scope: .meeting(301),
            question: "Quien dijo exactamente que el deadline era optimista?",
            meetings: [meeting],
            folders: []
        )

        #expect(bundle.prompt.contains("Transcript excerpt:"))
        #expect(bundle.prompt.contains("Ana said the deadline was too optimistic."))
    }

    @Test("meeting option can force transcript without detail wording")
    func meetingOptionForcesTranscript() {
        let meeting = meetingRecord(
            id: 401,
            title: "Launch Review",
            notes: "## Summary\n- Launch is on track.",
            transcript: "Detailed launch transcript evidence."
        )

        let bundle = MeetingChatContextBuilder.build(
            scope: .meeting(401),
            question: "What changed?",
            meetings: [meeting],
            folders: [],
            options: MeetingChatContextOptions(includeTranscriptMeetingIDs: [401])
        )

        #expect(bundle.prompt.contains("Transcript excerpt:"))
        #expect(bundle.prompt.contains("Detailed launch transcript evidence."))
    }

    @Test("folder option includes transcript only for explicitly selected meetings")
    func folderOptionIncludesSelectedTranscriptOnly() {
        let folder = MeetingFolder(id: 50, name: "Lyntia", createdAt: "2026-06-01T00:00:00Z")
        let selected = meetingRecord(
            id: 501,
            title: "Architecture Review",
            folderID: 50,
            notes: "## Summary\n- API risk.",
            transcript: "Selected transcript evidence."
        )
        let unselected = meetingRecord(
            id: 502,
            title: "Sales Sync",
            folderID: 50,
            notes: "## Summary\n- Renewal path.",
            transcript: "Unselected transcript should stay out."
        )

        let bundle = MeetingChatContextBuilder.build(
            scope: .folder(50),
            question: "Compare @Architecture Review with the rest.",
            meetings: [selected, unselected],
            folders: [folder],
            options: MeetingChatContextOptions(
                referencedMeetingIDs: [501],
                includeTranscriptMeetingIDs: [501]
            )
        )

        #expect(bundle.prompt.contains("Selected transcript evidence."))
        #expect(!bundle.prompt.contains("Unselected transcript should stay out."))
    }

    @Test("mention resolver matches meeting titles from at tokens")
    func mentionResolverMatchesMeetingTitles() {
        let meetings = [
            meetingRecord(id: 601, title: "Architecture Review"),
            meetingRecord(id: 602, title: "Sales Sync")
        ]

        let matches = MeetingChatMentionResolver.matches(
            in: "Compare @Architecture Review with last week",
            meetings: meetings
        )

        #expect(matches.map(\.meetingID) == [601])
        #expect(matches.first?.title == "Architecture Review")
    }

    private func meetingRecord(
        id: Int64,
        title: String,
        folderID: Int64? = nil,
        notes: String = "",
        transcript: String = "",
        manualNotes: String = "",
        mergedIntoMeetingID: Int64? = nil
    ) -> MeetingRecord {
        MeetingRecord(
            id: id,
            title: title,
            startTime: "2026-06-01T12:00:00Z",
            durationSeconds: 1800,
            rawTranscript: transcript,
            formattedNotes: notes,
            wordCount: 120,
            folderID: folderID,
            mergedIntoMeetingID: mergedIntoMeetingID,
            manualNotes: manualNotes
        )
    }
}

@Suite("Meeting chat provider routing")
struct MeetingChatProviderRoutingTests {
    @Test("authenticated ChatGPT provider is attempted before fallback providers")
    func authenticatedChatGPTProviderWins() async throws {
        let chatGPT = RecordingProvider(name: "chatgpt", availability: .available, response: "ChatGPT answer")
        let openAI = RecordingProvider(name: "openai", availability: .available, response: "OpenAI answer")
        let router = MeetingChatProviderRouter(providers: [chatGPT, openAI])

        let response = try await router.send(
            MeetingChatRequest(
                question: "What changed?",
                context: MeetingChatContextBundle(
                    scope: .meeting(1),
                    prompt: "Context",
                    sources: [MeetingChatSource(meetingID: 1, title: "One", startTime: "2026-06-01T12:00:00Z")]
                )
            )
        )

        #expect(response.text == "ChatGPT answer")
        #expect(chatGPT.requestCount == 1)
        #expect(openAI.requestCount == 0)
    }

    @Test("router falls back when the preferred provider is unavailable")
    func unavailableProviderFallsBack() async throws {
        let chatGPT = RecordingProvider(name: "chatgpt", availability: .unavailable("Not signed in"), response: "")
        let openAI = RecordingProvider(name: "openai", availability: .available, response: "Fallback answer")
        let router = MeetingChatProviderRouter(providers: [chatGPT, openAI])

        let response = try await router.send(
            MeetingChatRequest(
                question: "What changed?",
                context: MeetingChatContextBundle(scope: .meeting(1), prompt: "Context", sources: [])
            )
        )

        #expect(response.text == "Fallback answer")
        #expect(chatGPT.requestCount == 0)
        #expect(openAI.requestCount == 1)
    }

    @Test("router returns chat error when every provider fails")
    func allProvidersFail() async {
        let chatGPT = RecordingProvider(name: "chatgpt", availability: .unavailable("Not signed in"), response: "")
        let broken = RecordingProvider(name: "openai", availability: .available, response: "", error: MeetingChatError.providerFailed("No API key"))
        let router = MeetingChatProviderRouter(providers: [chatGPT, broken])

        do {
            _ = try await router.send(
                MeetingChatRequest(
                    question: "What changed?",
                    context: MeetingChatContextBundle(scope: .meeting(1), prompt: "Context", sources: [])
                )
            )
            Issue.record("Expected provider failure")
        } catch let error as MeetingChatError {
            #expect(error.localizedDescription.contains("No API key"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@Suite("Meeting chat panel presentation")
struct MeetingChatPanelPresentationTests {
    @Test("conversation visibility follows expanded state even when history exists")
    func conversationVisibilityFollowsExpandedState() {
        #expect(
            !MeetingChatPanelPresentationPolicy.showsConversation(
                isExpanded: false,
                hasMessages: true
            )
        )
        #expect(
            MeetingChatPanelPresentationPolicy.showsConversation(
                isExpanded: true,
                hasMessages: false
            )
        )
    }
}

@Suite("Meeting chat storage", .serialized)
struct MeetingChatStorageTests {
    @Test("meeting thread persists and restores messages with sources")
    func meetingThreadPersistsMessages() throws {
        let store = try makeStore()
        let loaded = try store.loadThread(scope: .meeting(42), title: "Customer Review")
        let message = MeetingChatMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
            role: .assistant,
            text: "Renewal risk was the main concern.",
            sources: [MeetingChatSource(meetingID: 42, title: "Customer Review", startTime: "2026-06-01T12:00:00Z")],
            createdAt: Date(timeIntervalSince1970: 42)
        )

        try store.appendMessage(message, to: loaded.thread)

        let restored = try store.loadThread(scope: .meeting(42), title: "Customer Review")
        #expect(restored.thread.id == loaded.thread.id)
        #expect(restored.messages == [message])
    }

    @Test("meeting and folder scopes stay isolated")
    func scopesStayIsolated() throws {
        let store = try makeStore()
        let meeting = try store.loadThread(scope: .meeting(7), title: "Project Sync")
        let folder = try store.loadThread(scope: .folder(7), title: "Project")

        try store.appendMessage(
            MeetingChatMessage(role: .user, text: "meeting question", createdAt: Date(timeIntervalSince1970: 1)),
            to: meeting.thread
        )
        try store.appendMessage(
            MeetingChatMessage(role: .user, text: "folder question", createdAt: Date(timeIntervalSince1970: 2)),
            to: folder.thread
        )

        #expect(try store.loadThread(scope: .meeting(7), title: "Project Sync").messages.map(\.text) == ["meeting question"])
        #expect(try store.loadThread(scope: .folder(7), title: "Project").messages.map(\.text) == ["folder question"])
    }

    @Test("clear removes only the current scope thread")
    func clearRemovesOnlyCurrentScope() throws {
        let store = try makeStore()
        let meeting = try store.loadThread(scope: .meeting(8), title: "One")
        let folder = try store.loadThread(scope: .folder(8), title: "Folder")
        try store.appendMessage(MeetingChatMessage(role: .user, text: "keep"), to: folder.thread)
        try store.appendMessage(MeetingChatMessage(role: .user, text: "delete"), to: meeting.thread)

        try store.clearThread(scope: .meeting(8))

        #expect(try store.loadThread(scope: .meeting(8), title: "One").messages.isEmpty)
        #expect(try store.loadThread(scope: .folder(8), title: "Folder").messages.map(\.text) == ["keep"])
    }

    private func makeStore() throws -> SQLiteMeetingChatStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-chat-test-\(UUID().uuidString).db")
        let store = SQLiteMeetingChatStore(databaseURL: url)
        try store.migrateIfNeeded()
        return store
    }
}

@Suite("Meeting chat mount policy")
struct MeetingChatMountPolicyTests {
    @Test("folder chat appears only for selected folder browser views")
    func folderChatVisibility() {
        #expect(
            MeetingChatMountPolicy.showsFolderChat(
                selectedFolderID: 10,
                isSearchActive: false,
                navigationState: .browser
            )
        )
        #expect(
            !MeetingChatMountPolicy.showsFolderChat(
                selectedFolderID: nil,
                isSearchActive: false,
                navigationState: .browser
            )
        )
        #expect(
            !MeetingChatMountPolicy.showsFolderChat(
                selectedFolderID: 10,
                isSearchActive: true,
                navigationState: .browser
            )
        )
        #expect(
            !MeetingChatMountPolicy.showsFolderChat(
                selectedFolderID: 10,
                isSearchActive: false,
                navigationState: .document(101)
            )
        )
    }

    @Test("meeting chat appears for completed meeting detail views")
    func meetingChatVisibility() {
        #expect(MeetingChatMountPolicy.showsMeetingChat(for: meetingRecord(id: 1, title: "Done")))
        #expect(!MeetingChatMountPolicy.showsMeetingChat(for: nil))
        #expect(
            !MeetingChatMountPolicy.showsMeetingChat(
                for: meetingRecord(id: 2, title: "Recording", status: .recording)
            )
        )
    }

    private func meetingRecord(
        id: Int64,
        title: String,
        status: MeetingStatus = .completed
    ) -> MeetingRecord {
        MeetingRecord(
            id: id,
            title: title,
            startTime: "2026-06-01T12:00:00Z",
            durationSeconds: 1800,
            rawTranscript: "",
            formattedNotes: "## Summary",
            wordCount: 1,
            folderID: nil,
            status: status
        )
    }
}

private final class RecordingProvider: MeetingChatProvider, @unchecked Sendable {
    let name: String
    let availability: MeetingChatProviderAvailability
    let response: String
    let error: Error?
    var requestCount = 0

    init(
        name: String,
        availability: MeetingChatProviderAvailability,
        response: String,
        error: Error? = nil
    ) {
        self.name = name
        self.availability = availability
        self.response = response
        self.error = error
    }

    func send(_ request: MeetingChatRequest) async throws -> MeetingChatProviderResponse {
        requestCount += 1
        if let error {
            throw error
        }
        return MeetingChatProviderResponse(text: response)
    }
}
