import Foundation

/// Static configuration for the Supabase backend, read from `Info.plist` at
/// launch. Values are injected by `scripts/build_native_app.sh` from
/// `config/Supabase.xcconfig` (gitignored). When neither value is configured
/// the app keeps working — sync features simply remain inert.
struct SupabaseConfig {
    let baseURL: URL
    let anonKey: String

    static let infoPlistURLKey = "MuesliSupabaseURL"
    static let infoPlistAnonKeyKey = "MuesliSupabaseAnonKey"

    /// Bundle-namespaced Keychain service used for refresh-token persistence.
    /// Each app variant (production, beta, dev, canary) gets its own service
    /// because each has its own `CFBundleIdentifier`.
    static var keychainService: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.muesli.app"
        return "\(bundleID).supabase-auth"
    }

    static func resolve(bundle: Bundle = .main) -> SupabaseConfig? {
        guard
            let urlString = trimmed(bundle.object(forInfoDictionaryKey: infoPlistURLKey)),
            !urlString.isEmpty,
            let url = URL(string: urlString),
            let anon = trimmed(bundle.object(forInfoDictionaryKey: infoPlistAnonKeyKey)),
            !anon.isEmpty
        else {
            return nil
        }
        return SupabaseConfig(baseURL: url, anonKey: anon)
    }

    /// `<base>/auth/v1/<path>`
    func authURL(_ path: String, query: [URLQueryItem] = []) -> URL {
        endpoint(prefix: "/auth/v1", path: path, query: query)
    }

    /// `<base>/rest/v1/<path>`
    func restURL(_ path: String, query: [URLQueryItem] = []) -> URL {
        endpoint(prefix: "/rest/v1", path: path, query: query)
    }

    private func endpoint(prefix: String, path: String, query: [URLQueryItem]) -> URL {
        let normalized = path.hasPrefix("/") ? path : "/\(path)"
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = "\(prefix)\(normalized)"
        if !query.isEmpty {
            components.queryItems = query
        }
        return components.url ?? baseURL
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let stripped = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }
}
