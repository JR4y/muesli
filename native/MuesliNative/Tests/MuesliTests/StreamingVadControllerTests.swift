import FluidAudio
import Foundation
import Testing
@testable import MuesliNativeApp

private actor StreamingVadTestProbe {
    private(set) var processedCount = 0
    private(set) var inFlightCount = 0
    private(set) var maxConcurrentCount = 0
    private(set) var boundaryCount = 0
    private(set) var speechEventKinds: [VadStreamEvent.Kind] = []

    func processingStarted() {
        inFlightCount += 1
        maxConcurrentCount = max(maxConcurrentCount, inFlightCount)
    }

    func processingFinished() {
        inFlightCount = max(0, inFlightCount - 1)
        processedCount += 1
    }

    func boundaryTriggered() {
        boundaryCount += 1
    }

    func speechEventTriggered(_ kind: VadStreamEvent.Kind) {
        speechEventKinds.append(kind)
    }
}

@Suite("StreamingVadController", .serialized)
struct StreamingVadControllerTests {
    @Test("meeting live transcript VAD configuration stays valid for debug builds")
    func meetingLiveTranscriptConfigurationIsValid() {
        let config = MeetingSession.makeLiveTranscriptVadConfiguration()

        #expect(config.segmentation.silenceThresholdForSplit == 0.50)
        #expect(config.segmentation.negativeThreshold == 0.35)
        #expect(config.segmentation.minSilenceDuration == 2.0)
        #expect(config.segmentation.speechPadding == 0.30)
        #expect(config.segmentation.minSpeechDuration == 0.30)
        #expect(config.segmentation.speechPadding <= config.segmentation.minSpeechDuration)
        #expect(config.returnSeconds)
        #expect(config.timeResolution == 3)
    }

    @Test("serializes streaming VAD processing to a single in-flight chunk")
    func serializesChunkProcessing() async throws {
        let probe = StreamingVadTestProbe()
        let controller = StreamingVadController(
            minChunkDuration: 0,
            maxChunkDuration: 3600,
            makeInitialState: { VadStreamState.initial() },
            processStreamChunk: { _, state in
                await probe.processingStarted()
                try? await Task.sleep(for: .milliseconds(25))
                await probe.processingFinished()
                return VadStreamResult(state: state, event: nil, probability: 0.0)
            }
        )

        controller.start()
        for _ in 0..<10 {
            controller.processAudio([Float](repeating: 0, count: VadManager.chunkSize))
        }

        let deadline = ContinuousClock.now + .seconds(2)
        while await probe.processedCount < 10, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        controller.stop()

        #expect(await probe.processedCount == 10)
        #expect(await probe.maxConcurrentCount == 1)
    }

    @Test("buffers chunks that arrive before stream state initialization completes")
    func buffersChunksBeforeStateReady() async throws {
        let probe = StreamingVadTestProbe()
        let controller = StreamingVadController(
            minChunkDuration: 0,
            maxChunkDuration: 3600,
            makeInitialState: {
                try? await Task.sleep(for: .milliseconds(120))
                return VadStreamState.initial()
            },
            processStreamChunk: { _, state in
                await probe.processingStarted()
                try? await Task.sleep(for: .milliseconds(10))
                await probe.processingFinished()
                return VadStreamResult(state: state, event: nil, probability: 0.0)
            }
        )

        controller.start()
        for _ in 0..<3 {
            controller.processAudio([Float](repeating: 0, count: VadManager.chunkSize))
        }

        let deadline = ContinuousClock.now + .seconds(2)
        while await probe.processedCount < 3, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        controller.stop()

        #expect(await probe.processedCount == 3)
        #expect(await probe.maxConcurrentCount == 1)
    }

    @Test("emits a chunk boundary when streaming VAD detects speech end")
    func emitsChunkBoundaryOnSpeechEnd() async throws {
        let probe = StreamingVadTestProbe()
        let controller = StreamingVadController(
            minChunkDuration: 0,
            maxChunkDuration: 3600,
            makeInitialState: { VadStreamState.initial() },
            processStreamChunk: { _, state in
                await probe.processingStarted()
                await probe.processingFinished()
                return VadStreamResult(
                    state: state,
                    event: VadStreamEvent(kind: .speechEnd, sampleIndex: VadManager.chunkSize),
                    probability: 0.05
                )
            }
        )

        controller.onChunkBoundary = {
            Task { await probe.boundaryTriggered() }
        }

        controller.start()
        controller.processAudio([Float](repeating: 0, count: VadManager.chunkSize))

        let deadline = ContinuousClock.now + .seconds(3)
        while await probe.boundaryCount < 1, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        controller.stop()

        #expect(await probe.boundaryCount == 1)
    }

