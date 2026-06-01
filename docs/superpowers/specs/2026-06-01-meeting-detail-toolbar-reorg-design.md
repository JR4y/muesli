# Meeting Detail Toolbar Reorganization Design

Date: 2026-06-01
Status: Proposed
Scope: `native/MuesliNative/Sources/MuesliNativeApp/MeetingDetailView.swift`

## Goal

Reorganize the completed meeting detail screen so actions feel integrated with the blocks they act on, instead of being split across unrelated toolbars.

The redesign must:

- keep the current capabilities
- make button placement feel intentional
- improve visual hierarchy
- remain consistent with the recording-related interaction patterns already used in `MeetingsView`
- avoid changing the ergonomics of live and transitional states more than necessary

## Problem Summary

The current completed meeting detail screen spreads actions across multiple areas:

- header actions mix global context, audio actions, and document actions
- content toolbar mixes document actions with audio-related actions
- event snapshot card has its own action pattern, visually separate from the rest

This creates three UX issues:

1. actions compete visually even when they belong to different objects
2. the same row can contain controls for audio, meeting metadata, and document editing
3. the page does not clearly communicate what the user should do first

The transcript visibility bug that was fixed previously made this feel worse, but the structural issue is broader than that bug.

## Design Direction

Adopt an "actions by object" layout for the `completed` state.

Each major block owns the controls that act on it:

- header owns global meeting context
- audio block owns audio-related actions
- event block owns event-related actions
- document toolbar owns notes/transcript and content-editing actions

This matches the mental model already visible in the recording UI, where the active meeting banner in `MeetingsView` groups recording actions around the active meeting state instead of scattering them across the page.

## Screen Structure

### 1. Header

The header should be reduced to global context and low-frequency actions:

- editable title
- date / duration / word count metadata
- folder chip
- status chip
- optional overflow menu for infrequent actions

The header should stop carrying document controls like summarize/template, and should stop carrying audio controls like show recording.

### 2. Audio Block

The saved recording player becomes a true audio action block.

It should contain:

- existing `MeetingRecordingPlayerView`
- `Show recording`
- `Re-transcribe`

These actions should visually sit with the waveform/player instead of appearing in the document toolbar.

### 3. Event Block

The associated event card remains the home for event-specific actions:

- open meeting link
- expand / collapse attendees
- associate or change calendar event when relevant

No document-editing or transcript actions should appear here.

### 4. Document Toolbar

The document toolbar becomes the main working surface for notes/transcript content.

It should contain:

- `Notes / Transcript`
- `Summarize` or `Apply Template`
- `Template`
- `Edit`
- `Copy`

The toolbar should live directly above the document content and act as the user’s main content control strip.

## Hierarchy Rules

### Primary action

Only one action in the document toolbar should feel primary:

- `Summarize` or `Apply Template`

This remains the highest-emphasis CTA because it changes generated content, not just how it is viewed or manipulated.

### Secondary visible actions

These remain visible but visually quieter:

- `Notes / Transcript`
- `Template`
- `Edit`
- `Copy`

They should be easy to discover without competing with the primary summary action.

### Contextual actions

These should be attached to their owning block and not visually promoted outside it:

- `Show recording`
- `Re-transcribe`
- `Open meeting link`
- `Associate event`

### Low-frequency or risky actions

These should move to an overflow menu when the meeting is completed:

- `Delete`
- `Merge`

If `Merge` proves to be highly frequent in practice, it can later be restored as a visible secondary action, but the default design assumes it is lower-frequency than content work.

## State Strategy

This reorganization applies primarily to `MeetingStatus.completed`.

The following states keep their specialized layout patterns:

- `recording`
- `processing`
- `noteOnly`
- `failed`

Reason:

- these states represent a different workflow
- they already rely on state-specific control groupings
- forcing a single universal toolbar would likely reduce clarity

The implementation should still extract shared visual primitives where useful, but should not force completed-state structure onto live-state flows.

## Consistency With Recording Screen

The completed-state redesign should borrow interaction language from the active recording screen in `MeetingsView`.

Patterns to preserve:

- one high-emphasis action per group
- state chip used as contextual information, not a competing CTA
- pause/resume and stop controls read as action cluster tied to recording state
- rounded, compact controls with consistent padding and border treatment

Applied to the completed meeting screen, this means:

- audio actions should sit next to audio context
- the document toolbar should read like the content equivalent of the recording action strip
- the overflow menu should prevent the header from becoming a second command bar

The goal is not to make both screens identical, but to make them clearly part of the same product family.

## Planned Code Changes

The preferred implementation path is compositional, not behavioral.

Reuse existing logic where possible:

- `summaryAction`
- `templateMenu`
- `editButton`
- `retranscribeAction`
- `recordingAction`
- `moreActionsMenu`
- `documentModePicker`

Likely structural changes:

- simplify `headerActions(for:appliedTemplate:)`
- move completed-state audio actions into a new audio action area near `MeetingRecordingPlayerView`
- move completed-state document actions into a dedicated document toolbar
- integrate event-specific actions more explicitly into `eventSnapshotSection(for:)`
- route low-frequency completed-state actions through `moreActionsMenu`

## Proposed Component Boundaries

Within `MeetingDetailView.swift`, introduce clearer completed-state view sections such as:

- `completedHeaderActions`
- `completedAudioSection`
- `completedDocumentToolbar`

Exact names may vary, but the goal is to reduce the current mixing of responsibilities between `headerActions` and `contentToolbar`.

## Non-Goals

This redesign does not aim to:

- redesign recording-state controls from scratch
- change note editor behavior
- change transcript generation logic
- change merge behavior
- introduce new product capabilities

## Risks

### Layout divergence across `ViewThatFits`

The header already had a regression where one branch showed controls and another did not. The new structure must avoid duplicating visibility logic across separate layout branches.

### State-specific regressions

Moving controls may accidentally affect:

- editing states
- transcript-only cases
- raw transcript CTA visibility
- meetings without recording files
- meetings without calendar association

### Over-centralizing the toolbar

If too many actions are retained in the document toolbar, the redesign will still feel crowded. This is why audio actions and low-frequency actions should move out of it.

## Verification Expectations

Implementation should be validated for:

- completed meetings with transcript and notes
- completed meetings with recording file
- completed meetings without recording file
- completed meetings with associated event
- completed meetings without associated event
- note-only meetings
- active recording meetings
- narrow and wide layouts that trigger different `ViewThatFits` branches

## Recommendation

Proceed with the "actions by object" redesign for `MeetingStatus.completed`, while preserving state-specific flows elsewhere and explicitly aligning spacing, emphasis, and grouping with the existing recording UI patterns in `MeetingsView`.
