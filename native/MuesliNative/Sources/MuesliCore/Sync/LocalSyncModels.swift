import Foundation

public enum SyncEntityType: String, Sendable, CaseIterable, Codable {
    case dictation
    case meeting
    case folder

    public var domainTableName: String {
        switch self {
        case .dictation: return "dictations"
        case .meeting: return "meetings"
        case .folder: return "meeting_folders"
        }
    }

    public var remoteTableName: String {
        switch self {
        case .dictation: return "dictations"
        case .meeting: return "meetings"
        case .folder: return "meeting_folders"
        }
    }
}

public struct SyncMetadataRecord: Sendable, Equatable {
    public let entityType: SyncEntityType
    public let localID: Int64
    public let remoteID: String?
    public let clientUpdatedAt: String
    public let remoteVersion: Int64
    public let lastSeenServerUpdatedAt: String?
    public let lastPayloadHash: String?
    public let dirty: Bool
    public let lastWriterDeviceID: String?

    public init(
        entityType: SyncEntityType,
        localID: Int64,
        remoteID: String?,
        clientUpdatedAt: String,
        remoteVersion: Int64,
        lastSeenServerUpdatedAt: String?,
        lastPayloadHash: String?,
        dirty: Bool,
        lastWriterDeviceID: String?
    ) {
        self.entityType = entityType
        self.localID = localID
        self.remoteID = remoteID
        self.clientUpdatedAt = clientUpdatedAt
        self.remoteVersion = remoteVersion
        self.lastSeenServerUpdatedAt = lastSeenServerUpdatedAt
        self.lastPayloadHash = lastPayloadHash
        self.dirty = dirty
        self.lastWriterDeviceID = lastWriterDeviceID
    }
}

public struct SyncTombstoneRecord: Sendable, Equatable {
    public let entityType: SyncEntityType
    public let localID: Int64
    public let remoteID: String?
    public let clientDeletedAt: String
    public let lastKnownRemoteVersion: Int64
    public let dirty: Bool

    public init(
        entityType: SyncEntityType,
        localID: Int64,
        remoteID: String?,
        clientDeletedAt: String,
        lastKnownRemoteVersion: Int64,
        dirty: Bool
    ) {
        self.entityType = entityType
        self.localID = localID
        self.remoteID = remoteID
        self.clientDeletedAt = clientDeletedAt
        self.lastKnownRemoteVersion = lastKnownRemoteVersion
        self.dirty = dirty
    }
}

public struct SyncCursor: Sendable, Codable, Equatable {
    public let serverUpdatedAt: String
    public let id: String

    public init(serverUpdatedAt: String, id: String) {
        self.serverUpdatedAt = serverUpdatedAt
        self.id = id
    }
}

/// Sync-relevant slice of `AppConfig`. Built by the App layer; stored opaquely
/// here so MuesliCore does not depend on AppConfig types.
public struct SyncPreferencesSnapshot: Sendable, Equatable, Codable {
    public var customMeetingTemplatesJSON: String
    public var hiddenBuiltInTemplateIDs: [String]
    public var customWordsJSON: String
    public var defaultMeetingTemplateID: String
    public var autoTemplateTargetID: String
    public var meetingTitlePrompt: String
    public var folderOrderRemoteIDs: [String]

    public init(
        customMeetingTemplatesJSON: String,
        hiddenBuiltInTemplateIDs: [String],
        customWordsJSON: String,
        defaultMeetingTemplateID: String,
        autoTemplateTargetID: String,
        meetingTitlePrompt: String,
        folderOrderRemoteIDs: [String]
    ) {
        self.customMeetingTemplatesJSON = customMeetingTemplatesJSON
        self.hiddenBuiltInTemplateIDs = hiddenBuiltInTemplateIDs
        self.customWordsJSON = customWordsJSON
        self.defaultMeetingTemplateID = defaultMeetingTemplateID
        self.autoTemplateTargetID = autoTemplateTargetID
        self.meetingTitlePrompt = meetingTitlePrompt
        self.folderOrderRemoteIDs = folderOrderRemoteIDs
    }

    public static let empty = SyncPreferencesSnapshot(
        customMeetingTemplatesJSON: "[]",
        hiddenBuiltInTemplateIDs: [],
        customWordsJSON: "[]",
        defaultMeetingTemplateID: "auto",
        autoTemplateTargetID: "",
        meetingTitlePrompt: "",
        folderOrderRemoteIDs: []
    )
}

