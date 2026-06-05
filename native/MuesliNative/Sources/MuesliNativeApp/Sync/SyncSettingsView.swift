import SwiftUI

@MainActor
struct SyncSettingsView: View {
    let appState: AppState
    let controller: MuesliController
    let embedded: Bool

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var inFlight: Bool = false
    @State private var localError: String?

    init(appState: AppState, controller: MuesliController, embedded: Bool = false) {
        self.appState = appState
        self.controller = controller
        self.embedded = embedded
        _email = State(initialValue: Self.suggestedEmail(appState: appState))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            if !embedded {
                header
            }

            if !appState.supabaseSyncConfigured {
                notConfiguredCard
            } else if appState.isSupabaseAuthenticated {
                signedInCard
            } else {
                signInCard
            }
        }
        .onAppear {
            syncSuggestedEmailIfNeeded()
        }
        .onChange(of: appState.supabaseEmail) { _, _ in
            syncSuggestedEmailIfNeeded()
        }
    }

    static func suggestedEmail(appState: AppState) -> String {
        let liveEmail = appState.supabaseEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !liveEmail.isEmpty {
            return liveEmail
        }
        return appState.config.lastSupabaseEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sync")
                .font(.system(size: 24, weight: .semibold))
            Text("Sign in to keep meetings, dictations, folders and templates in sync across your Macs.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var notConfiguredCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sync is not configured for this build.")
                .font(.headline)
            Text("config/Supabase.xcconfig is missing the URL and anon key. Rebuild the app after filling them in.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(MuesliTheme.spacing16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            if appState.supabaseAwaitingEmailConfirmation {
                Label("Check your email to confirm the new account, then sign in.", systemImage: "envelope")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Email").font(.system(size: 12, weight: .medium))
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Password").font(.system(size: 12, weight: .medium))
                SecureField("••••••••", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                Button("Sign in") { Task { await runSignIn() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(inFlight || email.isEmpty || password.isEmpty)
                Button("Create account") { Task { await runSignUp() } }
                    .disabled(inFlight || email.isEmpty || password.isEmpty)
                if inFlight {
                    ProgressView().scaleEffect(0.7)
                }
            }
            if let message = localError ?? appState.supabaseSyncErrorText, !message.isEmpty {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding(MuesliTheme.spacing16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var signedInCard: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            HStack {
                Label(appState.supabaseEmail ?? "Signed in", systemImage: "person.crop.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button("Sign out") { Task { controller.supabaseSignOut() } }
            }
            Divider()
            HStack(spacing: MuesliTheme.spacing24) {
                statTile(label: "Meetings", value: "\(appState.syncedMeetingCount)")
                statTile(label: "Dictations", value: "\(appState.syncedDictationCount)")
                statTile(label: "Folders", value: "\(appState.syncedFolderCount)")
            }
            Divider()
            HStack(spacing: 12) {
                Button {
                    Task { await controller.supabaseSyncNow() }
                } label: {
                    Label("Sync now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                if let last = appState.supabaseLastSyncAt {
                    Text("Last sync: \(Self.relativeFormatter.localizedString(for: last, relativeTo: Date()))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(appState.supabaseSyncStatusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if let err = appState.supabaseSyncErrorText, !err.isEmpty {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding(MuesliTheme.spacing16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func syncSuggestedEmailIfNeeded() {
        guard email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let suggested = Self.suggestedEmail(appState: appState)
        guard !suggested.isEmpty else { return }
        email = suggested
    }

    private func runSignIn() async {
        inFlight = true
        localError = nil
        defer { inFlight = false }
        do {
            try await controller.supabaseSignIn(email: email, password: password)
            password = ""
        } catch {
            localError = error.localizedDescription
        }
    }

    private func runSignUp() async {
        inFlight = true
        localError = nil
        defer { inFlight = false }
        do {
            try await controller.supabaseSignUp(email: email, password: password)
        } catch {
            localError = error.localizedDescription
        }
    }
}
