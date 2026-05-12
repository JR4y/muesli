import FluidAudio
import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Meetily-style live transcript importer")
struct MeetilyStyleLiveTranscriptImporterTests {
    @Test("defaults mirror Meetily pause segmentation baseline")
    func defaultsMirrorMeetilyPauseBaseline() {
        let config = MeetilyStyleLiveTranscriptConfiguration.default

        #expect(config.positiveSpeechThreshold == 0.50)
        #expect(config.negativeSpeechThreshold == 0.35)
        #expect(config.redemptionTime == 2.0)
        #expect(config.preSpeechPad == 0.30)
        #expect(config.postSpeechPad == 0.40)
        #expect(config.minSpeechTime == 0.25)
        #expect(config.minimumSegmentSamples == 800)

        let vadConfig = config.vadSegmentationConfig
        #expect(vadConfig.silenceThresholdForSplit == 0.50)
        #expect(vadConfig.negativeThreshold == 0.35)
        #expect(vadConfig.minSilenceDuration == 2.0)
        #expect(vadConfig.speechPadding == 0.30)
        #expect(vadConfig.minSpeechDuration == 0.30)
        #expect(vadConfig.speechPadding <= vadConfig.minSpeechDuration)
    }

    @Test("drops very short VAD segments and applies Meetily post padding")
    func dropsShortSegmentsAndAppliesPostPadding() {
        let segments = [
            VadSegment(startTime: 0.0, endTime: 0.02),
            VadSegment(startTime: 1.0, endTime: 1.30),
        ]

        let result = MeetilyStyleLiveTranscriptImporter.transcriptionCandidates(
            from: segments,
            sampleCount: 40_000,
            configuration: .default
        )

        #expect(result.droppedShortSegments == 1)
        #expect(result.ranges.count == 1)
        #expect(result.ranges.first?.range.lowerBound == 16_000)
        #expect(result.ranges.first?.range.upperBound == 22_400)
        #expect(result.ranges.first?.startTime == 1.0)
        #expect(result.ranges.first?.endTime == 1.40)
    }

    @Test("formats imported transcript as a single Audio source stream")
    func formatsImportedTranscriptAsSingleAudioSourceStream() {
        let result = MeetilyStyleLiveTranscriptImportResult(
            inputDuration: 65,
            detectedSpeechSegments: 2,
            droppedShortSegments: 0,
            segments: [
                MeetilyStyleLiveTranscriptSegment(
                    id: 1,
                    sequenceID: 1,
                    source: "Audio",
                    startTime: 0,
                    endTime: 4,
                    text: "Hola."
                ),
                MeetilyStyleLiveTranscriptSegment(
                    id: 2,
                    sequenceID: 2,
                    source: "Audio",
                    startTime: 63,
                    endTime: 65,
                    text: "Seguimos."
                ),
            ],
            configuration: .default
        )

        #expect(result.rawTranscript == "[00:00] Audio: Hola.\n[01:03] Audio: Seguimos.")
    }
}