/// Snapshot of preferences sync state stored in `sync_state`.
public struct SyncPreferencesState: Sendable, Equatable {
    public var dirty: Bool
    public var remoteVersion: Int64
    public var clientUpdatedAt: String?
    public var lastSeenServerUpdatedAt: String?
    public var lastPayloadHash: String?
    public var lastWriterDeviceID: String?

    public init(
        dirty: Bool,
        remoteVersion: Int64,
        clientUpdatedAt: String?,
        lastSeenServerUpdatedAt: String?,
        lastPayloadHash: String?,
        lastWriterDeviceID: String?
    ) {
        self.dirty = dirty
        self.remoteVersion = remoteVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.lastSeenServerUpdatedAt = lastSeenServerUpdatedAt
        self.lastPayloadHash = lastPayloadHash
        self.lastWriterDeviceID = lastWriterDeviceID
    }

    public static let empty = SyncPreferencesState(
        dirty: false,
        remoteVersion: 0,
        clientUpdatedAt: nil,
        lastSeenServerUpdatedAt: nil,
        lastPayloadHash: nil,
        lastWriterDeviceID: nil
    )
}

/// A dirty domain row paired with its sync metadata. The App layer reads these
/// to build upload payloads.
public struct DirtyDictation: Sendable {
    public let metadata: SyncMetadataRecord
    public let record: DictationRecord

    public init(metadata: SyncMetadataRecord, record: DictationRecord) {
        self.metadata = metadata
        self.record = record
    }
}

public struct DirtyMeeting: Sendable {
    public let metadata: SyncMetadataRecord
    public let record: MeetingRecord
    public let folderRemoteID: String?
    public let mergedIntoMeetingRemoteID: String?

    public init(
        metadata: SyncMetadataRecord,
        record: MeetingRecord,
        folderRemoteID: String?,
        mergedIntoMeetingRemoteID: String? = nil
    ) {
        self.metadata = metadata
        self.record = record
        self.folderRemoteID = folderRemoteID
        self.mergedIntoMeetingRemoteID = mergedIntoMeetingRemoteID
    }
}

public struct DirtyFolder: Sendable {
    public let metadata: SyncMetadataRecord
    public let record: MeetingFolder
    public let parentRemoteID: String?

    public init(metadata: SyncMetadataRecord, record: MeetingFolder, parentRemoteID: String?) {
        self.metadata = metadata
        self.record = record
        self.parentRemoteID = parentRemoteID
    }
}

/// Remote payload shapes the App layer hands to `LocalSyncRepository.applyRemote*`.
public struct RemoteFolderPayload: Sendable {
    public let remoteID: String
    public let parentRemoteID: String?
    public let name: String
    public let colorHex: String?
    public let iconName: String?
    public let sortOrder: Int
    public let clientUpdatedAt: String
    public let serverUpdatedAt: String
    public let remoteVersion: Int64
    public let lastWriterDeviceID: String
    public let deletedAt: String?

    public init(
        remoteID: String,
        parentRemoteID: String?,
        name: String,
        colorHex: String?,
        iconName: String?,
        sortOrder: Int,
        clientUpdatedAt: String,
        serverUpdatedAt: String,
        remoteVersion: Int64,
        lastWriterDeviceID: String,
        deletedAt: String?
    ) {
        self.remoteID = remoteID
        self.parentRemoteID = parentRemoteID
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.clientUpdatedAt = clientUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.remoteVersion = remoteVersion
        self.lastWriterDeviceID = lastWriterDeviceID
        self.deletedAt = deletedAt
    }
}

public struct RemoteDictationPayload: Sendable {
    public let remoteID: String
    public let timestamp: String
    public let durationSeconds: Double
    public let rawText: String
    public let appContext: String
    public let wordCount: Int
    public let source: String
    public let startedAt: String?
    public let endedAt: String?
    public let clientUpdatedAt: String
    public let serverUpdatedAt: String
    public let remoteVersion: Int64
    public let lastWriterDeviceID: String
    public let deletedAt: String?

    public init(
        remoteID: String,
        timestamp: String,
        durationSeconds: Double,
        rawText: String,
        appContext: String,
        wordCount: Int,
        source: String,
        startedAt: String?,
        endedAt: String?,
        clientUpdatedAt: String,
        serverUpdatedAt: String,
        remoteVersion: Int64,
        lastWriterDeviceID: String,
        deletedAt: String?
    ) {
        self.remoteID = remoteID
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.rawText = rawText
        self.appContext = appContext
        self.wordCount = wordCount
        self.source = source
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.clientUpdatedAt = clientUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.remoteVersion = remoteVersion
        self.lastWriterDeviceID = lastWriterDeviceID
        self.deletedAt = deletedAt
    }
}

