import Foundation
import Testing
@testable import MuesliNativeApp

@MainActor
@Suite("Embedded settings views")
struct SettingsEmbeddedViewTests {
    @Test("settings support embedded dictionary shortcuts and sync sections")
    func embeddedSettingsViewsCompile() {
        let appState = AppState()
        let controller = MuesliController(
            runtime: RuntimePaths(
                repoRoot: FileManager.default.temporaryDirectory,
                menuIcon: nil,
                appIcon: nil,
                bundlePath: nil
            )
        )

        _ = DictionaryView(appState: appState, controller: controller, embedded: true)
        _ = ShortcutsView(appState: appState, controller: controller, embedded: true)
        _ = SyncSettingsView(appState: appState, controller: controller, embedded: true)
    }
}
