import Foundation
import MuesliCore

public enum MeetingChatContextBuilder {
    private static let maxFolderMeetings = 12
    private static let maxNotesCharactersPerMeeting = 4_000
    private static let maxTranscriptCharacters = 10_000

    public static func build(
        scope: MeetingChatScope,
        question: String,
        meetings: [MeetingRecord],
        folders: [MeetingFolder],
        options: MeetingChatContextOptions = MeetingChatContextOptions()
    ) -> MeetingChatContextBundle {
        switch scope {
        case let .meeting(id):
            return buildMeetingContext(id: id, question: question, meetings: meetings, options: options)
        case let .folder(id):
            return buildFolderContext(id: id, question: question, meetings: meetings, folders: folders, options: options)
        }
    }

    private static func buildMeetingContext(
        id: Int64,
        question: String,
        meetings: [MeetingRecord],
        options: MeetingChatContextOptions
    ) -> MeetingChatContextBundle {
        guard let meeting = meetings.first(where: { $0.id == id && $0.mergedIntoMeetingID == nil }) else {
            return MeetingChatContextBundle(scope: .meeting(id), prompt: "", sources: [])
        }

        let prompt = meetingBlock(
            meeting,
            includeTranscript: options.includeTranscriptMeetingIDs.contains(meeting.id)
                || shouldIncludeTranscript(for: question, meeting: meeting)
        )
        let source = MeetingChatSource(meetingID: meeting.id, title: meeting.title, startTime: meeting.startTime)
        return MeetingChatContextBundle(scope: .meeting(id), prompt: prompt, sources: [source])
    }

    private static func buildFolderContext(
        id: Int64,
        question: String,
        meetings: [MeetingRecord],
        folders: [MeetingFolder],
        options: MeetingChatContextOptions
    ) -> MeetingChatContextBundle {
        guard let folder = folders.first(where: { $0.id == id }) else {
            return MeetingChatContextBundle(scope: .folder(id), prompt: "", sources: [])
        }

        let allowedFolderIDs = descendantFolderIDs(rootID: id, folders: folders).union([id])
        let sortedMeetings = meetings
            .filter { meeting in
                guard meeting.mergedIntoMeetingID == nil, let folderID = meeting.folderID else { return false }
                return allowedFolderIDs.contains(folderID)
            }
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime { return lhs.id > rhs.id }
                return lhs.startTime > rhs.startTime
            }
        let referencedMeetings = sortedMeetings.filter { options.referencedMeetingIDs.contains($0.id) }
        let recentMeetings = sortedMeetings.filter { !options.referencedMeetingIDs.contains($0.id) }
        let scopedMeetings = Array((referencedMeetings + recentMeetings).prefix(maxFolderMeetings))

        guard !scopedMeetings.isEmpty else {
            return MeetingChatContextBundle(scope: .folder(id), prompt: "", sources: [])
        }

        var sections = ["Folder: \(folder.name)"]
        var sources: [MeetingChatSource] = []
        for meeting in scopedMeetings {
            sections.append(
                meetingBlock(
                    meeting,
                    includeTranscript: options.includeTranscriptMeetingIDs.contains(meeting.id)
                )
            )
            sources.append(MeetingChatSource(meetingID: meeting.id, title: meeting.title, startTime: meeting.startTime))
        }
        return MeetingChatContextBundle(scope: .folder(id), prompt: sections.joined(separator: "\n\n---\n\n"), sources: sources)
    }

    private static func meetingBlock(_ meeting: MeetingRecord, includeTranscript: Bool) -> String {
        var lines = [
            "Meeting: \(meeting.title)",
            "ID: \(meeting.id)",
            "Date: \(meeting.startTime)"
        ]

        let notes = meeting.formattedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines.append("Notes:\n\(limited(notes, maxCharacters: maxNotesCharactersPerMeeting))")
        }

        let manualNotes = meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manualNotes.isEmpty {
            lines.append("User-written notes:\n\(limited(manualNotes, maxCharacters: maxNotesCharactersPerMeeting))")
        }

        let transcript = meeting.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if includeTranscript, !transcript.isEmpty {
            lines.append("Transcript excerpt:\n\(limited(transcript, maxCharacters: maxTranscriptCharacters))")
        }

        return lines.joined(separator: "\n\n")
    }

    private static func shouldIncludeTranscript(for question: String, meeting: MeetingRecord) -> Bool {
        let notes = meeting.formattedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.isEmpty {
            return true
        }
        let lowercased = question.lowercased()
        let detailTerms = [
            "detail", "details", "exact", "quote", "said", "mention", "mentioned",
            "transcript", "pricing", "detalle", "detalles", "exacto", "cita",
            "dijo", "mencion", "menciono", "mencionó", "transcripción"
        ]
        return detailTerms.contains { lowercased.contains($0) }
    }

    private static func descendantFolderIDs(rootID: Int64, folders: [MeetingFolder]) -> Set<Int64> {
        var descendants = Set<Int64>()
        var pending = [rootID]
        while let current = pending.popLast() {
            for folder in folders where folder.parentFolderID == current && descendants.insert(folder.id).inserted {
                pending.append(folder.id)
            }
        }
        return descendants
    }

    private static func limited(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        return String(text.prefix(maxCharacters)) + "\n[truncated]"
    }
}
