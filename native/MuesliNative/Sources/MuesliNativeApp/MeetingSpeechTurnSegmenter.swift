import FluidAudio
import Foundation
import NaturalLanguage

enum MeetingSpeechTurnSegmenter {
    private struct BoundaryWindow {
        let start: TimeInterval
        let end: TimeInterval
    }

    private struct IndexedSegment {
        let originalIndex: Int
        let segment: SpeechSegment
    }

    static let canonicalFormatterConsolidationGap: TimeInterval = 0.75

    static func segmentMic(
        _ segments: [SpeechSegment],
        speechBoundaries: [VadSegment],
        audioDuration: TimeInterval?,
        configuration: MeetilyStyleLiveTranscriptConfiguration = .default
    ) -> [SpeechSegment] {
        segment(
            segments,
            speechBoundaries: speechBoundaries,
            diarizationSegments: nil,
            audioDuration: audioDuration,
            configuration: configuration
        )
    }

    static func segmentSystem(
        _ segments: [SpeechSegment],
        speechBoundaries: [VadSegment],
        diarizationSegments: [TimedSpeakerSegment]?,
        audioDuration: TimeInterval?,
        configuration: MeetilyStyleLiveTranscriptConfiguration = .default
    ) -> [SpeechSegment] {
        segment(
            segments,
            speechBoundaries: speechBoundaries,
            diarizationSegments: diarizationSegments,
            audioDuration: audioDuration,
            configuration: configuration
        )
    }

    private static func segment(
        _ segments: [SpeechSegment],
        speechBoundaries: [VadSegment],
        diarizationSegments: [TimedSpeakerSegment]?,
        audioDuration: TimeInterval?,
        configuration: MeetilyStyleLiveTranscriptConfiguration
    ) -> [SpeechSegment] {
        let cleanedSegments = sortedSegments(segments).filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !cleanedSegments.isEmpty else { return [] }

        let windows = turnWindows(
            speechBoundaries: speechBoundaries,
            diarizationSegments: diarizationSegments,
            audioDuration: audioDuration,
            configuration: configuration
        )
        guard !windows.isEmpty else { return cleanedSegments }

        let expandedSegments = cleanedSegments.enumerated().flatMap { index, segment in
            sentenceSegments(from: segment).map { IndexedSegment(originalIndex: index, segment: $0) }
        }

        var grouped: [Int: [IndexedSegment]] = [:]
        var unmatched: [IndexedSegment] = []

        for indexedSegment in expandedSegments {
            guard let windowIndex = bestWindowIndex(for: indexedSegment.segment, in: windows) else {
                unmatched.append(indexedSegment)
                continue
            }
            grouped[windowIndex, default: []].append(indexedSegment)
        }

        var output: [SpeechSegment] = []
        for (windowIndex, indexedSegments) in grouped {
            let ordered = indexedSegments.sorted { lhs, rhs in
                if lhs.segment.start == rhs.segment.start {
                    if lhs.originalIndex == rhs.originalIndex {
                        return lhs.segment.text < rhs.segment.text
                    }
                    return lhs.originalIndex < rhs.originalIndex
                }
                return lhs.segment.start < rhs.segment.start
            }
            let text = ordered.reduce("") { partialResult, indexedSegment in
                joinText(partialResult, indexedSegment.segment.text)
            }
            let window = windows[windowIndex]
            output.append(SpeechSegment(
                start: window.start,
                end: max(window.end, window.start + 0.05),
                text: text
            ))
        }

        output.append(contentsOf: unmatched.map(\.segment))
        return sortedSegments(output)
    }

