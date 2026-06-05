# Meeting Chat Persistence Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist meeting/folder chat locally and keep each provider call bounded by recent messages plus deterministic context.

**Architecture:** `MuesliMeetingChat` owns persistence-facing models, storage protocols, chat memory selection, and transcript-demand policy. `MuesliNativeApp/MeetingChatIntegration` owns the SQLite adapter and injects it into the existing `MeetingChatPanel` through `AppState`, keeping main meeting screens as thin mounts.

**Tech Stack:** Swift, SwiftUI, Swift Testing, SQLite3, SwiftPM targets `MuesliMeetingChat` and `MuesliNativeApp`.

---

### Task 1: Chat Memory and Transcript Policy

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliMeetingChat/MeetingChatModels.swift`
- Modify: `native/MuesliNative/Sources/MuesliMeetingChat/MeetingChatContextBuilder.swift`
- Modify: `native/MuesliNative/Tests/MuesliTests/MeetingChatTests.swift`

- [x] Add failing tests for persisted memory window and transcript-demand behavior.
- [x] Run `swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter MeetingChatContextTests`.
- [x] Add `MeetingChatMemoryPolicy` and expose transcript demand through `MeetingChatContextBuilder`.
- [x] Re-run focused context tests.

### Task 2: Storage Protocol and SQLite Adapter

**Files:**
- Create: `native/MuesliNative/Sources/MuesliMeetingChat/MeetingChatStorage.swift`
- Create: `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/SQLiteMeetingChatStore.swift`
- Modify: `native/MuesliNative/Tests/MuesliTests/MeetingChatTests.swift`

- [x] Add failing tests for creating/restoring meeting and folder threads, scope isolation, source restoration, and clear.
- [x] Run `swift test --package-path native/MuesliNative --scratch-path /private/tmp/muesli-swiftpm-scratch --filter MeetingChatStorageTests`.
- [x] Implement storage protocol and SQLite-backed adapter with local-only tables.
- [x] Re-run focused storage tests.

### Task 3: Panel Persistence Integration

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/AppState.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatPanel.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingsView.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingDetailView.swift`

- [x] Inject `MeetingChatStore` through `AppState`.
- [x] Load messages on panel appear/scope change.
- [x] Persist user, assistant, and error messages.
- [x] Add scoped clear-chat control.
- [x] Use `MeetingChatMemoryPolicy` for provider `priorMessages`.

### Task 4: Provider Consistency and Verification

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingChatIntegration/MeetingChatNativeProviderFactory.swift`

- [x] Set `store: false` on official OpenAI Responses chat calls.
- [x] Run focused chat tests.
- [x] Run full native tests.
- [x] Run debug build.
- [x] Install beta with `scripts/beta-test.sh`.

## Execution Notes

- Focused Meeting Chat verification passed with `15 tests in 4 suites`.
- Full native verification passed with `1019 tests in 122 suites`.
- Debug SwiftPM build passed.
- Local beta install passed through `scripts/beta-test.sh`.
- The beta script installed and launched `/Applications/muesli-beta.app`.
- The beta script fell back to unsigned install because no local signing
  identity was available, using `MUESLI_SKIP_SIGN=1`.
- Follow-up visual alignment pass centered the established completed-meeting
  detail column inside the wider chat-aware host so the associated event block
  no longer appears offset to the left.
- The alignment pass was verified with focused `MeetingDetailViewTests`, a
  debug SwiftPM build, and a refreshed `/Applications/muesli-beta.app` install.

## Follow-Up Roadmap

Implementation should continue in this order:

1. Add semantic folder/project memory.
2. Add relevance-based meeting retrieval for folder chat.
3. Add a project bias/risk analysis mode with required source grounding.
4. Add selective transcript evidence retrieval for candidate meetings.
5. Replace compact older-message fallback memory with real stored thread
   summaries.
6. Improve chat management UX and localization.
7. Decide whether chat history should sync through Supabase.
8. Consider confirmed agentic actions only after retrieval and grounding are
   reliable.
