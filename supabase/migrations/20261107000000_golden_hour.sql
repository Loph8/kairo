-- Golden Hour schema. Times and outcomes only: no message text, no event titles, ever.
-- Clients read with the anon key (RLS: select only); every write goes through the `api` edge function.

create table members (
  id          text primary key,
  name        text not null,
  city        text not null,
  tz          text not null,
  onboarding  jsonb not null,              -- {wake, bed, busy: [[from, to], ...]}
  burden_min  int  not null default 0      -- fairness ledger: inconvenient minutes taken so far
);

create table observations (
  id            bigint generated always as identity primary key,
  member_id     text not null references members(id) on delete cascade,
  at            timestamptz not null,
  kind          text not null check (kind in ('call', 'text', 'label')),
  answered      boolean,
  reply_seconds int check (reply_seconds is null or reply_seconds >= 0),
  free          boolean,
  source        text not null check (source in ('channel', 'family_call', 'widget')),
  historical    boolean not null default false,
  check ((kind = 'call')  = (answered is not null)),
  check ((kind = 'label') = (free is not null))
);
create index observations_member_at on observations (member_id, at);

-- Calendar busy blocks pushed from each phone (EventKit). Start/end only; id is an opaque hash.
create table busy_blocks (
  member_id text not null references members(id) on delete cascade,
  id        text not null,
  starts_at timestamptz not null,
  ends_at   timestamptz not null,
  movable   boolean not null default false,
  primary key (member_id, id),
  check (ends_at > starts_at)
);

-- Demo clock: demo now = demo_anchor + (now() - real_anchor).
create table demo_state (
  id          int primary key default 1 check (id = 1),
  demo_anchor timestamptz not null default '2026-11-10T01:12:00Z',
  real_anchor timestamptz not null default now()
);
insert into demo_state default values;

create table bookings (
  id           uuid primary key default gen_random_uuid(),
  slot_utc     timestamptz not null,
  duration_min int not null default 45,
  accepted_by  text[] not null default '{}',
  status       text not null default 'proposed' check (status in ('proposed', 'booked', 'completed')),
  levels       jsonb not null default '{}',
  created_at   timestamptz not null default now()
);
create unique index one_open_booking_per_slot on bookings (slot_utc) where status <> 'completed';

-- Join a booking atomically; it becomes 'booked' once every member is in.
create or replace function accept_booking(booking_id uuid, member_ids text[])
returns bookings language plpgsql security definer set search_path = '' as $$
declare
  result public.bookings;
begin
  if exists (select 1 from unnest(member_ids) m where m not in (select id from public.members)) then
    raise exception 'unknown member in %', member_ids;
  end if;
  update public.bookings b
     set accepted_by = (select array_agg(distinct x order by x) from unnest(b.accepted_by || member_ids) x),
         status = case
           when (select count(*) from public.members) <=
                (select count(distinct x) from unnest(b.accepted_by || member_ids) x) then 'booked'
           else b.status end
   where b.id = booking_id and b.status <> 'completed'
  returning * into result;
  if result.id is null then
    raise exception 'booking % is not open', booking_id;
  end if;
  return result;
end $$;
revoke all on function accept_booking(uuid, text[]) from public, anon, authenticated;

alter table members      enable row level security;
alter table observations enable row level security;
alter table busy_blocks  enable row level security;
alter table demo_state   enable row level security;
alter table bookings     enable row level security;

create policy members_read    on members    for select to anon, authenticated using (true);
create policy demo_state_read on demo_state for select to anon, authenticated using (true);
create policy bookings_read   on bookings   for select to anon, authenticated using (true);
-- observations and busy_blocks: no client policies (server only).

alter publication supabase_realtime add table demo_state, bookings;
