> **Post-compaction recovery:** PreCompact hooks auto-generate context handover files at `Context/handoff-summary-YYYY-MM-DD-<slug>.md`. After compaction, read the latest handoff file in `Context/` to restore session memory and resume work.

# Muesli

Local-first macOS app for **dictation** and **meeting transcription** on Apple Silicon. All speech-to-text runs on-device via CoreML/Neural Engine. Native Swift/AppKit — no Electron, no Python runtime, no cloud STT costs.

**Status:** Live and public. Available at [GitHub Releases](https://github.com/Muesli-HQ/muesli/releases). Signed, notarized, stapled.

## What It Does

- **Dictation:** Hold hotkey → speak → release → text pasted at cursor (~0.13s with Parakeet)
- **Meeting transcription:** Captures mic (You) + system audio (Others) → VAD-driven chunking → pause-aware live transcript turns → speaker diarization/post-processing plus pause-aware canonical formatting for the final transcript → AI-powered meeting notes
- **Meeting export:** Export notes or transcript as PDF (paginated US Letter) or Markdown via `MeetingExporter.swift`
- **Screen context:** Accessibility API captures app name + text around cursor for dictation context-awareness (opt-in, off by default)
- **7 ASR models:** Parakeet v3/v2, Whisper Small/Medium/Large Turbo, Qwen3 ASR, Nemotron Streaming
- **3 summarization backends:** OpenAI API key, OpenRouter API key, ChatGPT OAuth (subscription-based)
- **Camera-based meeting detection:** Requires mic + camera + recognized meeting app (camera alone won't trigger)
- **Join & Record:** Extract meeting URLs from calendar events (Zoom, Meet, Teams, Webex, Chime, FaceTime), split button with "Join & Record" / "Join Only" / "Record Only", platform icons in notifications
- **Google Calendar integration:** Coming Up section, status bar, pre-meeting countdowns, event-driven notifications via `EKEventStoreChangedNotification`
- **Meeting templates:** Built-in and custom templates for structured meeting notes
- **Multi-Mac sync (beta-only):** Supabase-backed sync of meetings, dictations, folders, custom templates, custom words, and folder order across the same user's Macs. Triggered by data changes (debounced), manual `Sync now`, signin, and a 5-minute heartbeat. Email + password auth, no SDK, all REST.

## Building

### Production build (signed, installed to /Applications)
```bash
./scripts/build_native_app.sh
```

### Dev/test build (isolated, unsigned)
```bash
./scripts/dev-test.sh                  # Build MuesliDev.app (separate bundle ID, separate data)
./scripts/dev-test.sh --clean          # Wipe dev data, fresh onboarding
./scripts/dev-test.sh --reset          # Re-run onboarding, keep dev data
./scripts/dev-seed-from-prod.sh        # Copy production DB/config into MuesliDev safely
./scripts/dev-reset-permissions.sh     # Reset macOS privacy permissions for MuesliDev
```

MuesliDev uses bundle ID `com.muesli.dev` and stores data at `~/Library/Application Support/MuesliDev/`. Production data is never touched.

### Beta build for this fork
```bash
MUESLI_SWIFTPM_SCRATCH_PATH="$HOME/Library/Caches/muesli-spm/dev" ./scripts/beta-test.sh
```

For the fork's local beta app, always use `scripts/beta-test.sh`, not `scripts/build_native_app.sh` directly. The beta script installs `/Applications/muesli-beta.app`, uses bundle ID `com.jr4y.muesli.beta`, stores data under `~/Library/Application Support/MuesliBeta/`, and falls back to an unsigned local install with `MUESLI_SKIP_SIGN=1` when the local Developer ID identity is unavailable.

`scripts/build_native_app.sh` is the generic installer and defaults to `/Applications/Muesli.app`; using it directly is only correct for the generic app target, not for refreshing the fork's beta build.

### SwiftPM build artifacts in worktrees
SwiftPM writes build artifacts to `native/MuesliNative/.build` inside the active worktree by default. That can consume several GB per worktree. For worktree-heavy local testing, set `MUESLI_SWIFTPM_SCRATCH_PATH` when invoking `scripts/build_native_app.sh` directly or through helper scripts such as `scripts/dev-test.sh`:

```bash
MUESLI_SWIFTPM_SCRATCH_PATH="$HOME/Library/Caches/muesli-spm/dev" ./scripts/dev-test.sh
MUESLI_SWIFTPM_SCRATCH_PATH="$HOME/Library/Caches/muesli-spm/preprod" ./scripts/build_native_app.sh release
```

The build script passes that value to SwiftPM as `--scratch-path`, so multiple worktrees can reuse one scratch directory instead of each growing its own `.build`. Caveat: do not run concurrent builds from different worktrees into the same scratch path; use separate paths per channel, agent, or simultaneous build. Deleting a scratch path only removes rebuildable SwiftPM artifacts, not installed apps or app data.

### Tests
```bash
swift test --package-path native/MuesliNative    # 396 tests across 65 suites
```

### Onboarding testing
```bash
# Reset onboarding flag without losing data:
python3 -c "import json; p='$HOME/Library/Application Support/MuesliDev/config.json'; c=json.load(open(p)); c['has_completed_onboarding']=False; json.dump(c,open(p,'w'),indent=2)"
# Reset macOS permissions:
./scripts/dev-reset-permissions.sh
# Then:
./scripts/dev-test.sh
```
Note: config JSON uses snake_case keys (`has_completed_onboarding`, not `hasCompletedOnboarding`).

## CI/CD Pipeline

### Pull Requests
- **CI workflow** (`.github/workflows/ci.yml`): macOS 15 runners
  - `changes` → `build` → `cli-smoke` → `ci-gate` (required check)
- **Claude Code Review** — reviews every PR automatically
- **Greptile** — reviews every PR automatically
- **Vercel** — scoped to `site/` only
- **Concurrency** — stale CI runs auto-cancelled on new pushes

### Releases
```bash
./scripts/release.sh                   # Auto-increments version
./scripts/release.sh 1.0.0             # Explicit version
```
**Critical:** Staple the app bundle BEFORE creating the DMG, otherwise Gatekeeper rejects.

### Signing & Notarization
- Developer ID: `Pranav Hari Guruvayurappan (58W55QJ567)`
- Bundle ID: `com.muesli.app`
- Notary profile: `MuesliNotary` (Keychain)

## Key Architecture

```
native/MuesliNative/Sources/
├── MuesliNativeApp/              # Main app (~50 Swift files)
│   ├── MuesliController.swift    # Central orchestrator — dictation, meetings, onboarding, state
│   ├── TranscriptionRuntime.swift # Routes to ASR backends, post-processing, VAD + diarization
│   ├── FluidAudioBackend.swift   # Parakeet TDT on ANE
│   ├── Qwen3AsrBackend.swift     # Qwen3 ASR on ANE (macOS 15+)
│   ├── Qwen3PostProcessor.swift  # On-device GGUF LLM for dictation cleanup (opt-in)
│   ├── WhisperKitBackend.swift   # Whisper on CoreML/ANE via WhisperKit
│   ├── ScreenContextCapture.swift # AX-based app context for dictation + meetings
│   ├── MeetingExporter.swift     # PDF/Markdown export with NSPrintOperation
│   ├── OnboardingView.swift      # 7-step onboarding with real permission polling + dictation test
│   ├── OnboardingProgress.swift  # Crash-safe onboarding state persistence
│   ├── MeetingSession.swift      # Meeting lifecycle + canonical final transcript pipeline + live hooks
│   ├── MeetingLiveTranscript.swift # Live transcript pipeline, reducer, parser, display turns
│   ├── MeetingTranscriptChatView.swift # Shared chat-style transcript renderer for live + final views
│   ├── MeetingSpeechTurnSegmenter.swift # Canonical pause-aware turn projection over existing ASR output
│   ├── MeetilyStyleLiveTranscriptImporter.swift # WAV import harness using Meetily-style VAD pause defaults
│   ├── MeetingSummaryClient.swift # OpenAI / OpenRouter / ChatGPT summarization
│   ├── SystemAudioRecorder.swift # ScreenCaptureKit SCStream for system audio
│   ├── ChatGPTAuthManager.swift  # OAuth PKCE + WHAM API
│   ├── HotkeyMonitor.swift       # Global hotkey detection (modifier keys)
│   ├── MeetingDetector.swift     # Camera + mic + app detection for meetings
│   ├── MeetingNotificationController.swift # Join & Record notification panel with platform icons
│   └── PasteController.swift     # Clipboard-preserving Cmd+V paste
├── MuesliCore/                   # Shared library (SQLite, paths, models)
│   ├── DictationStore.swift      # SQLite3 C API — dictations + meetings CRUD
│   ├── MuesliPaths.swift         # App-identity-aware path resolution
│   └── Sync/                     # Local sync layer (auxiliary tables + triggers)
│       ├── LocalSyncModels.swift       # Entity types, metadata, tombstones, payloads
│       ├── LocalSyncRepository.swift   # sync_metadata + sync_tombstones + sync_state, triggers, reconciliation helpers
│       └── SyncPayloadHasher.swift     # Canonical JSON + SHA-256 per entity
└── MuesliCLI/                    # Agent-friendly CLI (JSON over stdout)

native/MuesliNative/Sources/MuesliNativeApp/Sync/
├── SupabaseConfig.swift            # Reads MuesliSupabaseURL/AnonKey from Info.plist
├── SupabaseKeychainStore.swift     # Refresh + access tokens in Keychain (variant-namespaced)
├── SupabaseAuthManager.swift       # signup / signin / signout / refresh, @MainActor @Observable
├── SupabaseRESTClient.swift        # PostgREST: select, upsert, update (optimistic), fetch, soft delete
├── SupabaseSyncManager.swift       # actor: cycle order, debounced triggers, LWW, reconciliation, heartbeat
├── AppConfigSyncSnapshot.swift     # AppConfig ↔ SyncPreferencesSnapshot bridge (sync fields only)
└── SyncSettingsView.swift          # Settings → Sync pane (signup / signin / Sync now)
```

## Data Storage

- **Config:** `~/Library/Application Support/{AppName}/config.json` (snake_case keys)
- **Database:** `~/Library/Application Support/{AppName}/muesli.db` (SQLite WAL)
- **Models:** `~/Library/Application Support/FluidAudio/Models/` (shared across app identities)
- **Onboarding progress:** `~/Library/Application Support/{AppName}/onboarding-progress.json` (deleted on completion)
- **ChatGPT tokens:** macOS Keychain (`com.muesli.app.chatgpt-auth`)
- **Whisper models:** `~/.cache/muesli/models/`
- **Supabase session:** macOS Keychain at service `<CFBundleIdentifier>.supabase-auth`. Variants get separate sessions automatically (e.g. `com.jr4y.muesli.beta.supabase-auth` vs `com.muesli.app.supabase-auth`).
- **Sync state (SQLite):** lives inside the same `muesli.db`. Auxiliary tables `sync_metadata`, `sync_tombstones`, `sync_state` plus triggers on `dictations`, `meetings`, `meeting_folders`. The business schema is unchanged; sync metadata is fully separated.
- **Supabase build credentials:** `config/Supabase.xcconfig` (gitignored, KEY=VALUE) with template at `config/Supabase.xcconfig.example`. The build script reads it and embeds `MuesliSupabaseURL` + `MuesliSupabaseAnonKey` into `Info.plist`. The Postgres password also lives there for `supabase db push`.
- **Supabase project:** `molli` (ref `pjjwmekbrchaytipxtjk`, `eu-west-1`, free tier, `JR4y's Org`). Migrations live in `supabase/migrations/`. Schema is `public.{meeting_folders, meetings, dictations, user_preferences}` with RLS, a `bump_remote_version` trigger, and `(user_id, server_updated_at, id)` cursor indexes per table.

`{AppName}` is `Muesli` for production, `MuesliDev` for dev, `MuesliCanary` for alpha, `MuesliBeta` for the fork's daily-use beta — controlled by `MuesliSupportDirectoryName` in Info.plist.

## macOS Permissions

| Permission | What Uses It | API |
|---|---|---|
| Microphone | Dictation + meeting mic | AVAudioRecorder, AVAudioEngine |
| Accessibility | Paste text + screen context capture | CGEvent Cmd+V, AXUIElement |
| Input Monitoring | Hotkey detection | NSEvent global monitors |
| Screen Recording | System audio capture | ScreenCaptureKit SCStream |
| Camera (implicit) | Meeting detection | CoreMediaIO property listeners |
| Calendar (optional) | Upcoming meetings | EKEventStore, Google Calendar API |

**Critical:** Accessibility permission requires an app restart to take effect. The onboarding flow handles this with an automatic restart after the hotkey configuration step.

**Important:** `CGWindowListCreateImage` (screenshots) conflicts with active `SCStream` sessions — causes `RPDaemonProxy: connection INTERRUPTED` and breaks system audio capture. Never take screenshots during meeting recording. See `Context/handoff-2026-04-16-coreaudio-tap-migration.md` for the planned fix.

## Onboarding Flow

7 steps: Welcome → Model → Permissions → Hotkey → **[app restart]** → Dictation Test → Meeting Summaries → Google Calendar

Key implementation details:
- Real OS permission polling every 1s (not fake timers) via `AXIsProcessTrusted()`, `CGPreflightListenEventAccess()`, etc.
- Uses proper request APIs: `AXIsProcessTrustedWithOptions`, `CGRequestScreenCaptureAccess`, `CGRequestListenEventAccess`
- Hotkey, calendar, and mic monitors are **deferred until after onboarding completes** to prevent premature permission prompts
- App restart via detached shell: `/bin/sh -c "sleep 1; open -- \"$1\"" -- <bundlePath>` then `NSApp.terminate(nil)`
- Progress saved on every step transition to `onboarding-progress.json` (schema-versioned, atomic writes)
- Dictation test step uses real hold-to-talk hotkey flow with `dictationTestCallback` routing (no paste, no floating indicator)
- `OnboardingView.dictationTestStep` (static Int = 4) — hotkey monitor only starts when resuming at this step or later

## Screen Context (opt-in, `enableScreenContext` in config)

**Dictation:** `DictationContextCapture.capture()` — synchronous Accessibility API call:
- App name + bundle ID via `NSWorkspace.shared.frontmostApplication`
- Text before cursor via `kAXSelectedTextRangeAttribute` + `kAXStringForRangeParameterizedAttribute` (falls back to `kAXValueAttribute` suffix for apps that don't support parameterized attributes)
- Selected text via `kAXSelectedTextAttribute`
- Browser URL via `kAXDocumentAttribute`
- Only runs when BOTH `enableScreenContext` AND `enablePostProcessor` are true
- Context injected into Qwen3 post-processor prompt as `<APP-CONTEXT>` tags
- Stored in existing `app_context` column in `dictations` table

**Meetings:** `MeetingScreenContextCollector` (actor) — periodic AX capture every 60s:
- Uses same `DictationContextCapture.capture()` (no screenshots — `CGWindowListCreateImage` conflicts with `SCStream`)
- Deduplicated, aggregated, injected into meeting summary prompt as "Visual context" section
- OCR-based capture (`ScreenContextCapture.captureOnce()`) exists in code but is unused until CoreAudio migration

## Meeting Export

`MeetingExporter.swift` — export menu in `MeetingDetailView` content toolbar:
- Two menu items: "Export Notes"/"Export Transcript" (contextual to active tab) + "Export Full Meeting"
- Format (PDF/Markdown) chosen via `ExportFormatAccessory` popup in NSSavePanel
- PDF: `NSPrintOperation` with paginated US Letter pages (612x792pt, 1" margins)
- Markdown: atomic write with metadata header (title, date, duration, word count, template)
- NSSavePanel presented via `beginSheetModal(for:)` — never `runModal()` (deadlocks in SwiftUI)
- File auto-opens in default app after save via `NSWorkspace.shared.open(url)`

## Transcript Rendering

- The final transcript source of truth remains `MeetingRecord.rawTranscript`
- The live transcript is a separate lightweight pipeline and can be disabled from Settings → Meetings via `enableLiveMeetingTranscript`
- Live transcript turns are segmented by speech start/end events from VAD, not by completed ASR chunks alone. Muesli keeps one active live turn per source (`You`/mic and `Others`/system), so overlapping speech can show as two simultaneous source-separated turns instead of being merged into one bubble.
- Live pause defaults intentionally mirror the Meetily-style baseline used by the WAV importer: positive speech threshold `0.50`, negative speech threshold `0.35`, redemption time `2.0s`, pre-speech pad `0.30s`, post-speech pad `0.40s`, minimum speech time `0.25s`, minimum raw segment `800` samples at 16 kHz, and maximum speech duration `30s`.
- Pause/stop recording paths flush active live turns so the last visible bubble closes before the final transcript pipeline completes.
- Imported WAV files can be transcribed through the Meetily-style importer from the Meetings browser. This is a diagnostic/control path for validating pause segmentation on known audio; it does not replace the normal meeting capture pipeline.
- The canonical final transcript remains based on the normal ASR/reconciliation/diarization/bleed-filtering pipeline, then projects the existing speech segments onto VAD pause windows for readability. It does not re-transcribe by VAD windows.
- When live transcript is disabled, no live transcript UI or publication happens during recording; the final transcript pipeline still runs unchanged when the meeting stops
- Meeting detail now renders completed transcripts in a chat-style view derived from `rawTranscript`
- Storage and export remain plain-text transcript based; the chat view is presentation only

## Supabase Multi-Mac Sync

Currently scoped to `muesli-beta.app`. Each app variant gets its own session and its own device id because the SQLite path and Keychain service are namespaced by app identity. Sign-in on MuesliBeta is therefore independent from production Muesli.

**Design philosophy** (see `docs/plans/2026-05-04-supabase-sync-corrected-plan.md` for the full rationale):
- The business schema (`dictations`, `meetings`, `meeting_folders`) is **not** modified. No `updated_at`, no `sync_id`, no `deleted_at` added. All sync metadata lives in separate auxiliary tables (`sync_metadata`, `sync_tombstones`, `sync_state`) so upstream merges stay clean.
- Dirty-detection is based on a `dirty` flag updated by SQLite triggers, not on `updated_at` of the domain row. That avoids the "remote write looks like a local edit" bug where `applyRemote*` would re-mark the row dirty.
- Conflict resolution is **last-write-wins** at the entity level using `client_updated_at`, with the lexicographically larger `device_id` as a tiebreak. Field-level merge is not attempted.
- Reconciliation on first sync uses fingerprints: `timestamp + raw_text + app_context` for dictations; `calendar_event_id + start_time` (then transcript fingerprint) for meetings; name + parent path for folders.

**Cycle order** (one actor, no overlapping cycles):
1. Download in order: folders → preferences → dictations → meetings (cursor: `server_updated_at ASC, id ASC`)
2. Upload in order: folders → dictations → meetings → preferences → tombstones (meetings → dictations → folders)
3. Purge clean tombstones older than 30 days

**First-sync bootstrap rules**:
- `LocalSyncRepository.migrateIfNeeded()` backfills `sync_metadata` for pre-existing local `dictations`, `meetings`, and `meeting_folders` that predate the sync feature. Signing into sync on an already-used beta install therefore uploads the existing local history instead of only newly created rows.
- Preferences are marked dirty on first bootstrap when no remote version exists yet, so templates/custom words/folder order upload immediately instead of waiting for a later config edit.

**Cursor timestamp normalization**:
- Supabase may return `server_updated_at` values formatted as `...+00:00`. Before building PostgREST cursor filters, the client normalizes that UTC offset to `Z`. Without this, PostgREST can parse the `+` as a space inside the query string and return `400 invalid input syntax for type timestamp with time zone`.

**Folder hierarchy upload guard**:
- Folder uploads are dependency-aware. If a local child folder is dirty but its parent still lacks a remote id, the manager defers the child and re-reads dirty folders after the parent syncs. This avoids bootstrapping a nested folder tree as a set of root folders on the first upload pass.

**Triggers** (see `LocalSyncRepository.installTriggers`):
- `AFTER INSERT` and `AFTER UPDATE` on `dictations`, `meetings`, `meeting_folders` upsert into `sync_metadata` with `dirty = 1` and the current timestamp via `strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`
- `BEFORE DELETE` copies `remote_id` and `remote_version` into `sync_tombstones` (NULL `remote_id` for never-synced rows, which the manager purges locally without a remote round-trip)
- `AFTER DELETE` removes the orphaned `sync_metadata` row

**`applyRemote*` ordering inside a single transaction:**
1. Resolve foreign-key remote ids to local ids (`folder_id`, `parent_folder_id`)
2. INSERT or UPDATE the domain row (the trigger fires and marks dirty)
3. Overwrite `sync_metadata` to clean state with the authoritative remote version + payload hash
4. Clear the tombstone the BEFORE DELETE trigger created on a remote-driven delete

Steps 3 and 4 are mandatory — without them the trigger's `dirty=1` survives and the next cycle re-uploads the row.

**Triggers from app code:**
- `MuesliController.syncAppState()` calls `Task { await syncManager.notifyPotentialLocalDataChange() }` (debounced 2s)
- `MuesliController.updateConfig(_:)` diffs `currentSyncPreferencesSnapshot()` before/after the mutation; if it changed it calls `syncRepo.markPreferencesDirty()` and `Task { await syncManager.notifyPreferencesChanged() }` (debounced 1s). Non-sync config edits never trigger work.
- `SyncSettingsView` exposes a manual `Sync now` button (`controller.supabaseSyncNow()` → `syncManager.syncNow(reason: "manual")`)
- `SupabaseSyncManager.start()` runs an initial sync at launch
- A 5-minute heartbeat task runs `Task.sleep(...)` then `syncNow(reason: "heartbeat")`. Subject to macOS 26 App Nap on LSUIElement apps; treat it as a safety net only.

**Privacy boundaries** (the upload payloads do not reference any of these):
- `openAIAPIKey`, `openRouterAPIKey`, ChatGPT/Google tokens
- Hotkey config, model picks, indicator/window state
- Onboarding flags, permission flags
- `hiddenLocalCalendarIDs`, `hiddenCalendarEventIDs`
- `mic_audio_path`, `system_audio_path`, `saved_recording_path`, any filesystem path

**Live meetings excluded from upload** — `dirtyMeetings` and `unsyncedMeetings` SQL filters out rows in `recording` or `processing` status. They become eligible the moment they transition to `completed`, `note_only`, or `failed`.

**Audio paths preserved on remote update** — `applyRemoteMeeting` UPDATE explicitly omits `mic_audio_path`, `system_audio_path`, `saved_recording_path`. Only when materializing a meeting for the first time on this Mac do those columns get set to NULL.

**Email confirmation** — handled either way. If Supabase has `Confirm email` ON (default), `signUp` returns no session and the auth manager surfaces `awaitingEmailConfirmation = true`; the user confirms via email then signs in. If `Confirm email` is OFF, `signUp` returns a full session and the manager logs in immediately. Toggle lives in Supabase Dashboard → Authentication → Providers → Email.

**Supabase CLI workflow:**
```bash
# One-time link (per checkout)
supabase link --project-ref pjjwmekbrchaytipxtjk

# New migration
supabase migration new <name>
# Edit the SQL file under supabase/migrations/

# Push to remote (uses MUESLI_SUPABASE_DB_PASSWORD from config/Supabase.xcconfig)
supabase db push
```

The `supabase` directory is committed (config + migrations); `supabase/.temp/` and `config/Supabase.xcconfig` are gitignored.

## Development Workflow

1. **Feature work:** Create branch → implement → `./scripts/dev-test.sh` → push → PR
2. **PR review:** Claude Code + Greptile review automatically. Fix P1s before merge.
3. **Merge to main** via squash merge
4. **Release:** `./scripts/release.sh` → notarize → GitHub Releases

## Calendar Notification Pipeline

Event-driven architecture for meeting notifications:

- **Primary trigger:** `EKEventStoreChangedNotification` — macOS pushes calendar changes (add/move/delete) instantly via `NotificationCenter`. Immune to App Nap timer suspension in LSUIElement apps.
- **Fallback:** 60s `Timer` polls Google Calendar API (sync token for efficiency) and checks the 5-minute notification window for time-based triggers.
- **Dedup:** Composite key `id|startDate` — rescheduled events generate fresh notifications. Stale entries pruned hourly.
- **Per-event timers:** `meetingStartingNowTimers: [String: Timer]` — concurrent events get independent "starting now" timers.
- **Suppression:** After user acts on a calendar notification (Join Only, Dismiss), mic/camera detection is suppressed for the remaining event duration.
- **Meeting URL extraction:** EventKit (`event.url`, `location`, `notes` via regex) + Google Calendar API (`hangoutLink`, `conferenceData.entryPoints[type=video]`). `mergeEvents` backfills Google URL when EventKit duplicate has none.

**macOS 26 App Nap behavior (LSUIElement apps):** All timer mechanisms (`Timer.scheduledTimer`, `DispatchSourceTimer`, `Task.sleep`, `Thread.sleep`, `DispatchQueue.asyncAfter`, POSIX `nanosleep`) get suspended by aggressive power management. Only `NotificationCenter` observers (system IPC) are immune. The 60s fallback timer may not fire reliably — `EKEventStoreChangedNotification` is the critical path. Users with Google Calendar synced to macOS Calendar (System Settings > Internet Accounts) get reliable notifications via EventKit. OAuth-only users depend on the 60s timer.

## Known Limitations

- **Nemotron Streaming:** English-only, best for 10s+ utterances (handsfree mode). Short dictations produce poor results.
- **Qwen3 ASR:** 2-3s latency (autoregressive decoder). First run after launch has ~30s CoreML compilation warmup.
- **ChatGPT OAuth:** Uses reverse-engineered WHAM API. Could break if OpenAI changes the API.
- **Speaker diarization:** Post-processing only. Runs after meeting stops. Live transcript does not attempt full diarization.
- **Screen context OCR disabled during meetings:** `CGWindowListCreateImage` conflicts with `SCStream`. AX-based context used instead. Planned fix: migrate to CoreAudio tap for system audio (see `Context/handoff-2026-04-16-coreaudio-tap-migration.md`).
- **NSSavePanel:** Must use `beginSheetModal(for:)` in SwiftUI, never `runModal()`. `NSAttributedString(html:)` deadlocks on main thread — build attributed strings manually.
- **App restart during onboarding:** Uses `exit(0)` via detached shell. `NSApp.terminate(nil)` inside SwiftUI animation context can crash.
- **macOS 26 App Nap:** LSUIElement apps have all timers suspended by aggressive power management. Calendar notifications rely on `EKEventStoreChangedNotification` (immune). The 60s Google Calendar poll timer may not fire. See Calendar Notification Pipeline section.
- **"Meeting starting now" after Join Only/Dismiss:** The scheduled timer is not cancelled when the user clicks Join Only or Dismiss on the "Upcoming meeting" notification. A redundant "Meeting starting now" fires at event start time. Fix: pass notification key into `handleUpcomingMeeting` so callbacks can cancel it.
- **Supabase sync is not E2E encrypted.** Transcripts, notes, dictations, custom templates, and custom words live readable in Supabase for the authenticated user. RLS keeps each user's rows private from other users; it does not hide them from Supabase admins. End-to-end encryption would be a separate initiative.
- **Supabase sync heartbeat is not guaranteed under App Nap.** The 5-minute heartbeat task uses `Task.sleep`, which suspends in LSUIElement apps. Primary sync triggers (launch, signin, debounced data/preferences changes, manual `Sync now`) cover the typical case; the heartbeat is a safety net.
- **Concurrent edits within milliseconds may drop one side.** LWW with millisecond `client_updated_at` plus the device id tiebreak is intentional for personal multi-Mac sync. It is not a CRDT.
- **First-sync reconciliation is fingerprint-based.** Two Macs with overlapping data that don't match by fingerprint (e.g. transcripts that diverge by one word, or different `calendar_event_id`s for the same meeting) will create duplicates. Manual cleanup in the UI is the current remedy.
- **Nested folders depend on parent remote ids.** The current code now defers child-folder upload until the parent has a remote id, but any future change to folder upload ordering must preserve that invariant or the hierarchy can be flattened remotely on bootstrap.
- **Live meetings are excluded.** Sync intentionally skips meetings in `recording` or `processing` status. A meeting in progress on Mac A is not visible on Mac B until it reaches a terminal status.

## Upcoming Work

1. **Cancel "starting now" timer on Join Only/Dismiss** — Pass notification key into `handleUpcomingMeeting` so `onJoinOnly`/`onDismiss` callbacks can cancel `meetingStartingNowTimers[key]`.
2. **CoreAudio tap migration** — Replace ScreenCaptureKit with CoreAudio aggregate device for system audio. Unblocks OCR during meetings + friendlier "System Audio" permission (not "Screen Recording"). See `Context/handoff-2026-04-16-coreaudio-tap-migration.md`.
3. **Google OAuth verification** — Pending Google approval (~4 weeks from April 12). Once approved, embed credentials with `verified: true`.
4. **Post-processor fine-tune** — Collect `postproc-pairs.jsonl` from canary testers, train v3 model for better implicit list formatting.
