# Progress Log

This document is the cumulative implementation log for this fork.

It is intended to serve three purposes at once:

- keep a running history of product and technical progress
- make it easy to resume work without losing context
- prepare a clean base for future beta release notes and README feature updates

Last updated: `2026-04-28`
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

## Recommended next work

1. Review why nearby calendar suggestions can appear intermittently and stabilize that query/state flow
2. Decide whether Google Calendar configuration should remain hidden/disabled without credentials or be exposed more explicitly
3. Continue improving summary/title quality now that template and title-prompt controls exist
4. Explore meeting-chat / copilot direction
5. Continue UX polish through daily real usage, especially `Coming Up` pagination/capping

## Editing note

If wording feels off in Spanish, the intended place to tweak it is:

- `native/MuesliNative/Sources/MuesliNativeApp/L10n.swift`

That file is now the main source of truth for the translation layer introduced
in this fork.
