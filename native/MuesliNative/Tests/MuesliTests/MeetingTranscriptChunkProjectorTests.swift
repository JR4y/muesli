import FluidAudio
import Testing
@testable import MuesliNativeApp

@Suite("Meeting transcript chunk projector")
struct MeetingTranscriptChunkProjectorTests {

    @Test("live and canonical system segmentation are independent")
    func liveAndCanonicalSystemSegmentationDiffer() {
        let longSentenceA = "This is a long sentence about the implementation details and how the work order update should flow through the system."
        let longSentenceB = "This is another long sentence that should remain independently addressable in the final transcript so the post processing pipeline can reconcile it safely."
        let longSentenceC = "This is a third long sentence that pushes the total text length high enough for the live display path to keep the chunk whole."
        let result = SpeechTranscriptionResult(
            text: "\(longSentenceA) \(longSentenceB) \(longSentenceC)",
            segments: [
                SpeechSegment(start: 0.0, end: 0.0, text: "\(longSentenceA) \(longSentenceB) \(longSentenceC)"),
            ]
        )
        let chunk = MeetingTranscriptChunk(result: result, startTime: 10.0, endTime: 14.5)

        let live = MeetingTranscriptChunkProjector.liveSystemSegments(from: chunk)
        let canonical = MeetingTranscriptChunkProjector.canonicalSystemSegments(from: [chunk])

        #expect(live.count == 1)
        #expect(canonical.count == 3)
        #expect(canonical[0].text == longSentenceA)
        #expect(canonical[1].text == longSentenceB)
        #expect(canonical[2].text == longSentenceC)
    }

    @Test("canonical projection stays sorted across multiple chunks")
    func canonicalProjectionSorted() {
        let first = MeetingTranscriptChunk(
            result: SpeechTranscriptionResult(
                text: "Second line.",
                segments: [SpeechSegment(start: 0.0, end: 0.0, text: "Second line.")]
            ),
            startTime: 20.0,
            endTime: 24.0
        )
        let second = MeetingTranscriptChunk(
            result: SpeechTranscriptionResult(
                text: "First line.",
                segments: [SpeechSegment(start: 0.0, end: 0.0, text: "First line.")]
            ),
            startTime: 10.0,
            endTime: 14.0
        )

        let canonical = MeetingTranscriptChunkProjector.canonicalMicSegments(from: [first, second])

        #expect(canonical.count == 2)
        #expect(canonical[0].start == 10.0)
        #expect(canonical[1].start == 20.0)
    }
}
