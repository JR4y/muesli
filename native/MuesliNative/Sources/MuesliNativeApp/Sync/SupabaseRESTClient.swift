import Foundation
import MuesliCore

enum SupabaseRESTError: Error, LocalizedError {
    case notConfigured
    case unauthorized
    case conflict
    case network(underlying: Error)
    case server(status: Int, message: String)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase sync is not configured."
        case .unauthorized: return "Supabase rejected the request (auth)."
        case .conflict: return "Supabase row version mismatch."
        case .network(let underlying): return "Network error: \(underlying.localizedDescription)"
        case .server(let status, let message): return "Supabase \(status): \(message)"
        case .decoding(let message): return "Decoding error: \(message)"
        }
    }
}

/// Thin PostgREST client. All routes assume the authenticated user_id is
/// already enforced by RLS — we never need to filter on user_id explicitly,
/// but we do for clarity and index hits.
@MainActor
final class SupabaseRESTClient {
    private let config: SupabaseConfig
    private let auth: SupabaseAuthManager
    private let session: URLSession
    private let isoFormatter: ISO8601DateFormatter

    init(config: SupabaseConfig, auth: SupabaseAuthManager, urlSession: URLSession = .shared) {
        self.config = config
        self.auth = auth
        self.session = urlSession
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
    }

    // MARK: - Folders

    func selectFolders(after cursor: SyncCursor?, limit: Int) async throws -> [RemoteFolderPayload] {
        let items = try await selectPage(table: "meeting_folders", after: cursor, limit: limit)
        return items.compactMap { Self.parseFolder($0) }
    }

    func upsertFolder(
        remoteID: String?,
        userID: String,
        parentRemoteID: String?,
        name: String,
        colorHex: String?,
        iconName: String?,
        sortOrder: Int,
        clientUpdatedAt: String,
        deviceID: String,
        deletedAt: String?
    ) async throws -> RemoteFolderPayload {
        var body: [String: Any] = [
            "user_id": userID,
            "name": name,
            "client_updated_at": clientUpdatedAt,
            "last_writer_device_id": deviceID,
            "sort_order": sortOrder,
            "deleted_at": deletedAt as Any? ?? NSNull(),
            "parent_folder_id": parentRemoteID as Any? ?? NSNull(),
            "color_hex": colorHex as Any? ?? NSNull(),
            "icon_name": iconName as Any? ?? NSNull(),
        ]
        if let remoteID {
            body["id"] = remoteID
        }
        let data = try await sendUpsert(path: "meeting_folders", body: body)
        guard let row = (try Self.firstObject(from: data)),
              let folder = Self.parseFolder(row) else {
            throw SupabaseRESTError.decoding(message: "missing folder row")
        }
        return folder
    }

    func updateFolder(
        remoteID: String,
        expectedVersion: Int64,
        parentRemoteID: String?,
        name: String,
        colorHex: String?,
        iconName: String?,
        sortOrder: Int,
        clientUpdatedAt: String,
        deviceID: String,
        deletedAt: String?
    ) async throws -> RemoteFolderPayload? {
        let body: [String: Any] = [
            "name": name,
            "parent_folder_id": parentRemoteID as Any? ?? NSNull(),
            "color_hex": colorHex as Any? ?? NSNull(),
            "icon_name": iconName as Any? ?? NSNull(),
            "sort_order": sortOrder,
            "client_updated_at": clientUpdatedAt,
            "last_writer_device_id": deviceID,
            "deleted_at": deletedAt as Any? ?? NSNull(),
        ]
        let query: [URLQueryItem] = [
            URLQueryItem(name: "id", value: "eq.\(remoteID)"),
            URLQueryItem(name: "remote_version", value: "eq.\(expectedVersion)"),
        ]
        let data = try await sendUpdate(path: "meeting_folders", query: query, body: body)
        guard let row = try Self.firstObject(from: data) else {
            return nil // conflict — caller re-fetches and resolves
        }
        return Self.parseFolder(row)
    }

    // MARK: - Dictations

