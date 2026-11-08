-- Accounts: every signed-in person belongs to one family, and every row is scoped to a family.
-- Phones never touch these tables directly: the `api` edge function verifies the user's token
-- and works with the service role. RLS is on with no policies, so the public key reads nothing.

drop function if exists accept_booking(uuid, text[]);
drop table if exists bookings, busy_blocks, observations, demo_state, members cascade;

create table families (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 60),
  invite_code text not null unique check (invite_code ~ '^[A-Z2-9]{6}$'),
  created_at  timestamptz not null default now()
);

create table members (
  id          text primary key,
  family_id   uuid not null references families(id) on delete cascade,
  user_id     uuid unique references auth.users(id) on delete cascade,
  simulated   boolean not null default false,
  persona     text check (persona in ('you', 'mom', 'grandpa', 'dad')),
  name        text not null check (char_length(name) between 1 and 40),
  city        text not null check (char_length(city) <= 60),
  tz          text not null,
  onboarding  jsonb not null,
  burden_min  integer not null default 0,
  created_at  timestamptz not null default now(),
  check (simulated or user_id is not null or persona is not null)
);
create index members_family on members (family_id);

create table observations (
  id            bigint generated always as identity primary key,
  family_id     uuid not null references families(id) on delete cascade,
  member_id     text not null references members(id) on delete cascade,
  at            timestamptz not null,
  kind          text not null check (kind in ('call', 'text', 'label')),
  answered      boolean,
  reply_seconds integer,
  free          boolean,
  source        text not null check (source in ('channel', 'family_call', 'widget', 'shortcut', 'sim')),
  historical    boolean not null default false,
  check ((kind = 'call') = (answered is not null)),
  check ((kind = 'label') = (free is not null))
);
create index observations_family_at on observations (family_id, at);

create table busy_blocks (
  member_id text not null references members(id) on delete cascade,
  family_id uuid not null references families(id) on delete cascade,
  id        text not null,
  starts_at timestamptz not null,
  ends_at   timestamptz not null check (ends_at > starts_at),
  movable   boolean not null default false,
  primary key (member_id, id)
);
create index busy_blocks_family on busy_blocks (family_id);

create table bookings (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null references families(id) on delete cascade,
  slot_utc     timestamptz not null,
  duration_min integer not null default 45,
  accepted_by  text[] not null default '{}',
  status       text not null default 'proposed' check (status in ('proposed', 'booked', 'completed')),
  levels       jsonb not null default '{}'
);
create unique index one_open_booking_per_family_slot on bookings (family_id, slot_utc) where status <> 'completed';

-- One sentence from Claude per suggested slot, cached so the API is called once per change.
create table ai_notes (
  family_id  uuid not null references families(id) on delete cascade,
  key        text not null,
  text       text not null check (char_length(text) <= 400),
  created_at timestamptz not null default now(),
  primary key (family_id, key)
);

-- Booked once everyone in that family has accepted. Atomic, so two phones joining at once both count.
create function accept_booking(booking_id uuid, member_ids text[]) returns bookings
language sql security definer set search_path = public as $$
  update bookings b set
    accepted_by = (select array_agg(distinct x order by x) from unnest(b.accepted_by || member_ids) x),
    status = case
      when (select count(*) from members m where m.family_id = b.family_id) <=
           (select count(distinct x) from unnest(b.accepted_by || member_ids) x) then 'booked'
      else b.status end
  where b.id = booking_id and b.status <> 'completed'
  returning b.*;
$$;
revoke all on function accept_booking(uuid, text[]) from public, anon, authenticated;

alter table families     enable row level security;
alter table members      enable row level security;
alter table observations enable row level security;
alter table busy_blocks  enable row level security;
alter table bookings     enable row level security;
alter table ai_notes     enable row level security;
