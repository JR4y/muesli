# Settings Reorganization Design

Date: 2026-06-05
Status: Proposed
Scope:
- `native/MuesliNative/Sources/MuesliNativeApp/AppState.swift`
- `native/MuesliNative/Sources/MuesliNativeApp/SettingsView.swift`
- `native/MuesliNative/Sources/MuesliNativeApp/DictionaryView.swift`
- `native/MuesliNative/Sources/MuesliNativeApp/ShortcutsView.swift`
- `native/MuesliNative/Sources/MuesliNativeApp/Sync/SyncSettingsView.swift`
- localization updates in `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`

## Goal

Reduce the settings surface from many narrow tabs into fewer, clearer areas while keeping every existing control available.

The redesign should:

- reduce the current 9 settings panes to 5 primary panes
- merge related dictation and dictionary controls
- fold shortcuts, sync, and Computer Use into a broader general area
- keep meetings, models, and appearance visible as substantial standalone areas
- make settings rows, sections, headers, and controls feel visually consistent
- avoid broad behavioral changes during the reorganization pass

## Problem Summary

Settings currently has 9 horizontal panes:

- General
- Dictation
- Computer Use
- Meetings
- Appearance
- Dictionary
- Models
- Shortcuts
- Sync

This creates three UX issues.

First, some panes are conceptually dependent on another pane. Dictionary belongs to dictation quality, shortcuts belong to app operation, sync belongs to account/app state, and Computer Use currently overlaps with shortcuts and account/model configuration.

Second, the horizontal pane picker is crowded. The user has to scan many peer-level choices even though not all of them have the same product weight.

Third, several panes use different visual structures. `DictionaryView`, `ShortcutsView`, and `SyncSettingsView` have their own headers and card patterns, while most settings panes use `SettingsView` helpers. This makes the settings area feel assembled from separate screens rather than one coherent control surface.

## Key Design Decision

Adopt a moderate 5-pane structure:

1. General
2. Voice & Dictation
3. Meetings
4. Models
5. Appearance

This keeps high-weight areas visible while removing low-value top-level fragmentation.

The design intentionally does not collapse everything into 3 or 4 panes. Models and Appearance should remain top-level because they are distinct, recognizable surfaces and are likely to be revisited directly by users.

## Rejected Approaches

### 1. Keep the current 9-pane structure

Rejected because it preserves the current scanning cost and leaves small, related panes disconnected.

### 2. Collapse into 3 panes

Rejected because it would make the top-level navigation cleaner at the cost of burying Models, Appearance, and several meeting controls behind extra internal navigation.

### 3. Move Computer Use into Voice & Dictation

Rejected for the first implementation because Computer Use is more than dictation. It uses a spoken command input, but its configuration also includes planner enablement, account state, model selection, timeout, and shortcuts. It fits better in General as an app capability until it grows enough to justify a dedicated advanced area.

## Proposed Information Architecture

### General

General becomes the home for app-wide behavior, account-like setup, permissions, and command shortcuts.

Sections:

- Application
  - language
  - launch at login
  - open dashboard on launch
- Shortcuts
  - dictation push-to-talk
  - Computer Use command shortcut
  - meeting recording shortcut
  - hands-free double-tap mode
  - reset shortcut defaults
- Sync
  - Supabase account/sign-in state
  - sync status and last sync
  - synced item counts
  - manual sync action
- Privacy & Permissions
  - microphone
  - accessibility
  - input monitoring
  - screen recording
  - system audio when relevant
- Data
  - clear dictation history
  - clear meeting history
- Computer Use
  - enable planner
  - ChatGPT account
  - planner model
  - timeout

Shortcuts should be presented as compact settings sections rather than the current separate full page. Computer Use can sit after shortcuts or near sync/account controls; the preferred first pass is after Sync so account/model state is nearby.

### Voice & Dictation

Voice & Dictation combines dictation engine configuration with transcription-improvement tools.

Sections:

- Transcription
  - dictation model
  - Cohere language when Cohere is selected
- AI Cleanup
  - enable transcript cleanup
  - cleanup model
  - missing model hint when enabled without a downloaded cleanup model
- Dictionary
  - custom word list
  - add custom word
  - replacement text
  - matching threshold
- Advanced
  - pause media during dictation
  - mute system audio during dictation
  - app/screen context control

Dictionary should no longer have a top-level settings pane. It should be embedded as a section in this pane, using the same section chrome as the rest of settings while preserving its table-like editing ergonomics.

Implementation note: the current dictation pane appears to render `screenContextRow` twice in Advanced. The implementation pass should verify whether that duplication is intentional. If it is accidental, keep a single app context row.

### Meetings

Meetings remains top-level because it is a broad workflow with transcription, summaries, recording behavior, notifications, calendars, and automation.

Sections:

- Transcription
  - meeting transcription model
  - Cohere language when Cohere is selected
  - live meeting transcript
  - meeting context
- Summaries
  - summary backend
  - backend-specific credentials/model settings
  - default template
  - manage templates
