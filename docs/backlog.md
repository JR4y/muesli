# Backlog

This backlog tracks product and UX changes for this fork.

Branch model reference:

- `vendor`: clean mirror of the author's upstream
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

- Separate beta app install (`MuesliBeta.app`) for safe daily testing
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
- Meeting folders now support accent colors and clearer note association visibility
- Meeting title prompt is now editable from `Manage Templates`
- Future meetings now persist associated calendar event snapshots
- Event snapshots now include attendee data and are shown in meeting detail
- `Coming Up` join-and-record now associates the selected calendar event immediately
- Manual written notes now render as a localized top-level `Notes` / `Notas` section
- Calendar popup flows now normalize malformed event ids and repair reuse paths instead of duplicating meetings

Known limitation:

- macOS permissions are currently re-requested after beta reinstalls because the
  app is being rebuilt without a stable local signing identity

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

### 3. Summary experience

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

### 4. Calendar behavior and source control

Goal:
make calendar-driven meeting behavior feel trustworthy, predictable, and aligned
with what the user actually sees in macOS Calendar.

Possible scope:

- review how local EventKit calendars are selected today
- avoid duplicate upcoming meetings when the same event appears in multiple synced calendars
- investigate whether event collection should respect the calendars the user has visible/enabled in Calendar
- verify how "visible" calendars in the macOS Calendar app map to what EventKit exposes, and decide whether app-side filtering is needed
- define a clearer source strategy for:
  - local EventKit calendars
  - optional Google OAuth calendars
- consider showing calendar source identity and color in upcoming meetings and related UI
- preserve or surface per-calendar colors where they help users understand which event source won or was deduplicated
- decide whether users should be able to include/exclude specific calendars inside app settings
- persist a useful snapshot of the associated calendar event inside the saved meeting record instead of relying only on `calendarEventID`
- review whether additional attendee/invitee details should be expanded beyond the current stored snapshot

Notes:

- current behavior appears broad enough to surface duplicate events in some calendar setups
- observed in real usage: the same meeting can appear repeated when it exists in two local calendars, even if only one seems visible in Calendar
- first pass implemented: users can now enable/disable local calendars explicitly from Settings instead of relying on inferred visibility
- second pass implemented: `Coming Up` already shows clearer calendar color/source cues, and notes can now be associated manually with nearby calendar events
- third pass implemented: future meetings now persist a rich event snapshot, store attendee data, and surface that context in meeting detail
- still open: nearby event suggestions have shown intermittent behavior and need stabilization before we can consider this area fully trustworthy
- this area is product-significant because it affects prompts, auto-recording, and note creation
- current limitation: older existing meetings were intentionally not backfilled with historical event snapshots
- this means historical traceability is now strong for future meetings, but older notes still depend on what was already stored at the time
- next review in this area should focus on suggestion stability, duplicate handling, and any extra attendee metadata worth surfacing

Implemented so far in the summary/template area:

- built-in templates can be hidden instead of always appearing in the picker
- custom templates can be promoted as default and drive `Auto`
- the editable meeting-title prompt now lives in `Manage Templates` as a separate system prompt

Still open in this area:

- improve title-language behavior so Spanish transcripts produce Spanish titles more reliably
- keep reviewing hardcoded English defaults in the title-generation and summary base prompts
- continue refining how manual notes and generated sections blend when the model does not integrate user-written notes naturally
- improve title generation so the current meeting title is treated as first-class context and can be preserved when the model judges it already appropriate

### 5. Personalization screen

Goal:
add a fork-specific settings area for user-facing customization.

Possible scope:

- Language selection (`es` / `en`)
- Summary style preferences
- Terminology overrides
- User-facing naming preferences

Important note:

- This screen should complement localization, not replace it

### 6. UX polish pass

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
- next likely step: paginate or cap long `Coming Up` lists so the meetings browser stays visible without excessive scrolling
- also worth exploring later: a direct shortcut from `Coming Up` into the relevant calendar area instead of only sync guidance
- folders now have a useful low-impact color accent system, but they are still single-assignment folders rather than tags or nested structures
- notification popups still need to be visually aligned with the active app theme; they currently remain dark even in lighter themes
- in-meeting note capture could use a more discreet mode so starting a meeting does not always force the note window open in front of the user
- the meeting detail action area still has too many buttons and needs a clearer grouping / hierarchy
- the associated calendar event block in meeting detail still needs layout polish because its position shifts too much as the note window width changes

### 7. In-meeting note handling

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

### 8. Meeting copilot chat

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

### 9. Visual direction and color system

Goal:
make the interface feel more intentional and more aligned with the preferred product identity.

Possible scope:

- Revisit accent colors and semantic colors
- Reduce default look-and-feel that does not match the desired UX direction
- Improve contrast and emphasis for important actions
- Bring better consistency across sidebar, settings, meetings, and onboarding
- bring popup/notification surfaces into the same theme language as the rest of the app

## Later

### 10. Slash actions in meeting notes/chat

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

### 11. Deeper custom screens

Only consider larger custom screens if:

- incremental improvements are not enough, or
- upstream structure blocks the UX direction we want

Until then, prefer targeted modifications over full replacements.

## Open questions

- Should language selection follow system language by default?
- Should summaries have separate templates for Spanish and English?
- Should personalized terminology live in settings, templates, or both?
- Should the meeting title prompt eventually move to a dedicated prompts surface if more system prompts appear?
- Which screen is the best first target for visible UX improvement: sidebar, settings, or meeting detail?
- Should meeting chat live inside the note editor, beside the transcript, or as a collapsible side panel?
- Should slash actions modify saved notes directly, create suggestions, or require explicit apply/accept?
