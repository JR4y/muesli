-- Muesli Archive state
-- Adds reversible archive state for folders and meetings.

alter table public.meeting_folders
    add column if not exists archived_at timestamptz;

alter table public.meetings
    add column if not exists archived_at timestamptz;

create index if not exists idx_meeting_folders_user_archived
    on public.meeting_folders (user_id, archived_at);

create index if not exists idx_meetings_user_archived
    on public.meetings (user_id, archived_at);
