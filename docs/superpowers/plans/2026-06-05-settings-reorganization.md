# Settings Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize Settings from 9 panes into 5 panes while preserving every existing control.

**Architecture:** Keep `SettingsView` as the owner of the pane picker and shared settings chrome. Convert dictionary, shortcuts, and sync from standalone settings pages into embeddable sections that can live inside the new `General` and `Voice & Dictation` panes. Preserve top-level dashboard routes outside Settings for now.

**Tech Stack:** Swift, SwiftUI, AppKit event monitoring for shortcut capture, Swift Testing.

---

## File Map

- Modify `native/MuesliNative/Sources/MuesliNativeApp/AppState.swift`
  - Replace `SettingsPane` cases with the new 5-pane shape.
- Modify `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`
  - Add `settingsPaneVoiceAndDictation`, `settingsSectionApplication`, `settingsSectionShortcuts`, `settingsSectionSync`, `settingsSectionPrivacyPermissions`, and `settingsSectionAiCleanup`.
- Modify `native/MuesliNative/Sources/MuesliNativeApp/SettingsView.swift`
  - Route the 5 panes.
  - Move Computer Use, shortcuts, and sync into General.
  - Move Dictionary into Voice & Dictation.
  - Keep Meetings, Models, and Appearance top-level.
- Modify `native/MuesliNative/Sources/MuesliNativeApp/DictionaryView.swift`
  - Add an embedded mode that suppresses the page header and outer scroll view.
- Modify `native/MuesliNative/Sources/MuesliNativeApp/ShortcutsView.swift`
  - Add an embedded mode that suppresses the page header and outer scroll view.
- Modify `native/MuesliNative/Sources/MuesliNativeApp/Sync/SyncSettingsView.swift`
  - Add an embedded mode that suppresses the page header.
- Add `native/MuesliNative/Tests/MuesliTests/SettingsPaneTests.swift`
  - Verify pane order and localized labels.
- Modify `native/MuesliNative/Tests/MuesliTests/SyncSettingsViewTests.swift`
  - Keep existing tests compiling after the sync component gains embedded mode.

## Task 1: Pane Model And Localization Tests

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/AppState.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`
- Add: `native/MuesliNative/Tests/MuesliTests/SettingsPaneTests.swift`

- [ ] **Step 1: Write the failing pane tests**

Create `native/MuesliNative/Tests/MuesliTests/SettingsPaneTests.swift`:

```swift
import Testing
@testable import MuesliNativeApp

@Suite("Settings panes")
struct SettingsPaneTests {
    @Test("settings panes use the reorganized order")
    func settingsPaneOrder() {
        #expect(SettingsPane.allCases == [
            .general,
            .voiceAndDictation,
            .meetings,
            .models,
            .appearance,
        ])
    }

    @Test("settings pane titles are localized in English")
    func settingsPaneTitlesEnglish() {
        var config = AppConfig()
        config.appLanguage = AppLanguage.english.rawValue

        #expect(SettingsPane.general.localizedTitle(config: config) == "General")
        #expect(SettingsPane.voiceAndDictation.localizedTitle(config: config) == "Voice & Dictation")
        #expect(SettingsPane.meetings.localizedTitle(config: config) == "Meetings")
        #expect(SettingsPane.models.localizedTitle(config: config) == "Models")
        #expect(SettingsPane.appearance.localizedTitle(config: config) == "Appearance")
    }

    @Test("settings pane titles are localized in Spanish")
    func settingsPaneTitlesSpanish() {
        var config = AppConfig()
        config.appLanguage = AppLanguage.spanish.rawValue

        #expect(SettingsPane.general.localizedTitle(config: config) == "General")
        #expect(SettingsPane.voiceAndDictation.localizedTitle(config: config) == "Voz y dictado")
        #expect(SettingsPane.meetings.localizedTitle(config: config) == "Reuniones")
        #expect(SettingsPane.models.localizedTitle(config: config) == "Modelos")
        #expect(SettingsPane.appearance.localizedTitle(config: config) == "Apariencia")
    }
}
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter SettingsPaneTests
```

Expected: FAIL because `.voiceAndDictation` and `localizedTitle(config:)` do not exist yet.

- [ ] **Step 3: Implement the new pane enum and localized title helper**

In `native/MuesliNative/Sources/MuesliNativeApp/AppState.swift`, replace the old `SettingsPane` enum with:

```swift
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case voiceAndDictation
    case meetings
    case models
    case appearance

    var id: String { rawValue }

    func localizedTitle(config: AppConfig) -> String {
        switch self {
        case .general:
            return L10n.text(.settingsPaneGeneral, config: config)
        case .voiceAndDictation:
            return L10n.text(.settingsPaneVoiceAndDictation, config: config)
        case .meetings:
            return L10n.text(.settingsPaneMeetings, config: config)
        case .models:
            return L10n.text(.sidebarModels, config: config)
        case .appearance:
            return L10n.text(.settingsPaneAppearance, config: config)
        }
    }
}
```

In `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`, add enum cases near the existing settings pane cases:

```swift
case settingsPaneVoiceAndDictation
case settingsSectionApplication
case settingsSectionShortcuts
case settingsSectionSync
case settingsSectionPrivacyPermissions
case settingsSectionAiCleanup
```

Add English returns:

```swift
case .settingsPaneVoiceAndDictation:
    return "Voice & Dictation"
