# Main Window Titlebar Controls Implementation Plan

Status: Completed on `beta`, later partially superseded when quick note moved out of the titlebar on 2026-06-02

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unstable SwiftUI/native toolbar mix with a real titlebar integration that keeps one fixed sidebar toggle on the left and one fixed quick note action on the right.

**Architecture:** Move sidebar visibility into app-owned shell state, replace `NavigationSplitView` with a small custom split shell, and install titlebar accessory views from AppKit so the visible controls live in the real macOS titlebar instead of the content area or a SwiftUI `ToolbarItem`.

**Tech Stack:** SwiftUI, AppKit, Observation (`@Observable`), Swift Testing, local beta installer script (`scripts/beta-test.sh`)

## Post-Implementation Notes

- The main architectural goal was achieved: the dashboard now uses an
  app-controlled split shell and AppKit titlebar accessories instead of a
  SwiftUI `ToolbarItem` plus `NavigationSplitView` mix.
- Real-world validation showed an AppKit constraint that mattered for the last
  UX mile: lateral `NSTitlebarAccessoryViewController` placements do not give
  enough effective vertical freedom to make a taller quick-note pill feel
  better just by increasing hosted SwiftUI height or padding.
- The final shipped compromise is therefore:
  - left: compact sidebar toggle
  - right: compact `+ Nota` pill at standard widths
  - narrow-window fallback: icon-only `+`
- The meetings browser was also adjusted during validation so the top
  `Proximamente` block can stay pinned while the lower meetings list scrolls
  independently.
- Follow-up validation on `2026-06-02` kept the left sidebar accessory but
  removed the right quick-note titlebar control entirely; the final quick-note
  CTA now lives inside the meetings surface as `Nota rápida`.

---

## File Map

**Create**
- `native/MuesliNative/Sources/MuesliNativeApp/DashboardSplitShell.swift` — app-owned sidebar/detail split shell with explicit visibility state
- `native/MuesliNative/Sources/MuesliNativeApp/MainWindowTitlebarController.swift` — installs and retains left/right titlebar accessory hosting views
- `native/MuesliNative/Tests/MuesliTests/DashboardSplitShellTests.swift` — tests shell sizing and visibility helpers
- `native/MuesliNative/Tests/MuesliTests/MainWindowTitlebarControllerTests.swift` — tests compact/full quick note layout and visibility helpers

**Modify**
- `native/MuesliNative/Sources/MuesliNativeApp/AppState.swift` — add `isSidebarVisible`
- `native/MuesliNative/Sources/MuesliNativeApp/DashboardRootView.swift` — remove the prototype content top bar, switch to `DashboardSplitShell`, keep quick note visibility logic
- `native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift` — retain and install `MainWindowTitlebarController`
- `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift` — add localized help text for the custom sidebar titlebar button
- `native/MuesliNative/Tests/MuesliTests/DashboardRootViewTests.swift` — cover quick note visibility and default sidebar shell state

**Leave Untouched**
- `native/MuesliNative/Sources/MuesliNativeApp/SidebarView.swift` — sidebar content itself should not be redesigned
- `native/MuesliNative/Sources/MuesliNativeApp/MeetingsView.swift` — no behavior change required

### Task 1: Introduce Shell State And Titlebar Visibility Rules

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/AppState.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/DashboardRootView.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`
- Modify: `native/MuesliNative/Tests/MuesliTests/DashboardRootViewTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import MuesliNativeApp

@Suite("Dashboard root view")
struct DashboardRootViewTests {
    @Test("quick note titlebar control only appears in meetings when search is inactive")
    func quickNoteTitlebarVisibility() {
        #expect(DashboardRootView.showsQuickNoteTitlebarControl(isSearchActive: false, selectedTab: .meetings))
        #expect(!DashboardRootView.showsQuickNoteTitlebarControl(isSearchActive: true, selectedTab: .meetings))
        #expect(!DashboardRootView.showsQuickNoteTitlebarControl(isSearchActive: false, selectedTab: .dictations))
    }