public struct RemoteMeetingPayload: Sendable {
    public let remoteID: String
    public let folderRemoteID: String?
    public let mergedIntoMeetingRemoteID: String?
    public let title: String
    public let calendarEventID: String?
    public let calendarEventSnapshotJSON: String?
    public let startTime: String
    public let endTime: String?
    public let durationSeconds: Double?
    public let rawTranscript: String
    public let formattedNotes: String
    public let meetingStatus: String
    public let manualNotes: String
    public let wordCount: Int
    public let selectedTemplateID: String?
    public let selectedTemplateName: String?
    public let selectedTemplateKind: String?
    public let selectedTemplatePrompt: String?
    public let clientUpdatedAt: String
    public let serverUpdatedAt: String
    public let remoteVersion: Int64
    public let lastWriterDeviceID: String
    public let deletedAt: String?

    public init(
        remoteID: String,
        folderRemoteID: String?,
        mergedIntoMeetingRemoteID: String? = nil,
        title: String,
        calendarEventID: String?,
        calendarEventSnapshotJSON: String?,
        startTime: String,
        endTime: String?,
        durationSeconds: Double?,
        rawTranscript: String,
        formattedNotes: String,
        meetingStatus: String,
        manualNotes: String,
        wordCount: Int,
        selectedTemplateID: String?,
        selectedTemplateName: String?,
        selectedTemplateKind: String?,
        selectedTemplatePrompt: String?,
        clientUpdatedAt: String,
        serverUpdatedAt: String,
        remoteVersion: Int64,
        lastWriterDeviceID: String,
        deletedAt: String?
    ) {
        self.remoteID = remoteID
        self.folderRemoteID = folderRemoteID
        self.mergedIntoMeetingRemoteID = mergedIntoMeetingRemoteID
        self.title = title
        self.calendarEventID = calendarEventID
        self.calendarEventSnapshotJSON = calendarEventSnapshotJSON
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.rawTranscript = rawTranscript
        self.formattedNotes = formattedNotes
        self.meetingStatus = meetingStatus
        self.manualNotes = manualNotes
        self.wordCount = wordCount
        self.selectedTemplateID = selectedTemplateID
        self.selectedTemplateName = selectedTemplateName
        self.selectedTemplateKind = selectedTemplateKind
        self.selectedTemplatePrompt = selectedTemplatePrompt
        self.clientUpdatedAt = clientUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.remoteVersion = remoteVersion
        self.lastWriterDeviceID = lastWriterDeviceID
        self.deletedAt = deletedAt
    }
}

public struct RemotePreferencesPayload: Sendable {
    public let snapshot: SyncPreferencesSnapshot
    public let clientUpdatedAt: String
    public let serverUpdatedAt: String
    public let remoteVersion: Int64
    public let lastWriterDeviceID: String

    public init(
        snapshot: SyncPreferencesSnapshot,
        clientUpdatedAt: String,
        serverUpdatedAt: String,
        remoteVersion: Int64,
        lastWriterDeviceID: String
    ) {
        self.snapshot = snapshot
        self.clientUpdatedAt = clientUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.remoteVersion = remoteVersion
        self.lastWriterDeviceID = lastWriterDeviceID
    }
}

public enum SyncStateKey: String {
    case deviceID = "device_id"
    case preferencesDirty = "preferences_dirty"
    case preferencesRemoteVersion = "preferences_remote_version"
    case preferencesClientUpdatedAt = "preferences_client_updated_at"
    case preferencesLastSeenServerUpdatedAt = "preferences_last_seen_server_updated_at"
    case preferencesLastPayloadHash = "preferences_last_payload_hash"
    case preferencesLastWriterDeviceID = "preferences_last_writer_device_id"
    case pullCursorDictations = "pull_cursor:dictations"
    case pullCursorMeetings = "pull_cursor:meetings"
    case pullCursorMeetingFolders = "pull_cursor:meeting_folders"
    case pullCursorUserPreferences = "pull_cursor:user_preferences"
}

public enum SyncTimestamp {
    /// ISO8601 with milliseconds in UTC, matching the format the SQLite triggers
    /// produce via `strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`.
    public static func now() -> String {
        format(Date())
    }

    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