case .settingsSectionApplication:
    return "Application"
case .settingsSectionShortcuts:
    return "Shortcuts"
case .settingsSectionSync:
    return "Sync"
case .settingsSectionPrivacyPermissions:
    return "Privacy & Permissions"
case .settingsSectionAiCleanup:
    return "AI Cleanup"
```

Add Spanish returns:

```swift
case .settingsPaneVoiceAndDictation:
    return "Voz y dictado"
case .settingsSectionApplication:
    return "Aplicacion"
case .settingsSectionShortcuts:
    return "Atajos"
case .settingsSectionSync:
    return "Sincronizacion"
case .settingsSectionPrivacyPermissions:
    return "Privacidad y permisos"
case .settingsSectionAiCleanup:
    return "Limpieza con IA"
```

- [ ] **Step 4: Run pane tests and verify they pass**

Run:

```bash
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter SettingsPaneTests
```

Expected: PASS.

## Task 2: Embed Existing Standalone Settings Views

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/DictionaryView.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/ShortcutsView.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/Sync/SyncSettingsView.swift`

- [ ] **Step 1: Add embedded mode to DictionaryView**

Change the initializer shape to accept `embedded: Bool = false` and render content without the header/scroll wrapper when embedded:

```swift
struct DictionaryView: View {
    let appState: AppState
    let controller: MuesliController
    let embedded: Bool

    init(appState: AppState, controller: MuesliController, embedded: Bool = false) {
        self.appState = appState
        self.controller = controller
        self.embedded = embedded
    }

    var body: some View {
        if embedded {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
                embeddedHeader
                wordList
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                    header
                    wordList
                }
                .padding(MuesliTheme.spacing32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(MuesliTheme.backgroundBase)
        }
    }
}
```

Add `embeddedHeader` with the same add action as the page header but smaller text.

- [ ] **Step 2: Add embedded mode to ShortcutsView**

Add `embedded: Bool = false` to the view, keep default behavior unchanged, and render only the shortcut sections when embedded:

```swift
struct ShortcutsView: View {
    let appState: AppState
    let controller: MuesliController
    let embedded: Bool

    init(appState: AppState, controller: MuesliController, embedded: Bool = false) {
        self.appState = appState
        self.controller = controller
        self.embedded = embedded
    }

    var body: some View {
        Group {
            if embedded {
                content(includeHeader: false)
            } else {
                ScrollView {
                    content(includeHeader: true)
                        .padding(MuesliTheme.spacing32)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onDisappear {
            stopRecording()
        }
    }
}
```

Move the existing body `VStack` into `content(includeHeader:)`.

- [ ] **Step 3: Add embedded mode to SyncSettingsView**

Add `embedded: Bool = false` to the initializer and hide the header when embedded:

```swift
init(appState: AppState, controller: MuesliController, embedded: Bool = false) {
    self.appState = appState
    self.controller = controller
    self.embedded = embedded
    _email = State(initialValue: Self.suggestedEmail(appState: appState))
}
```

Render `header` only when `embedded == false`.

- [ ] **Step 4: Build the app target**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift build --package-path native/MuesliNative -c debug
```

Expected: build succeeds.

## Task 3: Recompose SettingsView Into 5 Panes

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/SettingsView.swift`

- [ ] **Step 1: Use the enum title helper**

Replace `paneTitle(_:)` with:

```swift
private func paneTitle(_ pane: SettingsPane) -> String {
    pane.localizedTitle(config: appState.config)
}
```