    @Test("sidebar shell starts visible by default")
    func sidebarStartsVisible() {
        let appState = AppState()
        #expect(appState.isSidebarVisible)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/titlebar-plan --filter DashboardRootViewTests
```

Expected: FAIL because `showsQuickNoteTitlebarControl` and `isSidebarVisible` do not exist yet.

- [ ] **Step 3: Add the minimal state and helper implementation**

```swift
// AppState.swift
@MainActor
@Observable
final class AppState {
    // Navigation
    var selectedTab: DashboardTab = .meetings
    var selectedSettingsPane: SettingsPane = .general
    var isSidebarVisible: Bool = true
}
```

```swift
// DashboardRootView.swift
struct DashboardRootView: View {
    static func showsQuickNoteTitlebarControl(isSearchActive: Bool, selectedTab: DashboardTab) -> Bool {
        !isSearchActive && selectedTab == .meetings
    }
}
```

```swift
// L10n.swift
case titlebarToggleSidebarHelp

// English
case .titlebarToggleSidebarHelp: return "Toggle sidebar"

// Spanish
case .titlebarToggleSidebarHelp: return "Mostrar u ocultar barra lateral"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/titlebar-plan --filter DashboardRootViewTests
```

Expected: PASS for both tests in `DashboardRootViewTests`.

- [ ] **Step 5: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/AppState.swift \
        native/MuesliNative/Sources/MuesliNativeApp/DashboardRootView.swift \
        native/MuesliNative/Sources/MuesliNativeApp/L10n.swift \
        native/MuesliNative/Tests/MuesliTests/DashboardRootViewTests.swift
git commit -m "feat: add titlebar shell state"
```

### Task 2: Replace NavigationSplitView With An App-Owned Dashboard Split Shell

**Files:**
- Create: `native/MuesliNative/Sources/MuesliNativeApp/DashboardSplitShell.swift`
- Create: `native/MuesliNative/Tests/MuesliTests/DashboardSplitShellTests.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/DashboardRootView.swift`

- [ ] **Step 1: Write the failing shell behavior tests**

```swift
import Testing
@testable import MuesliNativeApp

@Suite("Dashboard split shell")
struct DashboardSplitShellTests {
    @Test("sidebar width resolves to zero when hidden")
    func hiddenSidebarUsesZeroWidth() {
        #expect(DashboardSplitShell.resolvedSidebarWidth(isVisible: false, preferredWidth: 260) == 0)
    }

    @Test("sidebar width is clamped to the supported range when visible")
    func visibleSidebarWidthIsClamped() {
        #expect(DashboardSplitShell.resolvedSidebarWidth(isVisible: true, preferredWidth: 120) == 240)
        #expect(DashboardSplitShell.resolvedSidebarWidth(isVisible: true, preferredWidth: 260) == 260)
        #expect(DashboardSplitShell.resolvedSidebarWidth(isVisible: true, preferredWidth: 420) == 300)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/titlebar-plan --filter DashboardSplitShellTests
```

Expected: FAIL because `DashboardSplitShell` does not exist yet.

- [ ] **Step 3: Implement the split shell and remove the prototype content bar**

```swift
// DashboardSplitShell.swift
import SwiftUI

struct DashboardSplitShell<Sidebar: View, Detail: View>: View {
    static let minSidebarWidth: CGFloat = 240
    static let idealSidebarWidth: CGFloat = 260
    static let maxSidebarWidth: CGFloat = 300

    @Binding var isSidebarVisible: Bool
    let preferredSidebarWidth: CGFloat
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail

    static func resolvedSidebarWidth(isVisible: Bool, preferredWidth: CGFloat) -> CGFloat {
        guard isVisible else { return 0 }
        return min(max(preferredWidth, minSidebarWidth), maxSidebarWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                    .frame(width: Self.resolvedSidebarWidth(isVisible: true, preferredWidth: preferredSidebarWidth))
                Divider()
            }

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

```swift
// DashboardRootView.swift
var body: some View {
    DashboardSplitShell(
        isSidebarVisible: Binding(
            get: { appState.isSidebarVisible },
            set: { appState.isSidebarVisible = $0 }
        ),
        preferredSidebarWidth: DashboardSplitShell.idealSidebarWidth,
        sidebar: {
            SidebarView(appState: appState, controller: controller)
        },
        detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MuesliTheme.backgroundBase)
        }
    )
    .frame(minWidth: 900, minHeight: 600)
    .background(MuesliTheme.backgroundBase)
    .preferredColorScheme(appState.config.darkMode ? .dark : .light)
}
```

This step must also delete the experimental `customTopBar`, `splitViewContent`, `topBarIconButton`, and `toggleSidebar` code from `DashboardRootView.swift`.

- [ ] **Step 4: Run the focused tests**

Run:

```bash
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/titlebar-plan --filter DashboardSplitShellTests
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/titlebar-plan --filter DashboardRootViewTests
```

Expected: PASS for the new shell helper tests and the existing quick note visibility tests.

- [ ] **Step 5: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/DashboardSplitShell.swift \
        native/MuesliNative/Tests/MuesliTests/DashboardSplitShellTests.swift \
        native/MuesliNative/Sources/MuesliNativeApp/DashboardRootView.swift \
        native/MuesliNative/Tests/MuesliTests/DashboardRootViewTests.swift
git commit -m "feat: replace dashboard split view shell"
```