    @Test("emits speech events for both start and end boundaries")
    func emitsSpeechEvents() async throws {
        let probe = StreamingVadTestProbe()
        let emittedEvents = [
            VadStreamEvent(kind: .speechStart, sampleIndex: 0, time: 0.0),
            VadStreamEvent(kind: .speechEnd, sampleIndex: VadManager.chunkSize, time: 0.256),
        ]
        let controller = StreamingVadController(
            minChunkDuration: 0,
            maxChunkDuration: 3600,
            makeInitialState: { VadStreamState.initial() },
            processStreamChunk: { _, state in
                await probe.processingStarted()
                let eventIndex = await probe.processedCount
                await probe.processingFinished()
                let event = emittedEvents[min(eventIndex, emittedEvents.count - 1)]
                return VadStreamResult(state: state, event: event, probability: 0.5)
            }
        )

        controller.onSpeechEvent = { event in
            Task { await probe.speechEventTriggered(event.kind) }
        }

        controller.start()
        controller.processAudio([Float](repeating: 0, count: VadManager.chunkSize))
        controller.processAudio([Float](repeating: 0, count: VadManager.chunkSize))

        let deadline = ContinuousClock.now + .seconds(2)
        while await probe.speechEventKinds.count < 2, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        controller.stop()

        #expect(await probe.speechEventKinds == [.speechStart, .speechEnd])
    }

    @Test("ignores stale VAD results after stop and restart")
    func ignoresStaleResultsAfterRestart() async throws {
        let probe = StreamingVadTestProbe()
        let controller = StreamingVadController(
            minChunkDuration: 0,
            maxChunkDuration: 3600,
            makeInitialState: { VadStreamState.initial() },
            processStreamChunk: { _, state in
                await probe.processingStarted()
                try? await Task.sleep(for: .milliseconds(120))
                await probe.processingFinished()
                return VadStreamResult(
                    state: state,
                    event: VadStreamEvent(kind: .speechEnd, sampleIndex: VadManager.chunkSize),
                    probability: 0.05
                )
            }
        )

        controller.onChunkBoundary = {
            Task { await probe.boundaryTriggered() }
        }

        controller.start()
        controller.processAudio([Float](repeating: 0, count: VadManager.chunkSize))

        let startedDeadline = ContinuousClock.now + .seconds(1)
        while await probe.inFlightCount == 0, ContinuousClock.now < startedDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        controller.stop()
        controller.start()

        let finishedDeadline = ContinuousClock.now + .seconds(2)
        while await probe.processedCount < 1, ContinuousClock.now < finishedDeadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        controller.stop()

        #expect(await probe.processedCount == 1)
        #expect(await probe.boundaryCount == 0)
    }

    @Test("stale drainer does not clear restarted session queue")
    func staleDrainerDoesNotClearRestartedSessionQueue() async throws {
        let probe = StreamingVadTestProbe()
        let controller = StreamingVadController(
            minChunkDuration: 0,
            maxChunkDuration: 3600,
            makeInitialState: { VadStreamState.initial() },
            processStreamChunk: { _, state in
                await probe.processingStarted()
                try? await Task.sleep(for: .milliseconds(120))
                await probe.processingFinished()
                return VadStreamResult(state: state, event: nil, probability: 0.0)
            }
        )

        controller.start()
        controller.processAudio([Float](repeating: 0, count: VadManager.chunkSize))

        let startedDeadline = ContinuousClock.now + .seconds(1)
        while await probe.inFlightCount == 0, ContinuousClock.now < startedDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        controller.stop()
        controller.start()
        for _ in 0..<3 {
            controller.processAudio([Float](repeating: 0, count: VadManager.chunkSize))
        }

        let finishedDeadline = ContinuousClock.now + .seconds(2)
        while await probe.processedCount < 4, ContinuousClock.now < finishedDeadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        controller.stop()

        #expect(await probe.processedCount == 4)
    }

    @Test("reset detection state clears triggered speech so a new start can be emitted")
    func resetDetectionStateClearsTriggeredSpeech() async throws {
        let probe = StreamingVadTestProbe()
        let initialState = VadStreamState(triggered: true, processedSamples: VadManager.chunkSize * 2)
        let controller = StreamingVadController(
            minChunkDuration: 0,
            maxChunkDuration: 3600,
            makeInitialState: { initialState },
            processStreamChunk: { _, state in
                await probe.processingStarted()
                await probe.processingFinished()
                let event: VadStreamEvent? = state.triggered
                    ? nil
                    : VadStreamEvent(kind: .speechStart, sampleIndex: state.processedSamples, time: 0.512)
                return VadStreamResult(state: state, event: event, probability: 0.0)
            }
        )

        controller.onSpeechEvent = { event in
            Task { await probe.speechEventTriggered(event.kind) }
        }
        controller.start()
        controller.processAudio([Float](repeating: 0, count: VadManager.chunkSize))
        try? await Task.sleep(for: .milliseconds(100))

        controller.resetDetectionState()
        try? await Task.sleep(for: .milliseconds(100))
        controller.processAudio([Float](repeating: 0, count: VadManager.chunkSize))

        let deadline = ContinuousClock.now + .seconds(2)
        while await probe.speechEventKinds.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        controller.stop()

        #expect(await probe.speechEventKinds == [.speechStart])
    }
}
