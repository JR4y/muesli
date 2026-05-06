import Foundation
import MuesliCore

enum MeetingMergeSummaryMode: Equatable, Sendable {
    case reSummarize
    case keepCurrentSummary
}

enum MeetingMergeCandidateBlockReason: Equatable, Sendable {
    case liveState
}

struct MeetingMergeCandidateOption: Identifiable, Sendable {
    let meeting: MeetingRecord
    let blockingReason: MeetingMergeCandidateBlockReason?

    var id: Int64 { meeting.id }
    var isMergeable: Bool { blockingReason == nil }
}

struct MeetingMergeDraft: Equatable, Sendable {
    let rawTranscript: String
    let manualNotes: String
    let appendedSummaryNotesBody: String?
    let shouldPromoteToCompleted: Bool
}

enum MeetingMergeSupport {
    static func relatedMeetings(
        for target: MeetingRecord,
        from meetings: [MeetingRecord]
    ) -> [MeetingMergeCandidateOption] {
        guard let normalizedID = MuesliController.normalizedCalendarEventID(target.calendarEventID) else {
            return []
        }

        return meetings
            .filter { candidate in
                candidate.id != target.id
                    && MuesliController.normalizedCalendarEventID(candidate.calendarEventID) == normalizedID
            }
            .map { candidate in
                MeetingMergeCandidateOption(
                    meeting: candidate,
                    blockingReason: (candidate.status == .recording || candidate.status == .processing) ? .liveState : nil
                )
            }
            .sorted { lhs, rhs in
                let lhsDate = MeetingBrowserLogic.parseDate(lhs.meeting.startTime) ?? .distantPast
                let rhsDate = MeetingBrowserLogic.parseDate(rhs.meeting.startTime) ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.meeting.id < rhs.meeting.id
                }
                return lhsDate < rhsDate
            }
    }

    static func mergeCandidates(
        for target: MeetingRecord,
        from meetings: [MeetingRecord]
    ) -> [MeetingRecord] {
        relatedMeetings(for: target, from: meetings)
            .filter(\.isMergeable)
            .map(\.meeting)
    }

    static func makeDraft(
        target: MeetingRecord,
        sources: [MeetingRecord]
    ) -> MeetingMergeDraft {
        let meetings = ([target] + sources).sorted { lhs, rhs in
            let lhsDate = MeetingBrowserLogic.parseDate(lhs.startTime) ?? .distantPast
            let rhsDate = MeetingBrowserLogic.parseDate(rhs.startTime) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.id < rhs.id
            }
            return lhsDate < rhsDate
        }

        let rawTranscript = meetings
            .map(\.rawTranscript)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let manualNoteSections = meetings.compactMap { meeting -> String? in
            let trimmed = meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return "### \(meeting.title)\n\n\(trimmed)"
        }
        let manualNotes = manualNoteSections.joined(separator: "\n\n")

        let importedSources = sources.sorted { lhs, rhs in
            let lhsDate = MeetingBrowserLogic.parseDate(lhs.startTime) ?? .distantPast
            let rhsDate = MeetingBrowserLogic.parseDate(rhs.startTime) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.id < rhs.id
            }
            return lhsDate < rhsDate
        }
        let importedManualSection = importedSources.compactMap { source -> String? in
            let trimmed = source.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return "### \(source.title)\n\n\(trimmed)"
        }
        let appendedSummaryNotesBody = importedManualSection.isEmpty
            ? nil
            : importedManualSection.joined(separator: "\n\n")

        return MeetingMergeDraft(
            rawTranscript: rawTranscript,
            manualNotes: manualNotes,
            appendedSummaryNotesBody: appendedSummaryNotesBody,
            shouldPromoteToCompleted: !rawTranscript.isEmpty
        )
    }
}
