-- Muesli Meeting Chat sync schema
-- Adds remote chat threads/messages for normal Supabase sync.

set check_function_bodies = off;

create table if not exists public.meeting_chat_threads (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    scope_kind text not null check (scope_kind in ('meeting', 'folder')),
    scope_id uuid not null,
    title text not null,
    summary text not null default '',
    client_updated_at timestamptz not null,
    server_updated_at timestamptz not null default now(),
    remote_version bigint not null default 1,
    last_writer_device_id text not null,
    deleted_at timestamptz
);

create index if not exists idx_meeting_chat_threads_user_cursor
    on public.meeting_chat_threads (user_id, server_updated_at, id);

create index if not exists idx_meeting_chat_threads_scope
    on public.meeting_chat_threads (user_id, scope_kind, scope_id);

create table if not exists public.meeting_chat_messages (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    thread_id uuid not null references public.meeting_chat_threads(id) on delete cascade,
    role text not null check (role in ('user', 'assistant', 'error')),
    content text not null,
    sources_json jsonb not null default '[]'::jsonb,
    created_at timestamptz not null,
    client_updated_at timestamptz not null,
    server_updated_at timestamptz not null default now(),
    remote_version bigint not null default 1,
    last_writer_device_id text not null,
    deleted_at timestamptz
);

create index if not exists idx_meeting_chat_messages_user_cursor
    on public.meeting_chat_messages (user_id, server_updated_at, id);

create index if not exists idx_meeting_chat_messages_thread_created
    on public.meeting_chat_messages (user_id, thread_id, created_at);

drop trigger if exists trg_meeting_chat_threads_version on public.meeting_chat_threads;
create trigger trg_meeting_chat_threads_version
    before update on public.meeting_chat_threads
    for each row execute function public.bump_remote_version();

drop trigger if exists trg_meeting_chat_messages_version on public.meeting_chat_messages;
create trigger trg_meeting_chat_messages_version
    before update on public.meeting_chat_messages
    for each row execute function public.bump_remote_version();

alter table public.meeting_chat_threads enable row level security;
alter table public.meeting_chat_messages enable row level security;

drop policy if exists meeting_chat_threads_own on public.meeting_chat_threads;
create policy meeting_chat_threads_own on public.meeting_chat_threads
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists meeting_chat_messages_own on public.meeting_chat_messages;
create policy meeting_chat_messages_own on public.meeting_chat_messages
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
