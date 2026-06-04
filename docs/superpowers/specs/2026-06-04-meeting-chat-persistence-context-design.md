# Meeting Chat Persistence and Context Design

## Purpose

Muesli Meeting Chat should feel continuous across navigation while keeping provider calls predictable and reasonably small. The first persistence upgrade stores chat history locally, then uses a deterministic context policy to decide what text is sent to the LLM on each turn.

The design keeps the feature read-only and modular. Chat persistence and context orchestration stay inside `MuesliMeetingChat` plus thin app adapters under `MeetingChatIntegration`.

## Goals

- Persist temporary chat history locally per meeting or folder.
- Restore chat history when returning to a meeting or selected folder.
- Avoid sending full transcripts or full folder histories by default.
- Keep LLM requests stateless from the provider's point of view unless a future provider explicitly supports durable conversations.
- Make context behavior explainable and testable.

## Non-Goals

- No remote ChatGPT conversation persistence.
- No write actions, task creation, note editing, or meeting movement.
- No Supabase sync for chat history in this iteration.
- No embeddings or vector search in this iteration.
- No global all-meetings chat.

## Storage Model

Add local-only chat persistence in SQLite through an app-side storage adapter. The module-facing API should hide SQLite details behind a protocol.

Conceptual records:

- `MeetingChatThread`
  - `id`
  - `scopeKind`: `meeting` or `folder`
  - `scopeID`
  - `title`
  - `createdAt`
  - `updatedAt`
  - `summary`
- `MeetingChatStoredMessage`
  - `id`
  - `threadID`
  - `role`: `user`, `assistant`, or `error`
  - `content`
  - `createdAt`
  - `sourceReferences`

The thread `summary` is a local memory summary of older chat turns. It is not the meeting summary and should not mutate meeting data.

## Context Policy

Each user prompt builds a fresh request using four layers:

1. Stable system instructions.
2. Scope context from meetings and folders.
3. Local chat memory.
4. The current user question.

Meeting context:

- Always include meeting title, date, formatted notes, and manual notes when available.
- Include transcript only when notes are missing or when the user question asks for detail, quotes, who said something, objections, exact wording, or transcript-specific lookup.
- Cap transcript text deterministically.

Folder context:

- Include folder name and descendant folder names.
- Include recent non-merged meetings in the folder tree.
- Prefer formatted notes and manual notes.
- Do not include transcripts by default.
- If transcript demand is detected, pick candidate meetings first and include only bounded transcript excerpts for those candidates.

Chat memory:

- Always include the last N persisted messages, with N initially between 6 and 10.
- If the thread has more history than the recent window, include the local `thread.summary`.
- Do not send the full persisted chat history by default.

## Transcript Demand

Transcript demand is decided locally before the provider call. It can be triggered by:

- Explicit user wording such as "transcript", "transcripcion", "cita", "exactamente", "quien dijo", "que dijo", "mencionaron", "objecion", or "detalle".
- Missing formatted notes/manual notes for a single meeting.
- Future fallback behavior where the assistant requests more evidence, handled as a second call only after v1.

For folder chat, transcript demand never means "send all transcripts". It means "narrow down candidate meetings, then send bounded excerpts".

## Provider Behavior

Provider calls remain stateless:

- Muesli sends the selected context and recent memory with every turn.
- Muesli does not depend on ChatGPT remembering a remote conversation.
- ChatGPT internal WHAM calls should continue using `store: false`.
- Official OpenAI Responses calls should also set `store: false` for consistency.

This keeps local persistence independent from provider state. It also makes it easier to switch between ChatGPT OAuth, OpenAI API, OpenRouter, Ollama, LM Studio, or custom providers.

## UI Behavior

- The chat panel loads the persisted thread for its scope on appear.
- Sending a message immediately appends and stores the user message.
- The assistant response or error is stored after the provider returns.
- Source chips are restored from stored assistant messages.
- Add a compact clear-chat action, scoped to the current meeting or folder.

## Error Handling

- Storage errors should surface as chat errors without mutating meeting data.
- Provider errors should preserve the user's message and store an error message.
- Context-empty states should remain clear and deterministic.
- A failed assistant response should not delete existing chat history.

## Testing

Unit tests in `MuesliMeetingChat`:

- Message window selection uses only recent messages plus summary.
- Transcript demand detection works for explicit detail questions.
- Folder context does not include all transcripts by default.
- Empty or missing context produces a clear no-context state.

Storage adapter tests:

- Create and restore a meeting thread.
- Create and restore a folder thread.
- Scope separation prevents meeting and folder chats from mixing.
- Clear chat deletes only the current scope's thread/messages.

Provider routing tests:

- ChatGPT remains preferred when authenticated.
- Fallback providers still work.
- OpenAI provider sets `store: false`.

UI checks:

- Meeting detail restores existing messages.
- Folder home restores existing messages.
- Sending a prompt persists user and assistant/error messages.
- Clear chat removes only the visible chat.

## Implementation Order

1. Add persistence protocols and chat memory selection to `MuesliMeetingChat`.
2. Add SQLite-backed storage adapter under `MeetingChatIntegration`.
3. Update `MeetingChatPanel` to load, append, persist, and clear messages.
4. Add context policy tests for memory window and transcript demand.
5. Add storage tests around the app-side adapter where practical.
6. Verify focused chat tests, full native tests, debug build, then beta install.