- Recording
  - auto-record calendar meetings
  - auto-record quick notes
  - recording save policy
- Notifications
  - scheduled meeting notifications
  - auto-detected meeting notifications
  - muted detection apps when enabled
- Calendars
  - Google Calendar connection
  - calendar source controls
- Advanced
  - post-meeting hook toggle
  - hook script
  - timeout

This is mostly a re-labeling and polish pass for Meetings rather than a large structural move.

### Models

Models remains top-level.

It should keep the existing `ModelsView` behavior for the initial implementation. A later pass can reorganize models by usage:

- dictation
- cleanup
- meeting transcription
- summaries/planner where applicable

This spec does not require that later grouping.

### Appearance

Appearance remains top-level.

Sections:

- Floating Indicator
  - show indicator
  - indicator position
- Theme & Interface
  - theme preset
  - dark mode
  - menu bar icon
  - accent color
  - sound effects
  - show next meeting in menu bar
- Optional unlocked extras
  - meeting countdown audio
  - reset/unlock-specific actions

No major behavior change is required here.

## Navigation Design

Keep the primary settings navigation as a horizontal segmented row for this pass, but reduce it to 5 items:

- General
- Voice & Dictation
- Meetings
- Models
- Appearance

This preserves the current interaction model and avoids introducing a new sidebar or nested navigation system. The reduction from 9 to 5 panes should be enough to remove the current crowding.

Within a pane, use section headers and consistent row composition rather than secondary tabs.

## Visual Design

The settings area should feel like one coherent control surface.

Recommended visual changes:

- one shared pane header pattern, owned by `SettingsView`
- one shared section container style
- settings rows with optional descriptions for controls that need context
- aligned right-side control columns where possible
- compact inline controls for actions like shortcut changes, sign-in, sync now, and add dictionary word
- no nested cards inside section cards

Dictionary and sync can keep richer internal layouts where needed, but they should be wrapped in the same section rhythm as the rest of settings.

## Component Strategy

Prefer extracting reusable settings primitives before moving large blocks of UI.

Potential primitives:

- `settingsPaneHeader(title:subtitle:)`
- `settingsSection(title:content:)`
- `settingsRow(label:description:control:)`
- a compact shortcut editor row reused for dictation, Computer Use, and meeting recording
- an embeddable dictionary editor section without its own page header
- an embeddable sync account/status section without its own page header

The first implementation should avoid a full design-system rewrite. The goal is to reuse and regularize the existing `SettingsView` helpers, then adapt `DictionaryView`, `ShortcutsView`, and `SyncSettingsView` so they can render as embedded sections.

## State And Routing

Replace the old `SettingsPane` cases:

- remove `computerUse`
- remove `dictionary`
- remove `shortcuts`
- remove `sync`
- replace `dictation` with `voiceAndDictation`

Final cases:

- `general`
- `voiceAndDictation`
- `meetings`
- `models`
- `appearance`

Any code that programmatically routes to a removed pane should be mapped to the closest new pane:

- dictionary routes -> `voiceAndDictation`
- shortcuts routes -> `general`
- sync routes -> `general`
- Computer Use routes -> `general`
- dictation routes -> `voiceAndDictation`

Existing persisted or default `selectedSettingsPane` behavior should remain safe if old raw values are encountered. Since `selectedSettingsPane` currently lives in memory on `AppState`, this is mostly a compile-time routing cleanup unless additional persistence is introduced elsewhere.

## Localization

Add or update localized strings for:

- `Voice & Dictation` / `Voz y dictado`
- `Application` / `Aplicacion`
- `Shortcuts` / `Atajos`
- `Sync` / `Sincronizacion`
- `Privacy & Permissions` / `Privacidad y permisos`
- `AI Cleanup` / `Limpieza con IA`

Existing strings should be reused where they already match.

The current codebase has several hard-coded English settings labels. This reorganization does not require full localization cleanup, but any moved or newly introduced section labels should use `L10n` when practical.

## Testing And Verification

Focused verification should cover:

- `SettingsPane.allCases` contains exactly the 5 intended panes in the intended order
- each pane title resolves in English and Spanish
- removed pane routes no longer appear in the picker
- controls moved into General still mutate the same `AppConfig` fields
- dictionary add/edit/remove behavior still works when embedded
- shortcut recording still stops on pane exit or disappearance
- sync sign-in/sign-out/sync-now controls still work when embedded
- Settings compiles without duplicate or unreachable switch cases

Suggested test scope:

- update any existing unit tests that reference `SettingsPane`
- add lightweight tests if there are pure helpers for pane titles or route mapping
- run the native Swift test target if the implementation touches state routing or helper logic

## Implementation Notes

Implementation should be incremental:

1. Add the new 5-pane enum shape and route old content into the new panes.
2. Move General-adjacent controls into the new General pane.
3. Embed Dictionary inside Voice & Dictation.
4. Convert Shortcuts and Sync from standalone pages into reusable embedded sections.
5. Polish visual consistency after all controls are reachable.

At every step, keep behavior stable and avoid changing config semantics.