### Task 3: Install Real Titlebar Accessories For Sidebar And Quick Note

**Files:**
- Create: `native/MuesliNative/Sources/MuesliNativeApp/MainWindowTitlebarController.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift`
- Create: `native/MuesliNative/Tests/MuesliTests/MainWindowTitlebarControllerTests.swift`

- [ ] **Step 1: Write the failing titlebar controller tests**

```swift
import Testing
@testable import MuesliNativeApp

@Suite("Main window titlebar controller")
struct MainWindowTitlebarControllerTests {
    @Test("quick note accessory uses the compact variant below the width threshold")
    func compactQuickNoteThreshold() {
        #expect(MainWindowTitlebarController.usesCompactQuickNoteLayout(availableWidth: 139))
        #expect(!MainWindowTitlebarController.usesCompactQuickNoteLayout(availableWidth: 180))
    }

    @Test("quick note accessory visibility follows dashboard context")
    func quickNoteVisibilityMatchesDashboardContext() {
        #expect(MainWindowTitlebarController.showsQuickNoteAccessory(isSearchActive: false, selectedTab: .meetings))
        #expect(!MainWindowTitlebarController.showsQuickNoteAccessory(isSearchActive: true, selectedTab: .meetings))
        #expect(!MainWindowTitlebarController.showsQuickNoteAccessory(isSearchActive: false, selectedTab: .settings))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/titlebar-plan --filter MainWindowTitlebarControllerTests
```

Expected: FAIL because `MainWindowTitlebarController` does not exist yet.

- [ ] **Step 3: Implement the titlebar controller and wire it into the main window**

```swift
// MainWindowTitlebarController.swift
import AppKit
import SwiftUI

@MainActor
final class MainWindowTitlebarController {
    private weak var window: NSWindow?
    private let appState: AppState
    private let controller: MuesliController
    private var leadingAccessory: NSTitlebarAccessoryViewController?
    private var trailingAccessory: NSTitlebarAccessoryViewController?

    init(appState: AppState, controller: MuesliController) {
        self.appState = appState
        self.controller = controller
    }

    static func showsQuickNoteAccessory(isSearchActive: Bool, selectedTab: DashboardTab) -> Bool {
        DashboardRootView.showsQuickNoteTitlebarControl(isSearchActive: isSearchActive, selectedTab: selectedTab)
    }

    static func usesCompactQuickNoteLayout(availableWidth: CGFloat) -> Bool {
        availableWidth < 140
    }

    func install(on window: NSWindow) {
        self.window = window
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        installLeadingAccessory(on: window)
        installTrailingAccessory(on: window)
    }
}
```

