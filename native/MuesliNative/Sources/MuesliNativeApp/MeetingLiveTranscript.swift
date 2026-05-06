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
    let meetingStart: Date
    private(set) var turns: [LiveMeetingTranscriptTurn] = []

    mutating func ingest(
        source: LiveMeetingTranscriptSource,
        chunk: MeetingTranscriptChunk
    ) -> [LiveMeetingTranscriptTurn] {
        let segments: [SpeechSegment]
        switch source {
        case .microphone:
            segments = MeetingTranscriptChunkProjector.liveMicSegments(from: chunk)
        case .system:
            segments = MeetingTranscriptChunkProjector.liveSystemSegments(from: chunk)
        }

        turns = LiveMeetingTranscriptReducer.merge(
            existing: turns,
            source: source,
            segments: segments,
            meetingStart: meetingStart
        )
        return turns
    }
}

enum LiveMeetingTranscriptReducer {
    private static let consolidationGapThreshold: TimeInterval = 2.0
    private static let maxConsolidatedDuration: TimeInterval = 14.0
    private static let maxVisibleLength = 280

    static func merge(
        existing: [LiveMeetingTranscriptTurn],
        source: LiveMeetingTranscriptSource,
        segments: [SpeechSegment],
        meetingStart: Date
    ) -> [LiveMeetingTranscriptTurn] {
        let appended = existing + segments.compactMap { segment in
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return LiveMeetingTranscriptTurn(
                id: identifier(for: source, start: segment.start, end: segment.end, text: trimmed),
                source: source,
                speakerLabel: source.speakerLabel,
                timestamp: meetingStart.addingTimeInterval(segment.start),
                startTimeSeconds: segment.start,
                endTimeSeconds: segment.end,
                text: trimmed
            )
        }
        return consolidate(deduplicate(appended))
    }

    private static func deduplicate(_ turns: [LiveMeetingTranscriptTurn]) -> [LiveMeetingTranscriptTurn] {
        var seen = Set<String>()
        return turns.filter { turn in
            seen.insert(turn.id).inserted
        }
    }

    private static func consolidate(_ turns: [LiveMeetingTranscriptTurn]) -> [LiveMeetingTranscriptTurn] {
        let sorted = turns.sorted { lhs, rhs in
            if lhs.startTimeSeconds == rhs.startTimeSeconds {
                return lhs.id < rhs.id
            }
            return lhs.startTimeSeconds < rhs.startTimeSeconds
        }
        guard var current = sorted.first else { return [] }

        var result: [LiveMeetingTranscriptTurn] = []
        for turn in sorted.dropFirst() {
            let gap = max(0, turn.startTimeSeconds - current.endTimeSeconds)
            let mergedDuration = max(current.endTimeSeconds, turn.endTimeSeconds) - current.startTimeSeconds
            let mergedText = join(current.text, turn.text)
            if turn.source == current.source &&
                gap <= consolidationGapThreshold &&
                mergedDuration <= maxConsolidatedDuration &&
                visibleLength(of: mergedText) <= maxVisibleLength {
                let text = join(current.text, turn.text)
                current = LiveMeetingTranscriptTurn(
                    id: identifier(
                        for: current.source,
                        start: current.startTimeSeconds,
                        end: max(current.endTimeSeconds, turn.endTimeSeconds),
                        text: text
                    ),
                    source: current.source,
                    speakerLabel: current.speakerLabel,
                    timestamp: current.timestamp,
                    startTimeSeconds: current.startTimeSeconds,
                    endTimeSeconds: max(current.endTimeSeconds, turn.endTimeSeconds),
                    text: text
                )
            } else {
                result.append(current)
                current = turn
            }
        }
        result.append(current)
        return result
    }

    private static func visibleLength(of text: String) -> Int {
        text.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + (CharacterSet.whitespacesAndNewlines.contains(scalar) ? 0 : 1)
        }
    }

    private static func join(_ lhs: String, _ rhs: String) -> String {
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

    private static func identifier(
        for source: LiveMeetingTranscriptSource,
        start: Double,
        end: Double,
        text: String
    ) -> String {
        "\(source.rawValue)|\(String(format: "%.3f", start))|\(String(format: "%.3f", end))|\(text)"
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
