import Foundation

enum LiveMeetingTranscriptSource: String, Codable, Sendable {
    case microphone
    case system

    var speakerLabel: String {
        switch self {
        case .microphone:
            return "You"
        case .system:
            return "Others"
        }
    }
}

enum LiveMeetingTranscriptEvent: Sendable {
    case speechStarted(source: LiveMeetingTranscriptSource, at: TimeInterval)
    case speechEnded(source: LiveMeetingTranscriptSource, at: TimeInterval)
    case transcriptChunk(source: LiveMeetingTranscriptSource, chunk: MeetingTranscriptChunk)
    case flush(source: LiveMeetingTranscriptSource)
}

struct LiveMeetingTranscriptTurn: Identifiable, Equatable, Sendable {
    let id: String
    let source: LiveMeetingTranscriptSource
    let speakerLabel: String
    let timestamp: Date
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let text: String
}

struct MeetingTranscriptDisplayTurn: Identifiable, Equatable, Sendable {
    enum Style: String, Sendable {
        case localSpeaker
        case remoteSpeaker
    }

    let id: String
    let speakerLabel: String
    let timestampLabel: String?
    let text: String
    let style: Style
}

struct LiveMeetingTranscriptPipeline: Sendable {
    struct Configuration: Sendable {
        let maxTurnDuration: TimeInterval
        let maxVisibleLength: Int
        let attachTolerance: TimeInterval
        let minimumTurnDuration: TimeInterval

        static let `default` = Configuration(
            maxTurnDuration: 14.0,
            maxVisibleLength: 280,
            attachTolerance: 0.75,
            minimumTurnDuration: 0.05
        )
    }

    private struct TurnEnvelope: Sendable {
        let id: String
        let source: LiveMeetingTranscriptSource
        let speakerLabel: String
        let timestamp: Date
        var startTimeSeconds: Double
        var endTimeSeconds: Double
        var text: String
        var isOpen: Bool

        var hasVisibleText: Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private struct LiveChunkText: Sendable {
        let text: String
        let startTimeSeconds: Double
        let endTimeSeconds: Double
    }

    let meetingStart: Date
    let configuration: Configuration
    private(set) var turns: [LiveMeetingTranscriptTurn] = []
    private var envelopes: [TurnEnvelope] = []
    private var nextSequence = 0

    init(meetingStart: Date, configuration: Configuration = .default) {
        self.meetingStart = meetingStart
        self.configuration = configuration
    }

    mutating func ingest(_ event: LiveMeetingTranscriptEvent) -> [LiveMeetingTranscriptTurn] {
        switch event {
        case .speechStarted(let source, let time):
            handleSpeechStarted(source: source, at: time)
        case .speechEnded(let source, let time):
            handleSpeechEnded(source: source, at: time)
        case .transcriptChunk(let source, let chunk):
            handleTranscriptChunk(source: source, chunk: chunk)
        case .flush(let source):
            handleFlush(source: source)
        }

        turns = materializedTurns()
        return turns
    }

    private mutating func handleSpeechStarted(
        source: LiveMeetingTranscriptSource,
        at time: TimeInterval
    ) {
        guard latestOpenIndex(for: source) == nil else { return }
        envelopes.append(makeEnvelope(
            source: source,
            startTimeSeconds: time,
            endTimeSeconds: time,
            text: "",
            isOpen: true
        ))
    }

    private mutating func handleSpeechEnded(
        source: LiveMeetingTranscriptSource,
        at time: TimeInterval
    ) {
        guard let index = latestOpenIndex(for: source) else { return }
        envelopes[index].endTimeSeconds = max(envelopes[index].endTimeSeconds, time)
        envelopes[index].isOpen = false
        pruneEmptyEnvelopeIfNeeded(at: index)
    }

    private mutating func handleFlush(source: LiveMeetingTranscriptSource) {
        guard let index = latestOpenIndex(for: source) else { return }
        envelopes[index].isOpen = false
        pruneEmptyEnvelopeIfNeeded(at: index)
    }

    private mutating func handleTranscriptChunk(
        source: LiveMeetingTranscriptSource,
        chunk: MeetingTranscriptChunk
    ) {
        guard let liveText = makeLiveChunkText(source: source, chunk: chunk) else { return }

        if let index = attachmentIndex(for: source, startTime: liveText.startTimeSeconds, endTime: liveText.endTimeSeconds) {
            append(liveText: liveText, toEnvelopeAt: index)
        } else {
            envelopes.append(makeEnvelope(
                source: source,
                startTimeSeconds: liveText.startTimeSeconds,
                endTimeSeconds: liveText.endTimeSeconds,
                text: liveText.text,
                isOpen: latestOpenIndex(for: source) != nil
            ))
        }
    }

