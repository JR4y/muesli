import Foundation
import Observation

enum SupabaseAuthError: Error, LocalizedError {
    case notConfigured
    case invalidCredentials(message: String)
    case emailConfirmationPending
    case networkFailure(underlying: Error)
    case decodingFailure(message: String)
    case serverError(status: Int, message: String)
    case noActiveSession
    case persistenceFailure(message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase sync is not configured for this build."
        case .invalidCredentials(let message):
            return message.isEmpty ? "Invalid email or password." : message
        case .emailConfirmationPending:
            return "Account created. Please confirm your email and sign in."
        case .networkFailure(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .decodingFailure(let message):
            return "Could not parse Supabase response: \(message)"
        case .serverError(let status, let message):
            return "Supabase returned \(status): \(message)"
        case .noActiveSession:
            return "Not signed in to Supabase."
        case .persistenceFailure(let message):
            return "Could not save Supabase session: \(message)"
        }
    }
}

struct SupabaseSession: Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?
}

struct SupabaseAuthSessionStore {
    let fileURL: URL

    init(fileURL: URL = AppIdentity.supportDirectoryURL.appendingPathComponent("supabase-auth.json")) {
        self.fileURL = fileURL
    }

    func load() throws -> SupabaseSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.session
    }

    func save(_ session: SupabaseSession) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Payload(session: session))
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private struct Payload: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: String
        var userID: String
        var email: String?

        init(session: SupabaseSession) {
            accessToken = session.accessToken
            refreshToken = session.refreshToken
            expiresAt = SupabaseAuthDateFormatter.format(session.expiresAt)
            userID = session.userID
            email = session.email
        }

        var session: SupabaseSession? {
            guard
                !refreshToken.isEmpty,
                !userID.isEmpty,
                let parsedExpiresAt = SupabaseAuthDateFormatter.parse(expiresAt)
            else {
                return nil
            }
            return SupabaseSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: parsedExpiresAt,
                userID: userID,
                email: email
            )
        }
    }
}

/// Owns the Supabase user session: signup, signin, refresh, signout. Persists
/// the session in app support and mirrors it to Keychain. Pure REST against
/// Supabase Auth — no SDK.
@MainActor
@Observable
final class SupabaseAuthManager {
    private(set) var isAuthenticated: Bool = false
    private(set) var userID: String?
    private(set) var email: String?
    private(set) var lastError: SupabaseAuthError?
    /// `true` between signup and email confirmation when "Confirm email" is on.
    private(set) var awaitingEmailConfirmation: Bool = false

    private let config: SupabaseConfig?
    private let keychain: SupabaseKeychainStore
    private let sessionStore: SupabaseAuthSessionStore
    private let session: URLSession
    private var currentSession: SupabaseSession?
    private var inFlightRefresh: Task<String, Error>?

    init(
        config: SupabaseConfig? = SupabaseConfig.resolve(),
        keychain: SupabaseKeychainStore = SupabaseKeychainStore(),
        sessionStore: SupabaseAuthSessionStore = SupabaseAuthSessionStore(),
        urlSession: URLSession = .shared
    ) {
        self.config = config
        self.keychain = keychain
        self.sessionStore = sessionStore
        self.session = urlSession
        restoreSessionFromPersistentStorage()
    }

    var isConfigured: Bool { config != nil }

    // MARK: - Public API

    func signUp(email: String, password: String) async throws {
        guard let config else { throw SupabaseAuthError.notConfigured }
        let payload: [String: Any] = ["email": email, "password": password]
        let response: SupabaseAuthResponse = try await postJSON(
            url: config.authURL("signup"),
            body: payload
        )
        if let session = response.intoSession() {
            try persist(session: session)
        } else {
            // Email confirmation required — no session yet.
            awaitingEmailConfirmation = true
            self.email = email
        }
    }

    func signIn(email: String, password: String) async throws {
        guard let config else { throw SupabaseAuthError.notConfigured }
        let payload: [String: Any] = ["email": email, "password": password]
        let response: SupabaseAuthResponse = try await postJSON(
            url: config.authURL("token", query: [URLQueryItem(name: "grant_type", value: "password")]),
            body: payload
        )
        guard let session = response.intoSession() else {
            throw SupabaseAuthError.invalidCredentials(message: "Sign in did not return a session.")
        }
        awaitingEmailConfirmation = false
        try persist(session: session)
    }

    func signOut() {
        currentSession = nil
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        sessionStore.delete()
        keychain.wipeAll()
        isAuthenticated = false
        userID = nil
        email = nil
        awaitingEmailConfirmation = false
        lastError = nil
    }

    /// Returns a valid access token for use as `Authorization: Bearer <token>`,
    /// refreshing if the cached one is within 30s of expiry. Throws
    /// `noActiveSession` when the user is not signed in.
    func currentAccessToken() async throws -> String {
        guard let _ = config else { throw SupabaseAuthError.notConfigured }
        guard let session = currentSession else {
            throw SupabaseAuthError.noActiveSession
        }
        if session.expiresAt.timeIntervalSinceNow > 30 {
            return session.accessToken
        }
        return try await refreshAccessToken()
    }

