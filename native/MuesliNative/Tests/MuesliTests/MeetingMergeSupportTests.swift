import Testing
import Foundation
import MuesliCore
@testable import MuesliNativeApp

@Suite("Meeting merge support")
struct MeetingMergeSupportTests {
    @Test("filters merge candidates by normalized calendar event and safe status")
    func filtersCandidates() {
        let target = makeMeeting(id: 1, title: "Target", calendarEventID: "evt_123|1714900000", status: .completed)
        let sameEvent = makeMeeting(id: 2, title: "Same", calendarEventID: "evt_123", status: .completed)
        let recording = makeMeeting(id: 3, title: "Recording", calendarEventID: "evt_123", status: .recording)
        let retainedAudio = makeMeeting(id: 4, title: "Retained", calendarEventID: "evt_123", status: .completed, savedRecordingPath: "/tmp/audio.wav")
        let otherEvent = makeMeeting(id: 5, title: "Other", calendarEventID: "evt_999", status: .completed)

        let candidates = MeetingMergeSupport.mergeCandidates(
            for: target,
            from: [target, sameEvent, recording, retainedAudio, otherEvent]
        )

        #expect(candidates.map(\.id) == [2, 4])
    }

    @Test("related meetings keep blocked same-event notes visible with reasons")
    func relatedMeetingsExposeBlockingReasons() {
        let target = makeMeeting(id: 1, title: "Target", calendarEventID: "evt_123|1714900000", status: .completed)
        let mergeable = makeMeeting(id: 2, title: "Same", calendarEventID: "evt_123", status: .completed)
        let recording = makeMeeting(id: 3, title: "Recording", calendarEventID: "evt_123", status: .recording)
        let retainedAudio = makeMeeting(id: 4, title: "Retained", calendarEventID: "evt_123", status: .completed, savedRecordingPath: "/tmp/audio.wav")

        let related = MeetingMergeSupport.relatedMeetings(
            for: target,
            from: [target, mergeable, recording, retainedAudio]
        )

        #expect(related.map(\.meeting.id) == [2, 3, 4])
        #expect(related[0].blockingReason == nil)
        #expect(related[1].blockingReason == .liveState)
        #expect(related[2].blockingReason == nil)
    }

    @Test("draft merges transcript and manual notes chronologically")
    func buildsDraftChronologically() {
        let target = makeMeeting(
            id: 1,
            title: "Target",
            startTime: "2026-05-05T10:05:00Z",
            calendarEventID: "evt_123",
            status: .completed,
            rawTranscript: "later transcript",
            manualNotes: "target notes"
        )
        let source = makeMeeting(
            id: 2,
            title: "Earlier",
            startTime: "2026-05-05T10:00:00Z",
            calendarEventID: "evt_123",
            status: .completed,
            rawTranscript: "earlier transcript",
            manualNotes: "source notes"
        )

        let draft = MeetingMergeSupport.makeDraft(target: target, sources: [source])

        #expect(draft.rawTranscript == "earlier transcript\nlater transcript")
        #expect(draft.manualNotes.contains("target notes"))
        #expect(draft.manualNotes.contains("### Earlier"))
        #expect(draft.manualNotes.contains("source notes"))
        #expect(draft.appendedSummaryNotesBody?.contains("### Earlier") == true)
        #expect(draft.shouldPromoteToCompleted)
    }

    private func makeMeeting(
        id: Int64,
        title: String,
        startTime: String = "2026-05-05T10:00:00Z",
        calendarEventID: String?,
        status: MeetingStatus,
        rawTranscript: String = "",
        formattedNotes: String = "",
        manualNotes: String = "",
        savedRecordingPath: String? = nil
    ) -> MeetingRecord {
        MeetingRecord(
            id: id,
            title: title,
            startTime: startTime,
            durationSeconds: 60,
            rawTranscript: rawTranscript,
            formattedNotes: formattedNotes,
            wordCount: 0,
            folderID: nil,
            calendarEventID: calendarEventID,
            calendarEventSnapshot: nil,
            micAudioPath: nil,
            systemAudioPath: nil,
            savedRecordingPath: savedRecordingPath,
            status: status,
            manualNotes: manualNotes,
            selectedTemplateID: "auto",
            selectedTemplateName: "Auto",
            selectedTemplateKind: .auto,
            selectedTemplatePrompt: "## Summary"
        )
    }
}
