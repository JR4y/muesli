# Meeting Archive Design

Date: 2026-06-06
Branch: beta
Status: Proposed

## Summary

Muesli needs an Archive area for folders and meetings without treating archived
content as deleted content. Archive should preserve the current folder
structure, sync through the normal Supabase cycle, and remain reversible.

The first implementation should add an `archived_at` field to meetings and
meeting folders locally and remotely. Active views hide rows with `archived_at`
set. The new Archive view shows archived folders and archived standalone
meetings while preserving the same hierarchy that exists in Meetings.

## Decisions

- Model archive as `archived_at`, not `deleted_at`.
- Keep physical deletion and Supabase purge behavior separate from archive.
- Sync archive state through the existing normal sync cycle for folders and
  meetings.
- Archive a folder by marking the folder, every descendant folder, and every
  meeting in that subtree with the same archive timestamp.
- Archive a single meeting by marking only that meeting.
- Restore a folder by clearing `archived_at` for the folder, every descendant
  folder, and every meeting in that subtree.
- Restore a single meeting by clearing only that meeting's `archived_at`.
- Do not restore a single meeting while its parent folder remains archived; the
  user restores the folder subtree first.
- Keep database and Swift model names as Meeting/Folder for this pass.
- Evaluate visible label changes from "Reuniones" to "Notas" after Archive is
  stable.

## Rejected Approaches

### Move rows into a synthetic Archive folder

Rejected because it would destroy or distort the existing folder hierarchy. A
folder moved under an Archive container would lose its original parent context,
and restoring would need extra bookkeeping.

### Duplicate archived rows into separate archive tables

Rejected because it would double the sync surface and complicate restores,
conflict resolution, searches, and chat scope references. Archive is a state of
an existing meeting or folder, not a separate entity.

### Use `deleted_at` for archive

Rejected because deleted rows are already eligible for remote purge. Archive
must be reversible and should not interact with the destructive delete lifecycle.

## Data Model

Local SQLite:

- Add nullable `archived_at TEXT` to `meetings`.
- Add nullable `archived_at TEXT` to `meeting_folders`.
- Add indexes that support active/archive filters:
  - `idx_meetings_archived_at`
  - `idx_meeting_folders_archived_at`

Supabase:

- Add nullable `archived_at timestamptz` to `public.meetings`.
- Add nullable `archived_at timestamptz` to `public.meeting_folders`.
- Add indexes on `(user_id, archived_at)` for both tables.

Swift models:

- Add `archivedAt: String?` to `MeetingRecord`.
- Add `archivedAt: String?` to `MeetingFolder`.
- Keep existing public initializers source-compatible by defaulting
  `archivedAt` to `nil`.

Sync payloads:

- Add `archivedAt` to `RemoteMeetingPayload` and `RemoteFolderPayload`.
- Include `archived_at` in Supabase REST upsert/update bodies.
- Parse `archived_at` from remote rows.
- Include archive state in `SyncPayloadHasher.meetingHash` and
  `SyncPayloadHasher.folderHash`.
- Include archive state in conflict resolution comparisons.

## Archive Semantics

Archive is a visibility state.

Active Meetings view:

- Shows only folders with `archived_at IS NULL`.
- Shows only meetings with `archived_at IS NULL`.
- Counts only active meetings.
- Folder trees are built only from active folders.

Archive view:

- Shows folders with `archived_at IS NOT NULL`.
- Shows meetings with `archived_at IS NOT NULL`.
- Preserves folder hierarchy among archived folders.
- Shows archived standalone meetings that are not inside an archived folder.

Folder archive:

1. User chooses Archive on a folder.
2. Local store resolves the folder's descendant folder IDs recursively.
3. Local store sets the same timestamp on those folder rows.
4. Local store sets the same timestamp on meetings whose `folder_id` is in the
   archived subtree.
5. Existing sync triggers mark changed rows dirty.
6. The normal sync cycle uploads the archive state.

Meeting archive:

1. User chooses Archive on a meeting.
2. Local store sets `archived_at` on that meeting.
3. Existing sync triggers mark the meeting dirty.
4. The normal sync cycle uploads the archive state.

Folder restore:

1. User chooses Restore on an archived folder.
2. Local store clears `archived_at` on the folder subtree.
3. Local store clears `archived_at` on meetings in that subtree.
4. The restored subtree returns to the active Meetings view.

Meeting restore:

1. User chooses Restore on an archived meeting that is not inside an archived
   folder.
2. Local store clears that meeting's `archived_at`.
3. If the meeting's folder is active, the meeting returns to that folder.
4. If the meeting has no folder, the meeting returns to the active unfiled
   list.

