# Meeting Chat Supabase Sync Design

Date: 2026-06-05
Branch: beta

## Summary

Meeting Chat should sync through Supabase using the same normal sync cycle as
meetings, folders, dictations, and preferences. Chat sync will be a separate
sync subsystem integrated into `SupabaseSyncManager`, rather than forcing chat
threads into the existing `LocalSyncRepository` metadata model. This keeps the
current sync model stable while giving chat the UUID/text identifiers and
message-level behavior it needs.

## Decisions

- Use the existing normal sync cadence, not immediate network sync per message.
- Include existing local chat threads and messages in the first migration
  backfill so current beta data is uploaded on the next sync cycle.
- Treat "Clear chat" as a global synced delete. Clearing a chat on one device
  marks the thread deleted and other devices remove it through sync.
- Sync visible chat data only: thread metadata, visible messages, source
  references, timestamps, and compact memory summaries.
- Do not sync raw provider prompts, full context bundles, hidden model payloads,
  or transient retrieval inputs.

## Remote Schema

Add two Supabase tables with RLS owner policies and the same version/cursor
style used by existing sync tables.

`meeting_chat_threads`:

- `id uuid primary key`
- `user_id uuid not null references auth.users(id)`
- `scope_kind text not null` (`meeting` or `folder`)
- `scope_id uuid not null`
- `title text not null`
- `summary text not null default ''`
- `client_updated_at timestamptz not null`
- `server_updated_at timestamptz not null default now()`
- `remote_version bigint not null default 1`
- `last_writer_device_id text not null`
- `deleted_at timestamptz`

`meeting_chat_messages`:

- `id uuid primary key`
- `user_id uuid not null references auth.users(id)`
- `thread_id uuid not null references meeting_chat_threads(id) on delete cascade`
- `role text not null` (`user`, `assistant`, or `error`)
- `content text not null`
- `sources_json jsonb not null default '[]'::jsonb`
- `created_at timestamptz not null`
- `client_updated_at timestamptz not null`
- `server_updated_at timestamptz not null default now()`
- `remote_version bigint not null default 1`
- `last_writer_device_id text not null`
- `deleted_at timestamptz`

Indexes:

- `(user_id, server_updated_at, id)` for cursor pagination on both tables.
- `(user_id, scope_kind, scope_id)` for resolving a thread by meeting/folder.
- `(user_id, thread_id, created_at)` for message load order.

RLS:

- Enable RLS on both tables.
- Owner-only policy: `user_id = auth.uid()` for select, insert, update, delete.

Versioning:

- Reuse the existing `bump_remote_version` trigger pattern for both tables.

## Local Schema

The existing local tables stay as the user-visible source of truth:

- `meeting_chat_threads`
- `meeting_chat_messages`

Add chat-specific sync metadata instead of adding chat to `SyncEntityType`:

`meeting_chat_sync_metadata`:

- `entity_kind text not null` (`thread` or `message`)
- `local_id text not null`
- `remote_id text`
- `client_updated_at text not null`
- `remote_version integer not null default 0`
- `last_seen_server_updated_at text`
- `last_payload_hash text`
- `dirty integer not null default 1`
- `last_writer_device_id text`
- primary key `(entity_kind, local_id)`
- unique `(entity_kind, remote_id)`

`meeting_chat_sync_tombstones`:

- `entity_kind text not null`
- `local_id text not null`
- `remote_id text`
- `client_deleted_at text not null`
- `last_known_remote_version integer not null default 0`
- `dirty integer not null default 1`
- primary key `(entity_kind, local_id)`

`sync_state` can store two new cursor keys:

- `pull_cursor:meeting_chat_threads`
- `pull_cursor:meeting_chat_messages`

Backfill:

- Migration inserts dirty metadata rows for all existing local chat threads and
  messages that do not already have chat sync metadata.
- Existing local chat data is uploaded on the next normal sync cycle.

## Sync Flow

Download order:

1. Existing folders.
2. Existing preferences.
3. Existing dictations.
4. Existing meetings.
5. Chat threads.
6. Chat messages.

Upload order:

1. Existing folders.
2. Existing dictations.
3. Existing meetings.
4. Chat threads.
5. Chat messages.
6. Existing preferences.
7. Existing tombstones.
8. Chat message tombstones.
9. Chat thread tombstones.

Rationale:

- Chat threads need meeting/folder remote IDs before upload.
- Chat messages need thread remote IDs before upload.
- Remote chat downloads need meetings/folders applied first so `scope_id` can
  resolve back to local `MeetingChatScope`.

Conflict policy:

- Threads use whole-row last-writer-wins based on `client_updated_at`, then
  `last_writer_device_id`.
- Messages are append-oriented. If the same message ID conflicts, use
  last-writer-wins for that message row.
- Clearing a thread wins as a delete if its `deleted_at` is newer than the
  competing update.

## Clear Chat Behavior

Current local clear deletes the visible thread. Fase 2 changes that into a
synced delete:

1. User chooses "Clear chat" in a meeting or folder.
2. Local store deletes the thread and messages and writes chat tombstones.
3. Normal sync uploads `deleted_at` for the remote thread.
4. Other devices receive the deleted thread and remove the local thread.

Messages under a deleted thread do not need individual remote deletes if the
remote thread is deleted and the table uses cascade. Local tombstones may still
track message cleanup when needed, but thread deletion is the primary operation.

## Privacy

Synced chat data contains user-visible conversation content. It can include
private notes or meeting details if the user typed them or if the assistant
answered with them. The app should not sync hidden prompt/context payloads or
raw transcript chunks merely because they were used to answer.

The feature follows the existing Supabase security model: RLS keeps rows scoped
to the authenticated user, but data is not end-to-end encrypted.

## UI Impact

No major UI redesign is required in Fase 2.

- Existing chat panels keep the same shape.
- "Clear chat" should continue to exist, but its confirmation/copy should make
  clear that clearing syncs across devices.
- Sync status can remain in the existing Sync settings section; no separate
  chat sync control is required for the first version.

## Testing

Add focused tests for:

- local migration creates chat sync metadata for existing threads/messages
- REST client encodes thread/message upsert, update, page select, and delete
- sync manager uploads a local existing chat after backfill
- sync manager downloads remote thread/message into local SQLite
- clear chat creates a synced tombstone and removes the chat on another local
  fixture after applying remote delete
- chat sync waits for scope remote IDs when a meeting/folder is not synced yet
- messages preserve ordering by `created_at`

Run the focused chat/sync tests and the full native suite before completion.

## Out Of Scope

- Realtime Supabase subscriptions.
- Semantic retrieval, embeddings, or project memory improvements.
- Syncing full provider prompts or raw context bundles.
- Multi-user shared workspaces.
- Renaming Reuniones to Notas.
