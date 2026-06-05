import CryptoKit
import Foundation
import MuesliMeetingChat

enum MeetingChatSyncEntityKind: String, CaseIterable, Sendable {
    case thread
    case message
}

struct MeetingChatSyncMetadataRecord: Sendable, Equatable {
    let entityKind: MeetingChatSyncEntityKind
    let localID: String
    let remoteID: String?
    let clientUpdatedAt: String
    let remoteVersion: Int64
    let lastSeenServerUpdatedAt: String?
    let lastPayloadHash: String?
    let dirty: Bool
    let lastWriterDeviceID: String?
}

struct MeetingChatSyncTombstoneRecord: Sendable, Equatable {
    let entityKind: MeetingChatSyncEntityKind
    let localID: String
    let remoteID: String?
    let clientDeletedAt: String
    let lastKnownRemoteVersion: Int64
    let dirty: Bool
}

struct DirtyMeetingChatThread: Sendable {
    let metadata: MeetingChatSyncMetadataRecord
    let thread: MeetingChatThread
    let scopeKind: String
    let scopeRemoteID: String?
}

struct DirtyMeetingChatMessage: Sendable {
    let metadata: MeetingChatSyncMetadataRecord
    let message: MeetingChatMessage
    let threadLocalID: UUID
    let threadRemoteID: String?
}

struct RemoteMeetingChatThreadPayload: Sendable, Equatable {
    let remoteID: String
    let scopeKind: String
    let scopeRemoteID: String
    let title: String
    let summary: String
    let clientUpdatedAt: String
    let serverUpdatedAt: String
    let remoteVersion: Int64
    let lastWriterDeviceID: String
    let deletedAt: String?
}

struct RemoteMeetingChatMessagePayload: Sendable, Equatable {
    let remoteID: String
    let threadRemoteID: String
    let role: MeetingChatRole
    let content: String
    let sources: [MeetingChatSource]
    let createdAt: String
    let clientUpdatedAt: String
    let serverUpdatedAt: String
    let remoteVersion: Int64
    let lastWriterDeviceID: String
    let deletedAt: String?
}

enum MeetingChatSyncHasher {
    static func threadHash(
        scopeKind: String,
        scopeRemoteID: String,
        title: String,
        summary: String
    ) -> String {
        hash([
            "scope_kind": scopeKind,
            "scope_remote_id": scopeRemoteID,
            "title": title,
            "summary": summary,
        ])
    }

    static func messageHash(
        role: MeetingChatRole,
        content: String,
        sources: [MeetingChatSource],
        createdAt: String
    ) -> String {
        let sourcesCanonical = sources.map { source in
            [
                "meetingID=\(source.meetingID)",
                "startTime=\(source.startTime)",
                "title=\(source.title)",
            ].joined(separator: "\n")
        }.joined(separator: "\n---\n")
        return hash([
            "role": role.rawValue,
            "content": content,
            "sources": sourcesCanonical,
            "created_at": createdAt,
        ])
    }

    private static func hash(_ object: [String: String]) -> String {
        let ordered = object.keys.sorted().map { "\($0)=\(object[$0] ?? "")" }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(ordered.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
