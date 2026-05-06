import Foundation

enum TranscriptSegmentationStyle {
    case canonical
    case liveDisplay
}

enum MeetingTranscriptChunkProjector {
    static func liveMicSegments(from chunk: MeetingTranscriptChunk) -> [SpeechSegment] {
        MicTurnNormalizer.normalize(
            result: chunk.result,
            startTime: chunk.startTime,
            endTime: chunk.endTime,
            style: .liveDisplay
        )
    }

    static func canonicalMicSegments(from chunks: [MeetingTranscriptChunk]) -> [SpeechSegment] {
        sortSegments(chunks.flatMap { chunk in
            MicTurnNormalizer.normalize(
                result: chunk.result,
                startTime: chunk.startTime,
                endTime: chunk.endTime,
                style: .canonical
            )
        })
    }

    static func liveSystemSegments(from chunk: MeetingTranscriptChunk) -> [SpeechSegment] {
        SystemTurnNormalizer.normalize(
            result: chunk.result,
            startTime: chunk.startTime,
            endTime: chunk.endTime,
            style: .liveDisplay
        )
    }

    static func canonicalSystemSegments(from chunks: [MeetingTranscriptChunk]) -> [SpeechSegment] {
        sortSegments(chunks.flatMap { chunk in
            SystemTurnNormalizer.normalize(
                result: chunk.result,
                startTime: chunk.startTime,
                endTime: chunk.endTime,
                style: .canonical
            )
        })
    }

    private static func sortSegments(_ segments: [SpeechSegment]) -> [SpeechSegment] {
        segments.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.text < rhs.text
            }
            return lhs.start < rhs.start
        }
    }
}
