# Backlog

This backlog tracks product and UX changes for this fork.

Branch model reference:

- `vendor`: clean mirror of the author's upstream
- `beta-mergework`: temporary upstream mergework branch / worktable
- `beta`: active development and integration
- `main`: stable product branch

## Current goals

- Improve navigation and overall UX
- Add bilingual support (`es` and `en`)
- Reduce English-only hardcoded copy in the UI
- Improve the summary experience and output quality
- Keep changes as upstream-friendly as possible

## Progress snapshot

Completed or largely completed:

- Separate beta app install (`muesli-beta.app`) for safe daily testing
- Warm beige light theme baseline
- `Meetings` promoted above `Dictations`
- `Meetings` made the default landing view
- Localization foundation via `L10n.swift`
- Language preference stored in app config
- Sidebar localization
- Major meetings localization pass
- Major settings localization pass
- Dictations localization pass
- Built-in summary templates can now be hidden
- Custom summary templates now appear before built-ins
- `Auto` template can now target the user's chosen default template
- `Coming Up` now supports collapse/expand
- Meeting folders now support nested hierarchy, curated accent colors/icons, and clearer note association visibility
- Meeting title prompt is now editable from `Manage Templates`
- Future meetings now persist associated calendar event snapshots
- Event snapshots now include attendee data and are shown in meeting detail
- The associated event block in meeting detail now supports collapse/expand for dense attendee lists
- `Coming Up` join-and-record now associates the selected calendar event immediately
- Manual written notes now render as a localized top-level `Notes` / `Notas` section
- Calendar popup flows now normalize malformed event ids and repair reuse paths instead of duplicating meetings
- `Dictionary`, `Models`, and `Shortcuts` now live inside `Settings` instead of cluttering the top-level sidebar
- Meeting notification popups now follow the app theme instead of staying visually detached in a fixed dark style
- The meetings browser header is cleaner, redundant folder summary chrome is removed, and folder editing now hangs off the folder icon beside the title
- The meetings browser and meeting detail header both use cleaner folder/calendar metadata pills, and the detail header now exposes folder reassignment directly from the folder pill
- Persistent active-row shading in the meetings browser was removed after validation because it made old selections feel visually stuck
- Meeting notification popups now localize their visible titles, timing labels, and actions
- The quick-note / live-notes surface now localizes placeholder copy, save state, editor helpers, and recording actions
- Quick notes now default to note-only mode, with an independent `Auto-record Quick Notes` setting and the ability to start recording later from the same note
- The dashboard `Quick Note` button now follows the configured app language
- The main window now uses an app-owned split shell plus real AppKit titlebar accessories, so the sidebar toggle is no longer duplicated and the quick-note action stays anchored in the native titlebar
- Manual-note editor toolbar commands were stabilized so formatting actions work reliably after button clicks
- Upstream Slack meeting detection hardening and stronger meeting-prompt suppression are now integrated into `beta`
- `Coming Up` now caps visible upcoming meetings to 5 for the moment, pending a more intentional pagination/expansion design
- Multi-Mac sync via Supabase (project `molli`, `eu-west-1`), scoped to `muesli-beta.app`. New tables, triggers, and tombstones live in `MuesliCore/Sync/`; auth, REST client, and orchestrator live in `MuesliNativeApp/Sync/`. Configured per build via `config/Supabase.xcconfig` (gitignored, with committed `.example` template). Settings → Sync pane handles signup, signin, manual sync, and surfaces status. Same-day beta fixes covered first-sync metadata backfill for existing local data, PostgREST cursor timestamp normalization, and safe parent-before-child upload ordering for nested folders. See `docs/progress.md` 2026-05-04 entry for the implementation map and `docs/plans/2026-05-04-supabase-sync-corrected-plan.md` for the design rationale.
- Live meeting transcript is now isolated behind a real `Settings → Meetings → Live transcript` toggle instead of being an always-on behavior
- Meeting detail now renders the final transcript as a chat-style conversation while keeping `rawTranscript` as the storage/export source of truth
- Meeting detail now keeps notes/transcript visibility consistent, uses a cleaner action hierarchy in completed meetings, and defaults the associated event block to a denser collapsed presentation
- Supabase beta builds now fail fast if local config is missing, and the sync UI keeps the last-used email available locally without storing the password

Known limitation:

- macOS permissions are currently re-requested after beta reinstalls because the
  app is being rebuilt without a stable local signing identity
- AppKit titlebar accessories on the left/right edges remain vertically
  constrained by the native titlebar lane, so the quick-note control there
  should stay compact rather than relying on extra vertical padding

## Principles

