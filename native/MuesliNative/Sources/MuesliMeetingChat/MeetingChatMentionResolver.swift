import Foundation
import MuesliCore

public enum MeetingChatMentionResolver {
    public static func matches(
        in text: String,
        meetings: [MeetingRecord]
    ) -> [MeetingChatSource] {
        let lowercased = text.lowercased()
        return meetings
            .filter { meeting in
                let title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return false }
                return lowercased.contains("@\(title.lowercased())")
            }
            .map { MeetingChatSource(meetingID: $0.id, title: $0.title, startTime: $0.startTime) }
    }

    public static func suggestions(
        for text: String,
        meetings: [MeetingRecord],
        limit: Int = 5
    ) -> [MeetingChatSource] {
        guard let token = activeToken(in: text) else { return [] }
        let query = token.lowercased()
        return meetings
            .filter { meeting in
                meeting.mergedIntoMeetingID == nil
                    && (query.isEmpty || meeting.title.lowercased().contains(query))
            }
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime { return lhs.id > rhs.id }
                return lhs.startTime > rhs.startTime
            }
            .prefix(limit)
            .map { MeetingChatSource(meetingID: $0.id, title: $0.title, startTime: $0.startTime) }
    }

    public static func replacingActiveToken(
        in text: String,
        with source: MeetingChatSource
    ) -> String {
        guard let range = activeTokenRange(in: text) else {
            return "\(text) @\(source.title) "
        }
        var updated = text
        updated.replaceSubrange(range, with: "@\(source.title) ")
        return updated
    }

    private static func activeToken(in text: String) -> String? {
        guard let range = activeTokenRange(in: text) else { return nil }
        let raw = text[range]
        return String(raw.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func activeTokenRange(in text: String) -> Range<String.Index>? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        let suffix = text[atIndex...]
        if suffix.contains("\n") { return nil }
        return atIndex..<text.endIndex
    }
}
