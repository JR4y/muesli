# Meeting Chat Persistence and Context Design

## Purpose

Muesli Meeting Chat should feel continuous across navigation while keeping provider calls predictable and reasonably small. The first persistence upgrade stores chat history locally, then uses a deterministic context policy to decide what text is sent to the LLM on each turn.

The design keeps the feature read-only and modular. Chat persistence and context orchestration stay inside `MuesliMeetingChat` plus thin app adapters under `MeetingChatIntegration`.

## Implemented MVP Status

Implemented in the local beta MVP:

- new SwiftPM target: `MuesliMeetingChat`
- thin app integration under `MuesliNativeApp/MeetingChatIntegration`
- meeting chat mounted in completed meeting detail
- folder chat mounted in selected-folder meeting home
- completed meeting detail uses a wider chat-aware host while centering the
  established notes/event column, so the associated event block stays aligned
  with the rest of the detail content
- local SQLite persistence through `SQLiteMeetingChatStore`
- local threads scoped by `meeting(id)` or `folder(id)`
- persisted user, assistant, and error messages
- persisted assistant source references
- restored chats when navigating back to the same meeting/folder
- scoped clear-chat action
- source chips that navigate to referenced meetings
- bounded local memory via `MeetingChatMemoryPolicy`
- stateless provider calls with current context, recent messages, and compact
  older-memory text
- ChatGPT OAuth provider preference with fallback providers preserved
- `store: false` for ChatGPT WHAM and official OpenAI Responses calls

Still intentionally omitted from the MVP:

- Supabase sync for chat history
- global all-meetings chat
- embeddings/vector search
- persistent remote provider threads
- write actions or agentic mutations
- semantic folder/project memory
- full transcript retrieval across folders

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
- If the thread has more history than the recent window, include local compact
  memory for the older turns. The current MVP can derive a bounded compact
  memory string from older messages; a future phase should replace that with a
  real semantic `thread.summary`.
- Do not send the full persisted chat history by default.

## Transcript Demand

Transcript demand is decided locally before the provider call. It can be triggered by:

- Explicit user wording such as "transcript", "transcripcion", "cita", "exactamente", "quien dijo", "que dijo", "mencionaron", "objecion", or "detalle".
- Missing formatted notes/manual notes for a single meeting.
- Future fallback behavior where the assistant requests more evidence, handled as a second call only after v1.

For folder chat, transcript demand never means "send all transcripts". It means "narrow down candidate meetings, then send bounded excerpts".

## Meeting Detail Layout Note

The completed meeting detail surface has two related widths:

- the classic detail column used by associated event, merged sources, document
  toolbar, notes, and transcript content
- the wider chat-aware host used to let the floating Meeting Chat overlay expand
  comfortably

The normal completed-meeting stack should center the classic column inside the
wider host. This prevents the associated event card from appearing left-heavy
while preserving the extra horizontal room required by the chat overlay.

## Provider Behavior

Provider calls remain stateless:

- Muesli sends the selected context and recent memory with every turn.
- Muesli does not depend on ChatGPT remembering a remote conversation.
- ChatGPT internal WHAM calls should continue using `store: false`.
- Official OpenAI Responses calls should also set `store: false` for consistency.

This keeps local persistence independent from provider state. It also makes it easier to switch between ChatGPT OAuth, OpenAI API, OpenRouter, Ollama, LM Studio, or custom providers.

## Prioritized Future Phases

### Phase 1: Stronger Local Project Memory

Build a real folder/project memory layer.

- Store a semantic local memory summary per folder/workspace.
- Track stable decisions, risks, open questions, recurring assumptions, and
  stakeholder positions.
- Keep this memory separate from meeting summaries and chat transcripts.
- Refresh it incrementally when relevant meetings change.

Why first:
folder chat is the core product idea. Without project memory, folder chat is
limited to recent deterministic context and cannot reliably answer long-running
project questions.

### Phase 2: Relevance-Based Retrieval

Replace "recent meetings only" with candidate selection.

- Rank candidate meetings by title, formatted notes, manual notes, date, and
  eventually transcript excerpts.
- Keep deterministic limits for selected meetings and characters.
- Preserve source references so answers remain auditable.

Why second:
project questions need the right meetings, not necessarily the latest meetings.
This should happen before adding broader agentic behavior.

### Phase 3: Bias and Risk Analysis Mode

Add a project-review prompt mode.

- Support questions about bias, blind spots, repeated assumptions, unchallenged
  decisions, missing stakeholders, and risk drift.
- Require answer grounding through meeting source chips.
- Prefer summaries/manual notes first.
- Pull transcript evidence only when the question asks for exact detail or the
  notes are insufficient.

Why third:
this is the highest-value product use case described for folder/project chat,
but it depends on stronger memory and retrieval.

### Phase 4: Transcript Evidence Retrieval

Make transcript lookup selective and evidence-oriented.

- Never send every transcript in a folder by default.
- Select candidate meetings first.
- Include bounded excerpts only for explicit quote/detail/transcript questions.
- Consider a two-call flow later: answer from notes first, then request
  transcript evidence if needed.

Why fourth:
transcripts are valuable but expensive. They should become an evidence layer,
not the default context payload.

### Phase 5: Real Thread Summaries

Replace compact older-message fallback memory with semantic chat summaries.

- Summarize older chat turns into the local thread `summary`.
- Include that summary plus recent turns in provider calls.
- Avoid sending the full persisted chat history.

Why fifth:
this improves long chats, but it is less important than selecting the right
project context for folder questions.

### Phase 6: Chat Management UX

Make chat state easier to understand and control.

- Add clearer reset/new-chat affordances.
- Show last-updated state only if it helps orientation.
- Keep the default panel compact.
- Localize visible chat copy once the interaction stabilizes.

Why sixth:
the current compact panel is enough for MVP validation. UX polish should follow
after the retrieval model proves useful.

### Phase 7: Sync and Portability

Decide if chat history should sync.

- Keep local-only as the default until privacy/product value is clear.
- If synced, model chat as optional separate entities from meetings/folders.
- Do not sync raw provider prompts unless there is a clear reason.

Why seventh:
syncing chat can create privacy and merge complexity. The feature should prove
itself locally before adding cross-device state.

### Phase 8: Confirmed Agentic Actions

Only add actions after context quality is trustworthy.

- Draft tasks or suggested follow-ups.
- Proposed note edits.
- Confirm-before-write for every mutation.
- Keep read-only analysis as the default mode.

Why last:
agentic actions without strong retrieval/source grounding would create more risk
than value.

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