- Prefer incremental UI improvements over full screen rewrites
- Isolate fork-specific behavior where possible
- Resolve integration issues in `beta`
- Avoid large structural divergence unless the existing UX proves too rigid

## Now

### 1. Localization foundation

Goal:
prepare the app for `es` and `en` without rewriting everything at once.

Tasks:

- Introduce a localization strategy for UI copy
- Replace hardcoded labels in primary navigation areas first
- Decide how language selection should be stored in user settings
- Keep the first rollout focused on app chrome, not every screen at once

Notes:

- The current app appears to rely heavily on hardcoded strings
- A localization layer should come before a full custom personalization screen

### 2. Navigation and information architecture

Goal:
make the app easier to understand and more comfortable to use daily.

Tasks:

- Review sidebar structure and section order
- Revisit labels for tabs, sections, and actions
- Simplify button hierarchy and clarify primary actions
- Identify friction in search, meetings, settings, and shortcuts navigation

Pain points observed so far:

- Navigation does not feel natural
- Button order and action priority need review
- Several labels and sections feel too English-centric

### 3. Residual copy cleanup

Goal:
finish the smaller hardcoded copy gaps that remain outside the main meetings flow.

Tasks:

- Sweep lower-priority hardcoded strings that still appear in alerts, onboarding, install/update, or failure states
- Review whether any beta-only helper text still sounds too English-centric in real usage
- Keep the localization pass incremental instead of reopening the main navigation/settings work

Notes:

- Meeting notification popups and the quick-note / live-notes surface are now localized
- Remaining work here should stay small and opportunistic rather than becoming a redesign stream

### 4. Summary experience

Goal:
make summaries feel more useful, more consistent, and less tied to English defaults.

Tasks:

- Audit summary prompts, section titles, and generated structure
- Identify hardcoded English headings and template text
- Define preferred output style for Spanish usage
- Separate "system summary behavior" from "user customization"
- Review exactly how meeting summaries are built and sent to ChatGPT/OpenAI
- Remove or replace hardcoded section titles that are being injected into generated summaries

## Next

Implemented so far in the summary/template area:

- built-in templates can be hidden instead of always appearing in the picker
- custom templates can be promoted as default and drive `Auto`
- the editable meeting-title prompt now lives in `Manage Templates` as a separate system prompt

Still open in this area:

- improve title-language behavior so Spanish transcripts produce Spanish titles more reliably
- keep reviewing hardcoded English defaults in the title-generation and summary base prompts
- continue refining how manual notes and generated sections blend when the model does not integrate user-written notes naturally
- improve title generation so the current meeting title is treated as first-class context and can be preserved when the model judges it already appropriate

### 5. UX polish pass

Goal:
improve the day-to-day feel once structure and language are clearer.

Possible scope:

- Empty states
- Copy tone
- Visual emphasis of primary actions
- Consistency across onboarding, settings, and meetings
- Further improve the `Coming Up` dashboard block

Notes:

- first ergonomic pass can stay small: keep the new collapse/expand behavior
- `Coming Up` is now temporarily capped at 5 visible upcoming meetings
- next likely step: replace that temporary cap with pagination or a clearer expand/load-more model so the meetings browser stays visible without excessive scrolling
- also worth exploring later: a direct shortcut from `Coming Up` into the relevant calendar area instead of only sync guidance
- folders are now hierarchical and visually identifiable, but they are still single-assignment folders rather than multi-tag classification
- meetings list now shows a subtle indicator when a note already has an associated calendar event
- in-meeting note capture could use a more discreet mode so starting a meeting does not always force the note window open in front of the user
- the meeting detail action area is cleaner than before, but it should still be watched in real usage to confirm the final control grouping feels stable
- the new titlebar shell solved duplication and position drift, but the quick-note control should still be watched in real usage to confirm `+ Nota` is the right balance between clarity and compactness
- transcript viewing is now visually stronger thanks to the shared chat-style transcript UI, so the next UX work should focus more on live quality and interaction behavior than on transcript styling basics

### 5b. Shortcut system consolidation

Goal:
reduce overlap between the fork's existing shortcut surfaces and the newer
upstream shortcut/computer-use layers without regressing the workflows that
already feel stable in `beta`.

Possible scope:

- map the current shortcut stack end to end: top app menu, status bar/menu bar
  actions, dictation hotkey, computer-use hotkey, and text-edit shortcuts
- confirm which parts are truly duplicated versus intentionally complementary
- decide whether any setup in `AppDelegate` / `StandardMainMenu` should be
  collapsed into one source of truth
- review whether the `Computer Use` shortcut should stay enabled by default in
  the fork or ship as a secondary opt-in capability
