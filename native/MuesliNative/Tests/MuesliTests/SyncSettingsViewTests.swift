import Testing
@testable import MuesliNativeApp

@MainActor
@Suite("Sync settings view")
struct SyncSettingsViewTests {
    @Test("suggested email prefers active Supabase session email")
    func suggestedEmailPrefersActiveSessionEmail() {
        let appState = AppState()
        appState.config.lastSupabaseEmail = "stored@example.com"
        appState.supabaseEmail = "session@example.com"

        #expect(SyncSettingsView.suggestedEmail(appState: appState) == "session@example.com")
    }

    @Test("suggested email falls back to stored email when session email is unavailable")
    func suggestedEmailFallsBackToStoredEmail() {
        let appState = AppState()
        appState.config.lastSupabaseEmail = "stored@example.com"
        appState.supabaseEmail = nil

        #expect(SyncSettingsView.suggestedEmail(appState: appState) == "stored@example.com")
    }
}