    private mutating func append(liveText: LiveChunkText, toEnvelopeAt index: Int) {
        guard envelopes.indices.contains(index) else { return }

        let existing = envelopes[index]
        let mergedText = join(existing.text, liveText.text)
        let mergedStart = min(existing.startTimeSeconds, liveText.startTimeSeconds)
        let mergedEnd = max(existing.endTimeSeconds, liveText.endTimeSeconds)
        let mergedDuration = mergedEnd - mergedStart
        let shouldSoftSplit = existing.hasVisibleText &&
            (mergedDuration > configuration.maxTurnDuration ||
             visibleLength(of: mergedText) > configuration.maxVisibleLength)

        if shouldSoftSplit {
            let continuationIsOpen = existing.isOpen
            envelopes[index].isOpen = false
            envelopes[index].endTimeSeconds = max(existing.endTimeSeconds, liveText.startTimeSeconds)

            envelopes.append(makeEnvelope(
                source: existing.source,
                startTimeSeconds: liveText.startTimeSeconds,
                endTimeSeconds: liveText.endTimeSeconds,
                text: liveText.text,
                isOpen: continuationIsOpen
            ))
            return
        }

        envelopes[index].startTimeSeconds = mergedStart
        envelopes[index].endTimeSeconds = mergedEnd
        envelopes[index].text = mergedText
    }

    private func attachmentIndex(
        for source: LiveMeetingTranscriptSource,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> Int? {
        let midpoint = (startTime + endTime) / 2

        let overlappingCandidates = envelopes.enumerated().filter { _, envelope in
            guard envelope.source == source else { return false }
            let lowerBound = envelope.startTimeSeconds - configuration.attachTolerance
            let upperBound = max(envelope.endTimeSeconds, envelope.startTimeSeconds) + configuration.attachTolerance
            return midpoint >= lowerBound && midpoint <= upperBound
        }

        if let bestOverlap = overlappingCandidates.max(by: { lhs, rhs in
            overlapScore(lhs.element, startTime: startTime, endTime: endTime) <
                overlapScore(rhs.element, startTime: startTime, endTime: endTime)
        }) {
            return bestOverlap.offset
        }

        if let openIndex = latestOpenIndex(for: source) {
            return openIndex
        }

        return envelopes.indices.reversed().first { index in
            let envelope = envelopes[index]
            guard envelope.source == source else { return false }
            let gap = startTime - envelope.endTimeSeconds
            return gap >= 0 && gap <= configuration.attachTolerance
        }
    }

    private func overlapScore(
        _ envelope: TurnEnvelope,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> Double {
        let overlapStart = max(envelope.startTimeSeconds, startTime)
        let overlapEnd = min(max(envelope.endTimeSeconds, envelope.startTimeSeconds), endTime)
        let overlap = max(0, overlapEnd - overlapStart)
        let distancePenalty = abs(envelope.startTimeSeconds - startTime) * 0.001
        return overlap - distancePenalty
    }

    private func latestOpenIndex(for source: LiveMeetingTranscriptSource) -> Int? {
        envelopes.indices.reversed().first { index in
            envelopes[index].source == source && envelopes[index].isOpen
        }
    }

    private mutating func pruneEmptyEnvelopeIfNeeded(at index: Int) {
        guard envelopes.indices.contains(index) else { return }
        let envelope = envelopes[index]
        let duration = envelope.endTimeSeconds - envelope.startTimeSeconds
        guard !envelope.hasVisibleText, duration < configuration.minimumTurnDuration else { return }
        envelopes.remove(at: index)
    }

    private func materializedTurns() -> [LiveMeetingTranscriptTurn] {
        envelopes
            .filter(\.hasVisibleText)
            .sorted { lhs, rhs in
                if lhs.startTimeSeconds == rhs.startTimeSeconds {
                    return lhs.id < rhs.id
                }
                return lhs.startTimeSeconds < rhs.startTimeSeconds
            }
            .map { envelope in
                LiveMeetingTranscriptTurn(
                    id: envelope.id,
                    source: envelope.source,
                    speakerLabel: envelope.speakerLabel,
                    timestamp: envelope.timestamp,
                    startTimeSeconds: envelope.startTimeSeconds,
                    endTimeSeconds: max(envelope.endTimeSeconds, envelope.startTimeSeconds),
                    text: envelope.text
                )
            }
    }

    private mutating func makeEnvelope(
        source: LiveMeetingTranscriptSource,
        startTimeSeconds: Double,
        endTimeSeconds: Double,
        text: String,
        isOpen: Bool
    ) -> TurnEnvelope {
        let identifier = "\(source.rawValue)|\(nextSequence)"
        nextSequence += 1
        return TurnEnvelope(
            id: identifier,
            source: source,
            speakerLabel: source.speakerLabel,
            timestamp: meetingStart.addingTimeInterval(startTimeSeconds),
            startTimeSeconds: startTimeSeconds,
            endTimeSeconds: max(endTimeSeconds, startTimeSeconds),
            text: text,
            isOpen: isOpen
        )
    }

    private func makeLiveChunkText(
        source: LiveMeetingTranscriptSource,
        chunk: MeetingTranscriptChunk
    ) -> LiveChunkText? {
        let segments: [SpeechSegment]
        switch source {
        case .microphone:
            segments = MeetingTranscriptChunkProjector.liveMicSegments(from: chunk)
        case .system:
            segments = MeetingTranscriptChunkProjector.liveSystemSegments(from: chunk)
        }

        let trimmedSegments = segments.compactMap { segment -> SpeechSegment? in
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return SpeechSegment(start: segment.start, end: segment.end, text: trimmed)
        }

        guard !trimmedSegments.isEmpty else { return nil }

        let combinedText = trimmedSegments
            .dropFirst()
            .reduce(trimmedSegments[0].text) { partialResult, segment in
                join(partialResult, segment.text)
            }

        return LiveChunkText(
            text: combinedText,
            startTimeSeconds: trimmedSegments.first?.start ?? chunk.startTime,
            endTimeSeconds: trimmedSegments.last?.end ?? chunk.endTime
        )
    }

    private func visibleLength(of text: String) -> Int {
        text.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + (CharacterSet.whitespacesAndNewlines.contains(scalar) ? 0 : 1)
        }
    }

    private func join(_ lhs: String, _ rhs: String) -> String {
        guard !lhs.isEmpty else { return rhs }
        guard !rhs.isEmpty else { return lhs }
        guard let lhsLast = lhs.last, let rhsFirst = rhs.first else {
            return lhs + rhs
        }
        if lhsLast.isWhitespace || rhsFirst.isWhitespace || rhsFirst.isPunctuation {
            return lhs + rhs
        }
        if lhsLast.isPunctuation {
            return lhs + " " + rhs
        }
        return lhs + " " + rhs
    }
}

enum MeetingTranscriptDisplayTurnParser {
    private static let linePattern = try! NSRegularExpression(
        pattern: #"^\[(\d{2}:\d{2}:\d{2})\]\s+([^:]+):\s*(.*)$"#,
        options: []
    )