- finish localizing the remaining `Computer Use` strings in `Shortcuts` once
  the behavior is considered stable

Notes:

- the current merge keeps the fork's existing shortcut UX and adds the
  upstream `Computer Use` shortcut as a second lane
- the author also hardened text-edit shortcut handling in the hotkey monitor,
  which is useful and should be preserved
- there is still conceptual overlap between "shortcut configuration",
  "standard macOS edit commands", and "global hotkey capture" that should be
  cleaned up deliberately instead of growing by accident

### 5c. Google Calendar auth cleanup

Goal:
keep the now-working Google Calendar path reliable and easier to debug without
reopening the broader calendar UX stream.

Possible scope:

- make the Google OAuth callback success page less optimistic so it does not
  imply the flow is fully complete before token exchange and first API load
  finish
- review whether Google auth/token failures should surface more explicit UI
  causes instead of generic request text
- clean up the remaining Swift concurrency warnings in
  `GoogleCalendarAuthManager`
- consider whether the local Google setup should eventually move into a more
  intentional contributor/developer config pattern alongside other local
  secrets

Notes:

- the fork now has a working local Google Calendar path via
  `config/google-oauth.json`
- the biggest functional blockers were fixed:
  wrong sign-out behavior on `403` and missing `calendarList` scope
- what remains is mostly auth-flow polish and technical debt, not a known
  product blocker

### 6. In-meeting note handling

Goal:
make note capture during a live meeting feel quieter and less intrusive.

Possible scope:

- consider not opening the full note automatically when a meeting recording starts
- rely on the smaller floating indicator as the primary in-meeting control surface
- add a subtle affordance to expand/open the note only when the user actually needs it
- preserve easy access to manual notes without forcing the main note window into focus

Notes:

- current behavior feels more disruptive than tools like Granola during live meetings
- this should be treated as a UX behavior change, not only a visual tweak
- quick notes now support note-only start with an independent auto-record toggle, so the remaining problem is intrusiveness rather than missing control
- the in-meeting notes window likely needs a broader UX pass beyond localization alone; it still feels like a rough utility surface rather than a polished live-meeting note mode
- the new live-transcript toggle gives a practical daily-use escape hatch, but the live transcript still needs quality work to justify leaving it on all the time

### 6b. Live transcript quality

Goal:
improve live transcript usefulness without regressing the already-working final transcript pipeline.

Possible scope:

- revisit how the 60-second VAD safety cap shapes long live bubbles
- explore whether a short-window reconciliation step could improve `You` / `Others` grouping during live capture
- continue refining source/time grouping now that the live lane is isolated from the final lane

Notes:

- the final transcript should remain canonical and post-processed
- live transcript should keep behaving as a provisional presentation layer, not a source of truth

### 7. Meeting copilot chat

Goal:
add a chat experience inside meeting notes so the user can ask questions about a meeting and iterate on outputs with an LLM.

Possible scope:

- Chat panel attached to meeting notes or transcript
- Questions over transcript, notes, and meeting context
- Quick transforms such as rewrite, summarize, extract action items, or draft follow-ups
- Clear separation between stored notes and chat-generated temporary answers

Notes:

- This should feel like a meeting copilot, not just a raw API textbox
- It will likely depend on the same provider strategy already used for summaries

### 8. Visual direction and color system

Goal:
make the interface feel more intentional and more aligned with the preferred product identity.

Possible scope:

- Revisit accent colors and semantic colors
- Reduce default look-and-feel that does not match the desired UX direction
- Improve contrast and emphasis for important actions
- Bring better consistency across sidebar, settings, meetings, and onboarding
- bring popup/notification surfaces into the same theme language as the rest of the app

## Later

### 9. Slash actions in meeting notes/chat

Goal:
trigger useful meeting actions with `/` commands from a notes or chat experience.

Possible scope:

- `/summary`
- `/action-items`
- `/follow-up`
- `/rewrite`
- `/translate`

Notes:

- This should come after the basic meeting chat exists
- It should be fast, discoverable, and aligned with the final summary workflow

### 10. Deeper custom screens

Only consider larger custom screens if:

- incremental improvements are not enough, or
- upstream structure blocks the UX direction we want

Until then, prefer targeted modifications over full replacements.

## Open questions

- Should language selection follow system language by default?
- Should summaries have separate templates for Spanish and English?
- Should the meeting title prompt eventually move to a dedicated prompts surface if more system prompts appear?
- Which screen is the best first target for visible UX improvement: sidebar, settings, or meeting detail?
- Should meeting chat live inside the note editor, beside the transcript, or as a collapsible side panel?
- Should slash actions modify saved notes directly, create suggestions, or require explicit apply/accept?
