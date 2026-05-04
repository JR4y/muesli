-- Muesli sync schema (initial)
-- See docs/plans/2026-05-04-supabase-sync-corrected-plan.md sections 7 and 8.
--
-- Tables: meeting_folders, meetings, dictations, user_preferences.
-- Each business table has client_updated_at, server_updated_at, remote_version,
-- last_writer_device_id, deleted_at (soft delete).
-- A trigger bumps remote_version and server_updated_at on UPDATE.
-- RLS restricts every row to its owning auth.uid().

set check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- meeting_folders
-- ---------------------------------------------------------------------------

create table if not exists public.meeting_folders (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    parent_folder_id uuid references public.meeting_folders(id) on delete set null,
    name text not null,
    color_hex text,
    icon_name text,
    sort_order integer not null default 0,
    client_updated_at timestamptz not null,
    server_updated_at timestamptz not null default now(),
    remote_version bigint not null default 1,
    last_writer_device_id text not null,
    deleted_at timestamptz
);

create index if not exists idx_meeting_folders_user_cursor
    on public.meeting_folders (user_id, server_updated_at, id);

create index if not exists idx_meeting_folders_parent
    on public.meeting_folders (parent_folder_id);

-- ---------------------------------------------------------------------------
-- meetings
-- ---------------------------------------------------------------------------

create table if not exists public.meetings (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    folder_id uuid references public.meeting_folders(id) on delete set null,
    title text not null,
    calendar_event_id text,
    calendar_event_snapshot jsonb,
    start_time timestamptz not null,
    end_time timestamptz,
    duration_seconds double precision,
    raw_transcript text not null default '',
    formatted_notes text not null default '',
    meeting_status text not null,
    manual_notes text not null default '',
    word_count integer not null default 0,
    selected_template_id text,
    selected_template_name text,
    selected_template_kind text,
    selected_template_prompt text,
    client_updated_at timestamptz not null,
    server_updated_at timestamptz not null default now(),
    remote_version bigint not null default 1,
    last_writer_device_id text not null,
    deleted_at timestamptz
);

create index if not exists idx_meetings_user_cursor
    on public.meetings (user_id, server_updated_at, id);

create index if not exists idx_meetings_folder
    on public.meetings (folder_id);

create index if not exists idx_meetings_calendar_event
    on public.meetings (user_id, calendar_event_id)
    where calendar_event_id is not null;

-- ---------------------------------------------------------------------------
-- dictations
-- ---------------------------------------------------------------------------

create table if not exists public.dictations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    timestamp timestamptz not null,
    duration_seconds double precision,
    raw_text text not null default '',
    app_context text not null default '',
    word_count integer not null default 0,
    source text not null default 'dictation',
    started_at timestamptz,
    ended_at timestamptz,
    client_updated_at timestamptz not null,
    server_updated_at timestamptz not null default now(),
    remote_version bigint not null default 1,
    last_writer_device_id text not null,
    deleted_at timestamptz
);

create index if not exists idx_dictations_user_cursor
    on public.dictations (user_id, server_updated_at, id);

-- ---------------------------------------------------------------------------
-- user_preferences (one row per user)
-- ---------------------------------------------------------------------------

create table if not exists public.user_preferences (
    user_id uuid primary key references auth.users(id) on delete cascade,
    custom_meeting_templates jsonb not null default '[]'::jsonb,
    hidden_built_in_template_ids jsonb not null default '[]'::jsonb,
    custom_words jsonb not null default '[]'::jsonb,
    default_meeting_template_id text not null default 'auto',
    auto_template_target_id text not null default '',
    meeting_title_prompt text not null default '',
    folder_order_remote_ids jsonb not null default '[]'::jsonb,
    client_updated_at timestamptz not null,
    server_updated_at timestamptz not null default now(),
    remote_version bigint not null default 1,
    last_writer_device_id text not null
);

-- ---------------------------------------------------------------------------
-- Version bump trigger for all sync tables
-- ---------------------------------------------------------------------------

create or replace function public.bump_remote_version()
returns trigger
language plpgsql
as $$
begin
    new.remote_version := coalesce(old.remote_version, 0) + 1;
    new.server_updated_at := now();
    return new;
end;
$$;

drop trigger if exists trg_meeting_folders_version on public.meeting_folders;
create trigger trg_meeting_folders_version
    before update on public.meeting_folders
    for each row execute function public.bump_remote_version();

drop trigger if exists trg_meetings_version on public.meetings;
create trigger trg_meetings_version
    before update on public.meetings
    for each row execute function public.bump_remote_version();

drop trigger if exists trg_dictations_version on public.dictations;
create trigger trg_dictations_version
    before update on public.dictations
    for each row execute function public.bump_remote_version();

drop trigger if exists trg_user_preferences_version on public.user_preferences;
create trigger trg_user_preferences_version
    before update on public.user_preferences
    for each row execute function public.bump_remote_version();

-- ---------------------------------------------------------------------------
-- RLS — owner-only access on every table
-- ---------------------------------------------------------------------------

alter table public.meeting_folders enable row level security;
alter table public.meetings enable row level security;
alter table public.dictations enable row level security;
alter table public.user_preferences enable row level security;

drop policy if exists meeting_folders_own on public.meeting_folders;
create policy meeting_folders_own on public.meeting_folders
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists meetings_own on public.meetings;
create policy meetings_own on public.meetings
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists dictations_own on public.dictations;
create policy dictations_own on public.dictations
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists user_preferences_own on public.user_preferences;
create policy user_preferences_own on public.user_preferences
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
