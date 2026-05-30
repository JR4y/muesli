# Progress Log

This document is the cumulative implementation log for this fork.

It is intended to serve three purposes at once:

- keep a running history of product and technical progress
- make it easy to resume work without losing context
- prepare a clean base for future beta release notes and README feature updates

Last updated: `2026-05-30`
Working branch: `beta`
Dev app: `muesli-beta.app`

## Current state

The fork is now running locally as a separate beta app install and is usable
for daily real-world testing while development continues.

Git workflow currently documented and aligned:

- `upstream` remote points to the author's repository
- `origin` remote points to the fork
- `vendor` is the local clean mirror branch for upstream
- `beta-mergework` is the named merge desk used to trial upstream integration before promoting it
- `beta` is the active development branch
- `main` is reserved as the stable product branch

## Incremental history

### 2026-05-30

This pass refreshed the fork from the author's latest upstream branch through
`vendor`, resolved the larger meetings and audio merge conflicts in
`beta-mergework`, validated the result in the local beta app, and prepared the
consolidated promotion into `beta`.

#### Upstream merge refreshed from the author's current branch

- `vendor` was treated as the local mirror of `upstream/main`, not as a
  comparison target against `beta`
- the current review window was the author's changes published after the prior
  vendor sync on `2026-05-12`
- `docs/fork-workflow.md` was tightened again so the interpretation guardrails
  are explicit: first compare `vendor..upstream/main`, then refresh `vendor`,
  then recreate `beta-mergework`, then merge there

#### Meetings and lifecycle integration

- the upstream meetings stack was absorbed while preserving the fork's
  beta-specific work around live transcript, calendar association, folders,
  quick notes, note-only entries, local title and note caching, and transcript
  repair fallback behavior
- the merge now includes upstream support for more robust meeting lifecycle
  handling, concurrent recording and transcription flow, browser and media
  session improvements, audio import, and newer summary backends
- the merge conflict resolution favored the newer upstream core where it
  reduced future divergence, then reintroduced the fork features that remain
  product-significant for daily beta use

#### Stability fixes applied during validation

- `TranscriptFormatter` was adjusted so very short transcript fragments are not
  discarded when they are valid standalone content
- the `HotkeyMonitor` test suite was serialized and timing margins were widened
  to remove flaky hold-threshold failures during automated validation
- the update badge in the sidebar was restored to the fork's intended
  informational state after the upstream merge

#### Verification and local beta install

- `swift build` passed in `beta-mergework`
- `swift test` passed in full with `985 tests in 114 suites`
- the validated app was installed through `./scripts/beta-test.sh` as
  `/Applications/muesli-beta.app`
- the local beta build was smoke-tested manually before promotion
- promotion to `beta` is only performed after that validation gate, keeping the
  fork aligned with the documented merge discipline

### 2026-05-13

This pass finished the latest upstream calendar integration, made Google
Calendar usable in the fork's local beta workflow, and cleaned up the meetings
settings presentation so the calendar controls are easier to trust.

#### Upstream calendar merge promoted through mergework

- the latest upstream `vendor` changes around per-calendar filtering and
  retranscription recovery were reviewed and integrated through
  `beta-mergework`
- the validated merge was installed locally, tested in `muesli-beta.app`, and
  then promoted into `beta`
- the fork continued using the documented merge discipline:
  refresh `vendor`, recreate `beta-mergework`, validate there, then promote

#### Google Calendar activation for local beta builds

- local Google Calendar OAuth credentials are now supported through
  `config/google-oauth.json`, which stays ignored by git
- a committed template now exists at `config/google-oauth.json.example`
- local app builds now bundle that config automatically into the app resources
  when present, so beta installs can test Google Calendar without relying on a
  hidden home-directory setup
- the fallback path `~/.config/muesli/google-oauth.json` still works, but the
  fork now prefers the repo-local config because it is easier to reason about
  during mergework and beta validation
- README and dedicated local-setup documentation were added so the Google
  Cloud / OAuth flow is no longer implicit tribal knowledge

#### Google Calendar auth and API hardening

- the Google Calendar sign-in UI now distinguishes between:
  missing credentials, pending verification, active connection, and API load
  failures
- a real upstream auth bug was fixed: Google Calendar API `403` responses no
  longer force an automatic sign-out as if the session were invalid
- another real upstream scope mismatch was fixed: the app now requests both
  `calendar.events.readonly` and `calendar.calendarlist.readonly`, which are
  both required by the current calendar-list plus events flow
- after this fix, direct Google Calendar connection was verified working in the
  local beta app instead of only looking theoretically wired

#### Calendar settings UX cleanup

- the old overlap between the fork's local calendar controls and the newer
  upstream `Calendar Sources` panel was consolidated
- local EventKit calendars and direct Google OAuth calendars now flow through a
  shared enable/disable path, so settings toggles are less contradictory
- the `Google Calendar` connect/state area now lives in its own section above
  `Calendar Sources`
- `Calendar Sources` now focuses on sources and calendars only, instead of
  mixing connection state with the source list

### 2026-05-12

This pass stabilized the Meetily-inspired speech-pause transcript work in the
local beta build. The goal was to keep Muesli's stronger source separation and
canonical pipeline while adopting the more natural pause-based turn boundaries
that tested well in Meetily and in the new WAV importer.

#### Beta build discipline

- the beta install flow is now documented and enforced around
  `scripts/beta-test.sh`
- local beta builds install as `/Applications/muesli-beta.app`
- the beta bundle id is `com.jr4y.muesli.beta`
- beta data lives under `~/Library/Application Support/MuesliBeta/`
- if the local Developer ID signing identity is unavailable, the beta script
  explicitly falls back to an unsigned local install via `MUESLI_SKIP_SIGN=1`
- direct `scripts/build_native_app.sh` usage is documented as the generic
  production-style installer and should not be used for beta refreshes

#### Meetily-style WAV import harness

- Reuniones gained an `Import WAV` action for comparing pause segmentation on
  real audio files
- imported WAVs are normalized to 16 kHz mono, segmented with the shared
  Meetily-style VAD defaults, transcribed by turn, and saved as completed
  meetings with a single `Audio` source
- the importer intentionally remains a clean harness/control path and does not
  run through the full canonical meeting pipeline yet

