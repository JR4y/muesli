import FluidAudio
import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Meeting speech turn segmenter")
struct MeetingSpeechTurnSegmenterTests {
    @Test("mic pause windows keep same speaker turns separate for canonical formatting")
    func micPauseWindowsKeepTurnsSeparate() {
        let turns = MeetingSpeechTurnSegmenter.segmentMic(
            [
                SpeechSegment(start: 0.0, end: 1.0, text: "First thought."),
                SpeechSegment(start: 4.0, end: 5.0, text: "Second thought."),
            ],
            speechBoundaries: [
                VadSegment(startTime: 0.0, endTime: 1.0),
                VadSegment(startTime: 4.0, endTime: 5.0),
            ],
            audioDuration: 6.0
        )

        let transcript = TranscriptFormatter.merge(
            micSegments: turns,
            systemSegments: [],
            diarizationSegments: nil,
            meetingStart: Date(timeIntervalSince1970: 0),
            consolidationGapThreshold: MeetingSpeechTurnSegmenter.canonicalFormatterConsolidationGap
        )
        let lines = transcript.components(separatedBy: "\n").filter { !$0.isEmpty }

        #expect(turns.count == 2)
        #expect(lines.count == 2)
        #expect(lines[0].contains("You: First thought."))
        #expect(lines[1].contains("You: Second thought."))
    }

    @Test("system diarization boundaries split continuous remote speech by speaker")
    func systemDiarizationBoundariesSplitBySpeaker() {
        let diarization = [
            makeDiarSeg(speakerId: "alice", start: 0.0, end: 2.0),
            makeDiarSeg(speakerId: "bob", start: 2.0, end: 4.0),
        ]
        let turns = MeetingSpeechTurnSegmenter.segmentSystem(
            [
                SpeechSegment(start: 0.0, end: 4.0, text: "Alice starts. Bob responds."),
            ],
            speechBoundaries: [
                VadSegment(startTime: 0.0, endTime: 4.0),
            ],
            diarizationSegments: diarization,
            audioDuration: 4.5
        )

        let transcript = TranscriptFormatter.merge(
            micSegments: [],
            systemSegments: turns,
            diarizationSegments: diarization,
            meetingStart: Date(timeIntervalSince1970: 0),
            consolidationGapThreshold: MeetingSpeechTurnSegmenter.canonicalFormatterConsolidationGap
        )
        let lines = transcript.components(separatedBy: "\n").filter { !$0.isEmpty }

        #expect(turns.count == 2)
        #expect(lines.count == 2)
        #expect(lines[0].contains("Speaker 1: Alice starts."))
        #expect(lines[1].contains("Speaker 2: Bob responds."))
    }

    @Test("empty pause windows preserve cleaned original segments")
    func emptyPauseWindowsPreserveOriginalSegments() {
        let turns = MeetingSpeechTurnSegmenter.segmentMic(
            [
                SpeechSegment(start: 0.0, end: 1.0, text: "Kept."),
            ],
            speechBoundaries: [],
            audioDuration: 1.0
        )

        #expect(turns.count == 1)
        #expect(turns.first?.start == 0.0)
        #expect(turns.first?.end == 1.0)
        #expect(turns.first?.text == "Kept.")
    }

    private func makeDiarSeg(speakerId: String, start: Float, end: Float) -> TimedSpeakerSegment {
        TimedSpeakerSegment(
            speakerId: speakerId,
            embedding: [],
            startTimeSeconds: start,
            endTimeSeconds: end,
            qualityScore: 1.0
        )
    }
}