    private static func turnWindows(
        speechBoundaries: [VadSegment],
        diarizationSegments: [TimedSpeakerSegment]?,
        audioDuration: TimeInterval?,
        configuration: MeetilyStyleLiveTranscriptConfiguration
    ) -> [BoundaryWindow] {
        let sampleRate = VadManager.sampleRate
        let additionalPostPad = max(0, configuration.postSpeechPad - configuration.preSpeechPad)
        let maxEnd = audioDuration ?? .greatestFiniteMagnitude

        let speechWindows = speechBoundaries.compactMap { segment -> BoundaryWindow? in
            guard segment.sampleCount(sampleRate: sampleRate) >= configuration.minimumSegmentSamples else {
                return nil
            }
            let start = max(0, segment.startTime)
            let end = min(maxEnd, segment.endTime + additionalPostPad)
            guard end > start else { return nil }
            return BoundaryWindow(start: start, end: end)
        }

        guard let diarizationSegments, !diarizationSegments.isEmpty else {
            return mergeOverlappingWindows(speechWindows)
        }

        let diarizedWindows = speechWindows.flatMap { speechWindow -> [BoundaryWindow] in
            let overlapping = diarizationSegments
                .sorted { $0.startTimeSeconds < $1.startTimeSeconds }
                .compactMap { diarizationSegment -> BoundaryWindow? in
                    let start = max(speechWindow.start, TimeInterval(diarizationSegment.startTimeSeconds))
                    let end = min(speechWindow.end, TimeInterval(diarizationSegment.endTimeSeconds))
                    guard end > start else { return nil }
                    return BoundaryWindow(start: start, end: end)
                }
            return overlapping.isEmpty ? [speechWindow] : overlapping
        }

        return diarizedWindows.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }
    }

    private static func mergeOverlappingWindows(_ windows: [BoundaryWindow]) -> [BoundaryWindow] {
        let ordered = windows.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }
        guard var current = ordered.first else { return [] }

        var merged: [BoundaryWindow] = []
        for window in ordered.dropFirst() {
            if window.start <= current.end {
                current = BoundaryWindow(start: current.start, end: max(current.end, window.end))
            } else {
                merged.append(current)
                current = window
            }
        }
        merged.append(current)
        return merged
    }

    private static func bestWindowIndex(
        for segment: SpeechSegment,
        in windows: [BoundaryWindow]
    ) -> Int? {
        let midpoint = (segment.start + segment.end) / 2

        let scored = windows.enumerated().map { index, window in
            let overlap = max(0, min(segment.end, window.end) - max(segment.start, window.start))
            let distance: TimeInterval
            if midpoint < window.start {
                distance = window.start - midpoint
            } else if midpoint > window.end {
                distance = midpoint - window.end
            } else {
                distance = 0
            }
            return (index: index, overlap: overlap, distance: distance)
        }

        if let bestOverlap = scored.max(by: { lhs, rhs in
            if lhs.overlap == rhs.overlap {
                return lhs.distance > rhs.distance
            }
            return lhs.overlap < rhs.overlap
        }), bestOverlap.overlap > 0 {
            return bestOverlap.index
        }

        return scored
            .filter { $0.distance <= 0.75 }
            .min { lhs, rhs in lhs.distance < rhs.distance }?
            .index
    }

    private static func sentenceSegments(from segment: SpeechSegment) -> [SpeechSegment] {
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let units = sentenceUnits(from: text)
        guard units.count > 1 else { return [SpeechSegment(start: segment.start, end: segment.end, text: text)] }

        let weights = units.map(visibleLength)
        let totalWeight = max(weights.reduce(0, +), 1)
        let totalDuration = max(segment.end - segment.start, 0.1)

        var cursor = segment.start
        var result: [SpeechSegment] = []

        for (index, unit) in units.enumerated() {
            let duration: TimeInterval
            if index == units.count - 1 {
                duration = max(segment.end - cursor, 0.05)
            } else {
                duration = max(totalDuration * (Double(weights[index]) / Double(totalWeight)), 0.05)
            }
            let end = min(segment.end, cursor + duration)
            result.append(SpeechSegment(start: cursor, end: max(end, cursor + 0.05), text: unit))
            cursor = end
        }

        return result
    }

    private static func sentenceUnits(from text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var units: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                units.append(String(sentence))
            }
            return true
        }

        return units.isEmpty ? [text] : units
    }

    private static func sortedSegments(_ segments: [SpeechSegment]) -> [SpeechSegment] {
        segments.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.text < rhs.text
            }
            return lhs.start < rhs.start
        }
    }

    private static func visibleLength(of text: String) -> Int {
        text.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + (CharacterSet.whitespacesAndNewlines.contains(scalar) ? 0 : 1)
        }
    }

    private static func joinText(_ lhs: String, _ rhs: String) -> String {
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