#### Live transcript by speech pauses

- live transcript now consumes explicit speech-start, speech-end, chunk, and
  flush events instead of only appended transcript chunks
- live state is projected as open/closed turns, with independent lanes for
  microphone (`You`) and system audio (`Others`)
- the live VAD settings now reuse the shared Meetily-style baseline:
  `0.50` positive threshold, `0.35` negative threshold, `2.0s` redemption,
  `300ms` pre-speech pad, and `400ms` effective post-speech pad
- pause/stop now flushes active live turns and resets VAD detection state
- the live transcript panel auto-scrolls when the user is at the bottom and can
  be expanded/resized manually in the meeting detail view

#### Canonical transcript pause segmentation

- the final transcript pipeline now performs a safe post-reconciliation
  pause-projection pass before formatting the raw transcript
- the pass runs after ASR chunk collection, repair, reconciliation, and bleed
  filtering, so it does not replace the canonical quality gates
- microphone turns stay labelled as `You`
- system turns stay labelled as `Others` without diarization, or `Speaker N`
  with diarization
- system diarization boundaries are used as additional hard turn boundaries, so
  remote speaker changes can split a continuous speech region even when VAD
  sees it as one larger region
- the canonical formatter accepts a stricter consolidation gap for this path so
  natural pause turns are less likely to collapse back into large blocks

#### Verification

- focused tests were added for the Meetily-style importer and canonical speech
  turn segmenter
- verified suites include:
  `MeetilyStyleLiveTranscriptImporterTests`,
  `MeetingSpeechTurnSegmenterTests`,
  `LiveMeetingTranscriptReducerTests`,
  `StreamingVadControllerTests`,
  `TranscriptFormatterTests`, and `TranscriptReconcilerTests`
- `/Applications/muesli-beta.app` was rebuilt and reinstalled with
  `scripts/beta-test.sh`

### 2026-05-07

This pass pulled in the author's latest upstream native changes, validated
them in `beta-mergework`, documented the merge discipline more explicitly, and
then promoted the validated integration into `beta`.

#### Upstream integration promoted through mergework

- `vendor` was refreshed from the author's current `upstream/main`
- `beta-mergework` was recreated from the current `beta` before any upstream
  integration work
- upstream was merged and reviewed in `beta-mergework` first, not directly in
  `beta`
- `docs/fork-workflow.md` was tightened so the required order is now explicit:
  refresh `vendor`, recreate `beta-mergework`, merge there, validate there,
  then promote to `beta`

#### Computer Use foundations incorporated into the fork

- the author's new `Computer Use` lane is now present in the fork's beta code
- Settings gained a dedicated `Computer Use` pane for planner enablement,
  account/model choices, and timeout controls
- Shortcuts gained a second configurable hotkey surface specifically for
  `Computer Use`
- dictation history rows now understand the new `CUA` command records and
  expose the trace-copy flow that came with the upstream feature
- the merge kept the fork's existing settings shell, navigation, and
  localization structure while absorbing the new upstream capability under it

#### Shortcut behavior and coexistence

- the fork's existing status/menu bar behavior remains the primary UX layer
- the upstream work did not replace that layer; it added a second hotkey lane
  for `Computer Use`
- the upstream hotkey monitor hardening for text editing was kept, so standard
  edit shortcuts behave more safely while note fields are focused
- the current merged state intentionally allows `Dictation` and `Computer Use`
  to coexist as separate modifier-key shortcuts, with runtime protection
  against both using the same key at once

#### Follow-up captured for the fork

- `docs/backlog.md` now explicitly tracks a shortcut-system consolidation pass
  to clean up the remaining conceptual overlap between standard macOS edit
  commands, the fork's shortcut surfaces, and the new upstream `Computer Use`
  hotkey lane
- the current beta app install was intentionally left in place for continued
  manual validation after promotion

### 2026-05-06

This pass reworked the meeting transcript presentation layer without changing
the canonical final transcript pipeline.

#### Live transcript light pipeline

- The meeting stack now keeps a lightweight live transcript lane separate from
  the canonical final transcript lane
- Live transcript state is built from `MeetingTranscriptChunk` values and
  grouped for UI only; it no longer acts as an input to final transcript
  generation
- The live transcript reducer still groups by source and time, but it now
  lives behind an explicit pipeline object instead of being scattered across
  meeting session callbacks
- Settings now expose a `Live transcript` toggle under `Meetings`
- The toggle is operational, not cosmetic:
  - when enabled, live transcript chunks are projected and published for UI
  - when disabled, no live transcript turns are published or rendered during
    recording/processing
  - the final transcript pipeline still runs normally after stop

#### Final transcript chat view

- Meeting detail now renders completed transcripts as a chat-style conversation
  instead of plain monospaced text
- The same visual language is reused for live and final transcript display
  through a shared transcript chat view
- Alignment follows transcript semantics:
  - `You` renders on the right
  - `Others` and `Speaker N` render on the left
  - timestamps render above each bubble
- The app still stores and exports the transcript as the same plain-text
  `rawTranscript` format

#### Transcript display parsing

- Added a deterministic parser that converts persisted `rawTranscript` lines
  like `[HH:mm:ss] You: ...` into display turns for the final transcript UI
- Malformed lines fall back safely to a generic left-aligned transcript bubble
  instead of breaking the transcript panel

#### Regression coverage

- Added focused tests for:
  - default config behavior of `enableLiveMeetingTranscript`
  - backward-compatible decoding of older config payloads
  - live transcript pipeline chunk projection
  - final transcript display parsing, including malformed-line fallback

This change intentionally did **not** alter the canonical transcript formatter,
post-live diarization, or export/storage format. The goal was to improve live
control and transcript presentation without reopening the already-working
final transcript pipeline.

### 2026-05-04

This pass implemented multi-Mac sync via Supabase, following the plan in
`docs/plans/2026-05-04-supabase-sync-corrected-plan.md`. Sync is currently
scoped to `muesli-beta.app` only (production and dev variants stay
unaffected because each variant has its own data directory and Keychain
service namespaced by `Bundle.main.bundleIdentifier`).

#### Supabase project provisioned

- New Supabase project `molli` created under `JR4y's Org` in `eu-west-1`
  (West EU / Ireland), free tier
