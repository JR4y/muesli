import FluidAudio
import Foundation

struct MeetilyStyleLiveTranscriptConfiguration: Equatable, Sendable {
    var positiveSpeechThreshold: Float = 0.50
    var negativeSpeechThreshold: Float = 0.35
    var redemptionTime: TimeInterval = 2.0
    var preSpeechPad: TimeInterval = 0.30
    var postSpeechPad: TimeInterval = 0.40
    var minSpeechTime: TimeInterval = 0.25
    var minimumSegmentSamples: Int = 800
    var maxSpeechDuration: TimeInterval = 30.0

    static let `default` = MeetilyStyleLiveTranscriptConfiguration()

    var vadSegmentationConfig: VadSegmentationConfig {
        VadSegmentationConfig(
            minSpeechDuration: max(minSpeechTime, preSpeechPad),
            minSilenceDuration: redemptionTime,
            maxSpeechDuration: maxSpeechDuration,
            speechPadding: preSpeechPad,
            silenceThresholdForSplit: positiveSpeechThreshold,
            negativeThreshold: negativeSpeechThreshold,
            negativeThresholdOffset: max(positiveSpeechThreshold - negativeSpeechThreshold, 0.01),
            minSilenceAtMaxSpeech: 0.098,
            useMaxPossibleSilenceAtMaxSpeech: true
        )
    }
}

struct MeetilyStyleLiveTranscriptSegment: Equatable, Sendable, Identifiable {
    let id: Int
    let sequenceID: Int
    let source: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String

    var duration: TimeInterval {
        max(0, endTime - startTime)
    }

    var transcriptLine: String {
        "[\(Self.timestamp(startTime))] \(source): \(text)"
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct MeetilyStyleLiveTranscriptImportResult: Sendable {
    let inputDuration: TimeInterval
    let detectedSpeechSegments: Int
    let droppedShortSegments: Int
    let segments: [MeetilyStyleLiveTranscriptSegment]
    let configuration: MeetilyStyleLiveTranscriptConfiguration

    var rawTranscript: String {
        segments.map(\.transcriptLine).joined(separator: "\n")
    }
}

enum MeetilyStyleLiveTranscriptImporterError: LocalizedError {
    case vadUnavailable
    case noSpeechDetected
    case noTranscriptProduced

    var errorDescription: String? {
        switch self {
        case .vadUnavailable:
            return "The local VAD engine is not available yet. Prepare the meeting transcription model and try again."
        case .noSpeechDetected:
            return "No speech was detected in this WAV file."
        case .noTranscriptProduced:
            return "Speech was detected, but the selected transcription model did not produce text."
        }
    }
}

struct MeetilyStyleLiveTranscriptImporter {
    typealias ProgressHandler = @Sendable (_ completed: Int, _ total: Int, _ message: String) -> Void

    let configuration: MeetilyStyleLiveTranscriptConfiguration

    init(configuration: MeetilyStyleLiveTranscriptConfiguration = .default) {
        self.configuration = configuration
    }

    func importWAV(
        url: URL,
        backend: BackendOption,
        cohereLanguage: CohereTranscribeLanguage,
        transcriptionCoordinator: TranscriptionCoordinator,
        progress: ProgressHandler? = nil
    ) async throws -> MeetilyStyleLiveTranscriptImportResult {
        guard let vadManager = await transcriptionCoordinator.getVadManager() else {
            throw MeetilyStyleLiveTranscriptImporterError.vadUnavailable
        }

        let samples = try AudioConverter().resampleAudioFile(url)
        let inputDuration = Double(samples.count) / Double(VadManager.sampleRate)
        let vadSegments = try await vadManager.segmentSpeech(
            samples,
            config: configuration.vadSegmentationConfig
        )
        guard !vadSegments.isEmpty else {
            throw MeetilyStyleLiveTranscriptImporterError.noSpeechDetected
        }

        let candidates = Self.transcriptionCandidates(
            from: vadSegments,
            sampleCount: samples.count,
            configuration: configuration
        )
        guard !candidates.ranges.isEmpty else {
            throw MeetilyStyleLiveTranscriptImporterError.noSpeechDetected
        }

        var transcriptSegments: [MeetilyStyleLiveTranscriptSegment] = []
        for (index, candidate) in candidates.ranges.enumerated() {
            let sequenceID = index + 1
            progress?(index, candidates.ranges.count, "Transcribing turn \(sequenceID) of \(candidates.ranges.count)...")

            let segmentSamples = Array(samples[candidate.range])
            let segmentURL = try WavWriter.writeTemporaryWAV(
                samples: segmentSamples,
                directoryName: "muesli-meetily-live-import"
            )
            defer { try? FileManager.default.removeItem(at: segmentURL) }

            let result = try await transcriptionCoordinator.transcribeMeeting(
                at: segmentURL,
                backend: backend,
                cohereLanguage: cohereLanguage
            )
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            transcriptSegments.append(MeetilyStyleLiveTranscriptSegment(
                id: sequenceID,
                sequenceID: sequenceID,
                source: "Audio",
                startTime: candidate.startTime,
                endTime: candidate.endTime,
                text: text
            ))
        }

        progress?(candidates.ranges.count, candidates.ranges.count, "Import complete")

        guard !transcriptSegments.isEmpty else {
            throw MeetilyStyleLiveTranscriptImporterError.noTranscriptProduced
        }

        return MeetilyStyleLiveTranscriptImportResult(
            inputDuration: inputDuration,
            detectedSpeechSegments: vadSegments.count,
            droppedShortSegments: candidates.droppedShortSegments,
            segments: transcriptSegments,
            configuration: configuration
        )
    }

    static func transcriptionCandidates(
        from vadSegments: [VadSegment],
        sampleCount: Int,
        configuration: MeetilyStyleLiveTranscriptConfiguration = .default
    ) -> (ranges: [(range: Range<Int>, startTime: TimeInterval, endTime: TimeInterval)], droppedShortSegments: Int) {
        var ranges: [(range: Range<Int>, startTime: TimeInterval, endTime: TimeInterval)] = []
        var droppedShortSegments = 0
        let sampleRate = VadManager.sampleRate
        let additionalPostPad = max(0, configuration.postSpeechPad - configuration.preSpeechPad)
        let additionalPostPadSamples = Int((additionalPostPad * Double(sampleRate)).rounded())

        for segment in vadSegments {
            let rawStartSample = max(0, segment.startSample(sampleRate: sampleRate))
            let rawEndSample = min(sampleCount, segment.endSample(sampleRate: sampleRate))
            guard rawEndSample > rawStartSample else { continue }
            guard rawEndSample - rawStartSample >= configuration.minimumSegmentSamples else {
                droppedShortSegments += 1
                continue
            }

            let startSample = rawStartSample
            let endSample = min(sampleCount, rawEndSample + additionalPostPadSamples)
            guard endSample > startSample else { continue }
            ranges.append((
                range: startSample..<endSample,
                startTime: Double(startSample) / Double(sampleRate),
                endTime: Double(endSample) / Double(sampleRate)
            ))
        }

        return (ranges, droppedShortSegments)
    }
}
