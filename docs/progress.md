# Progress Log

This document is the cumulative implementation log for this fork.

It is intended to serve three purposes at once:

- keep a running history of product and technical progress
- make it easy to resume work without losing context
- prepare a clean base for future beta release notes and README feature updates

Last updated: `2026-04-29`
Working branch: `beta`
Dev app: `MuesliBeta.app`

## Current state

The fork is now running locally as a separate beta app install and is usable
for daily real-world testing while development continues.

Git workflow currently documented and aligned:

- `upstream` remote points to the author's repository
- `origin` remote points to the fork
- `vendor` is the local clean mirror branch for upstream
- `beta` is the active development branch
- `main` is reserved as the stable product branch

## Incremental history

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
- local beta builds now install as `MuesliBeta.app`
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

#### Validation

- targeted Swift tests were re-run after the refactor and passed
- `MuesliBeta.app` was rebuilt and reinstalled from the current `beta`
- real beta usage confirmed that themed popups now respect app styling
- real beta usage also confirmed a calendar-linked meeting example still associated the expected event context
- real beta usage confirmed orphaned notes can now be linked again through the picker without misleading empty-state flashes
- real beta usage validated the hierarchical folder tree, folder colors/icons, and meetings-list association indicator in the browser flow
- the window/titlebar experiment for replacing the native SwiftUI sidebar toggle was intentionally discarded, and the beta remains on the stable `NavigationSplitView` titlebar behavior
### 2026-04-27 to 2026-04-28

This was the first major fork setup and product-shaping pass.

#### Environment and app setup

- Xcode was installed and activated as the active toolchain
- A separate beta app build was created as `MuesliBeta.app`
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

Reinstalling `MuesliBeta.app` currently causes macOS permissions such as
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

## Recommended next work

1. Review remaining calendar edge cases around nearby suggestions and any residual non-calendar quick-start paths
2. Decide whether Google Calendar configuration should remain hidden/disabled without credentials or be exposed more explicitly
3. Continue improving summary/title quality now that template and title-prompt controls exist
4. Continue UX polish for meeting detail, popup behavior, and in-meeting note handling
5. Explore meeting-chat / copilot direction

## Editing note

If wording feels off in Spanish, the intended place to tweak it is:

- `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`

That file is now the main source of truth for the translation layer introduced
in this fork.