Archived meetings inside archived folders are restored through the folder
restore action. This keeps archive visibility consistent and avoids clearing a
meeting's archive state while its containing folder remains hidden from active
views.

## Navigation And UI

Add a top-level sidebar item:

- Label: `Archivo` in Spanish, `Archive` in English.
- Icon: `archivebox`.
- Tab: add `DashboardTab.archive`.

The Archive screen should reuse the Meetings browser structure instead of
introducing a separate visual system. It can share the same list item component
where possible, with these behavioral differences:

- No upcoming calendar section.
- No quick note button.
- No meeting recording import drop target in the first pass.
- No folder chat panel in Archive.
- Meeting rows expose Restore instead of Delete as the primary archive action.
- Meeting rows inside archived folders do not expose single-meeting Restore;
  they are restored with the folder subtree.
- Folder context menus expose Restore.

Active Meetings additions:

- Folder context menu gets Archive.
- Meeting row overflow gets Archive.
- Archive actions should use a confirmation only for folder archive because it
  affects a subtree.

Archive empty state:

- When there are no archived folders or meetings, show a compact empty state
  saying the archive is empty.

## Sync Flow

Archive uses the existing sync order:

1. Folders download/apply.
2. Dictations download/apply.
3. Meetings download/apply.
4. Existing upload flow sends dirty folders and meetings.

No new sync entity type is required. `archived_at` is a normal synced field on
folder and meeting payloads.

Conflict policy remains last-writer-wins:

- If one device archives and another edits the title, the later
  `client_updated_at` wins for the whole row, matching the current sync model.
- If remote and local payload hashes match after including `archived_at`, mark
  the row clean without overwriting.
- A row with `deleted_at` set still behaves as deleted. Delete wins through the
  existing tombstone/delete flow because archive is not a tombstone.

Supabase purge:

- Existing purge continues to remove only rows with `deleted_at IS NOT NULL`.
- Archived rows are not purged.

## Search And Chat

Search remains focused on active content for the first Archive pass. Searching
archived content is out of scope for this implementation.

Meeting Chat should not mount in Archive. Existing archived meeting/folder chat
history remains in the database and stays linked to its scope, but Archive does
not introduce new chat entry points.

## Rename Evaluation: Meetings To Notes

The product concept is closer to notes than meetings because the app manages
notes that may be associated with meetings. The safer path is a later visible
copy pass:

- Rename sidebar labels from Reuniones/Meetings to Notas/Notes.
- Rename user-facing button and empty-state copy where it says meetings but
  refers to note records.
- Keep Swift types, SQLite tables, Supabase tables, and sync entity names as
  `Meeting`/`meetings`.

This avoids a risky model/table rename while improving user clarity. A deeper
technical rename can be considered only after the product language is stable.

## Testing

Add focused tests for:

- SQLite migration adds `archived_at` to meetings and folders.
- Active `recentMeetings` excludes archived meetings.
- Archive queries return archived meetings.
- Folder archive marks descendant folders and meetings with one timestamp.
- Folder restore clears archive state across the subtree.
- Meeting archive and restore affect only the selected meeting.
- Active folder counts ignore archived meetings.
- Archive folder counts include archived subtree meetings.
- REST client includes `archived_at` for meeting and folder upsert/update.
- Remote payload parsing reads `archived_at`.
- Sync hashes change when `archived_at` changes.
- Applying a remote archived folder/meeting updates local archive state.

Run focused store/sync/navigation tests, then the full native test suite before
completion.

## Phases

### Phase 3A: Archive Data And Sync

- Add local and remote schema fields.
- Add store archive/restore APIs.
- Include `archived_at` in sync payloads, hashes, and conflict resolution.
- Add focused store/sync tests.

### Phase 3B: Archive Navigation

- Add `DashboardTab.archive`.
- Add sidebar item.
- Add Archive browser mode using the existing Meetings browser structure.
- Add archive/restore actions and localized copy.
- Add focused navigation/UI logic tests.

### Phase 3C: Notes Label Evaluation

- Change visible copy from Reuniones/Meetings to Notas/Notes for the primary
  sidebar label, browser headers, empty states, and actions that describe the
  records as a collection.
- Keep code and schema names unchanged.
- Add localization tests for key labels.

## Out Of Scope

- Full text search across archived content.
- Permanent delete actions inside Archive.
- Separate Archive Supabase tables.
- Realtime Supabase subscriptions.
- Renaming database tables or Swift model types from Meeting to Note.
- New visual redesign beyond the minimal Archive navigation and actions.