- [ ] **Step 2: Route paneContent to the 5 panes**

Replace the `paneContent` switch with:

```swift
switch appState.selectedSettingsPane {
case .general:
    settingsScrollPane { generalSettingsPane }
case .voiceAndDictation:
    settingsScrollPane { voiceAndDictationSettingsPane }
case .meetings:
    settingsScrollPane { meetingsSettingsPane }
case .models:
    ModelsView(appState: appState, controller: controller)
case .appearance:
    settingsScrollPane { appearanceSettingsPane }
}
```

- [ ] **Step 3: Rename and rebuild the dictation pane**

Rename `dictationSettingsPane` to `voiceAndDictationSettingsPane`.

Split the old transcription section into:

- `Transcription`
- `AI Cleanup`
- `Dictionary`
- `Advanced`

Embed the dictionary section with:

```swift
settingsSection(L10n.text(.dictionaryTitle, config: appState.config)) {
    DictionaryView(appState: appState, controller: controller, embedded: true)
}
```

Keep only one `screenContextRow` in Advanced.

- [ ] **Step 4: Expand General with embedded sections**

In `generalSettingsPane`, keep application controls first, then add:

```swift
settingsSection(L10n.text(.settingsSectionShortcuts, config: appState.config)) {
    ShortcutsView(appState: appState, controller: controller, embedded: true)
}

settingsSection(L10n.text(.settingsSectionSync, config: appState.config)) {
    SyncSettingsView(appState: appState, controller: controller, embedded: true)
}

settingsSection("Computer Use") {
    computerUseSettingsContent
}
```

Move the body of `computerUseSettingsPane` into `computerUseSettingsContent` so it can be embedded without a nested section.

- [ ] **Step 5: Keep permissions and data in General**

Rename the existing `permissionsSection` title to:

```swift
settingsSection(L10n.text(.settingsSectionPrivacyPermissions, config: appState.config)) {
    ...
}
```

Keep the existing data section after permissions.

- [ ] **Step 6: Build the app target**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift build --package-path native/MuesliNative -c debug
```

Expected: build succeeds with no references to removed settings pane cases.

## Task 4: Verification And Commit

**Files:**
- Verify all modified source files.

- [ ] **Step 1: Run targeted tests**

Run:

```bash
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter SettingsPaneTests
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter SyncSettingsViewTests
```

Expected: both commands pass.

- [ ] **Step 2: Run a debug build**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/muesli-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/muesli-swiftpm-cache MUESLI_SWIFTPM_SCRATCH_PATH=/private/tmp/muesli-swiftpm-scratch swift build --package-path native/MuesliNative -c debug
```

Expected: build succeeds.

- [ ] **Step 3: Review changed files**

Run:

```bash
git diff -- native/MuesliNative/Sources/MuesliNativeApp/AppState.swift native/MuesliNative/Sources/MuesliNativeApp/L10n.swift native/MuesliNative/Sources/MuesliNativeApp/SettingsView.swift native/MuesliNative/Sources/MuesliNativeApp/DictionaryView.swift native/MuesliNative/Sources/MuesliNativeApp/ShortcutsView.swift native/MuesliNative/Sources/MuesliNativeApp/Sync/SyncSettingsView.swift native/MuesliNative/Tests/MuesliTests/SettingsPaneTests.swift native/MuesliNative/Tests/MuesliTests/SyncSettingsViewTests.swift
```

Expected: diff only contains the settings reorganization and test coverage.

- [ ] **Step 4: Commit only this implementation**

Run:

```bash
git add docs/superpowers/plans/2026-06-05-settings-reorganization.md native/MuesliNative/Sources/MuesliNativeApp/AppState.swift native/MuesliNative/Sources/MuesliNativeApp/L10n.swift native/MuesliNative/Sources/MuesliNativeApp/SettingsView.swift native/MuesliNative/Sources/MuesliNativeApp/DictionaryView.swift native/MuesliNative/Sources/MuesliNativeApp/ShortcutsView.swift native/MuesliNative/Sources/MuesliNativeApp/Sync/SyncSettingsView.swift native/MuesliNative/Tests/MuesliTests/SettingsPaneTests.swift native/MuesliNative/Tests/MuesliTests/SyncSettingsViewTests.swift
git commit -m "feat: reorganize settings panes"
```

Expected: commit includes only plan and settings reorganization files.