    func selectDictations(after cursor: SyncCursor?, limit: Int) async throws -> [RemoteDictationPayload] {
        let items = try await selectPage(table: "dictations", after: cursor, limit: limit)
        return items.compactMap { Self.parseDictation($0) }
    }

    func upsertDictation(
        remoteID: String?,
        userID: String,
        timestamp: String,
        durationSeconds: Double,
        rawText: String,
        appContext: String,
        wordCount: Int,
        source: String,
        startedAt: String?,
        endedAt: String?,
        clientUpdatedAt: String,
        deviceID: String,
        deletedAt: String?
    ) async throws -> RemoteDictationPayload {
        var body: [String: Any] = [
            "user_id": userID,
            "timestamp": timestamp,
            "duration_seconds": durationSeconds,
            "raw_text": rawText,
            "app_context": appContext,
            "word_count": wordCount,
            "source": source,
            "started_at": startedAt as Any? ?? NSNull(),
            "ended_at": endedAt as Any? ?? NSNull(),
            "client_updated_at": clientUpdatedAt,
            "last_writer_device_id": deviceID,
            "deleted_at": deletedAt as Any? ?? NSNull(),
        ]
        if let remoteID {
            body["id"] = remoteID
        }
        let data = try await sendUpsert(path: "dictations", body: body)
        guard let row = try Self.firstObject(from: data),
              let dict = Self.parseDictation(row) else {
            throw SupabaseRESTError.decoding(message: "missing dictation row")
        }
        return dict
    }

    func updateDictation(
        remoteID: String,
        expectedVersion: Int64,
        timestamp: String,
        durationSeconds: Double,
        rawText: String,
        appContext: String,
        wordCount: Int,
        source: String,
        startedAt: String?,
        endedAt: String?,
        clientUpdatedAt: String,
        deviceID: String,
        deletedAt: String?
    ) async throws -> RemoteDictationPayload? {
        let body: [String: Any] = [
            "timestamp": timestamp,
            "duration_seconds": durationSeconds,
            "raw_text": rawText,
            "app_context": appContext,
            "word_count": wordCount,
            "source": source,
            "started_at": startedAt as Any? ?? NSNull(),
            "ended_at": endedAt as Any? ?? NSNull(),
            "client_updated_at": clientUpdatedAt,
            "last_writer_device_id": deviceID,
            "deleted_at": deletedAt as Any? ?? NSNull(),
        ]
        let query: [URLQueryItem] = [
            URLQueryItem(name: "id", value: "eq.\(remoteID)"),
            URLQueryItem(name: "remote_version", value: "eq.\(expectedVersion)"),
        ]
        let data = try await sendUpdate(path: "dictations", query: query, body: body)
        guard let row = try Self.firstObject(from: data) else {
            return nil
        }
        return Self.parseDictation(row)
    }