- Reference id: `pjjwmekbrchaytipxtjk`
- Existing project `facturador` was paused to free a free-tier slot
- Initial migration lives in
  `supabase/migrations/20260504000000_init_sync_schema.sql` and was applied
  via `supabase db push`
- Tables created: `meeting_folders`, `meetings`, `dictations`,
  `user_preferences`. Each business table carries `client_updated_at`,
  `server_updated_at`, `remote_version`, `last_writer_device_id` and
  `deleted_at` (soft delete)
- A Postgres trigger `bump_remote_version` increments `remote_version` and
  updates `server_updated_at` on every UPDATE, on all four tables
- RLS is enabled on every table, with a `*_own` policy that restricts each
  row to `auth.uid() = user_id`
- Indexes: `(user_id, server_updated_at, id)` per table, plus
  `(parent_folder_id)` on folders, `(folder_id)` on meetings, and a
  partial index on `meetings(user_id, calendar_event_id)` when
  `calendar_event_id IS NOT NULL`

#### Build-time credential injection

- New committed template: `config/Supabase.xcconfig.example`
- New gitignored local file: `config/Supabase.xcconfig` (KEY=VALUE format
  with `MUESLI_SUPABASE_URL`, `MUESLI_SUPABASE_ANON_KEY`, and
  `MUESLI_SUPABASE_DB_PASSWORD`)
- `.gitignore` updated to ignore `config/Supabase.xcconfig` and
  `supabase/.temp/`
- `scripts/build_native_app.sh` parses the xcconfig before generating
  `Info.plist` and embeds two new keys inside the bundle:
  - `MuesliSupabaseURL`
  - `MuesliSupabaseAnonKey`
- A build with the file missing is still valid — the sync stack just stays
  inert and the Sync settings pane shows a "not configured" message
- The anon/publishable key is safe to ship in the bundle because RLS
  enforces per-user access; the `service_role` key never enters the
  client

#### Local sync layer (MuesliCore)

New files inside `native/MuesliNative/Sources/MuesliCore/Sync/`:

- `LocalSyncModels.swift` — shared types (`SyncEntityType`,
  `SyncMetadataRecord`, `SyncTombstoneRecord`, `SyncCursor`,
  `SyncPreferencesSnapshot`, `SyncPreferencesState`, `RemoteFolderPayload`,
  `RemoteDictationPayload`, `RemoteMeetingPayload`, `RemotePreferencesPayload`,
  `DirtyDictation`, `DirtyMeeting`, `DirtyFolder`, `SyncStateKey`,
  `SyncTimestamp`)
- `LocalSyncRepository.swift` — sole owner of the sync auxiliary tables
  and triggers. It opens its own SQLite connection but shares the same
  `muesli.db` file as `DictationStore`. The schema is unchanged at the
  business level: no new columns added to `dictations`, `meetings`, or
  `meeting_folders`.
- `SyncPayloadHasher.swift` — canonical JSON + SHA-256 hashing of the
  sync payload for each entity type. Used to detect "different version,
  identical content" no-op conflicts.

Auxiliary tables created lazily by `LocalSyncRepository.migrateIfNeeded()`:

- `sync_metadata` — one row per `(entity_type, local_id)`. Tracks
  `remote_id`, `client_updated_at`, `remote_version`,
  `last_seen_server_updated_at`, `last_payload_hash`, `dirty`,
  `last_writer_device_id`. UNIQUE on `(entity_type, remote_id)`.
- `sync_tombstones` — one row per local delete, even if the row was
  never synced. Stores `client_deleted_at`, `last_known_remote_version`,
  and `dirty`.
- `sync_state` — generic key/value store for cursors, device id, and
  preferences sync state.

Same-day beta hardening after first real multi-Mac test added three
important operational fixes:

- `migrateIfNeeded()` now backfills missing `sync_metadata` rows for
  pre-existing local `dictations`, `meetings`, and `meeting_folders`, so a
  first sign-in on an already-used beta install uploads the existing local
  history instead of only rows created after sync shipped.
- Supabase cursor timestamps that come back as `...+00:00` are normalized
  before building PostgREST cursor filters. This fixes the
  `Supabase 400: invalid input syntax for type timestamp with time zone`
  failure seen after the first successful page download.
- Folder uploads now defer child folders whose local parent exists but does
  not yet have a `remote_id`, then re-read dirty folders after the parent
  syncs. Without that, first-sync bootstrap could upload nested folders as
  roots and then reapply the broken root state back into SQLite on the next
  download cycle.

Triggers installed on the existing business tables:

- `AFTER INSERT` and `AFTER UPDATE` on each of `dictations`, `meetings`,
  `meeting_folders` upsert into `sync_metadata` with `dirty = 1` and a
  fresh `client_updated_at` derived from
  `strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`.
- `BEFORE DELETE` copies `remote_id` and `remote_version` from
  `sync_metadata` into a tombstone row, even when no metadata exists yet
  (in that case the tombstone has a `NULL` remote_id and is purged
  locally without a remote round-trip).
- `AFTER DELETE` removes the orphaned `sync_metadata` row.

Important behaviour: the triggers fire during remote-applied changes too.
`applyRemoteFolder`, `applyRemoteDictation`, and `applyRemoteMeeting` run
inside an immediate transaction, perform the domain INSERT/UPDATE/DELETE,
then immediately overwrite the metadata row to `dirty = 0` with the
authoritative remote values, and clear any tombstone the BEFORE DELETE
trigger created on a remote-driven delete. Without that final fix-up the
remote write would look like a fresh local edit on the next cycle.

Reconciliation helpers live on `LocalSyncRepository`:

- `findUnmappedDictation(timestamp:rawText:appContext:)`
- `findUnmappedMeetingByCalendar(calendarEventID:startTime:)`
- `findUnmappedMeetingByFingerprint(startTime:durationSeconds:rawTranscript:)`
- `findUnmappedFolder(name:parentRemoteID:)`
- `localID(forRemoteID:entityType:)` /
  `remoteID(forLocalID:entityType:)`
- `unsyncedDictations(limit:)`, `unsyncedMeetings(limit:)`,
  `unsyncedFolders(limit:)`

These let the sync manager pre-bind a freshly downloaded remote row to an
existing local row so the apply step UPDATEs instead of inserting a
duplicate.

