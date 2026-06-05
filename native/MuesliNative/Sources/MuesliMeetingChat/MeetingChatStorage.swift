import Foundation

public struct MeetingChatThread: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let scope: MeetingChatScope
    public var title: String
    public var summary: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        scope: MeetingChatScope,
        title: String,
        summary: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.scope = scope
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MeetingChatThreadSnapshot: Equatable, Sendable {
    public let thread: MeetingChatThread
    public let messages: [MeetingChatMessage]

    public init(thread: MeetingChatThread, messages: [MeetingChatMessage]) {
        self.thread = thread
        self.messages = messages
    }
}

public protocol MeetingChatStoring: AnyObject {
    func loadThread(scope: MeetingChatScope, title: String) throws -> MeetingChatThreadSnapshot
    func appendMessage(_ message: MeetingChatMessage, to thread: MeetingChatThread) throws
    func clearThread(scope: MeetingChatScope) throws
}

public enum MeetingChatStorageError: LocalizedError, Equatable, Sendable {
    case database(String)
    case invalidScope(String, Int64)
    case invalidMessageRole(String)

    public var errorDescription: String? {
        switch self {
        case let .database(message):
            return "Meeting chat storage failed: \(message)"
        case let .invalidScope(kind, id):
            return "Meeting chat storage found an invalid scope: \(kind) \(id)."
        case let .invalidMessageRole(role):
            return "Meeting chat storage found an invalid message role: \(role)."
        }
    }
}
