import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Live meeting transcript pipeline")
struct LiveMeetingTranscriptReducerTests {
    @Test("builds timestamped turns from a speech-bounded chunk")
    func buildsTurns() throws {
        let meetingStart = Date(timeIntervalSince1970: 100)
        var pipeline = LiveMeetingTranscriptPipeline(meetingStart: meetingStart)

        _ = pipeline.ingest(.speechStarted(source: .microphone, at: 5.0))
        _ = pipeline.ingest(.speechEnded(source: .microphone, at: 6.0))
        let turns = pipeline.ingest(.transcriptChunk(source: .microphone, chunk: chunk(
            text: "Hello there",
            start: 5.0,
            end: 6.0
        )))

        let turn = try #require(turns.first)
        #expect(turns.count == 1)
        #expect(turn.source == .microphone)
        #expect(turn.speakerLabel == "You")
        #expect(turn.timestamp == meetingStart.addingTimeInterval(5))
        #expect(turn.text == "Hello there")
    }

    @Test("keeps one bubble across multiple chunks before a pause")
    func keepsOneBubbleAcrossChunks() {
        var pipeline = LiveMeetingTranscriptPipeline(meetingStart: .init(timeIntervalSince1970: 0))

        _ = pipeline.ingest(.speechStarted(source: .system, at: 1.0))
        _ = pipeline.ingest(.transcriptChunk(source: .system, chunk: chunk(
            text: "Hello",
            start: 1.0,
            end: 1.5
        )))
        let turns = pipeline.ingest(.transcriptChunk(source: .system, chunk: chunk(
            text: "world",
            start: 1.6,
            end: 2.1
        )))

        #expect(turns.count == 1)
        #expect(turns[0].text == "Hello world")
        #expect(turns[0].speakerLabel == "Others")
    }

    @Test("keeps different sources as separate turns")
    func keepsDifferentSourcesSeparate() {
        var pipeline = LiveMeetingTranscriptPipeline(meetingStart: .init(timeIntervalSince1970: 0))

        _ = pipeline.ingest(.speechStarted(source: .microphone, at: 1.0))
        let micTurns = pipeline.ingest(.transcriptChunk(source: .microphone, chunk: chunk(
            text: "My turn",
            start: 1.0,
            end: 1.5
        )))
        _ = pipeline.ingest(.speechStarted(source: .system, at: 1.2))
        let allTurns = pipeline.ingest(.transcriptChunk(source: .system, chunk: chunk(
            text: "Other turn",
            start: 1.2,
            end: 1.8
        )))

        #expect(micTurns.count == 1)
        #expect(allTurns.count == 2)
        #expect(allTurns[0].speakerLabel == "You")
        #expect(allTurns[1].speakerLabel == "Others")
    }

    @Test("starts a new bubble when consolidated text gets too long")
    func splitsLongBubble() {
        var pipeline = LiveMeetingTranscriptPipeline(meetingStart: .init(timeIntervalSince1970: 0))
        let repeated = String(repeating: "very long sentence ", count: 12)

        _ = pipeline.ingest(.speechStarted(source: .microphone, at: 1.0))
        _ = pipeline.ingest(.transcriptChunk(source: .microphone, chunk: chunk(
            text: repeated,
            start: 1.0,
            end: 4.0
        )))
        let turns = pipeline.ingest(.transcriptChunk(source: .microphone, chunk: chunk(
            text: repeated,
            start: 4.2,
            end: 7.0
        )))

        #expect(turns.count == 2)
    }

    @Test("starts a new bubble when consolidated duration gets too long")
    func splitsLongDurationBubble() {
        var pipeline = LiveMeetingTranscriptPipeline(meetingStart: .init(timeIntervalSince1970: 0))

        _ = pipeline.ingest(.speechStarted(source: .system, at: 1.0))
        _ = pipeline.ingest(.transcriptChunk(source: .system, chunk: chunk(
            text: "First chunk",
            start: 1.0,
            end: 8.0
        )))
        let turns = pipeline.ingest(.transcriptChunk(source: .system, chunk: chunk(
            text: "Second chunk",
            start: 8.5,
            end: 16.5
        )))

        #expect(turns.count == 2)
    }

    @Test("late chunks still attach to the turn that already closed")
    func lateChunkAttachesToClosedTurn() {
        var pipeline = LiveMeetingTranscriptPipeline(meetingStart: .init(timeIntervalSince1970: 0))

        _ = pipeline.ingest(.speechStarted(source: .microphone, at: 2.0))
        _ = pipeline.ingest(.speechEnded(source: .microphone, at: 4.5))
        _ = pipeline.ingest(.speechStarted(source: .microphone, at: 6.0))

        let turns = pipeline.ingest(.transcriptChunk(source: .microphone, chunk: chunk(
            text: "First idea",
            start: 2.0,
            end: 4.0
        )))

        #expect(turns.count == 1)
        #expect(turns[0].startTimeSeconds == 2.0)
        #expect(turns[0].text == "First idea")
    }

    @Test("flush closes the current turn so the next chunk starts fresh")
    func flushClosesCurrentTurn() {
        var pipeline = LiveMeetingTranscriptPipeline(meetingStart: .init(timeIntervalSince1970: 0))

        _ = pipeline.ingest(.speechStarted(source: .microphone, at: 1.0))
        _ = pipeline.ingest(.transcriptChunk(source: .microphone, chunk: chunk(
            text: "Before pause",
            start: 1.0,
            end: 2.0
        )))
        _ = pipeline.ingest(.flush(source: .microphone))
        _ = pipeline.ingest(.speechStarted(source: .microphone, at: 5.0))
        let turns = pipeline.ingest(.transcriptChunk(source: .microphone, chunk: chunk(
            text: "After pause",
            start: 5.0,
            end: 6.0
        )))

        #expect(turns.count == 2)
        #expect(turns[0].text == "Before pause")
        #expect(turns[1].text == "After pause")
    }

    private func chunk(text: String, start: TimeInterval, end: TimeInterval) -> MeetingTranscriptChunk {
        MeetingTranscriptChunk(
            result: SpeechTranscriptionResult(
                text: text,
                segments: [SpeechSegment(start: 0.0, end: max(end - start, 0.1), text: text)]
            ),
            startTime: start,
            endTime: end
        )
    }
}
