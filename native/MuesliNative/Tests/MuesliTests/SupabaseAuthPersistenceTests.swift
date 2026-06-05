import Foundation
import Testing
@testable import MuesliNativeApp

@MainActor
@Suite("Supabase auth persistence")
struct SupabaseAuthPersistenceTests {
    @Test("sync cycle downloads and uploads meeting chat after meetings")
    func syncCycleOrdersMeetingChatAfterMeetings() throws {
        let sourceURL = URL(fileURLWithPath: "Sources/MuesliNativeApp/Sync/SupabaseSyncManager.swift")
        let source = try String(contentsOf: sourceURL)
        let downloadMeetings = try #require(source.range(of: "try await downloadMeetings(rest: rest)"))
        let downloadChatThreads = try #require(
            source.range(
                of: "try await downloadMeetingChatThreads(rest: rest)",
                range: downloadMeetings.upperBound..<source.endIndex
            )
        )
        _ = try #require(
            source.range(
                of: "try await downloadMeetingChatMessages(rest: rest)",
                range: downloadChatThreads.upperBound..<source.endIndex
            )
        )
        let uploadMeetings = try #require(source.range(of: "try await uploadMeetings(rest: rest, userID: userID)"))
        let uploadChatThreads = try #require(
            source.range(
                of: "try await uploadMeetingChatThreads(rest: rest, userID: userID)",
                range: uploadMeetings.upperBound..<source.endIndex
            )
        )
        _ = try #require(
            source.range(
                of: "try await uploadMeetingChatMessages(rest: rest, userID: userID)",
                range: uploadChatThreads.upperBound..<source.endIndex
            )
        )
    }

    @Test("file-backed session store restores auth across manager instances")
    func fileBackedSessionRestoresAuth() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let session = SupabaseSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            userID: "user-123",
            email: "sync@example.com"
        )
        try fixture.store.save(session)

        let restored = SupabaseAuthManager(
            config: fixture.config,
            keychain: SupabaseKeychainStore(service: fixture.keychainService),
            sessionStore: fixture.store
        )

        #expect(restored.isAuthenticated)
        #expect(restored.sessionSnapshot == session)
        #expect(restored.email == "sync@example.com")
    }

    @Test("file-backed session store restricts file permissions")
    func fileBackedSessionStoreRestrictsFilePermissions() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        try fixture.store.save(SupabaseSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            userID: "user-123",
            email: "sync@example.com"
        ))

        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.store.fileURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue == 0o600)
    }

    @Test("controller mirrors restored Supabase auth into app state")
    func controllerMirrorsRestoredAuthSession() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        try fixture.store.save(SupabaseSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            userID: "user-123",
            email: "sync@example.com"
        ))
        let auth = SupabaseAuthManager(
            config: fixture.config,
            keychain: SupabaseKeychainStore(service: fixture.keychainService),
            sessionStore: fixture.store
        )
        let controller = MuesliController(
            runtime: RuntimePaths(
                repoRoot: fixture.directory,
                menuIcon: nil,
                appIcon: nil,
                bundlePath: nil
            )
        )

        controller.supabaseAuth = auth
        controller.syncAppState()

        #expect(controller.appState.supabaseSyncConfigured)
        #expect(controller.appState.isSupabaseAuthenticated)
        #expect(controller.appState.supabaseEmail == "sync@example.com")
    }

    @Test("app launch mirrors restored Supabase auth after wiring sync")
    func appLaunchMirrorsRestoredSupabaseAuthAfterWiring() throws {
        let source = try appDelegateSource()

        let wiringIndex = try #require(source.firstRange(of: "controller.syncManager = syncManager"))
        let mirrorIndex = try #require(source.range(of: "controller.syncAppState()", range: wiringIndex.upperBound..<source.endIndex))
        let startIndex = try #require(source.range(of: "await syncManager.start()", range: mirrorIndex.upperBound..<source.endIndex))
        _ = try #require(source.range(
            of: "await MainActor.run { controller.syncAppState() }",
            range: startIndex.upperBound..<source.endIndex
        ))
    }

    private struct Fixture {
        let directory: URL
        let store: SupabaseAuthSessionStore
        let config: SupabaseConfig
        let keychainService: String
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-supabase-auth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return Fixture(
            directory: directory,
            store: SupabaseAuthSessionStore(fileURL: directory.appendingPathComponent("supabase-auth.json")),
            config: SupabaseConfig(baseURL: URL(string: "https://example.supabase.co")!, anonKey: "anon-key"),
            keychainService: "test.muesli.supabase.\(UUID().uuidString)"
        )
    }

    private func appDelegateSource() throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appDelegateURL = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("MuesliNativeApp")
            .appendingPathComponent("AppDelegate.swift")
        return try String(contentsOf: appDelegateURL, encoding: .utf8)
    }
}
