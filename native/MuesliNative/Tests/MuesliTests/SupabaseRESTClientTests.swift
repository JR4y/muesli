import Foundation
import MuesliMeetingChat
import MuesliCore
import Testing
@testable import MuesliNativeApp

@MainActor
@Suite("Supabase REST client", .serialized)
struct SupabaseRESTClientTests {
    @Test("upserts archived folder and meeting fields through PostgREST")
    func upsertsArchiveFields() async throws {
        let recorder = RequestRecorder()
        let session = URLSession(configuration: recorder.configuration(responseBodies: [
            [
                "id": "11111111-1111-1111-1111-111111111111",
                "parent_folder_id": NSNull(),
                "name": "Archive Folder",
                "color_hex": NSNull(),
                "icon_name": NSNull(),
                "sort_order": 0,
                "client_updated_at": "2026-06-06T11:00:00.000Z",
                "server_updated_at": "2026-06-06T11:00:01.000Z",
                "remote_version": 1,
                "last_writer_device_id": "device-a",
                "deleted_at": NSNull(),
                "archived_at": "2026-06-06T11:00:00.000Z",
            ],
            [
                "id": "22222222-2222-2222-2222-222222222222",
                "folder_id": "11111111-1111-1111-1111-111111111111",
                "merged_into_meeting_id": NSNull(),
                "title": "Archive Meeting",
                "calendar_event_id": NSNull(),
                "calendar_event_snapshot": NSNull(),
                "start_time": "2026-06-06T10:00:00.000Z",
                "end_time": NSNull(),
                "duration_seconds": 60,
                "raw_transcript": "Transcript",
                "formatted_notes": "Notes",
                "meeting_status": "completed",
                "manual_notes": "",
                "word_count": 2,
                "selected_template_id": NSNull(),
                "selected_template_name": NSNull(),
                "selected_template_kind": NSNull(),
                "selected_template_prompt": NSNull(),
                "client_updated_at": "2026-06-06T11:00:00.000Z",
                "server_updated_at": "2026-06-06T11:00:01.000Z",
                "remote_version": 1,
                "last_writer_device_id": "device-a",
                "deleted_at": NSNull(),
                "archived_at": "2026-06-06T11:00:00.000Z",
            ],
        ]))
        let config = SupabaseConfig(
            baseURL: URL(string: "https://example.supabase.co")!,
            anonKey: "anon-key"
        )
        let auth = try authenticatedManager(config: config)
        let client = SupabaseRESTClient(config: config, auth: auth, urlSession: session)

        let folder = try await client.upsertFolder(
            remoteID: nil,
            userID: "user-id",
            parentRemoteID: nil,
            name: "Archive Folder",
            colorHex: nil,
            iconName: nil,
            sortOrder: 0,
            clientUpdatedAt: "2026-06-06T11:00:00.000Z",
            deviceID: "device-a",
            deletedAt: nil,
            archivedAt: "2026-06-06T11:00:00.000Z"
        )
        let meeting = try await client.upsertMeeting(
            remoteID: nil,
            userID: "user-id",
            folderRemoteID: "11111111-1111-1111-1111-111111111111",
            mergedIntoMeetingRemoteID: nil,
            title: "Archive Meeting",
            calendarEventID: nil,
            calendarEventSnapshotJSON: nil,
            startTime: "2026-06-06T10:00:00.000Z",
            endTime: nil,
            durationSeconds: 60,
            rawTranscript: "Transcript",
            formattedNotes: "Notes",
            meetingStatus: "completed",
            manualNotes: "",
            wordCount: 2,
            selectedTemplateID: nil,
            selectedTemplateName: nil,
            selectedTemplateKind: nil,
            selectedTemplatePrompt: nil,
            clientUpdatedAt: "2026-06-06T11:00:00.000Z",
            deviceID: "device-a",
            deletedAt: nil,
            archivedAt: "2026-06-06T11:00:00.000Z"
        )

        #expect(folder.archivedAt == "2026-06-06T11:00:00.000Z")
        #expect(meeting.archivedAt == "2026-06-06T11:00:00.000Z")
        #expect(try jsonBody(recorder.requests[0])["archived_at"] as? String == "2026-06-06T11:00:00.000Z")
        #expect(try jsonBody(recorder.requests[1])["archived_at"] as? String == "2026-06-06T11:00:00.000Z")
    }

