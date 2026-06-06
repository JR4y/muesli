import Foundation
import MuesliCore

/// Bridge that lets the actor-isolated SyncManager read and write the user's
/// preferences without importing AppConfig. Closures are MainActor-isolated.
struct SupabasePreferencesBridge: Sendable {
    var snapshot: @MainActor @Sendable () -> SyncPreferencesSnapshot
    var applyRemoteSnapshot: @MainActor @Sendable (SyncPreferencesSnapshot) -> Void
}

enum SupabaseSyncStatus: Sendable, Equatable {
    case idle
    case syncing(reason: String)
    case error(message: String)
    case waitingForAuth
}

@MainActor
@Observable
final class SupabaseSyncStateObserver {
    private(set) var status: SupabaseSyncStatus = .idle
    private(set) var lastSyncAt: Date?
    private(set) var lastErrorMessage: String?
    private(set) var syncedFolderCount: Int = 0
    private(set) var syncedDictationCount: Int = 0
    private(set) var syncedMeetingCount: Int = 0

    func update(
        status: SupabaseSyncStatus? = nil,
        lastSyncAt: Date? = nil,
        lastErrorMessage: String?? = nil,
        syncedFolderCount: Int? = nil,
        syncedDictationCount: Int? = nil,
        syncedMeetingCount: Int? = nil
    ) {
        if let status { self.status = status }
        if let lastSyncAt { self.lastSyncAt = lastSyncAt }
        if let lastErrorMessage { self.lastErrorMessage = lastErrorMessage }
        if let syncedFolderCount { self.syncedFolderCount = syncedFolderCount }
        if let syncedDictationCount { self.syncedDictationCount = syncedDictationCount }
        if let syncedMeetingCount { self.syncedMeetingCount = syncedMeetingCount }
    }
}

