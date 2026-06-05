# Meetings Home Header Cleanup Implementation Plan

Status: Implemented on `beta`, with the quick-note CTA finalized inline in the meetings content

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify the meetings home header by keeping only the canonical `Import Audio` action, removing the templates shortcut, making the `Coming Up` collapse affordance icon-only, and validating the final quick-note placement for this surface.

**Architecture:** Keep the behavior changes local to the meetings browser surface. Encode the approved toolbar order, `Coming Up` icon choice, and top-spacing rules in small pure helpers so tests can validate the UX direction without adding snapshot infrastructure.

**Tech Stack:** Swift, SwiftUI, Swift Testing

---

## Post-Implementation Notes

- `Import Audio` stayed as the single canonical import action and now reuses the
  same accent-capsule language as the lightweight titlebar action styling
- the meetings-home templates shortcut was removed from this surface and left in
  `Settings`
- the `Coming Up` collapse control shipped as icon-only
- beta validation showed that keeping quick note in the titlebar introduced too
  much chrome competition for this screen, so the final product direction moved
  quick note into the meetings content as the inline `Nota rápida` CTA
- the inline quick-note CTA is rendered as an overlay in the same top lane so it
  does not push `Coming Up` downward or consume extra vertical spacing

### Task 1: Encode the approved meetings-home chrome in testable helpers

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingsView.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/MeetingsNavigationTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
    @Test("meetings home keeps the canonical import action ahead of sort and filter")
    func meetingsHomeToolbarOrder() {
        #expect(MeetingsHomeChrome.trailingToolbarItems == [.importAudio, .sort, .filter])
    }

    @Test("coming up toggle uses icon-only expand and collapse symbols")
    func comingUpToggleSymbols() {
        #expect(MeetingsHomeChrome.comingUpToggleSymbolName(isExpanded: true) == "rectangle.compress.vertical")
        #expect(MeetingsHomeChrome.comingUpToggleSymbolName(isExpanded: false) == "rectangle.expand.vertical")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/meetings-home-header --filter MeetingBrowserLogicTests`
Expected: FAIL because `MeetingsHomeChrome` is undefined.

- [ ] **Step 3: Write the minimal implementation**

```swift
enum MeetingsHomeToolbarItem: Hashable {
    case importAudio
    case sort
    case filter
}

enum MeetingsHomeChrome {
    static let trailingToolbarItems: [MeetingsHomeToolbarItem] = [
        .importAudio,
        .sort,
        .filter,
    ]

    static func comingUpToggleSymbolName(isExpanded: Bool) -> String {
        isExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/meetings-home-header --filter MeetingBrowserLogicTests`
Expected: PASS.

### Task 2: Apply the simplified meetings-home toolbar and icon-only Coming Up toggle

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingsView.swift`

- [ ] **Step 1: Update the Coming Up toggle to icon-only**

```swift
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isComingUpExpanded.toggle()
                    }
                } label: {
                    Image(systemName: MeetingsHomeChrome.comingUpToggleSymbolName(isExpanded: isComingUpExpanded))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .help(L10n.text(
                    isComingUpExpanded ? .meetingsCollapseComingUp : .meetingsExpandComingUp,
                    config: appState.config
                ))
```

- [ ] **Step 2: Rebuild the header actions around one canonical import button**

```swift
        HStack(spacing: MuesliTheme.spacing8) {
            importAudioButton
            sortButton
            dateFilterButton
        }
```

- [ ] **Step 3: Style Import Audio as the primary accent action**

```swift
    private var importAudioButton: some View {
        Button {
            controller.importAudioFile()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text("Import Audio")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isImportAudioDisabled ? MuesliTheme.textTertiary : MuesliTheme.backgroundBase)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 8)
            .background(isImportAudioDisabled ? MuesliTheme.surfacePrimary : MuesliTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
        .disabled(isImportAudioDisabled)
    }
```

- [ ] **Step 4: Remove the meetings-home template manager button**

```swift
            Button {
                controller.showMeetingTemplatesManager()
            } label: {
                ...
            }
```

Delete the block above from `browserHeaderActions`.

### Task 3: Deprecate the legacy WAV harness entrypoint and run focused verification

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/MeetingsNavigationTests.swift`

- [ ] **Step 1: Mark the legacy WAV importer entrypoint deprecated**

```swift
    @available(*, deprecated, message: "Use importAudioFile() for the canonical meetings import flow.")
    func importMeetilyStyleLiveTranscriptWAV() {
        ...
    }
```

- [ ] **Step 2: Run the focused tests**

Run: `swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/meetings-home-header --filter MeetingBrowserLogicTests`
Expected: PASS.

- [ ] **Step 3: Run the broader import-related tests**

Run: `swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-spm/meetings-home-header --filter AudioFileImportControllerTests`
Expected: PASS.