    static func parse(_ rawTranscript: String) -> [MeetingTranscriptDisplayTurn] {
        rawTranscript
            .components(separatedBy: .newlines)
            .compactMap(parseLine)
    }

    private static func parseLine(_ line: String) -> MeetingTranscriptDisplayTurn? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = linePattern.firstMatch(in: trimmed, options: [], range: range) else {
            return fallbackTurn(for: trimmed)
        }

        guard
            let timestampRange = Range(match.range(at: 1), in: trimmed),
            let speakerRange = Range(match.range(at: 2), in: trimmed),
            let textRange = Range(match.range(at: 3), in: trimmed)
        else {
            return fallbackTurn(for: trimmed)
        }

        let timestampLabel = String(trimmed[timestampRange])
        let speakerLabel = String(trimmed[speakerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let text = String(trimmed[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !speakerLabel.isEmpty else {
            return fallbackTurn(for: trimmed)
        }

        let normalizedText = text.isEmpty ? trimmed : text
        return MeetingTranscriptDisplayTurn(
            id: "\(timestampLabel)|\(speakerLabel)|\(normalizedText)",
            speakerLabel: speakerLabel,
            timestampLabel: timestampLabel,
            text: normalizedText,
            style: displayStyle(for: speakerLabel)
        )
    }

    private static func fallbackTurn(for line: String) -> MeetingTranscriptDisplayTurn {
        MeetingTranscriptDisplayTurn(
            id: "fallback|\(line)",
            speakerLabel: "Transcript",
            timestampLabel: nil,
            text: line,
            style: .remoteSpeaker
        )
    }

    private static func displayStyle(for speakerLabel: String) -> MeetingTranscriptDisplayTurn.Style {
        speakerLabel == LiveMeetingTranscriptSource.microphone.speakerLabel ? .localSpeaker : .remoteSpeaker
    }
}

extension LiveMeetingTranscriptTurn {
    func asDisplayTurn() -> MeetingTranscriptDisplayTurn {
        MeetingTranscriptDisplayTurn(
            id: id,
            speakerLabel: speakerLabel,
            timestampLabel: Self.timestampFormatter.string(from: timestamp),
            text: text,
            style: source == .microphone ? .localSpeaker : .remoteSpeaker
        )
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