    /// Fetches a single dictation row by remote_id. Used to inspect remote
    /// state during conflict resolution.
    func fetchDictation(remoteID: String) async throws -> RemoteDictationPayload? {
        let data = try await get(
            path: "dictations",
            query: [
                URLQueryItem(name: "id", value: "eq.\(remoteID)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard let row = try Self.firstObject(from: data) else { return nil }
        return Self.parseDictation(row)
    }

    func fetchFolder(remoteID: String) async throws -> RemoteFolderPayload? {
        let data = try await get(
            path: "meeting_folders",
            query: [
                URLQueryItem(name: "id", value: "eq.\(remoteID)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard let row = try Self.firstObject(from: data) else { return nil }
        return Self.parseFolder(row)
    }

    func fetchMeeting(remoteID: String) async throws -> RemoteMeetingPayload? {
        let data = try await get(
            path: "meetings",
            query: [
                URLQueryItem(name: "id", value: "eq.\(remoteID)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard let row = try Self.firstObject(from: data) else { return nil }
        return Self.parseMeeting(row)
    }

    // MARK: - Meetings

    func selectMeetings(after cursor: SyncCursor?, limit: Int) async throws -> [RemoteMeetingPayload] {
        let items = try await selectPage(table: "meetings", after: cursor, limit: limit)
        return items.compactMap { Self.parseMeeting($0) }
    }

    func upsertMeeting(
        remoteID: String?,
        userID: String,
        folderRemoteID: String?,
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
        deviceID: String,
        deletedAt: String?
    ) async throws -> RemoteMeetingPayload {
        var body: [String: Any] = [
            "user_id": userID,
            "folder_id": folderRemoteID as Any? ?? NSNull(),
            "title": title,
            "calendar_event_id": calendarEventID as Any? ?? NSNull(),
            "calendar_event_snapshot": Self.parseJSONOrNull(calendarEventSnapshotJSON),
            "start_time": startTime,
            "end_time": endTime as Any? ?? NSNull(),
            "duration_seconds": durationSeconds as Any? ?? NSNull(),
            "raw_transcript": rawTranscript,
            "formatted_notes": formattedNotes,
            "meeting_status": meetingStatus,
            "manual_notes": manualNotes,
            "word_count": wordCount,
            "selected_template_id": selectedTemplateID as Any? ?? NSNull(),
            "selected_template_name": selectedTemplateName as Any? ?? NSNull(),
            "selected_template_kind": selectedTemplateKind as Any? ?? NSNull(),
            "selected_template_prompt": selectedTemplatePrompt as Any? ?? NSNull(),
            "client_updated_at": clientUpdatedAt,
            "last_writer_device_id": deviceID,
            "deleted_at": deletedAt as Any? ?? NSNull(),
        ]
        if let remoteID {
            body["id"] = remoteID
        }
        let data = try await sendUpsert(path: "meetings", body: body)
        guard let row = try Self.firstObject(from: data),
              let meeting = Self.parseMeeting(row) else {
            throw SupabaseRESTError.decoding(message: "missing meeting row")
        }
        return meeting
    }

    func updateMeeting(
        remoteID: String,
        expectedVersion: Int64,
        folderRemoteID: String?,
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
        deviceID: String,
        deletedAt: String?
    ) async throws -> RemoteMeetingPayload? {
        let body: [String: Any] = [
            "folder_id": folderRemoteID as Any? ?? NSNull(),
            "title": title,
            "calendar_event_id": calendarEventID as Any? ?? NSNull(),
            "calendar_event_snapshot": Self.parseJSONOrNull(calendarEventSnapshotJSON),
            "start_time": startTime,
            "end_time": endTime as Any? ?? NSNull(),
            "duration_seconds": durationSeconds as Any? ?? NSNull(),
            "raw_transcript": rawTranscript,
            "formatted_notes": formattedNotes,
            "meeting_status": meetingStatus,
            "manual_notes": manualNotes,
            "word_count": wordCount,
            "selected_template_id": selectedTemplateID as Any? ?? NSNull(),
            "selected_template_name": selectedTemplateName as Any? ?? NSNull(),
            "selected_template_kind": selectedTemplateKind as Any? ?? NSNull(),
            "selected_template_prompt": selectedTemplatePrompt as Any? ?? NSNull(),
            "client_updated_at": clientUpdatedAt,
            "last_writer_device_id": deviceID,
            "deleted_at": deletedAt as Any? ?? NSNull(),
        ]
        let query: [URLQueryItem] = [
            URLQueryItem(name: "id", value: "eq.\(remoteID)"),
            URLQueryItem(name: "remote_version", value: "eq.\(expectedVersion)"),
        ]
        let data = try await sendUpdate(path: "meetings", query: query, body: body)
        guard let row = try Self.firstObject(from: data) else { return nil }
        return Self.parseMeeting(row)
    }

    // MARK: - Preferences

    func fetchPreferences(userID: String) async throws -> RemotePreferencesPayload? {
        let data = try await get(
            path: "user_preferences",
            query: [
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard let row = try Self.firstObject(from: data) else { return nil }
        return Self.parsePreferences(row)
    }

    func upsertPreferences(
        userID: String,
        snapshot: SyncPreferencesSnapshot,
        clientUpdatedAt: String,
        deviceID: String
    ) async throws -> RemotePreferencesPayload {
        let body: [String: Any] = [
            "user_id": userID,
            "custom_meeting_templates": Self.parseJSONOrEmptyArray(snapshot.customMeetingTemplatesJSON),
            "hidden_built_in_template_ids": snapshot.hiddenBuiltInTemplateIDs,
            "custom_words": Self.parseJSONOrEmptyArray(snapshot.customWordsJSON),
            "default_meeting_template_id": snapshot.defaultMeetingTemplateID,
            "auto_template_target_id": snapshot.autoTemplateTargetID,
            "meeting_title_prompt": snapshot.meetingTitlePrompt,
            "folder_order_remote_ids": snapshot.folderOrderRemoteIDs,
            "client_updated_at": clientUpdatedAt,
            "last_writer_device_id": deviceID,
        ]
        let data = try await sendUpsert(path: "user_preferences", body: body)
        guard let row = try Self.firstObject(from: data),
              let prefs = Self.parsePreferences(row) else {
            throw SupabaseRESTError.decoding(message: "missing preferences row")
        }
        return prefs
    }

    // MARK: - Generic page

    private func selectPage(table: String, after cursor: SyncCursor?, limit: Int) async throws -> [[String: Any]] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "server_updated_at.asc,id.asc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let cursor {
            let cursorTS = Self.normalizedQueryTimestamp(cursor.serverUpdatedAt)
            // PostgREST does not support "(a,b) > (x,y)" directly. We approximate:
            // server_updated_at > cursor.server_updated_at OR
            // (server_updated_at = cursor AND id > cursor.id).
            // We use a single `or=(...)` filter.
            let filter = "or=(server_updated_at.gt.\(cursorTS),and(server_updated_at.eq.\(cursorTS),id.gt.\(cursor.id)))"
            // PostgREST query-item form: this is a single key=value in the URL,
            // but quoting is touchy. We pass it raw via percent-encoded value.
            query.append(URLQueryItem(name: "or", value: "(server_updated_at.gt.\(cursorTS),and(server_updated_at.eq.\(cursorTS),id.gt.\(cursor.id)))"))
            _ = filter
        }
        let data = try await get(path: table, query: query)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array
    }

    // MARK: - HTTP plumbing

    private func get(path: String, query: [URLQueryItem]) async throws -> Data {
        var request = URLRequest(url: config.restURL(path, query: query))
        request.httpMethod = "GET"
        return try await perform(&request)
    }

    private func sendUpsert(path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: config.restURL(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(&request)
    }

    private func sendUpdate(path: String, query: [URLQueryItem], body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: config.restURL(path, query: query))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(&request)
    }

    private func perform(_ request: inout URLRequest) async throws -> Data {
        try await attachAuth(&request)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SupabaseRESTError.server(status: -1, message: "no http response")
            }
            if http.statusCode == 401 {
                // Try once with a refreshed token.
                try await attachAuth(&request, force: true)
                let (retryData, retryResponse) = try await session.data(for: request)
                guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                    throw SupabaseRESTError.server(status: -1, message: "no http response")
                }
                if retryHTTP.statusCode == 401 {
                    throw SupabaseRESTError.unauthorized
                }
                if !(200..<300).contains(retryHTTP.statusCode) {
                    throw SupabaseRESTError.server(status: retryHTTP.statusCode, message: Self.errorMessage(retryData))
                }
                return retryData
            }
            if !(200..<300).contains(http.statusCode) {
                throw SupabaseRESTError.server(status: http.statusCode, message: Self.errorMessage(data))
            }
            return data
        } catch let error as SupabaseRESTError {
            throw error
        } catch {
            throw SupabaseRESTError.network(underlying: error)
        }
    }

    private func attachAuth(_ request: inout URLRequest, force: Bool = false) async throws {
        let token: String
        do {
            token = try await auth.currentAccessToken()
        } catch {
            throw SupabaseRESTError.unauthorized
        }
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = force
    }

    // MARK: - Parse helpers

    private static func errorMessage(_ data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = object["message"] as? String { return msg }
            if let msg = object["msg"] as? String { return msg }
            if let msg = object["error"] as? String { return msg }
            if let hint = object["hint"] as? String { return hint }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func firstObject(from data: Data) throws -> [String: Any]? {
        let object = try JSONSerialization.jsonObject(with: data)
        if let array = object as? [[String: Any]] {
            return array.first
        }
        if let dict = object as? [String: Any] {
            return dict
        }
        return nil
    }

    private static func parseJSONOrNull(_ raw: String?) -> Any {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return NSNull()
        }
        return object
    }

    private static func parseJSONOrEmptyArray(_ raw: String) -> Any {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        return object
    }

    nonisolated static func normalizedQueryTimestamp(_ raw: String) -> String {
        guard raw.contains("+") else { return raw }
        return raw.replacingOccurrences(of: "+00:00", with: "Z")
    }

    private static func parseFolder(_ row: [String: Any]) -> RemoteFolderPayload? {
        guard let id = row["id"] as? String,
              let name = row["name"] as? String,
              let clientUpdatedAt = row["client_updated_at"] as? String,
              let serverUpdatedAt = row["server_updated_at"] as? String,
              let deviceID = row["last_writer_device_id"] as? String else {
            return nil
        }
        let parentID = row["parent_folder_id"] as? String
        let colorHex = row["color_hex"] as? String
        let iconName = row["icon_name"] as? String
        let sortOrder = row["sort_order"] as? Int ?? 0
        let remoteVersion = (row["remote_version"] as? Int64) ?? Int64((row["remote_version"] as? Int) ?? 1)
        let deletedAt = row["deleted_at"] as? String
        return RemoteFolderPayload(
            remoteID: id,
            parentRemoteID: parentID,
            name: name,
            colorHex: colorHex,
            iconName: iconName,
            sortOrder: sortOrder,
            clientUpdatedAt: clientUpdatedAt,
            serverUpdatedAt: serverUpdatedAt,
            remoteVersion: remoteVersion,
            lastWriterDeviceID: deviceID,
            deletedAt: deletedAt
        )
    }

    private static func parseDictation(_ row: [String: Any]) -> RemoteDictationPayload? {
        guard let id = row["id"] as? String,
              let timestamp = row["timestamp"] as? String,
              let rawText = row["raw_text"] as? String,
              let appContext = row["app_context"] as? String,
              let clientUpdatedAt = row["client_updated_at"] as? String,
              let serverUpdatedAt = row["server_updated_at"] as? String,
              let deviceID = row["last_writer_device_id"] as? String else {
            return nil
        }
        let duration = (row["duration_seconds"] as? Double) ?? Double((row["duration_seconds"] as? Int) ?? 0)
        let wordCount = (row["word_count"] as? Int) ?? 0
        let source = (row["source"] as? String) ?? "dictation"
        let startedAt = row["started_at"] as? String
        let endedAt = row["ended_at"] as? String
        let remoteVersion = (row["remote_version"] as? Int64) ?? Int64((row["remote_version"] as? Int) ?? 1)
        let deletedAt = row["deleted_at"] as? String
        return RemoteDictationPayload(
            remoteID: id,
            timestamp: timestamp,
            durationSeconds: duration,
            rawText: rawText,
            appContext: appContext,
            wordCount: wordCount,
            source: source,
            startedAt: startedAt,
            endedAt: endedAt,
            clientUpdatedAt: clientUpdatedAt,
            serverUpdatedAt: serverUpdatedAt,
            remoteVersion: remoteVersion,
            lastWriterDeviceID: deviceID,
            deletedAt: deletedAt
        )
    }

    private static func parseMeeting(_ row: [String: Any]) -> RemoteMeetingPayload? {
        guard let id = row["id"] as? String,
              let title = row["title"] as? String,
              let startTime = row["start_time"] as? String,
              let meetingStatus = row["meeting_status"] as? String,
              let clientUpdatedAt = row["client_updated_at"] as? String,
              let serverUpdatedAt = row["server_updated_at"] as? String,
              let deviceID = row["last_writer_device_id"] as? String else {
            return nil
        }
        let folderRemoteID = row["folder_id"] as? String
        let calendarEventID = row["calendar_event_id"] as? String
        let snapshotJSON: String? = {
            guard let object = row["calendar_event_snapshot"] else { return nil }
            if object is NSNull { return nil }
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                  let s = String(data: data, encoding: .utf8) else {
                return nil
            }
            return s
        }()
        let endTime = row["end_time"] as? String
        let durationSeconds = (row["duration_seconds"] as? Double) ?? (row["duration_seconds"] as? Int).map(Double.init)
        let rawTranscript = (row["raw_transcript"] as? String) ?? ""
        let formattedNotes = (row["formatted_notes"] as? String) ?? ""
        let manualNotes = (row["manual_notes"] as? String) ?? ""
        let wordCount = (row["word_count"] as? Int) ?? 0
        let selectedTemplateID = row["selected_template_id"] as? String
        let selectedTemplateName = row["selected_template_name"] as? String
        let selectedTemplateKind = row["selected_template_kind"] as? String
        let selectedTemplatePrompt = row["selected_template_prompt"] as? String
        let remoteVersion = (row["remote_version"] as? Int64) ?? Int64((row["remote_version"] as? Int) ?? 1)
        let deletedAt = row["deleted_at"] as? String
        return RemoteMeetingPayload(
            remoteID: id,
            folderRemoteID: folderRemoteID,
            title: title,
            calendarEventID: calendarEventID,
            calendarEventSnapshotJSON: snapshotJSON,
            startTime: startTime,
            endTime: endTime,
            durationSeconds: durationSeconds,
            rawTranscript: rawTranscript,
            formattedNotes: formattedNotes,
            meetingStatus: meetingStatus,
            manualNotes: manualNotes,
            wordCount: wordCount,
            selectedTemplateID: selectedTemplateID,
            selectedTemplateName: selectedTemplateName,
            selectedTemplateKind: selectedTemplateKind,
            selectedTemplatePrompt: selectedTemplatePrompt,
            clientUpdatedAt: clientUpdatedAt,
            serverUpdatedAt: serverUpdatedAt,
            remoteVersion: remoteVersion,
            lastWriterDeviceID: deviceID,
            deletedAt: deletedAt
        )
    }

    private static func parsePreferences(_ row: [String: Any]) -> RemotePreferencesPayload? {
        guard let clientUpdatedAt = row["client_updated_at"] as? String,
              let serverUpdatedAt = row["server_updated_at"] as? String,
              let deviceID = row["last_writer_device_id"] as? String else {
            return nil
        }
        let remoteVersion = (row["remote_version"] as? Int64) ?? Int64((row["remote_version"] as? Int) ?? 1)
        func encodeJSON(_ key: String, fallback: String) -> String {
            guard let object = row[key] else { return fallback }
            if object is NSNull { return fallback }
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                  let s = String(data: data, encoding: .utf8) else {
                return fallback
            }
            return s
        }
        let snapshot = SyncPreferencesSnapshot(
            customMeetingTemplatesJSON: encodeJSON("custom_meeting_templates", fallback: "[]"),
            hiddenBuiltInTemplateIDs: row["hidden_built_in_template_ids"] as? [String] ?? [],
            customWordsJSON: encodeJSON("custom_words", fallback: "[]"),
            defaultMeetingTemplateID: row["default_meeting_template_id"] as? String ?? "auto",
            autoTemplateTargetID: row["auto_template_target_id"] as? String ?? "",
            meetingTitlePrompt: row["meeting_title_prompt"] as? String ?? "",
            folderOrderRemoteIDs: row["folder_order_remote_ids"] as? [String] ?? []
        )
        return RemotePreferencesPayload(
            snapshot: snapshot,
            clientUpdatedAt: clientUpdatedAt,
            serverUpdatedAt: serverUpdatedAt,
            remoteVersion: remoteVersion,
            lastWriterDeviceID: deviceID
        )
    }
}