```swift
// RecentHistoryWindowController.swift
@MainActor
final class RecentHistoryWindowController: NSObject, NSWindowDelegate {
    private var titlebarController: MainWindowTitlebarController?

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 180, y: 140, width: 1120, height: 790),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let titlebarController = MainWindowTitlebarController(
            appState: controller.appState,
            controller: controller
        )
        titlebarController.install(on: window)
        self.titlebarController = titlebarController
        self.window = window
    }
}
```

Accessory content should be hosted with SwiftUI views that:

- bind the leading button to `appState.isSidebarVisible.toggle()`
- keep the right quick note button hidden unless `showsQuickNoteAccessory(...)` is true
- reuse `L10n.text(.quickNoteButtonHelp, ...)` and `L10n.text(.titlebarToggleSidebarHelp, ...)`

- [ ] **Step 4: Run the focused tests and a compile-level smoke test**

Run:

```bash
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/titlebar-plan --filter MainWindowTitlebarControllerTests
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/titlebar-plan --filter DashboardRootViewTests
```

Expected: PASS for the titlebar controller tests and the dashboard tests.

- [ ] **Step 5: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/MainWindowTitlebarController.swift \
        native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift \
        native/MuesliNative/Tests/MuesliTests/MainWindowTitlebarControllerTests.swift
git commit -m "feat: install custom main window titlebar controls"
```

### Task 4: Verify The Shell In Beta And Remove Any Remaining Prototype Artifacts

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/DashboardRootView.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/DashboardRootViewTests.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/MainWindowTitlebarControllerTests.swift`

- [ ] **Step 1: Run the focused automated checks**

Run:

```bash
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/titlebar-plan --filter DashboardRootViewTests
swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/titlebar-plan --filter MainWindowTitlebarControllerTests
```

Expected: PASS for both suites.

- [ ] **Step 2: Build and reinstall the beta**

Run:

```bash
MUESLI_SWIFTPM_SCRATCH_PATH="$HOME/Library/Caches/muesli-spm/dev" ./scripts/beta-test.sh
```

Expected: `/Applications/muesli-beta.app` is replaced and launched successfully.

- [ ] **Step 3: Perform the manual chrome checklist**

Verify in the beta:

```text
1. There is exactly one sidebar button.
2. The sidebar button stays at the left side of the titlebar.
3. "Nota rapida" stays at the right side of the titlebar.
4. Resizing the window does not create position jumps.
5. Toggling the sidebar repeatedly does not duplicate controls.
6. The quick note button no longer shows the white toolbar artifact.
7. Search and non-meetings tabs hide the quick note accessory when expected.
```

- [ ] **Step 4: Remove any temporary debug or prototype remnants**

Before finalizing, confirm these prototype remnants are gone:

```text
- no content-level fake top bar in DashboardRootView
- no ToolbarItem-based quick note button
- no NSApp.sendAction(toggleSidebar:) fallback path in DashboardRootView
```

- [ ] **Step 5: Commit**

```bash
git add native/MuesliNative/Sources/MuesliNativeApp/DashboardRootView.swift \
        native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift \
        native/MuesliNative/Tests/MuesliTests/DashboardRootViewTests.swift \
        native/MuesliNative/Tests/MuesliTests/MainWindowTitlebarControllerTests.swift
git commit -m "fix: finalize stable main window titlebar controls"
```

## Self-Review Notes

- Spec coverage: Task 1 covers explicit sidebar state and titlebar visibility rules. Task 2 covers removal of `NavigationSplitView` and the app-owned shell. Task 3 covers AppKit titlebar accessories. Task 4 covers beta/manual verification and removal of the prototype bar.
- Placeholder scan: no `TODO`, `TBD`, or “implement later” markers remain.
- Type consistency: `showsQuickNoteTitlebarControl`, `isSidebarVisible`, `DashboardSplitShell.resolvedSidebarWidth`, `MainWindowTitlebarController.showsQuickNoteAccessory`, and `usesCompactQuickNoteLayout` are used consistently across tasks.
