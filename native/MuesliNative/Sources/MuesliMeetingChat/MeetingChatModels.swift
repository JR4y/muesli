import Foundation

public enum MeetingChatScope: Hashable, Sendable {
    case meeting(Int64)
    case folder(Int64)
}

public enum MeetingChatRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case error
}

public struct MeetingChatSource: Codable, Equatable, Sendable {
    public let meetingID: Int64
    public let title: String
    public let startTime: String

    public init(meetingID: Int64, title: String, startTime: String) {
        self.meetingID = meetingID
        self.title = title
        self.startTime = startTime
    }
}

public struct MeetingChatMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let role: MeetingChatRole
    public var text: String
    public var sources: [MeetingChatSource]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: MeetingChatRole,
        text: String,
        sources: [MeetingChatSource] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.sources = sources
        self.createdAt = createdAt
    }
}

public struct MeetingChatContextBundle: Equatable, Sendable {
    public let scope: MeetingChatScope
    public let prompt: String
    public let sources: [MeetingChatSource]

    public init(scope: MeetingChatScope, prompt: String, sources: [MeetingChatSource]) {
        self.scope = scope
        self.prompt = prompt
        self.sources = sources
    }

    public var isEmpty: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sources.isEmpty
    }
}

public struct MeetingChatContextOptions: Equatable, Sendable {
    public var referencedMeetingIDs: Set<Int64>
    public var includeTranscriptMeetingIDs: Set<Int64>

    public init(
        referencedMeetingIDs: Set<Int64> = [],
        includeTranscriptMeetingIDs: Set<Int64> = []
    ) {
        self.referencedMeetingIDs = referencedMeetingIDs
        self.includeTranscriptMeetingIDs = includeTranscriptMeetingIDs
    }
}

public struct MeetingChatRequest: Equatable, Sendable {
    public let question: String
    public let context: MeetingChatContextBundle
    public let priorMessages: [MeetingChatMessage]
    public let memorySummary: String?

    public init(
        question: String,
        context: MeetingChatContextBundle,
        priorMessages: [MeetingChatMessage] = [],
        memorySummary: String? = nil
    ) {
        self.question = question
        self.context = context
        self.priorMessages = priorMessages
        self.memorySummary = memorySummary
    }
}

public struct MeetingChatMemory: Equatable, Sendable {
    public let summary: String?
    public let recentMessages: [MeetingChatMessage]

    public init(summary: String?, recentMessages: [MeetingChatMessage]) {
        self.summary = summary
        self.recentMessages = recentMessages
    }
}

public enum MeetingChatMemoryPolicy {
    public static let defaultRecentLimit = 8

    public static func memory(
        messages: [MeetingChatMessage],
        summary: String?,
        recentLimit: Int = defaultRecentLimit,
        maxDerivedSummaryCharacters: Int = 2_000
    ) -> MeetingChatMemory {
        let limit = max(0, recentLimit)
        let sorted = messages.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt == rhs.element.createdAt {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.createdAt < rhs.element.createdAt
            }
            .map(\.element)
        let recent = limit == 0 ? [] : Array(sorted.suffix(limit))
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSummary: String?
        if let trimmedSummary, !trimmedSummary.isEmpty {
            effectiveSummary = trimmedSummary
        } else {
            effectiveSummary = derivedSummary(
                from: Array(sorted.dropLast(recent.count)),
                maxCharacters: maxDerivedSummaryCharacters
            )
        }
        return MeetingChatMemory(
            summary: sorted.count > recent.count ? effectiveSummary : nil,
            recentMessages: recent
        )
    }

    private static func derivedSummary(
        from messages: [MeetingChatMessage],
        maxCharacters: Int
    ) -> String? {
        guard !messages.isEmpty, maxCharacters > 0 else { return nil }
        let transcript = messages
            .map { "\($0.role.rawValue): \($0.text)" }
            .joined(separator: "\n")
        guard transcript.count > maxCharacters else { return transcript }
        return String(transcript.prefix(maxCharacters)) + "\n[truncated]"
    }
}

public struct MeetingChatProviderResponse: Equatable, Sendable {
    public let text: String
    public let sources: [MeetingChatSource]

    public init(text: String, sources: [MeetingChatSource] = []) {
        self.text = text
        self.sources = sources
    }
}

public enum MeetingChatError: LocalizedError, Equatable, Sendable {
    case noContext
    case noAvailableProvider
    case providerFailed(String)
    case emptyResponse(String)

    public var errorDescription: String? {
        switch self {
        case .noContext:
            return "No meeting context is available for this chat."
        case .noAvailableProvider:
            return "No AI provider is available. Sign in to ChatGPT or configure a meeting summary provider."
        case let .providerFailed(message):
            return message
        case let .emptyResponse(provider):
            return "\(provider) returned an empty chat response."
        }
    }
}