    @Test("upserts chat thread and message through PostgREST")
    func upsertsChatThreadAndMessage() async throws {
        let recorder = RequestRecorder()
        let session = URLSession(configuration: recorder.configuration(responseBodies: [
            [
                "id": "11111111-1111-1111-1111-111111111111",
                "scope_kind": "meeting",
                "scope_id": "22222222-2222-2222-2222-222222222222",
                "title": "Chat",
                "summary": "",
                "client_updated_at": "2026-06-05T10:00:00.000Z",
                "server_updated_at": "2026-06-05T10:00:01.000Z",
                "remote_version": 1,
                "last_writer_device_id": "device-a",
                "deleted_at": NSNull(),
            ],
            [
                "id": "33333333-3333-3333-3333-333333333333",
                "thread_id": "11111111-1111-1111-1111-111111111111",
                "role": "user",
                "content": "Hello",
                "sources_json": [],
                "created_at": "2026-06-05T10:00:02.000Z",
                "client_updated_at": "2026-06-05T10:00:02.000Z",
                "server_updated_at": "2026-06-05T10:00:03.000Z",
                "remote_version": 1,
                "last_writer_device_id": "device-a",
                "deleted_at": NSNull(),
            ],
        ]))
        let config = SupabaseConfig(
            baseURL: URL(string: "https://example.supabase.co")!,
            anonKey: "anon-key"
        )
        let auth = try authenticatedManager(config: config)
        let client = SupabaseRESTClient(config: config, auth: auth, urlSession: session)

        _ = try await client.upsertMeetingChatThread(
            remoteID: nil,
            userID: "user-id",
            scopeKind: "meeting",
            scopeRemoteID: "22222222-2222-2222-2222-222222222222",
            title: "Chat",
            summary: "",
            clientUpdatedAt: "2026-06-05T10:00:00.000Z",
            deviceID: "device-a",
            deletedAt: nil
        )
        _ = try await client.upsertMeetingChatMessage(
            remoteID: nil,
            userID: "user-id",
            threadRemoteID: "11111111-1111-1111-1111-111111111111",
            role: .user,
            content: "Hello",
            sources: [],
            createdAt: "2026-06-05T10:00:02.000Z",
            clientUpdatedAt: "2026-06-05T10:00:02.000Z",
            deviceID: "device-a",
            deletedAt: nil
        )

        #expect(recorder.requests.map { $0.url?.path } == [
            "/rest/v1/meeting_chat_threads",
            "/rest/v1/meeting_chat_messages",
        ])
        #expect(recorder.requests.map(\.httpMethod) == ["POST", "POST"])
    }

    @Test("purge deleted sync rows physically deletes all soft-deleted sync tables")
    func purgeDeletedSyncRowsDeletesAllTables() async throws {
        let recorder = RequestRecorder()
        let session = URLSession(configuration: recorder.configuration())
        let config = SupabaseConfig(
            baseURL: URL(string: "https://example.supabase.co")!,
            anonKey: "anon-key"
        )
        let auth = try authenticatedManager(config: config)
        let client = SupabaseRESTClient(config: config, auth: auth, urlSession: session)

        try await client.purgeDeletedSyncRows()

        let requests = recorder.requests
        #expect(requests.count == 5)
        #expect(requests.map(\.httpMethod) == ["DELETE", "DELETE", "DELETE", "DELETE", "DELETE"])
        #expect(requests.map { $0.url?.path } == [
            "/rest/v1/meeting_chat_messages",
            "/rest/v1/meeting_chat_threads",
            "/rest/v1/meetings",
            "/rest/v1/dictations",
            "/rest/v1/meeting_folders",
        ])
        for request in requests {
            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.queryItems?.contains(URLQueryItem(name: "deleted_at", value: "not.is.null")) == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        }
    }

    private func authenticatedManager(config: SupabaseConfig) throws -> SupabaseAuthManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-rest-client-test-\(UUID().uuidString)", isDirectory: true)
        let store = SupabaseAuthSessionStore(fileURL: directory.appendingPathComponent("supabase-auth.json"))
        try store.save(SupabaseSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3_600),
            userID: "user-id",
            email: "sync@example.com"
        ))
        return SupabaseAuthManager(
            config: config,
            keychain: SupabaseKeychainStore(service: "muesli-rest-client-test-\(UUID().uuidString)"),
            sessionStore: store
        )
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let body = try bodyData(request)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func bodyData(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read < 0 {
                throw stream.streamError ?? CocoaError(.fileReadUnknown)
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []
    private var responseBodies: [[String: Any]] = []
    private var responseIndex = 0

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        let recorder = self
        RecordingURLProtocol.handler = { request in
            recorder.lock.lock()
            recorder.storage.append(request)
            recorder.lock.unlock()
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!, Data())
        }
        configuration.protocolClasses = [RecordingURLProtocol.self]
        return configuration
    }

    func configuration(responseBodies: [[String: Any]]) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        let recorder = self
        recorder.setResponseBodies(responseBodies)
        RecordingURLProtocol.handler = { request in
            recorder.lock.lock()
            recorder.storage.append(request)
            let body = recorder.nextResponseBodyLocked()
            recorder.lock.unlock()

            let data = try JSONSerialization.data(withJSONObject: [body])
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, data)
        }
        configuration.protocolClasses = [RecordingURLProtocol.self]
        return configuration
    }

    private func setResponseBodies(_ bodies: [[String: Any]]) {
        lock.lock()
        responseBodies = bodies
        responseIndex = 0
        lock.unlock()
    }

    private func nextResponseBodyLocked() -> [String: Any] {
        let body = responseIndex < responseBodies.count ? responseBodies[responseIndex] : [:]
        responseIndex += 1
        return body
    }
}

private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) = { _ in
        (HTTPURLResponse(), Data())
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