    var anonKey: String? { config?.anonKey }
    var configured: SupabaseConfig? { config }
    var sessionSnapshot: SupabaseSession? { currentSession }

    // MARK: - Token refresh

    private func refreshAccessToken() async throws -> String {
        if let inFlight = inFlightRefresh {
            return try await inFlight.value
        }
        let task = Task<String, Error> { [weak self] in
            try await self?.performRefresh() ?? ""
        }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        guard let config else { throw SupabaseAuthError.notConfigured }
        guard let refresh = currentSession?.refreshToken, !refresh.isEmpty else {
            throw SupabaseAuthError.noActiveSession
        }
        do {
            let response: SupabaseAuthResponse = try await postJSON(
                url: config.authURL(
                    "token",
                    query: [URLQueryItem(name: "grant_type", value: "refresh_token")]
                ),
                body: ["refresh_token": refresh]
            )
            guard let session = response.intoSession() else {
                throw SupabaseAuthError.noActiveSession
            }
            try persist(session: session)
            return session.accessToken
        } catch SupabaseAuthError.serverError(let status, _) where status == 400 || status == 401 {
            // Refresh token is no longer valid — local session is dead.
            signOut()
            throw SupabaseAuthError.noActiveSession
        }
    }

    // MARK: - Persistence

    private func persist(session: SupabaseSession) throws {
        do {
            try sessionStore.save(session)
        } catch {
            lastError = .persistenceFailure(message: error.localizedDescription)
            throw SupabaseAuthError.persistenceFailure(message: error.localizedDescription)
        }
        currentSession = session
        keychain.write(session.refreshToken, for: .refreshToken)
        keychain.write(session.accessToken, for: .accessToken)
        keychain.write(SupabaseAuthDateFormatter.format(session.expiresAt), for: .expiresAt)
        keychain.write(session.userID, for: .userID)
        if let email = session.email {
            keychain.write(email, for: .email)
        } else {
            keychain.delete(.email)
        }
        isAuthenticated = true
        userID = session.userID
        email = session.email
        awaitingEmailConfirmation = false
        lastError = nil
    }

    private func restoreSessionFromPersistentStorage() {
        do {
            if let session = try sessionStore.load() {
                applyRestored(session: session)
                return
            }
        } catch {
            fputs("[muesli-sync] failed to restore Supabase session file: \(error)\n", stderr)
        }
        restoreSessionFromKeychain()
    }

    private func restoreSessionFromKeychain() {
        guard
            let refresh = keychain.read(.refreshToken), !refresh.isEmpty,
            let userID = keychain.read(.userID), !userID.isEmpty
        else {
            return
        }
        let access = keychain.read(.accessToken) ?? ""
        let expiresAtString = keychain.read(.expiresAt) ?? ""
        let expiresAt = SupabaseAuthDateFormatter.parse(expiresAtString) ?? Date(timeIntervalSince1970: 0)
        let storedEmail = keychain.read(.email)
        let session = SupabaseSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiresAt,
            userID: userID,
            email: storedEmail
        )
        applyRestored(session: session)
        try? sessionStore.save(session)
    }

    private func applyRestored(session: SupabaseSession) {
        currentSession = session
        userID = session.userID
        email = session.email
        isAuthenticated = true
    }

    // MARK: - Networking

    private func postJSON<T: Decodable>(url: URL, body: [String: Any]) async throws -> T {
        guard let config else { throw SupabaseAuthError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SupabaseAuthError.networkFailure(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.serverError(status: -1, message: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.parseErrorMessage(from: data)
            if http.statusCode == 400 || http.statusCode == 401 {
                throw SupabaseAuthError.invalidCredentials(message: message)
            }
            throw SupabaseAuthError.serverError(status: http.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SupabaseAuthError.decodingFailure(message: String(describing: error))
        }
    }

    private static func parseErrorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }
        if let msg = object["msg"] as? String { return msg }
        if let msg = object["error_description"] as? String { return msg }
        if let msg = object["message"] as? String { return msg }
        return "Unknown error"
    }
}

// MARK: - Wire types

private struct SupabaseAuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Int?
    let expiresIn: Int?
    let user: SupabaseUserPayload?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case user
    }

    func intoSession() -> SupabaseSession? {
        guard
            let access = accessToken, !access.isEmpty,
            let refresh = refreshToken, !refresh.isEmpty,
            let user
        else {
            return nil
        }
        let expires: Date
        if let expiresAt {
            expires = Date(timeIntervalSince1970: TimeInterval(expiresAt))
        } else if let expiresIn {
            expires = Date().addingTimeInterval(TimeInterval(expiresIn))
        } else {
            expires = Date().addingTimeInterval(3600)
        }
        return SupabaseSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expires,
            userID: user.id,
            email: user.email
        )
    }
}

private struct SupabaseUserPayload: Decodable {
    let id: String
    let email: String?
}

enum SupabaseAuthDateFormatter {
    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: string) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
