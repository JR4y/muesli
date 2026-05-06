import Testing
import Foundation
@testable import MuesliNativeApp

@Suite("Live meeting transcript reducer")
struct LiveMeetingTranscriptReducerTests {
    @Test("builds timestamped turns from incoming segments")
    func buildsTurns() throws {
        let meetingStart = Date(timeIntervalSince1970: 100)
        let turns = LiveMeetingTranscriptReducer.merge(
            existing: [],
            source: .microphone,
            segments: [SpeechSegment(start: 5, end: 6, text: "Hello there")],
            meetingStart: meetingStart
        )

        let turn = try #require(turns.first)
        #expect(turns.count == 1)
        #expect(turn.source == .microphone)
        #expect(turn.speakerLabel == "You")
        #expect(turn.timestamp == meetingStart.addingTimeInterval(5))
        #expect(turn.text == "Hello there")
    }

    @Test("consolidates nearby turns from the same source")
    func consolidatesNearbyTurns() {
        let meetingStart = Date(timeIntervalSince1970: 0)
        let turns = LiveMeetingTranscriptReducer.merge(
            existing: [],
            source: .system,
            segments: [
                SpeechSegment(start: 1.0, end: 1.5, text: "Hello"),
                SpeechSegment(start: 1.7, end: 2.1, text: "world"),
            ],
            meetingStart: meetingStart
        )

        #expect(turns.count == 1)
        #expect(turns[0].text == "Hello world")
        #expect(turns[0].speakerLabel == "Others")
    }

    @Test("keeps different sources as separate turns")
    func keepsDifferentSourcesSeparate() {
        let meetingStart = Date(timeIntervalSince1970: 0)
        let micTurns = LiveMeetingTranscriptReducer.merge(
            existing: [],
            source: .microphone,
            segments: [SpeechSegment(start: 1.0, end: 1.5, text: "My turn")],
            meetingStart: meetingStart
        )
        let allTurns = LiveMeetingTranscriptReducer.merge(
            existing: micTurns,
            source: .system,
            segments: [SpeechSegment(start: 1.2, end: 1.8, text: "Other turn")],
            meetingStart: meetingStart
        )

        #expect(allTurns.count == 2)
        #expect(allTurns[0].speakerLabel == "You")
        #expect(allTurns[1].speakerLabel == "Others")
    }

    @Test("starts a new bubble when consolidated text gets too long")
    func splitsLongBubble() {
        let meetingStart = Date(timeIntervalSince1970: 0)
        let repeated = String(repeating: "very long sentence ", count: 12)
        let turns = LiveMeetingTranscriptReducer.merge(
            existing: [],
            source: .microphone,
            segments: [
                SpeechSegment(start: 1.0, end: 4.0, text: repeated),
                SpeechSegment(start: 4.2, end: 7.0, text: repeated),
            ],
            meetingStart: meetingStart
        )

        #expect(turns.count == 2)
    }

    @Test("starts a new bubble when consolidated duration gets too long")
    func splitsLongDurationBubble() {
        let meetingStart = Date(timeIntervalSince1970: 0)
        let turns = LiveMeetingTranscriptReducer.merge(
            existing: [],
            source: .system,
            segments: [
                SpeechSegment(start: 1.0, end: 8.0, text: "First chunk"),
                SpeechSegment(start: 8.5, end: 16.5, text: "Second chunk"),
            ],
            meetingStart: meetingStart
        )

        #expect(turns.count == 2)
    }

    @Test("live transcript pipeline projects chunks into display turns")
    func livePipelineProjectsChunks() {
        var pipeline = LiveMeetingTranscriptPipeline(meetingStart: Date(timeIntervalSince1970: 0))
        let chunk = MeetingTranscriptChunk(
            result: SpeechTranscriptionResult(
                text: "Hello there.",
                segments: [
                    SpeechSegment(start: 0.0, end: 1.2, text: "Hello there.")
                ]
            ),
            startTime: 5.0,
            endTime: 6.2
        )

        let turns = pipeline.ingest(source: .microphone, chunk: chunk)

        #expect(turns.count == 1)
        #expect(turns[0].speakerLabel == "You")
        #expect(turns[0].startTimeSeconds == 5.0)
        #expect(turns[0].timestamp == Date(timeIntervalSince1970: 5.0))
    }
}
