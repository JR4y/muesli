alter table public.meetings
    add column if not exists merged_into_meeting_id uuid
    references public.meetings(id) on delete set null;

create index if not exists idx_meetings_merged_into
    on public.meetings (merged_into_meeting_id);