/// Top-level orchestrator for Supabase sync. Serializes all sync work in a
/// single actor so cycles cannot overlap. Schedules cycles via debounced
/// triggers, a 5-minute heartbeat, and explicit `syncNow(reason:)` calls.
actor SupabaseSyncManager {
    private let repo: LocalSyncRepository
    private let chatRepo: MeetingChatSyncRepository
    private let auth: SupabaseAuthManager
    private let rest: SupabaseRESTClient?
    private let preferencesBridge: SupabasePreferencesBridge
    private let observer: SupabaseSyncStateObserver
    private let pageSize: Int = 100

    private var debounceTask: Task<Void, Never>?
    private var preferencesDebounceTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var inflightSync: Task<Void, Never>?
    private var cachedDeviceID: String?

    init(
        repo: LocalSyncRepository,
        chatRepo: MeetingChatSyncRepository,
        auth: SupabaseAuthManager,
        rest: SupabaseRESTClient?,
        preferencesBridge: SupabasePreferencesBridge,
        observer: SupabaseSyncStateObserver
    ) {
        self.repo = repo
        self.chatRepo = chatRepo
        self.auth = auth
        self.rest = rest
        self.preferencesBridge = preferencesBridge
        self.observer = observer
    }

    var isConfigured: Bool { rest != nil }

    // MARK: - Lifecycle

    func start() async {
        if heartbeatTask != nil { return }
        do {
            try repo.migrateIfNeeded()
            try chatRepo.migrateIfNeeded()
            cachedDeviceID = try repo.ensureDeviceID()
            let preferencesState = try repo.loadPreferencesState()
            if preferencesState.remoteVersion == 0, preferencesState.clientUpdatedAt == nil {
                try repo.markPreferencesDirty()
            }
        } catch {
            await reportError("Failed to bootstrap sync: \(error.localizedDescription)")
            return
        }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000) // 5 minutes
                if Task.isCancelled { break }
                await self?.syncNow(reason: "heartbeat")
            }
        }
        await syncNow(reason: "launch")
    }

    func shutdown() async {
        debounceTask?.cancel()
        preferencesDebounceTask?.cancel()
        heartbeatTask?.cancel()
        debounceTask = nil
        preferencesDebounceTask = nil
        heartbeatTask = nil
        // Best-effort short final sync — only if we are mid-cycle, the inflight
        // task will finish on its own; we don't await it here to avoid blocking
        // app termination.
    }

    // MARK: - Triggers

    func notifyPotentialLocalDataChange() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            if Task.isCancelled { return }
            await self?.syncNow(reason: "data-change")
        }
    }

    func notifyPreferencesChanged() {
        preferencesDebounceTask?.cancel()
        preferencesDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            if Task.isCancelled { return }
            await self?.syncNow(reason: "preferences-change")
        }
    }

    // MARK: - Sync entry point

    func syncNow(reason: String) async {
        guard let rest, let userID = await auth.userID, await auth.isAuthenticated else {
            await observer.update(status: .waitingForAuth)
            return
        }
        if let inflight = inflightSync {
            // Coalesce: wait for in-flight to finish, then run again.
            await inflight.value
        }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.runCycle(reason: reason, rest: rest, userID: userID)
        }
        inflightSync = task
        await task.value
        inflightSync = nil
    }

    func purgeDeletedSyncRowsNow() async throws {
        guard let rest, await auth.isAuthenticated else {
            await observer.update(status: .waitingForAuth)
            throw SupabaseRESTError.unauthorized
        }
        if let inflight = inflightSync {
            await inflight.value
        }
        await observer.update(status: .syncing(reason: "purge-deleted"))
        do {
            try await rest.purgeDeletedSyncRows()
            await observer.update(
                status: .idle,
                lastSyncAt: Date(),
                lastErrorMessage: .some(nil)
            )
        } catch SupabaseRESTError.unauthorized {
            await observer.update(status: .waitingForAuth)
            throw SupabaseRESTError.unauthorized
        } catch {
            await reportError(error.localizedDescription)
            throw error
        }
    }

    private func runCycle(reason: String, rest: SupabaseRESTClient, userID: String) async {
        await observer.update(status: .syncing(reason: reason))
        do {
            try await downloadFolders(rest: rest)
            try await downloadPreferences(rest: rest, userID: userID)
            try await downloadDictations(rest: rest)
            try await downloadMeetings(rest: rest)
            try await downloadMeetingChatThreads(rest: rest)
            try await downloadMeetingChatMessages(rest: rest)

            try await uploadFolders(rest: rest, userID: userID)
            try await uploadDictations(rest: rest, userID: userID)
            try await uploadMeetings(rest: rest, userID: userID)
            try await uploadMeetingChatThreads(rest: rest, userID: userID)
            try await uploadMeetingChatMessages(rest: rest, userID: userID)
            try await uploadPreferences(rest: rest, userID: userID)
            try await uploadTombstones(rest: rest, entityType: .meeting)
            try await uploadTombstones(rest: rest, entityType: .dictation)
            try await uploadTombstones(rest: rest, entityType: .folder)
            try await uploadMeetingChatTombstones(rest: rest, userID: userID, entityKind: .message)
            try await uploadMeetingChatTombstones(rest: rest, userID: userID, entityKind: .thread)

            try repo.purgeCleanTombstones(olderThanDays: 30)

            await observer.update(
                status: .idle,
                lastSyncAt: Date(),
                lastErrorMessage: .some(nil)
            )
        } catch SupabaseRESTError.unauthorized {
            await observer.update(status: .waitingForAuth)
        } catch {
            await reportError(error.localizedDescription)
        }
    }

    // MARK: - Download paths

    private func downloadFolders(rest: SupabaseRESTClient) async throws {
        let cursor = try repo.loadCursor(for: .folder)
        var current = cursor
        while true {
            let rows = try await rest.selectFolders(after: current, limit: pageSize)
            if rows.isEmpty { break }
            for row in rows {
                try await applyRemoteFolder(row, rest: rest)
            }
            current = SyncCursor(serverUpdatedAt: rows.last!.serverUpdatedAt, id: rows.last!.remoteID)
            try repo.saveCursor(current!, for: .folder)
            if rows.count < pageSize { break }
        }
        let total = try repo.dirtyFolders(limit: 1).count
        await observer.update(syncedFolderCount: try countMetadata(.folder))
        _ = total
    }

    private func downloadDictations(rest: SupabaseRESTClient) async throws {
        var current = try repo.loadCursor(for: .dictation)
        while true {
            let rows = try await rest.selectDictations(after: current, limit: pageSize)
            if rows.isEmpty { break }
            for row in rows {
                try await applyRemoteDictation(row)
            }
            current = SyncCursor(serverUpdatedAt: rows.last!.serverUpdatedAt, id: rows.last!.remoteID)
            try repo.saveCursor(current!, for: .dictation)
            if rows.count < pageSize { break }
        }
        await observer.update(syncedDictationCount: try countMetadata(.dictation))
    }

    private func downloadMeetings(rest: SupabaseRESTClient) async throws {
        var current = try repo.loadCursor(for: .meeting)
        while true {
            let rows = try await rest.selectMeetings(after: current, limit: pageSize)
            if rows.isEmpty { break }
            for row in rows {
                try await applyRemoteMeeting(row)
            }
            current = SyncCursor(serverUpdatedAt: rows.last!.serverUpdatedAt, id: rows.last!.remoteID)
            try repo.saveCursor(current!, for: .meeting)
            if rows.count < pageSize { break }
        }
        await observer.update(syncedMeetingCount: try countMetadata(.meeting))
    }

    private func downloadMeetingChatThreads(rest: SupabaseRESTClient) async throws {
        var current = try chatRepo.loadCursor(key: "pull_cursor:meeting_chat_threads")
        while true {
            let rows = try await rest.selectMeetingChatThreads(after: current, limit: pageSize)
            if rows.isEmpty { break }
            for row in rows {
                try chatRepo.applyRemoteThread(row)
            }
            current = SyncCursor(serverUpdatedAt: rows.last!.serverUpdatedAt, id: rows.last!.remoteID)
            try chatRepo.saveCursor(current!, key: "pull_cursor:meeting_chat_threads")
            if rows.count < pageSize { break }
        }
    }

    private func downloadMeetingChatMessages(rest: SupabaseRESTClient) async throws {
        var current = try chatRepo.loadCursor(key: "pull_cursor:meeting_chat_messages")
        while true {
            let rows = try await rest.selectMeetingChatMessages(after: current, limit: pageSize)
            if rows.isEmpty { break }
            for row in rows {
                try chatRepo.applyRemoteMessage(row)
            }
            current = SyncCursor(serverUpdatedAt: rows.last!.serverUpdatedAt, id: rows.last!.remoteID)
            try chatRepo.saveCursor(current!, key: "pull_cursor:meeting_chat_messages")
            if rows.count < pageSize { break }
        }
    }

    private func downloadPreferences(rest: SupabaseRESTClient, userID: String) async throws {
        guard let remote = try await rest.fetchPreferences(userID: userID) else { return }
        let state = try repo.loadPreferencesState()
        let remoteHash = SyncPayloadHasher.preferencesHash(remote.snapshot)

        // No local state yet — accept the remote payload as-is.
        if state.lastSeenServerUpdatedAt == nil {
            await preferencesBridge.applyRemoteSnapshot(remote.snapshot)
            try repo.applyRemotePreferencesState(
                clientUpdatedAt: remote.clientUpdatedAt,
                serverUpdatedAt: remote.serverUpdatedAt,
                remoteVersion: remote.remoteVersion,
                payloadHash: remoteHash,
                lastWriterDeviceID: remote.lastWriterDeviceID
            )
            return
        }

        // We've already seen this version — nothing to do.
        if remote.remoteVersion == state.remoteVersion {
            return
        }

        if state.dirty {
            // Local edits pending. Compare client_updated_at to decide who wins.
            let localTS = state.clientUpdatedAt ?? ""
            if remote.clientUpdatedAt > localTS ||
                (remote.clientUpdatedAt == localTS && remote.lastWriterDeviceID > (state.lastWriterDeviceID ?? "")) {
                // Remote wins
                await preferencesBridge.applyRemoteSnapshot(remote.snapshot)
                try repo.applyRemotePreferencesState(
                    clientUpdatedAt: remote.clientUpdatedAt,
                    serverUpdatedAt: remote.serverUpdatedAt,
                    remoteVersion: remote.remoteVersion,
                    payloadHash: remoteHash,
                    lastWriterDeviceID: remote.lastWriterDeviceID
                )
            }
            // Local wins → uploadPreferences will push later in this cycle.
            return
        }

        // Clean local — accept remote.
        await preferencesBridge.applyRemoteSnapshot(remote.snapshot)
        try repo.applyRemotePreferencesState(
            clientUpdatedAt: remote.clientUpdatedAt,
            serverUpdatedAt: remote.serverUpdatedAt,
            remoteVersion: remote.remoteVersion,
            payloadHash: remoteHash,
            lastWriterDeviceID: remote.lastWriterDeviceID
        )
    }

    /// Reconciles a remote folder against existing local rows by name+parent
    /// path before applying.
    private func applyRemoteFolder(_ payload: RemoteFolderPayload, rest: SupabaseRESTClient) async throws {
        let alreadyMapped = try repo.localID(forRemoteID: payload.remoteID, entityType: .folder)
        if alreadyMapped == nil, payload.deletedAt == nil,
           let candidate = try repo.findUnmappedFolder(name: payload.name, parentRemoteID: payload.parentRemoteID) {
            // Pre-bind the local row to this remote so applyRemoteFolder will
            // UPDATE rather than INSERT.
            let hash = SyncPayloadHasher.folderHash(
                name: payload.name,
                parentRemoteID: payload.parentRemoteID,
                colorHex: payload.colorHex,
                iconName: payload.iconName,
                sortOrder: payload.sortOrder,
                archivedAt: payload.archivedAt
            )
            try repo.attachRemoteID(
                entityType: .folder,
                localID: candidate,
                remoteID: payload.remoteID,
                remoteVersion: payload.remoteVersion,
                clientUpdatedAt: payload.clientUpdatedAt,
                serverUpdatedAt: payload.serverUpdatedAt,
                payloadHash: hash,
                lastWriterDeviceID: payload.lastWriterDeviceID
            )
        }
        try repo.applyRemoteFolder(payload)
    }

    private func applyRemoteDictation(_ payload: RemoteDictationPayload) async throws {
        let alreadyMapped = try repo.localID(forRemoteID: payload.remoteID, entityType: .dictation)
        if alreadyMapped == nil, payload.deletedAt == nil,
           let candidate = try repo.findUnmappedDictation(
            timestamp: payload.timestamp,
            rawText: payload.rawText,
            appContext: payload.appContext
           ) {
            let hash = SyncPayloadHasher.dictationHash(
                timestamp: payload.timestamp,
                durationSeconds: payload.durationSeconds,
                rawText: payload.rawText,
                appContext: payload.appContext,
                wordCount: payload.wordCount,
                source: payload.source,
                startedAt: payload.startedAt,
                endedAt: payload.endedAt
            )
            try repo.attachRemoteID(
                entityType: .dictation,
                localID: candidate,
                remoteID: payload.remoteID,
                remoteVersion: payload.remoteVersion,
                clientUpdatedAt: payload.clientUpdatedAt,
                serverUpdatedAt: payload.serverUpdatedAt,
                payloadHash: hash,
                lastWriterDeviceID: payload.lastWriterDeviceID
            )
        }
        try repo.applyRemoteDictation(payload)
    }

    private func applyRemoteMeeting(_ payload: RemoteMeetingPayload) async throws {
        if let mergedIntoMeetingRemoteID = payload.mergedIntoMeetingRemoteID,
           mergedIntoMeetingRemoteID != payload.remoteID,
           try repo.localID(forRemoteID: mergedIntoMeetingRemoteID, entityType: .meeting) == nil,
           let rest,
           let parent = try await rest.fetchMeeting(remoteID: mergedIntoMeetingRemoteID) {
            try await applyRemoteMeeting(parent)
        }
        let alreadyMapped = try repo.localID(forRemoteID: payload.remoteID, entityType: .meeting)
        if alreadyMapped == nil, payload.deletedAt == nil {
            var candidate: Int64?
            if let calendarEventID = payload.calendarEventID, !calendarEventID.isEmpty {
                candidate = try repo.findUnmappedMeetingByCalendar(
                    calendarEventID: calendarEventID,
                    startTime: payload.startTime
                )
            }
            if candidate == nil {
                candidate = try repo.findUnmappedMeetingByFingerprint(
                    startTime: payload.startTime,
                    durationSeconds: payload.durationSeconds ?? 0,
                    rawTranscript: payload.rawTranscript
                )
            }
            if let candidate {
                let hash = SyncPayloadHasher.meetingHash(
                    title: payload.title,
                    calendarEventID: payload.calendarEventID,
                    calendarEventSnapshotJSON: payload.calendarEventSnapshotJSON,
                    startTime: payload.startTime,
                    endTime: payload.endTime,
                    durationSeconds: payload.durationSeconds,
                    rawTranscript: payload.rawTranscript,
                    formattedNotes: payload.formattedNotes,
                    meetingStatus: payload.meetingStatus,
                    manualNotes: payload.manualNotes,
                    wordCount: payload.wordCount,
                    selectedTemplateID: payload.selectedTemplateID,
                    selectedTemplateName: payload.selectedTemplateName,
                    selectedTemplateKind: payload.selectedTemplateKind,
                    selectedTemplatePrompt: payload.selectedTemplatePrompt,
                    folderRemoteID: payload.folderRemoteID,
                    mergedIntoMeetingRemoteID: payload.mergedIntoMeetingRemoteID,
                    archivedAt: payload.archivedAt
                )
                try repo.attachRemoteID(
                    entityType: .meeting,
                    localID: candidate,
                    remoteID: payload.remoteID,
                    remoteVersion: payload.remoteVersion,
                    clientUpdatedAt: payload.clientUpdatedAt,
                    serverUpdatedAt: payload.serverUpdatedAt,
                    payloadHash: hash,
                    lastWriterDeviceID: payload.lastWriterDeviceID
                )
            }
        }
        try repo.applyRemoteMeeting(payload)
    }

    // MARK: - Upload paths

    private func uploadFolders(rest: SupabaseRESTClient, userID: String) async throws {
        while true {
            let dirty = try repo.dirtyFolders(limit: pageSize)
            guard !dirty.isEmpty else { return }

            var uploadedAny = false
            for entry in dirty {
                // When bootstrapping an existing tree, child folders may be
                // marked dirty before their parent has received a remote_id.
                // Defer those children and re-read dirty rows after parents
                // have synced so we never upload a child as a root folder.
                if entry.record.parentFolderID != nil, entry.parentRemoteID == nil {
                    continue
                }
                try await uploadFolder(entry: entry, rest: rest, userID: userID)
                uploadedAny = true
            }

            if !uploadedAny {
                return
            }
        }
    }

    private func uploadFolder(entry: DirtyFolder, rest: SupabaseRESTClient, userID: String) async throws {
        let deviceID = try repo.ensureDeviceID()
        let now = SyncTimestamp.now()
        let hash = SyncPayloadHasher.folderHash(
            name: entry.record.name,
            parentRemoteID: entry.parentRemoteID,
            colorHex: entry.record.colorHex,
            iconName: entry.record.iconName,
            sortOrder: 0,
            archivedAt: entry.record.archivedAt
        )
        if entry.metadata.lastPayloadHash == hash, entry.metadata.remoteID != nil {
            // Nothing actually changed — clean the dirty flag without an upload.
            try repo.markFolderSynced(
                localID: entry.record.id,
                remoteID: entry.metadata.remoteID!,
                remoteVersion: entry.metadata.remoteVersion,
                clientUpdatedAt: entry.metadata.clientUpdatedAt,
                serverUpdatedAt: entry.metadata.lastSeenServerUpdatedAt ?? now,
                payloadHash: hash,
                lastWriterDeviceID: entry.metadata.lastWriterDeviceID ?? deviceID
            )
            return
        }
        if let remoteID = entry.metadata.remoteID {
            // Optimistic update path
            let updated = try await rest.updateFolder(
                remoteID: remoteID,
                expectedVersion: entry.metadata.remoteVersion,
                parentRemoteID: entry.parentRemoteID,
                name: entry.record.name,
                colorHex: entry.record.colorHex,
                iconName: entry.record.iconName,
                sortOrder: 0,
                clientUpdatedAt: entry.metadata.clientUpdatedAt,
                deviceID: deviceID,
                deletedAt: nil,
                archivedAt: entry.record.archivedAt
            )
            if let updated {
                try repo.markFolderSynced(
                    localID: entry.record.id,
                    remoteID: updated.remoteID,
                    remoteVersion: updated.remoteVersion,
                    clientUpdatedAt: updated.clientUpdatedAt,
                    serverUpdatedAt: updated.serverUpdatedAt,
                    payloadHash: hash,
                    lastWriterDeviceID: deviceID
                )
            } else {
                // Conflict — re-fetch and resolve LWW.
                if let remote = try await rest.fetchFolder(remoteID: remoteID) {
                    try await resolveFolderConflict(local: entry, remote: remote, rest: rest, deviceID: deviceID)
                }
            }
        } else {
            let inserted = try await rest.upsertFolder(
                remoteID: nil,
                userID: userID,
                parentRemoteID: entry.parentRemoteID,
                name: entry.record.name,
                colorHex: entry.record.colorHex,
                iconName: entry.record.iconName,
                sortOrder: 0,
                clientUpdatedAt: entry.metadata.clientUpdatedAt,
                deviceID: deviceID,
                deletedAt: nil,
                archivedAt: entry.record.archivedAt
            )
            try repo.markFolderSynced(
                localID: entry.record.id,
                remoteID: inserted.remoteID,
                remoteVersion: inserted.remoteVersion,
                clientUpdatedAt: inserted.clientUpdatedAt,
                serverUpdatedAt: inserted.serverUpdatedAt,
                payloadHash: hash,
                lastWriterDeviceID: deviceID
            )
        }
    }

    private func uploadDictations(rest: SupabaseRESTClient, userID: String) async throws {
        let dirty = try repo.dirtyDictations(limit: pageSize)
        for entry in dirty {
            try await uploadDictation(entry: entry, rest: rest, userID: userID)
        }
    }

    private func uploadDictation(entry: DirtyDictation, rest: SupabaseRESTClient, userID: String) async throws {
        let deviceID = try repo.ensureDeviceID()
        let hash = SyncPayloadHasher.dictationHash(
            timestamp: entry.record.timestamp,
            durationSeconds: entry.record.durationSeconds,
            rawText: entry.record.rawText,
            appContext: entry.record.appContext,
            wordCount: entry.record.wordCount,
            source: "dictation",
            startedAt: nil, // not surfaced in DictationRecord — accept potential mismatch
            endedAt: nil
        )
        if entry.metadata.lastPayloadHash == hash, entry.metadata.remoteID != nil {
            try repo.markDictationSynced(
                localID: entry.record.id,
                remoteID: entry.metadata.remoteID!,
                remoteVersion: entry.metadata.remoteVersion,
                clientUpdatedAt: entry.metadata.clientUpdatedAt,
                serverUpdatedAt: entry.metadata.lastSeenServerUpdatedAt ?? SyncTimestamp.now(),
                payloadHash: hash,
                lastWriterDeviceID: entry.metadata.lastWriterDeviceID ?? deviceID
            )
            return
        }
        if let remoteID = entry.metadata.remoteID {
            let updated = try await rest.updateDictation(
                remoteID: remoteID,
                expectedVersion: entry.metadata.remoteVersion,
                timestamp: entry.record.timestamp,
                durationSeconds: entry.record.durationSeconds,
                rawText: entry.record.rawText,
                appContext: entry.record.appContext,
                wordCount: entry.record.wordCount,
                source: "dictation",
                startedAt: nil,
                endedAt: nil,
                clientUpdatedAt: entry.metadata.clientUpdatedAt,
                deviceID: deviceID,
                deletedAt: nil
            )
            if let updated {
                try repo.markDictationSynced(
                    localID: entry.record.id,
                    remoteID: updated.remoteID,
                    remoteVersion: updated.remoteVersion,
                    clientUpdatedAt: updated.clientUpdatedAt,
                    serverUpdatedAt: updated.serverUpdatedAt,
                    payloadHash: hash,
                    lastWriterDeviceID: deviceID
                )
            } else if let remote = try await rest.fetchDictation(remoteID: remoteID) {
                try await resolveDictationConflict(local: entry, remote: remote, rest: rest, deviceID: deviceID)
            }
        } else {
            let inserted = try await rest.upsertDictation(
                remoteID: nil,
                userID: userID,
                timestamp: entry.record.timestamp,
                durationSeconds: entry.record.durationSeconds,
                rawText: entry.record.rawText,
                appContext: entry.record.appContext,
                wordCount: entry.record.wordCount,
                source: "dictation",
                startedAt: nil,
                endedAt: nil,
                clientUpdatedAt: entry.metadata.clientUpdatedAt,
                deviceID: deviceID,
                deletedAt: nil
            )
            try repo.markDictationSynced(
                localID: entry.record.id,
                remoteID: inserted.remoteID,
                remoteVersion: inserted.remoteVersion,
                clientUpdatedAt: inserted.clientUpdatedAt,
                serverUpdatedAt: inserted.serverUpdatedAt,
                payloadHash: hash,
                lastWriterDeviceID: deviceID
            )
        }
    }

    private func uploadMeetings(rest: SupabaseRESTClient, userID: String) async throws {
        while true {
            let dirty = try repo.dirtyMeetings(limit: pageSize)
            guard !dirty.isEmpty else { return }

            var uploadedAny = false
            for entry in dirty {
                if entry.record.mergedIntoMeetingID != nil, entry.mergedIntoMeetingRemoteID == nil {
                    continue
                }
                try await uploadMeeting(entry: entry, rest: rest, userID: userID)
                uploadedAny = true
            }

            if !uploadedAny {
                return
            }
        }
    }

    private func uploadMeeting(entry: DirtyMeeting, rest: SupabaseRESTClient, userID: String) async throws {
        let deviceID = try repo.ensureDeviceID()
        let snapshotJSON = encodeCalendarEventSnapshot(entry.record.calendarEventSnapshot)
        let hash = SyncPayloadHasher.meetingHash(
            title: entry.record.title,
            calendarEventID: entry.record.calendarEventID,
            calendarEventSnapshotJSON: snapshotJSON,
            startTime: entry.record.startTime,
            endTime: nil,
            durationSeconds: entry.record.durationSeconds,
            rawTranscript: entry.record.rawTranscript,
            formattedNotes: entry.record.formattedNotes,
            meetingStatus: entry.record.status.rawValue,
            manualNotes: entry.record.manualNotes,
            wordCount: entry.record.wordCount,
            selectedTemplateID: entry.record.selectedTemplateID,
            selectedTemplateName: entry.record.selectedTemplateName,
            selectedTemplateKind: entry.record.selectedTemplateKind?.rawValue,
            selectedTemplatePrompt: entry.record.selectedTemplatePrompt,
            folderRemoteID: entry.folderRemoteID,
            mergedIntoMeetingRemoteID: entry.mergedIntoMeetingRemoteID,
            archivedAt: entry.record.archivedAt
        )
        if entry.metadata.lastPayloadHash == hash, entry.metadata.remoteID != nil {
            try repo.markMeetingSynced(
                localID: entry.record.id,
                remoteID: entry.metadata.remoteID!,
                remoteVersion: entry.metadata.remoteVersion,
                clientUpdatedAt: entry.metadata.clientUpdatedAt,
                serverUpdatedAt: entry.metadata.lastSeenServerUpdatedAt ?? SyncTimestamp.now(),
                payloadHash: hash,
                lastWriterDeviceID: entry.metadata.lastWriterDeviceID ?? deviceID
            )
            return
        }
        if let remoteID = entry.metadata.remoteID {
            let updated = try await rest.updateMeeting(
                remoteID: remoteID,
                expectedVersion: entry.metadata.remoteVersion,
                folderRemoteID: entry.folderRemoteID,
                mergedIntoMeetingRemoteID: entry.mergedIntoMeetingRemoteID,
                title: entry.record.title,
                calendarEventID: entry.record.calendarEventID,
                calendarEventSnapshotJSON: snapshotJSON,
                startTime: entry.record.startTime,
                endTime: nil,
                durationSeconds: entry.record.durationSeconds,
                rawTranscript: entry.record.rawTranscript,
                formattedNotes: entry.record.formattedNotes,
                meetingStatus: entry.record.status.rawValue,
                manualNotes: entry.record.manualNotes,
                wordCount: entry.record.wordCount,
                selectedTemplateID: entry.record.selectedTemplateID,
                selectedTemplateName: entry.record.selectedTemplateName,
                selectedTemplateKind: entry.record.selectedTemplateKind?.rawValue,
                selectedTemplatePrompt: entry.record.selectedTemplatePrompt,
                clientUpdatedAt: entry.metadata.clientUpdatedAt,
                deviceID: deviceID,
                deletedAt: nil,
                archivedAt: entry.record.archivedAt
            )
            if let updated {
                try repo.markMeetingSynced(
                    localID: entry.record.id,
                    remoteID: updated.remoteID,
                    remoteVersion: updated.remoteVersion,
                    clientUpdatedAt: updated.clientUpdatedAt,
                    serverUpdatedAt: updated.serverUpdatedAt,
                    payloadHash: hash,
                    lastWriterDeviceID: deviceID
                )
            } else if let remote = try await rest.fetchMeeting(remoteID: remoteID) {
                try await resolveMeetingConflict(local: entry, remote: remote, rest: rest, deviceID: deviceID)
            }
        } else {
            let inserted = try await rest.upsertMeeting(
                remoteID: nil,
                userID: userID,
                folderRemoteID: entry.folderRemoteID,
                mergedIntoMeetingRemoteID: entry.mergedIntoMeetingRemoteID,
                title: entry.record.title,
                calendarEventID: entry.record.calendarEventID,
                calendarEventSnapshotJSON: snapshotJSON,
                startTime: entry.record.startTime,
                endTime: nil,
                durationSeconds: entry.record.durationSeconds,
                rawTranscript: entry.record.rawTranscript,
                formattedNotes: entry.record.formattedNotes,
                meetingStatus: entry.record.status.rawValue,
                manualNotes: entry.record.manualNotes,
                wordCount: entry.record.wordCount,
                selectedTemplateID: entry.record.selectedTemplateID,
                selectedTemplateName: entry.record.selectedTemplateName,
                selectedTemplateKind: entry.record.selectedTemplateKind?.rawValue,
                selectedTemplatePrompt: entry.record.selectedTemplatePrompt,
                clientUpdatedAt: entry.metadata.clientUpdatedAt,
                deviceID: deviceID,
                deletedAt: nil,
                archivedAt: entry.record.archivedAt
            )
            try repo.markMeetingSynced(
                localID: entry.record.id,
                remoteID: inserted.remoteID,
                remoteVersion: inserted.remoteVersion,
                clientUpdatedAt: inserted.clientUpdatedAt,
                serverUpdatedAt: inserted.serverUpdatedAt,
                payloadHash: hash,
                lastWriterDeviceID: deviceID
            )
        }
    }

    private func uploadMeetingChatThreads(rest: SupabaseRESTClient, userID: String) async throws {
        let deviceID = try repo.ensureDeviceID()
        let dirty = try chatRepo.dirtyThreads(limit: pageSize)
        for entry in dirty {
            guard let scopeRemoteID = entry.scopeRemoteID else {
                continue
            }
            let hash = MeetingChatSyncHasher.threadHash(
                scopeKind: entry.scopeKind,
                scopeRemoteID: scopeRemoteID,
                title: entry.thread.title,
                summary: entry.thread.summary
            )
            if entry.metadata.lastPayloadHash == hash, let remoteID = entry.metadata.remoteID {
                try chatRepo.markThreadSynced(
                    localID: entry.thread.id,
                    remoteID: remoteID,
                    remoteVersion: entry.metadata.remoteVersion,
                    clientUpdatedAt: entry.metadata.clientUpdatedAt,
                    serverUpdatedAt: entry.metadata.lastSeenServerUpdatedAt ?? SyncTimestamp.now(),
                    payloadHash: hash,
                    lastWriterDeviceID: entry.metadata.lastWriterDeviceID ?? deviceID
                )
                continue
            }
            let remote = try await rest.upsertMeetingChatThread(
                remoteID: entry.metadata.remoteID,
                userID: userID,
                scopeKind: entry.scopeKind,
                scopeRemoteID: scopeRemoteID,
                title: entry.thread.title,
                summary: entry.thread.summary,
                clientUpdatedAt: entry.metadata.clientUpdatedAt,
                deviceID: deviceID,
                deletedAt: nil
            )
            try chatRepo.markThreadSynced(
                localID: entry.thread.id,
                remoteID: remote.remoteID,
                remoteVersion: remote.remoteVersion,
                clientUpdatedAt: remote.clientUpdatedAt,
                serverUpdatedAt: remote.serverUpdatedAt,
                payloadHash: hash,
                lastWriterDeviceID: deviceID
            )
        }
    }

    private func uploadMeetingChatMessages(rest: SupabaseRESTClient, userID: String) async throws {
        let deviceID = try repo.ensureDeviceID()
        let dirty = try chatRepo.dirtyMessages(limit: pageSize)
        for entry in dirty {
            guard let threadRemoteID = entry.threadRemoteID else {
                continue
            }
            let createdAt = SyncTimestamp.format(entry.message.createdAt)
            let hash = MeetingChatSyncHasher.messageHash(
                role: entry.message.role,
                content: entry.message.text,
                sources: entry.message.sources,
                createdAt: createdAt
            )
            if entry.metadata.lastPayloadHash == hash, let remoteID = entry.metadata.remoteID {
                try chatRepo.markMessageSynced(
                    localID: entry.message.id,
                    remoteID: remoteID,
                    remoteVersion: entry.metadata.remoteVersion,
                    clientUpdatedAt: entry.metadata.clientUpdatedAt,
                    serverUpdatedAt: entry.metadata.lastSeenServerUpdatedAt ?? SyncTimestamp.now(),
                    payloadHash: hash,
                    lastWriterDeviceID: entry.metadata.lastWriterDeviceID ?? deviceID
                )
                continue
            }
            let remote = try await rest.upsertMeetingChatMessage(
                remoteID: entry.metadata.remoteID,
                userID: userID,
                threadRemoteID: threadRemoteID,
                role: entry.message.role,
                content: entry.message.text,
                sources: entry.message.sources,
                createdAt: createdAt,
                clientUpdatedAt: entry.metadata.clientUpdatedAt,
                deviceID: deviceID,
                deletedAt: nil
            )
            try chatRepo.markMessageSynced(
                localID: entry.message.id,
                remoteID: remote.remoteID,
                remoteVersion: remote.remoteVersion,
                clientUpdatedAt: remote.clientUpdatedAt,
                serverUpdatedAt: remote.serverUpdatedAt,
                payloadHash: hash,
                lastWriterDeviceID: deviceID
            )
        }
    }

    private func uploadPreferences(rest: SupabaseRESTClient, userID: String) async throws {
        let state = try repo.loadPreferencesState()
        guard state.dirty else { return }
        let snapshot = await preferencesBridge.snapshot()
        let hash = SyncPayloadHasher.preferencesHash(snapshot)
        if state.lastPayloadHash == hash {
            try repo.markPreferencesSynced(
                remoteVersion: state.remoteVersion,
                clientUpdatedAt: state.clientUpdatedAt ?? SyncTimestamp.now(),
                serverUpdatedAt: state.lastSeenServerUpdatedAt ?? SyncTimestamp.now(),
                payloadHash: hash,
                lastWriterDeviceID: state.lastWriterDeviceID ?? (try repo.ensureDeviceID())
            )
            return
        }
        let deviceID = try repo.ensureDeviceID()
        let result = try await rest.upsertPreferences(
            userID: userID,
            snapshot: snapshot,
            clientUpdatedAt: state.clientUpdatedAt ?? SyncTimestamp.now(),
            deviceID: deviceID
        )
        try repo.markPreferencesSynced(
            remoteVersion: result.remoteVersion,
            clientUpdatedAt: result.clientUpdatedAt,
            serverUpdatedAt: result.serverUpdatedAt,
            payloadHash: hash,
            lastWriterDeviceID: deviceID
        )
    }

    private func uploadTombstones(rest: SupabaseRESTClient, entityType: SyncEntityType) async throws {
        let tombstones = try repo.dirtyTombstones(entityType: entityType, limit: pageSize)
        let deviceID = try repo.ensureDeviceID()
        for tombstone in tombstones {
            guard let remoteID = tombstone.remoteID, !remoteID.isEmpty else {
                // Never synced — just clear the tombstone locally.
                try repo.clearTombstone(entityType: entityType, localID: tombstone.localID)
                continue
            }
            let now = SyncTimestamp.now()
            switch entityType {
            case .folder:
                _ = try await rest.upsertFolder(
                    remoteID: remoteID,
                    userID: await auth.userID ?? "",
                    parentRemoteID: nil,
                    name: "(deleted)",
                    colorHex: nil,
                    iconName: nil,
                    sortOrder: 0,
                    clientUpdatedAt: tombstone.clientDeletedAt,
                    deviceID: deviceID,
                    deletedAt: tombstone.clientDeletedAt,
                    archivedAt: nil
                )
            case .dictation:
                _ = try await rest.upsertDictation(
                    remoteID: remoteID,
                    userID: await auth.userID ?? "",
                    timestamp: now,
                    durationSeconds: 0,
                    rawText: "",
                    appContext: "",
                    wordCount: 0,
                    source: "dictation",
                    startedAt: nil,
                    endedAt: nil,
                    clientUpdatedAt: tombstone.clientDeletedAt,
                    deviceID: deviceID,
                    deletedAt: tombstone.clientDeletedAt
                )
            case .meeting:
                _ = try await rest.upsertMeeting(
                    remoteID: remoteID,
                    userID: await auth.userID ?? "",
                    folderRemoteID: nil,
                    mergedIntoMeetingRemoteID: nil,
                    title: "(deleted)",
                    calendarEventID: nil,
                    calendarEventSnapshotJSON: nil,
                    startTime: now,
                    endTime: nil,
                    durationSeconds: nil,
                    rawTranscript: "",
                    formattedNotes: "",
                    meetingStatus: "completed",
                    manualNotes: "",
                    wordCount: 0,
                    selectedTemplateID: nil,
                    selectedTemplateName: nil,
                    selectedTemplateKind: nil,
                    selectedTemplatePrompt: nil,
                    clientUpdatedAt: tombstone.clientDeletedAt,
                    deviceID: deviceID,
                    deletedAt: tombstone.clientDeletedAt,
                    archivedAt: nil
                )
            }
            try repo.markTombstoneSynced(
                entityType: entityType,
                localID: tombstone.localID,
                lastKnownRemoteVersion: tombstone.lastKnownRemoteVersion + 1
            )
        }
    }

    private func uploadMeetingChatTombstones(
        rest: SupabaseRESTClient,
        userID: String,
        entityKind: MeetingChatSyncEntityKind
    ) async throws {
        let tombstones = try chatRepo.dirtyTombstones(entityKind: entityKind, limit: pageSize)
        let deviceID = try repo.ensureDeviceID()
        for tombstone in tombstones {
            guard let remoteID = tombstone.remoteID, !remoteID.isEmpty else {
                try chatRepo.clearTombstone(entityKind: entityKind, localID: tombstone.localID)
                continue
            }
            switch entityKind {
            case .thread:
                guard let existing = try await rest.fetchMeetingChatThread(remoteID: remoteID) else {
                    try chatRepo.markTombstoneSynced(
                        entityKind: entityKind,
                        localID: tombstone.localID,
                        lastKnownRemoteVersion: tombstone.lastKnownRemoteVersion
                    )
                    continue
                }
                let remote = try await rest.upsertMeetingChatThread(
                    remoteID: remoteID,
                    userID: userID,
                    scopeKind: existing.scopeKind,
                    scopeRemoteID: existing.scopeRemoteID,
                    title: existing.title,
                    summary: existing.summary,
                    clientUpdatedAt: tombstone.clientDeletedAt,
                    deviceID: deviceID,
                    deletedAt: tombstone.clientDeletedAt
                )
                try chatRepo.markTombstoneSynced(
                    entityKind: entityKind,
                    localID: tombstone.localID,
                    lastKnownRemoteVersion: remote.remoteVersion
                )
            case .message:
                try chatRepo.markTombstoneSynced(
                    entityKind: entityKind,
                    localID: tombstone.localID,
                    lastKnownRemoteVersion: tombstone.lastKnownRemoteVersion
                )
            }
        }
    }

    // MARK: - Conflict resolution (LWW)

    private func resolveFolderConflict(
        local: DirtyFolder,
        remote: RemoteFolderPayload,
        rest: SupabaseRESTClient,
        deviceID: String
    ) async throws {
        let remoteHash = SyncPayloadHasher.folderHash(
            name: remote.name,
            parentRemoteID: remote.parentRemoteID,
            colorHex: remote.colorHex,
            iconName: remote.iconName,
            sortOrder: remote.sortOrder,
            archivedAt: remote.archivedAt
        )
        let localHash = SyncPayloadHasher.folderHash(
            name: local.record.name,
            parentRemoteID: local.parentRemoteID,
            colorHex: local.record.colorHex,
            iconName: local.record.iconName,
            sortOrder: 0,
            archivedAt: local.record.archivedAt
        )
        if remoteHash == localHash {
            try repo.markFolderSynced(
                localID: local.record.id,
                remoteID: remote.remoteID,
                remoteVersion: remote.remoteVersion,
                clientUpdatedAt: remote.clientUpdatedAt,
                serverUpdatedAt: remote.serverUpdatedAt,
                payloadHash: remoteHash,
                lastWriterDeviceID: remote.lastWriterDeviceID
            )
            return
        }
        if Self.localWins(localTS: local.metadata.clientUpdatedAt, remoteTS: remote.clientUpdatedAt,
                          localDevice: deviceID, remoteDevice: remote.lastWriterDeviceID) {
            // Retry update with the new known remote version
            let updated = try await rest.updateFolder(
                remoteID: remote.remoteID,
                expectedVersion: remote.remoteVersion,
                parentRemoteID: local.parentRemoteID,
                name: local.record.name,
                colorHex: local.record.colorHex,
                iconName: local.record.iconName,
                sortOrder: 0,
                clientUpdatedAt: local.metadata.clientUpdatedAt,
                deviceID: deviceID,
                deletedAt: nil,
                archivedAt: local.record.archivedAt
            )
            if let updated {
                try repo.markFolderSynced(
                    localID: local.record.id,
                    remoteID: updated.remoteID,
                    remoteVersion: updated.remoteVersion,
                    clientUpdatedAt: updated.clientUpdatedAt,
                    serverUpdatedAt: updated.serverUpdatedAt,
                    payloadHash: localHash,
                    lastWriterDeviceID: deviceID
                )
            }
        } else {
            try repo.applyRemoteFolder(remote)
        }
    }

    private func resolveDictationConflict(
        local: DirtyDictation,
        remote: RemoteDictationPayload,
        rest: SupabaseRESTClient,
        deviceID: String
    ) async throws {
        let remoteHash = SyncPayloadHasher.dictationHash(
            timestamp: remote.timestamp,
            durationSeconds: remote.durationSeconds,
            rawText: remote.rawText,
            appContext: remote.appContext,
            wordCount: remote.wordCount,
            source: remote.source,
            startedAt: remote.startedAt,
            endedAt: remote.endedAt
        )
        let localHash = SyncPayloadHasher.dictationHash(
            timestamp: local.record.timestamp,
            durationSeconds: local.record.durationSeconds,
            rawText: local.record.rawText,
            appContext: local.record.appContext,
            wordCount: local.record.wordCount,
            source: "dictation",
            startedAt: nil,
            endedAt: nil
        )
        if remoteHash == localHash {
            try repo.markDictationSynced(
                localID: local.record.id,
                remoteID: remote.remoteID,
                remoteVersion: remote.remoteVersion,
                clientUpdatedAt: remote.clientUpdatedAt,
                serverUpdatedAt: remote.serverUpdatedAt,
                payloadHash: remoteHash,
                lastWriterDeviceID: remote.lastWriterDeviceID
            )
            return
        }
        if Self.localWins(localTS: local.metadata.clientUpdatedAt, remoteTS: remote.clientUpdatedAt,
                          localDevice: deviceID, remoteDevice: remote.lastWriterDeviceID) {
            let updated = try await rest.updateDictation(
                remoteID: remote.remoteID,
                expectedVersion: remote.remoteVersion,
                timestamp: local.record.timestamp,
                durationSeconds: local.record.durationSeconds,
                rawText: local.record.rawText,
                appContext: local.record.appContext,
                wordCount: local.record.wordCount,
                source: "dictation",
                startedAt: nil,
                endedAt: nil,
                clientUpdatedAt: local.metadata.clientUpdatedAt,
                deviceID: deviceID,
                deletedAt: nil
            )
            if let updated {
                try repo.markDictationSynced(
                    localID: local.record.id,
                    remoteID: updated.remoteID,
                    remoteVersion: updated.remoteVersion,
                    clientUpdatedAt: updated.clientUpdatedAt,
                    serverUpdatedAt: updated.serverUpdatedAt,
                    payloadHash: localHash,
                    lastWriterDeviceID: deviceID
                )
            }
        } else {
            try repo.applyRemoteDictation(remote)
        }
    }

    private func resolveMeetingConflict(
        local: DirtyMeeting,
        remote: RemoteMeetingPayload,
        rest: SupabaseRESTClient,
        deviceID: String
    ) async throws {
        let snapshotJSON = encodeCalendarEventSnapshot(local.record.calendarEventSnapshot)
        let remoteHash = SyncPayloadHasher.meetingHash(
            title: remote.title,
            calendarEventID: remote.calendarEventID,
            calendarEventSnapshotJSON: remote.calendarEventSnapshotJSON,
            startTime: remote.startTime,
            endTime: remote.endTime,
            durationSeconds: remote.durationSeconds,
            rawTranscript: remote.rawTranscript,
            formattedNotes: remote.formattedNotes,
            meetingStatus: remote.meetingStatus,
            manualNotes: remote.manualNotes,
            wordCount: remote.wordCount,
            selectedTemplateID: remote.selectedTemplateID,
            selectedTemplateName: remote.selectedTemplateName,
            selectedTemplateKind: remote.selectedTemplateKind,
            selectedTemplatePrompt: remote.selectedTemplatePrompt,
            folderRemoteID: remote.folderRemoteID,
            mergedIntoMeetingRemoteID: remote.mergedIntoMeetingRemoteID,
            archivedAt: remote.archivedAt
        )
        let localHash = SyncPayloadHasher.meetingHash(
            title: local.record.title,
            calendarEventID: local.record.calendarEventID,
            calendarEventSnapshotJSON: snapshotJSON,
            startTime: local.record.startTime,
            endTime: nil,
            durationSeconds: local.record.durationSeconds,
            rawTranscript: local.record.rawTranscript,
            formattedNotes: local.record.formattedNotes,
            meetingStatus: local.record.status.rawValue,
            manualNotes: local.record.manualNotes,
            wordCount: local.record.wordCount,
            selectedTemplateID: local.record.selectedTemplateID,
            selectedTemplateName: local.record.selectedTemplateName,
            selectedTemplateKind: local.record.selectedTemplateKind?.rawValue,
            selectedTemplatePrompt: local.record.selectedTemplatePrompt,
            folderRemoteID: local.folderRemoteID,
            mergedIntoMeetingRemoteID: local.mergedIntoMeetingRemoteID,
            archivedAt: local.record.archivedAt
        )
        if remoteHash == localHash {
            try repo.markMeetingSynced(
                localID: local.record.id,
                remoteID: remote.remoteID,
                remoteVersion: remote.remoteVersion,
                clientUpdatedAt: remote.clientUpdatedAt,
                serverUpdatedAt: remote.serverUpdatedAt,
                payloadHash: remoteHash,
                lastWriterDeviceID: remote.lastWriterDeviceID
            )
            return
        }
        if Self.localWins(localTS: local.metadata.clientUpdatedAt, remoteTS: remote.clientUpdatedAt,
                          localDevice: deviceID, remoteDevice: remote.lastWriterDeviceID) {
            let updated = try await rest.updateMeeting(
                remoteID: remote.remoteID,
                expectedVersion: remote.remoteVersion,
                folderRemoteID: local.folderRemoteID,
                mergedIntoMeetingRemoteID: local.mergedIntoMeetingRemoteID,
                title: local.record.title,
                calendarEventID: local.record.calendarEventID,
                calendarEventSnapshotJSON: snapshotJSON,
                startTime: local.record.startTime,
                endTime: nil,
                durationSeconds: local.record.durationSeconds,
                rawTranscript: local.record.rawTranscript,
                formattedNotes: local.record.formattedNotes,
                meetingStatus: local.record.status.rawValue,
                manualNotes: local.record.manualNotes,
                wordCount: local.record.wordCount,
                selectedTemplateID: local.record.selectedTemplateID,
                selectedTemplateName: local.record.selectedTemplateName,
                selectedTemplateKind: local.record.selectedTemplateKind?.rawValue,
                selectedTemplatePrompt: local.record.selectedTemplatePrompt,
                clientUpdatedAt: local.metadata.clientUpdatedAt,
                deviceID: deviceID,
                deletedAt: nil,
                archivedAt: local.record.archivedAt
            )
            if let updated {
                try repo.markMeetingSynced(
                    localID: local.record.id,
                    remoteID: updated.remoteID,
                    remoteVersion: updated.remoteVersion,
                    clientUpdatedAt: updated.clientUpdatedAt,
                    serverUpdatedAt: updated.serverUpdatedAt,
                    payloadHash: localHash,
                    lastWriterDeviceID: deviceID
                )
            }
        } else {
            try repo.applyRemoteMeeting(remote)
        }
    }

    private static func localWins(localTS: String, remoteTS: String, localDevice: String, remoteDevice: String) -> Bool {
        if localTS != remoteTS { return localTS > remoteTS }
        return localDevice > remoteDevice
    }

    // MARK: - Helpers

    private func encodeCalendarEventSnapshot(_ snapshot: MeetingCalendarEventSnapshot?) -> String? {
        guard let snapshot,
              let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func countMetadata(_ entityType: SyncEntityType) throws -> Int {
        // Best-effort approximation. The repo doesn't expose a count helper to
        // avoid leaking SQL details, so we ride the dirty-query path to scan.
        // We just count rows with sync_metadata rows (synced or dirty).
        let dirty = try {
            switch entityType {
            case .folder: return try repo.dirtyFolders(limit: 10_000).count
            case .dictation: return try repo.dirtyDictations(limit: 10_000).count
            case .meeting: return try repo.dirtyMeetings(limit: 10_000).count
            }
        }()
        return dirty
    }

    private func reportError(_ message: String) async {
        await observer.update(
            status: .error(message: message),
            lastErrorMessage: message
        )
    }
}