`device_id` is generated lazily on first call to `ensureDeviceID()` and
persisted in `sync_state`. Each app variant
(`Muesli` / `MuesliBeta` / `MuesliDev` / `MuesliCanary`) has its own
`muesli.db`, which means each has its own device id automatically.

Tests added: `native/MuesliNative/Tests/MuesliTests/LocalSyncRepositoryTests.swift`.
The suite covers migration idempotency, device-id stability, the
insert/update/delete trigger contract, dirty-tombstone semantics for both
synced and never-synced rows, `applyRemote*` cleanliness and audio-path
preservation, parent remapping for folders, dictation-status filtering on
meetings, cursor save/load roundtrip, preferences dirty/synced flow,
tombstone purge behaviour, and hash stability across equivalent JSON
payloads. It also covers the first-sync metadata backfill path and the
UTC-offset cursor normalization helper. Tests use real temporary SQLite
databases (no mocks) per the project preference for SQLite-backed tests
over in-memory mocks for the sync layer.

#### Auth and REST client (MuesliNativeApp)

New files under `native/MuesliNative/Sources/MuesliNativeApp/Sync/`:

- `SupabaseConfig.swift` — reads `MuesliSupabaseURL` and
  `MuesliSupabaseAnonKey` from `Bundle.main`. Returns `nil` when the
  build wasn't given an xcconfig, which keeps the rest of the stack
  inert. Builds `/auth/v1/...` and `/rest/v1/...` URLs. The Keychain
  service is bundle-id-namespaced
  (`<CFBundleIdentifier>.supabase-auth`), so each variant keeps its own
  session.
- `SupabaseKeychainStore.swift` — generic password store on top of the
  macOS Keychain Services. Persists refresh token, access token, expiry,
  user id, and email. Uses `kSecUseDataProtectionKeychain = true`.
- `SupabaseAuthManager.swift` — `@MainActor @Observable` class with
  `signUp`, `signIn`, `signOut`, and `currentAccessToken()`. Does pure
  REST against `/auth/v1/signup`, `/auth/v1/token?grant_type=password`,
  and `/auth/v1/token?grant_type=refresh_token`. Restores the session
  from Keychain at init. Refresh is idempotent via a single in-flight
  task. A failed refresh with 400/401 calls `signOut()` so the UI can
  surface the disconnected state. Email-confirmation-pending signup is
  surfaced as `awaitingEmailConfirmation = true` so the UI can prompt
  the user to confirm by email and then sign in.
- `SupabaseRESTClient.swift` — thin PostgREST client. One method per
  operation per entity (`selectFolders`, `upsertFolder`, `updateFolder`,
  `fetchFolder`, etc.), plus a generic paginator that orders by
  `(server_updated_at ASC, id ASC)` and walks the cursor with the
  `or=(server_updated_at.gt.X, and(server_updated_at.eq.X, id.gt.Y))`
  PostgREST pattern. Updates use optimistic concurrency via
  `remote_version=eq.<expected>`; an empty response means a conflict and
  the caller is expected to refetch and resolve with LWW. The client
  retries once on 401 after asking the auth manager for a fresh token.

#### Sync orchestrator (actor)

`native/MuesliNative/Sources/MuesliNativeApp/Sync/SupabaseSyncManager.swift`
is an `actor` that serializes every sync cycle. Public API:

- `start()` — bootstraps the repo (idempotent migrate + ensureDeviceID),
  starts a 5-minute heartbeat task, runs an initial sync
- `shutdown()` — cancels every internal task; the in-flight cycle is
  allowed to finish on its own
- `notifyPotentialLocalDataChange()` — debounced 2s, called from
  `MuesliController.syncAppState()`
- `notifyPreferencesChanged()` — debounced 1s, called from
  `MuesliController.updateConfig(_:)` only when the sync-relevant slice
  of `AppConfig` actually changed
- `syncNow(reason:)` — manual trigger used by the Sync settings pane
  and post-signin/signup hooks

Cycle order matches `docs/plans/2026-05-04-supabase-sync-corrected-plan.md`
sections §13.1 / §13.2: download in the order folders → preferences →
dictations → meetings, then upload in the order folders → dictations →
meetings → preferences → tombstones (meetings, then dictations, then
folders). After the cycle runs, `purgeCleanTombstones(olderThanDays: 30)`
sweeps the local tombstone table.

Conflict resolution is last-write-wins per entity:

1. Hash the local payload and the remote payload with the canonical
   serializer
2. If the hashes match, mark the local row clean with the remote version
   (no write at all, no false data swap)
3. Otherwise compare `client_updated_at`. The newer side wins
4. If the timestamps tie, the lexicographically larger `device_id` wins

Reconciliation runs on download: before applying a remote payload, the
manager checks whether any local row already matches by fingerprint
(`timestamp + raw_text + app_context` for dictations,
`calendar_event_id + start_time` and then transcript-based fingerprint
for meetings, name + parent path for folders). If it finds a match, it
calls `attachRemoteID` so the subsequent `applyRemote*` becomes an
UPDATE on the existing row instead of inserting a duplicate.

Audio paths are protected per §23 of the plan. When a remote meeting
update lands on top of an existing local meeting, `mic_audio_path`,
`system_audio_path` and `saved_recording_path` are intentionally left
untouched; only the new download path inserts NULLs because we're
materializing a row for the first time on this Mac.

Tombstone uploads piggy-back on the existing upsert routes: each
tombstone is written as a regular row with `deleted_at` set to the local
delete timestamp, the user id from the auth manager, and the device id
from the repo. Once the upsert succeeds, the tombstone is marked clean
locally so the 30-day purge can eventually remove it.

Heartbeat uses `Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)`. Per
the existing CLAUDE.md note about macOS 26 App Nap behaviour for
LSUIElement apps, the heartbeat may be delayed when the app is fully
idle. It's a safety net only; the primary triggers are launch, signin,
the debounced `notify*` calls, and the manual `Sync now` button.

#### Preferences bridge

`native/MuesliNative/Sources/MuesliNativeApp/Sync/AppConfigSyncSnapshot.swift`
declares two extensions on `AppConfig`:

- `syncPreferencesSnapshot(folderRemoteIDLookup:)` — serializes
  `customMeetingTemplates` and `customWords` with a sorted-keys
  JSONEncoder, copies `hiddenBuiltInTemplateIDs`,
  `defaultMeetingTemplateID`, `autoTemplateTargetID`, and
  `meetingTitlePrompt` verbatim, and converts `folderOrder: [Int64]`
  into `folderOrderRemoteIDs: [String]` via the lookup. Folders without
  a remote id yet are silently dropped from the order; they'll be
  back-filled on a later cycle once the folder has been uploaded.
- `applyingSyncSnapshot(_:folderLocalIDLookup:)` — produces a copy of
  `AppConfig` where only the sync-relevant fields are replaced. Every
  other field (`openAIAPIKey`, hotkey, model picks, onboarding state,
  hidden calendar ids, indicator anchor, theme, etc.) is preserved as-is.
  `folderOrderRemoteIDs` is mapped back to `[Int64]`; remote ids without
  a local mapping are dropped.

The bridge struct `SupabasePreferencesBridge` carries two
`@MainActor @Sendable` closures (`snapshot` and `applyRemoteSnapshot`).
They are constructed in `AppDelegate` over the live `MuesliController`.

#### Controller and lifecycle integration

- `AppDelegate.applicationDidFinishLaunching(_:)` now constructs the
  full sync stack after `controller.start()`:
  - `LocalSyncRepository(databaseURL:)` against the same path the
    `DictationStore` is using (`MuesliPaths.defaultDatabaseURL` with
    the variant-specific support directory)
  - `SupabaseAuthManager`, `SupabaseSyncStateObserver`,
    `SupabaseRESTClient` (only when the bundle is configured)
  - `SupabasePreferencesBridge` over `MuesliController`
  - `SupabaseSyncManager`, started via `Task { await syncManager.start() }`
  - All four are injected back into `MuesliController` (`syncManager`,
    `syncRepo`, `supabaseAuth`, `supabaseSyncObserver`)
- `applicationWillTerminate(_:)` calls
  `Task { await syncManager.shutdown() }` before the controller's own
  shutdown, mirroring the plan's "best-effort short final sync" intent
  (the in-flight cycle is left to drain naturally so termination is not
  blocked)
- `MuesliController.syncAppState()` now emits a
  `Task { await syncManager.notifyPotentialLocalDataChange() }` at the
  end and mirrors the auth + observer state into `AppState` so the Sync
  settings pane stays current
- `MuesliController.updateConfig(_:)` now diffs
  `currentSyncPreferencesSnapshot()` before and after the mutation;
  when the snapshot changes it calls
  `syncRepo.markPreferencesDirty()` and
  `Task { await syncManager.notifyPreferencesChanged() }`. Non-sync
  config edits (API key changes, hotkey changes, etc.) do not trigger
  sync work
- New helpers on `MuesliController`:
  `currentSyncPreferencesSnapshot()`,
  `applyRemoteSyncPreferences(_:)`,
  `supabaseSignIn(email:password:)`,
  `supabaseSignUp(email:password:)`, `supabaseSignOut()`, and
  `supabaseSyncNow()`

#### Settings UI

- `AppState` gains `case sync` in `SettingsPane` plus the mirrored
  fields `supabaseSyncConfigured`, `isSupabaseAuthenticated`,
  `supabaseEmail`, `supabaseAwaitingEmailConfirmation`,
  `supabaseSyncStatusText`, `supabaseSyncErrorText`,
  `supabaseLastSyncAt`, and the three counters
  `syncedFolderCount` / `syncedDictationCount` / `syncedMeetingCount`
- `SettingsView.paneTitle` and `SettingsView.paneContent` now route the
  new `.sync` case
- New view:
  `native/MuesliNative/Sources/MuesliNativeApp/Sync/SyncSettingsView.swift`.
  Shows three states:
  - "Sync is not configured for this build" when the xcconfig wasn't
    embedded
  - Email + password fields with `Sign in` and `Create account`
    buttons when not authenticated; surfaces the
    `Check your email to confirm` notice when signup returns no session
  - A signed-in card with the user email, a `Sign out` button, three
    counters, a `Sync now` button, the relative-date last-sync label,
    the live status text, and any error text
- `L10n.swift` gains a single new key `syncTitle` with localized
  strings for English ("Sync") and Spanish ("Sincronización")

#### Privacy boundaries reinforced in code

The fields the plan lists as "must not leave the device" are not
referenced anywhere in the sync stack. Specifically the upload payloads
never include `openAIAPIKey`, `openRouterAPIKey`, ChatGPT tokens, Google
Calendar tokens, hotkey config, model picks, indicator/window state,
onboarding flags, `hiddenLocalCalendarIDs`, `hiddenCalendarEventIDs`,
permission flags, `mic_audio_path`, `system_audio_path`,
`saved_recording_path`, or any other filesystem path. The
`SyncPreferencesSnapshot` is intentionally narrow.

#### Live meetings excluded from upload

Meetings in `recording` or `processing` status are filtered out of
`dirtyMeetings` and `unsyncedMeetings` SQL. They become eligible the
moment they transition to `completed`, `note_only`, or `failed`.

#### Test results

`swift test --package-path native/MuesliNative` was used throughout the
implementation. The new `LocalSyncRepository` suite was added to the
existing test base; the full run finished with all suites green (the
pre-existing `MeetingNotificationController` non-sendable warning is
unchanged). Sync-specific tests use real temporary SQLite databases
under `FileManager.default.temporaryDirectory`, never mocks.

#### Manual follow-up the user still owns

- Decide on the `Confirm email` toggle in the Supabase dashboard under
  Authentication → Providers → Email. The code handles either choice;
  OFF is more convenient for personal multi-Mac sync.
- Build the beta variant with `./scripts/beta-test.sh` (or the regular
  `./scripts/build_native_app.sh`) from a checkout that has
  `config/Supabase.xcconfig` populated. The sync stack stays inert
  otherwise.
- Sign up on the first Mac, sign in on the second Mac, watch data
  reconcile.
