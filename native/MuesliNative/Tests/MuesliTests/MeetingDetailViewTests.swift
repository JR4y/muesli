import Testing
import MuesliCore
@testable import MuesliNativeApp

@Suite("Meeting detail view")
struct MeetingDetailViewTests {
    @Test("document mode picker remains available for completed meetings in both header layouts")
    func documentModePickerIsAvailableForCompletedMeetings() {
        let meeting = makeMeeting(status: .completed)

        #expect(MeetingDetailView.showsDocumentModePicker(for: meeting, in: .horizontalHeader))
        #expect(MeetingDetailView.showsDocumentModePicker(for: meeting, in: .stackedHeader))
    }

    @Test("document mode picker stays hidden for live note states in both header layouts")
    func documentModePickerStaysHiddenForLiveNoteStates() {
        let statuses: [MeetingStatus] = [.recording, .processing, .noteOnly, .failed]

        for status in statuses {
            let meeting = makeMeeting(status: status)
            #expect(!MeetingDetailView.showsDocumentModePicker(for: meeting, in: .horizontalHeader))
            #expect(!MeetingDetailView.showsDocumentModePicker(for: meeting, in: .stackedHeader))
        }
    }

    @Test("completed meetings use the dedicated document toolbar")
    func completedMeetingsUseDedicatedDocumentToolbar() {
        let completed = makeMeeting(status: .completed)
        let recording = makeMeeting(status: .recording)

        #expect(MeetingDetailView.usesCompletedDocumentToolbar(for: completed))
        #expect(!MeetingDetailView.usesCompletedDocumentToolbar(for: recording))
    }

    @Test("completed meetings with recordings show dedicated audio actions")
    func completedMeetingsWithRecordingsShowDedicatedAudioActions() {
        let completedWithRecording = makeMeeting(status: .completed, savedRecordingPath: "/tmp/meeting.m4a")
        let completedWithoutRecording = makeMeeting(status: .completed)
        let noteOnlyWithRecording = makeMeeting(status: .noteOnly, savedRecordingPath: "/tmp/meeting.m4a")

        #expect(MeetingDetailView.showsCompletedAudioActions(for: completedWithRecording))
        #expect(!MeetingDetailView.showsCompletedAudioActions(for: completedWithoutRecording))
        #expect(!MeetingDetailView.showsCompletedAudioActions(for: noteOnlyWithRecording))
    }

    @Test("completed meetings route merge and delete through overflow actions")
    func completedMeetingsRouteOverflowActions() {
        let completed = makeMeeting(status: .completed)
        let noteOnly = makeMeeting(status: .noteOnly)

        #expect(MeetingDetailView.showsCompletedOverflowActions(for: completed, canDelete: true, canMerge: false))
        #expect(MeetingDetailView.showsCompletedOverflowActions(for: completed, canDelete: false, canMerge: true))
        #expect(!MeetingDetailView.showsCompletedOverflowActions(for: completed, canDelete: false, canMerge: false))
        #expect(!MeetingDetailView.showsCompletedOverflowActions(for: noteOnly, canDelete: true, canMerge: true))
    }

    @Test("completed meetings use the summary template split control")
    func completedMeetingsUseSummaryTemplateSplitControl() {
        let completed = makeMeeting(status: .completed)
        let failed = makeMeeting(status: .failed)

        #expect(MeetingDetailView.usesSummaryTemplateSplitControl(for: completed))
        #expect(!MeetingDetailView.usesSummaryTemplateSplitControl(for: failed))
    }

    @Test("document overflow menu is hidden while editing")
    func documentOverflowMenuIsHiddenWhileEditing() {
        let completed = makeMeeting(status: .completed)
        let noteOnly = makeMeeting(status: .noteOnly)

        #expect(MeetingDetailView.showsCompletedDocumentOverflowMenu(for: completed, isEditing: false))
        #expect(!MeetingDetailView.showsCompletedDocumentOverflowMenu(for: completed, isEditing: true))
        #expect(!MeetingDetailView.showsCompletedDocumentOverflowMenu(for: noteOnly, isEditing: false))
    }

    private func makeMeeting(status: MeetingStatus, savedRecordingPath: String? = nil) -> MeetingRecord {
        MeetingRecord(
            id: 1,
            title: "Weekly sync",
            startTime: "2026-05-19T15:27:00",
            durationSeconds: 900,
            rawTranscript: "[00:00:03] You: Hola",
            formattedNotes: "## Summary\n\n- Punto clave",
            wordCount: 2578,
            folderID: nil,
            savedRecordingPath: savedRecordingPath,
            status: status
        )
    }
}