- Back up the Postgres password from `config/Supabase.xcconfig` (it
  isn't in git) somewhere durable, e.g. 1Password. It's only needed to
  run future `supabase db push` migrations from the CLI.

### 2026-05-03

This pass brought the fork back in line with the author's latest upstream
native changes, validated the result in `beta-mergework`, and published that
validated integration as the new `beta` baseline.

#### Upstream integration promoted through mergework

- `vendor` was advanced to upstream `main` at `d21e0f7`
- the upstream merge was rehearsed in `beta-mergework` before publication
- conflicts were resolved there first so the fork's daily branch could stay clean
- the resulting merge keeps the current fork behavior while absorbing the newer upstream app changes

#### Fork-specific behavior preserved and aligned

- the fork's `ThemePreset` model changes were preserved alongside the author's newer onboarding use case work
- the fork's settings structure and localization paths were kept while adopting the author's better screen-recording permission UX
- the sidebar kept the fork's current labels while gaining the upstream model-preparation status block
- the quick-note meeting detail flow now uses the author's preferred compact stop button treatment
- the meeting-record CTA was simplified to `Record` / `Grabar` while keeping the stronger orange upstream visual language

#### Beta app and validation cleanup

- the daily test app name is now consistently documented and built as `muesli-beta.app`
- `scripts/beta-test.sh` now cleans up the legacy `MuesliBeta.app` install if it still exists
- local beta builds now fall back cleanly to an unsigned install when the expected codesign identity is not present on this machine
- `MeetingHookIntegrationTests` was corrected so the failure case now exercises the intended missing-live-meeting path instead of relying on stale duplicate-calendar-id assumptions
- the focused `MeetingHookIntegrationTests` suite passes again on top of the updated beta integration

### 2026-04-29

This pass focused on keeping the fork aligned with upstream while continuing
to shape the beta app into a cleaner daily-use product.

#### Upstream sync and branch hygiene

- `vendor` was advanced to the author's latest `upstream/main`
- upstream changes were merged into `beta` through the fork workflow without app-level conflicts
- the current `beta` work was committed cleanly before continuing integration
- a dedicated mergework branch was used first so upstream integration could be reviewed safely before fast-forwarding `beta`

The upstream delta turned out to be small for product behavior in this fork:
it mainly added repository automation and updated the upstream preprod Sparkle
feed, without touching the native app runtime used in daily beta testing.

#### Local beta app build path

- the fork's local beta build path is now explicitly codified in `scripts/beta-test.sh`
- local beta builds now install as `muesli-beta.app`
- local beta builds keep using the fork bundle id `com.jr4y.muesli.beta`
- local beta builds now disable Sparkle feed lookup instead of inheriting the author's `appcast.xml` or `appcast-preprod.xml`
- `docs/fork-workflow.md` now documents that `release-preprod.sh` is upstream-oriented infrastructure, not the day-to-day beta build path for this fork

This matters because the previous beta install had been pointing at the
author's production Sparkle feed, which was not the intended behavior for a
local fork build under active development.

#### Sidebar and settings information architecture

- `Dictionary`, `Models`, and `Shortcuts` were removed from the top level of the sidebar
- those areas now live as dedicated panes inside `Settings`
- the main sidebar is now more focused on daily-use surfaces rather than utility/configuration screens
- compatibility paths were preserved so existing code that tries to open those areas can redirect into the correct settings pane instead of breaking

This was intentionally kept incremental rather than replacing the whole
navigation model, so the fork stays easier to maintain as upstream grows.

#### Themed meeting popups

- meeting notification popups now respect the app's current light/dark mode
- popup surfaces now follow the active theme palette instead of staying on a fixed dark look
- popup accent/progress colors now follow the app accent more closely

This closes an important visual consistency gap because the popup had remained
stylistically detached from the rest of the app even after the theme system was
introduced.

#### Meeting detail UX and calendar association polish

- the meeting detail sidebar/header area was reorganized so title, actions, and content align more consistently
- notes/transcript content now shares the same visual column as the associated event panel
- the associated event chip below the title was removed in favor of keeping event actions inside the event panel itself
- the associated event panel can now collapse when attendee detail makes it too tall
- old notes with a `calendar_event_id` but no persisted snapshot can now still show the `Associate event` action instead of getting stuck in a half-linked state
- nearby calendar suggestions now prioritize the note's own local date context instead of behaving like a pure "future events" helper
- local suggestion search now looks across the previous day, the same day, and the following day
- the event association picker now shows a loading state while querying calendars instead of briefly claiming no nearby events exist

This was an important quality pass because it improved both readability of the
meeting detail screen and trust in the late-association flow for older orphaned
notes.

#### Hierarchical folders and meeting browser polish

- folders now support parent-child hierarchy while keeping a single canonical folder assignment per meeting
- selecting a parent folder now scopes the meeting browser to that full subtree rather than only direct children
- folders now support both curated accent colors and curated SF Symbol icons for quicker visual recognition
- the folder editor now allows updating name, parent, color, and icon from the meetings browser
- the sidebar now renders folders as an indented tree with expand/collapse behavior and subfolder creation from the context menu
- the meeting detail view now shows the full folder path instead of only the leaf folder name
- the meetings list now shows a subtle associated-calendar indicator before the folder marker when a note is already linked to an event
- the meetings browser header was simplified by removing redundant folder summary chrome and moving folder editing to the folder icon beside the title
- the custom folder palette was tuned to a more muted product direction during validation:
  - `e03e3e`
  - `d9730d`
  - `dfab01`
  - `0f7b6c`
  - `337ea9`
  - `9065b0`
  - `ad1a72`
  - `64473a`

This pass intentionally stopped short of multi-folder tagging. The implemented
model is hierarchical navigation first, with one folder per meeting and parent
folders inheriting visibility over descendant meetings.

#### Meetings visual cleanup pass

- `Coming Up` now hides the secondary `Add to folder` and dismiss controls so the row stays focused on the join/record action
- the meetings list now uses the same compact localized date style as the meeting detail view
- list-level calendar linkage now uses a neutral calendar icon instead of a success-colored badge
- the folder pill in the meetings list now replaces the trailing folder button and keeps the assigned folder color on the icon only
- the meeting detail folder pill now uses the persisted folder color on its icon and also opens the move/create-folder menu directly from the header
- the meeting detail template control was tested as a pill/selector fusion and then intentionally reverted to a normal selector because the hybrid styling reduced clarity
- `Show Recording` now sits beside the resummarize/template controls instead of feeling detached below them
- persistent row-selection shading in the meetings browser was removed so opening a note no longer leaves the previous row visibly stuck in an active state

This round was intentionally visual and interaction-focused. The goal was to
make meetings feel calmer and more legible without changing the underlying
recording, summary, or folder data model.

#### Secondary-surface localization and quick-note behavior

- meeting notification popups now localize their titles, timing copy, and action labels through `L10n.swift`
- the live notes / quick-note surface now localizes save state, placeholder copy, editor helper buttons, and recording controls
- the dashboard `Quick Note` button now also respects the configured app language instead of staying hardcoded in English
- quick notes no longer start recording automatically by default; a dedicated `Settings > Meetings > Recording` toggle now controls that behavior independently from normal meetings
- when a quick note opens in note-only mode, the same meeting can start recording later from inside the detail view without creating a second note
- the embedded markdown editor was hardened so toolbar commands restore focus/selection before applying formatting, fixing the previous "button bounce" behavior seen in manual notes

This pass closed the most visible remaining English-only surfaces in daily beta
usage while also making quick notes feel safer as a lightweight capture mode.

#### Validation

- targeted Swift tests were re-run after the refactor and passed
- `muesli-beta.app` was rebuilt and reinstalled from the current `beta`
- real beta usage confirmed that themed popups now respect app styling
- real beta usage also confirmed a calendar-linked meeting example still associated the expected event context
- real beta usage confirmed orphaned notes can now be linked again through the picker without misleading empty-state flashes
- real beta usage validated the hierarchical folder tree, folder colors/icons, and meetings-list association indicator in the browser flow
- real beta usage confirmed quick notes can open without auto-recording, start recording later from the same note, and now show localized editor copy throughout the flow
- the window/titlebar experiment for replacing the native SwiftUI sidebar toggle was intentionally discarded, and the beta remains on the stable `NavigationSplitView` titlebar behavior

#### Upstream vendor integration follow-up

After the local beta UX/localization pass was stable, the fork was brought back
up to date with the author's newer upstream changes through `beta-mergework`
before promoting them into `beta`.

- `vendor` was advanced again to the author's newer `upstream/main`
- the merge was rehearsed in `beta-mergework`, validated there, and then fast-forwarded into `beta`
- Slack meeting detection was hardened so Slack no longer behaves like a noisy generic app-presence signal and instead requires stronger audio attribution before prompting
- the meeting prompt state machine now adds a short candidate dwell period and stronger suppression semantics so repeated prompts are less jumpy
- detection prompts are now suppressed while dictation activity is active, reducing cross-talk between dictation and meeting detection flows
- `Coming Up` now temporarily caps the visible upcoming-meetings list to 5 events, which is acceptable for now and can later evolve into proper pagination
- upstream Sparkle/update verification hardening and related release metadata updates were also pulled in

This upstream pass was intentionally accepted as infrastructure-first work. The
Slack and prompt-state changes improve reliability immediately, while the
5-item `Coming Up` cap gives a reasonable short-term ceiling until a richer
pagination or expansion model is added.
### 2026-04-27 to 2026-04-28

This was the first major fork setup and product-shaping pass.

#### Environment and app setup

- Xcode was installed and activated as the active toolchain
- A separate beta app build was created as `muesli-beta.app`
- Beta data was migrated from the author's app where it made sense for daily use
- The beta app is now being used as the main test environment

#### UX and navigation improvements

- `Meetings` was moved above `Dictations` in the sidebar
- `Meetings` was made the default landing screen
- The app now opens in the area that feels more important for daily use

#### Localization foundation

- A centralized localization layer was introduced in `L10n.swift`
- Language preference is now stored in app config
- Supported modes are:
  - `System`
  - `Espanol`
  - `English`
- The sidebar was migrated to the localization layer first
- A language selector was added to `Settings > General`

#### Localization coverage expansion

The main daily-use interface received a broad localization pass, including:

- meetings browser
- meeting detail actions
- list item actions
- meeting templates manager
- settings panes and labels
- dictations flow
- dictionary
- shortcuts
- about
- status bar / menu bar menu
- stats labels

At this point, the main everyday experience is largely bilingual. Remaining
English text appears mostly in onboarding or lower-priority internal surfaces.

#### Visual direction and themes

- The light theme moved away from stark white to a warmer, calmer direction
- The main window background no longer stays black in light mode
- Appearance now supports preset-based theming in addition to accent color
- A persistent `themePreset` was added to app config
- Theme resolution was centralized in `MuesliTheme.swift`
- A selector was added to `Settings > Appearance`

Current theme presets:

- `Calido`
- `Neutro`
- `Grafito`

The preset system was intentionally chosen over freeform editing so the fork
can stay visually coherent while still being easy to tune.

#### Data and migration work

The beta install already received a practical migration for daily use:

- meetings were migrated
- dictations were migrated
- retained meeting recordings were copied
- meeting recording paths were rewritten so beta points to `MuesliBeta`

Not intentionally migrated:

- app config
- auth/session files

This was done on purpose so configuration can be reviewed manually as part of
UX work.

#### Calendar and meeting behavior review

The current calendar pipeline was reviewed at a product level:

- local calendars are primarily read through EventKit
- optional Google Calendar support exists, but only when credentials are available
- upcoming meeting notifications currently rely on hardcoded timing rules
- meeting detection can happen both with and without a calendar event
- meeting notes and calendar events are not yet linked as reliably as they should be
- attendee data is not currently surfaced or stored

This area is now captured in backlog as a dedicated product stream.

#### Calendar source controls

A first practical calendar control pass was implemented:

- local EventKit events now carry calendar metadata for future UX work
- the app now tracks which local macOS calendars are available
- users can enable or disable individual local calendars in `Settings`
- local calendar filtering now affects upcoming meetings, calendar-based prompts, and detection

This intentionally avoids aggressive deduplication for now and gives the user
direct control over which local sources participate.

#### Calendar recovery and note association

The next pass focused on making calendar usage more resilient in daily use:

- `Coming Up` now surfaces calendar color and source identity more clearly
- manual recordings can now auto-link silently when there is a single active calendar event
- notes that were created without a linked calendar event can now be associated later from the note detail view
- the association flow suggests nearby calendar events based on the note start time

This turned out to be important because older migrated notes already existed
without `calendar_event_id`, so the problem was not limited to new recordings.

#### Local time rendering for notes

A date formatting fix was added for note timestamps:

- note and meeting timestamps are now rendered in local time instead of showing the raw UTC-backed ISO string
- this fix was applied across note detail, note list, and search results

This matters because the stored data was already correct, but the UI could show
misleading times such as `09:01` instead of the real local `11:01`.

#### Summary workflow and template controls

The next pass focused on making meeting summaries more controllable in daily use:

- the summary pipeline and transcript-cleanup pipeline were reviewed separately
- custom summary templates are now the main way to control summary structure and language
- built-in templates can now be hidden from the UI without removing them from code
- any visible built-in or custom template can now be marked as the default
- `Auto` can now resolve to the user's chosen template target instead of always behaving like a fixed built-in
- custom templates are now shown before built-ins in template management and selection surfaces
- the meeting title generation prompt is now editable from `Manage Templates`

This matters because the fork now supports a much clearer editorial split:
cleanup prompt in settings, summary templates in the templates manager, and the
meeting-title prompt as a separate system prompt.

#### Meetings dashboard and folder polish

A small but practical UX pass was added for meetings organization:

- `Coming Up` can now be collapsed and expanded from the dashboard
- this keeps long upcoming lists from pushing the meetings browser too far down
- meeting folders now support optional accent colors
- folder colors are chosen from the folder context menu
- meetings now surface the assigned folder more clearly in the list and in the meeting detail header

This was intentionally kept lightweight: folders are still single-assignment
containers, not tags or nested structures.

#### Calendar persistence and meeting context

The next pass focused on making calendar-linked meetings durable and easier to
trust after the event has already passed:

- future meetings now persist a calendar event snapshot instead of keeping only `calendarEventID`
- the snapshot includes useful event metadata such as title, time range, calendar source, color, and join URL
- attendee data is now persisted together with the event snapshot
- active meetings refresh that snapshot while they are still recording or processing, then keep it frozen once completed
- meeting detail now shows the associated event, join link, and attendee list directly in the note view

This was intentionally scoped forward-only: older historical notes were not
backfilled.

#### Meeting start and manual-notes consistency

Two behavior fixes closed important daily-use gaps in the meetings flow:

- `Coming Up > Join and Record` now passes the concrete calendar event id, so meetings started from the dashboard are associated immediately instead of relying on time-based inference
- protected manual notes now render as a localized top section (`## Notes` / `## Notas`) instead of falling back to a trailing hardcoded English appendix

This keeps handwritten notes intact while making the final document structure
feel consistent with the rest of the generated summary.

#### Calendar incident hardening

After more real-world beta usage, a serious calendar-linking incident was
reviewed and fixed:

- one real meeting was split into two rows because the recording row carried an invalid composite calendar id while a second empty row was later created from the dashboard
- the broken database state was repaired manually by moving the calendar link back onto the saved meeting with transcript and deleting the empty duplicate
- the root cause was traced to the `Meeting starting now` notification path, which was passing an internal deduplication key (`eventID|timestamp`) as if it were the real calendar event id
- that notification path now passes the real event id
- calendar ids are now normalized centrally so malformed values like `eventID|timestamp` can still be recovered instead of silently breaking association
- creating a meeting from a calendar event now attempts to reuse and repair an existing meeting row that matches the normalized calendar id instead of always creating a new empty row

This was an important stabilization pass because the calendar popups are not a
minor UX detail in this fork; for normal meeting recordings they are expected
to be the primary and trustworthy entry points.

## Current technical notes

### Permissions after reinstall

Reinstalling `muesli-beta.app` currently causes macOS permissions such as
Accessibility, Input Monitoring, and Screen Recording to be requested again.

Current understanding:

- the beta app is being installed with ad hoc signing
- there is currently no stable local signing identity available on this machine
- macOS tracks sensitive permissions against app code identity, not only bundle id
- because the identity changes across rebuilds, those permissions are not retained

Conclusion:

- this is not currently solved in the fork code itself
- the proper fix is to sign the beta app with a stable local Apple development identity
- until then, permission re-granting after reinstall is expected behavior

## Candidate release notes

These are good candidates to eventually promote into beta release notes or a
README "delivered features" section:

- Separate beta app install for safe daily testing
- Better default navigation with `Meetings` as the primary landing area
- Broad Spanish/English localization foundation
- Localized meetings, settings, dictations, and key utility surfaces
- New preset-based theme system with `Calido`, `Neutro`, and `Grafito`
- Improved light-mode visual consistency across the main app window
- Local calendar source controls inside Settings
- Calendar-aware recovery flow to associate notes with nearby invites after recording
- Correct local-time rendering for note timestamps
- Better template control with hideable built-ins and user-targeted `Auto`
- Editable meeting title prompt from the templates manager
- Collapsible `Coming Up` dashboard section
- Optional accent colors for meeting folders
- Persisted calendar event snapshots with attendee context for future meetings
- Meeting detail event card with join link and attendee visibility
- Reliable calendar association when starting from `Coming Up`
- Reliable calendar association when starting from the `Meeting starting now` popup
- Centralized normalization for malformed calendar event ids
- Localized `Notes` / `Notas` section for protected written notes
- Localized meeting notification popups and quick-note / live-notes editing surfaces
- Quick notes can now default to note-only mode with an independent auto-record toggle
- Hardened Slack meeting detection and meeting prompt suppression from newer upstream work
- Temporary 5-event cap in `Coming Up` adopted from upstream as a stepping stone toward future pagination

## Recommended next work

1. Review remaining calendar edge cases around nearby suggestions and any residual non-calendar quick-start paths
2. Decide whether Google Calendar configuration should remain hidden/disabled without credentials or be exposed more explicitly
3. Continue improving summary/title quality now that template and title-prompt controls exist
4. Continue UX polish for meeting detail and in-meeting note handling, especially how aggressively the note window steals focus during live meetings
5. Replace the temporary 5-item `Coming Up` cap with a more intentional pagination or expansion model once the desired browsing behavior is clearer
6. Explore meeting-chat / copilot direction

## Editing note

If wording feels off in Spanish, the intended place to tweak it is:

- `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`

That file is now the main source of truth for the translation layer introduced
in this fork.
