-- Golden Hour: proposed production schema. NOT executed in this environment.
-- Principles: RLS everywhere; clients read what membership allows and mutate only through
-- SECURITY DEFINER functions that derive the actor from auth.uid(); no service-role key in the app.

create extension if not exists pgcrypto;

-- ───────────────────────── tables ─────────────────────────
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 60),
  time_zone text not null check (time_zone ~ '^[A-Za-z_]+(/[A-Za-z0-9_+\-]+)*$'),  -- IANA id
  created_at timestamptz not null default now()
);

create table public.family_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.memberships (
  group_id uuid not null references public.family_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  relationship_label text not null default '' check (char_length(relationship_label) <= 40),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index on public.memberships(user_id);

-- Explicit restrictions the scheduler must honor (hard constraints). Stored in the person's local zone.
create table public.scheduling_restrictions (
  group_id uuid not null,
  user_id uuid not null,
  quiet_start_min int not null check (quiet_start_min between 0 and 1439),
  quiet_end_min int not null check (quiet_end_min between 0 and 1439),
  time_zone text not null,
  preferred_minutes int not null default 30 check (preferred_minutes between 15 and 120),
  primary key (group_id, user_id),
  foreign key (group_id, user_id) references public.memberships(group_id, user_id) on delete cascade
);

-- Coarse shared summaries ONLY: level + confidence bucket + validity. No raw events, no numeric scores.
create table public.availability_summaries (
  group_id uuid not null,
  user_id uuid not null,
  slot_start timestamptz not null,
  level text not null check (level in ('likelyFree','maybeFree','unlikely','busy','quietHours','learning')),
  confidence text not null check (confidence in ('low','medium','high')),
  valid_until timestamptz not null,
  primary key (group_id, user_id, slot_start),
  foreign key (group_id, user_id) references public.memberships(group_id, user_id) on delete cascade,
  check (valid_until > slot_start)
);

create table public.busy_overrides (
  group_id uuid not null,
  user_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  primary key (group_id, user_id),               -- one active override per person: repeated taps replace, never duplicate
  foreign key (group_id, user_id) references public.memberships(group_id, user_id) on delete cascade,
  check (ends_at > starts_at and ends_at <= starts_at + interval '24 hours')
);

create table public.proposals (
  id text primary key check (id ~ '^[A-Za-z0-9_+.:\-]{1,80}$'),  -- deterministic: window + participants
  group_id uuid not null references public.family_groups(id) on delete cascade,
  created_by uuid references auth.users(id),     -- null when created by the agent on a user's behalf
  created_via_agent boolean not null default false,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  expires_at timestamptz not null,
  status text not null default 'suggested'
    check (status in ('suggested','pending','confirmed','declined','expired','canceled','completed')),
  explanation text not null default '' check (char_length(explanation) <= 300),
  version int not null default 0,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at and expires_at <= starts_at)
);
create index on public.proposals(group_id, starts_at);

create table public.proposal_participants (
  proposal_id text not null references public.proposals(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  confirmed_at timestamptz,                      -- set only by that user, via confirm_proposal()
  primary key (proposal_id, user_id)
);

create table public.scheduling_burden (
  id bigint generated always as identity primary key,
  group_id uuid not null references public.family_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  proposal_id text not null references public.proposals(id) on delete cascade,
  at timestamptz not null default now(),
  amount real not null check (amount between 0 and 1),
  unique (user_id, proposal_id)
);

create table public.device_registrations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'ios',
  apns_token text,                               -- ordinary notifications
  activity_push_token text,                      -- ActivityKit push updates (NOT a VoIP/PushKit token)
  created_at timestamptz not null default now(),
  unique (user_id, apns_token)
);

-- ───────────────────────── helpers ─────────────────────────
create or replace function public.is_member(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships m where m.group_id = g and m.user_id = auth.uid());
$$;

create or replace function public.in_quiet_hours(p_group uuid, p_user uuid, p_start timestamptz, p_end timestamptz)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare r scheduling_restrictions; t timestamptz; m int;
begin
  select * into r from scheduling_restrictions where group_id = p_group and user_id = p_user;
  if not found then return false; end if;
  t := p_start;
  while t < p_end loop
    m := extract(hour from (t at time zone r.time_zone))::int * 60 + extract(minute from (t at time zone r.time_zone))::int;
    if (r.quiet_start_min < r.quiet_end_min and m >= r.quiet_start_min and m < r.quiet_end_min)
       or (r.quiet_start_min > r.quiet_end_min and (m >= r.quiet_start_min or m < r.quiet_end_min)) then
      return true;
    end if;
    t := t + interval '15 minutes';
  end loop;
  return false;
end $$;

-- ───────────────────────── RLS ─────────────────────────
alter table public.profiles enable row level security;
alter table public.family_groups enable row level security;
alter table public.memberships enable row level security;
alter table public.scheduling_restrictions enable row level security;
alter table public.availability_summaries enable row level security;
alter table public.busy_overrides enable row level security;
alter table public.proposals enable row level security;
alter table public.proposal_participants enable row level security;
alter table public.scheduling_burden enable row level security;
alter table public.device_registrations enable row level security;

revoke all on all tables in schema public from anon;

create policy profiles_read on public.profiles for select to authenticated using (
  id = auth.uid() or exists (select 1 from memberships a join memberships b on a.group_id = b.group_id
                             where a.user_id = auth.uid() and b.user_id = profiles.id));
create policy profiles_write_self on public.profiles for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy groups_read on public.family_groups for select to authenticated using (public.is_member(id));
create policy memberships_read on public.memberships for select to authenticated using (public.is_member(group_id));
-- No direct insert/update/delete on groups or memberships: use create_group()/invite flow (deferred).

create policy restrictions_read on public.scheduling_restrictions for select to authenticated using (public.is_member(group_id));
create policy restrictions_write on public.scheduling_restrictions for all to authenticated
  using (user_id = auth.uid() and public.is_member(group_id)) with check (user_id = auth.uid() and public.is_member(group_id));

create policy summaries_read on public.availability_summaries for select to authenticated
  using (public.is_member(group_id) and valid_until > now());
create policy summaries_write_own on public.availability_summaries for all to authenticated
  using (user_id = auth.uid() and public.is_member(group_id))
  with check (user_id = auth.uid() and public.is_member(group_id));

create policy busy_read on public.busy_overrides for select to authenticated using (public.is_member(group_id) and ends_at > now());
create policy busy_write_own on public.busy_overrides for all to authenticated
  using (user_id = auth.uid() and public.is_member(group_id))
  with check (user_id = auth.uid() and public.is_member(group_id));

create policy proposals_read on public.proposals for select to authenticated
  using (exists (select 1 from proposal_participants pp where pp.proposal_id = proposals.id and pp.user_id = auth.uid()));
create policy participants_read on public.proposal_participants for select to authenticated
  using (exists (select 1 from proposal_participants me where me.proposal_id = proposal_participants.proposal_id and me.user_id = auth.uid()));
-- proposals / proposal_participants: NO write policies. All mutations go through the functions below.

create policy burden_read on public.scheduling_burden for select to authenticated using (public.is_member(group_id));
create policy devices_own on public.device_registrations for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ───────────────────────── transactional booking transitions ─────────────────────────
-- The actor is ALWAYS auth.uid(). There is no parameter to act for someone else, so neither a client
-- nor the Claude agent (which calls with the end user's JWT) can impersonate another participant.

create or replace function public.create_proposal(
  p_id text, p_group uuid, p_participants uuid[], p_starts timestamptz, p_ends timestamptz,
  p_explanation text default '', p_via_agent boolean default false)
returns public.proposals language plpgsql security definer set search_path = public as $$
declare pr proposals; u uuid;
begin
  if auth.uid() is null or not is_member(p_group) then raise exception 'not a member' using errcode = '42501'; end if;
  if not (auth.uid() = any(p_participants)) then raise exception 'creator must be a participant' using errcode = '42501'; end if;
  if array_length(p_participants, 1) < 2 or array_length(p_participants, 1) > 6 then raise exception 'participants 2-6'; end if;
  if p_starts <= now() or p_ends <= p_starts or p_ends - p_starts > interval '2 hours' then raise exception 'invalid window'; end if;
  foreach u in array p_participants loop
    if not exists (select 1 from memberships where group_id = p_group and user_id = u) then raise exception 'participant not in group'; end if;
    if in_quiet_hours(p_group, u, p_starts, p_ends) then raise exception 'window violates quiet hours' using errcode = 'P0001'; end if;
    if exists (select 1 from busy_overrides b where b.group_id = p_group and b.user_id = u and b.starts_at < p_ends and b.ends_at > p_starts)
      then raise exception 'participant is busy' using errcode = 'P0001'; end if;
  end loop;
  insert into proposals(id, group_id, created_by, created_via_agent, starts_at, ends_at, expires_at, explanation)
  values (p_id, p_group, auth.uid(), p_via_agent, p_starts, p_ends,
          least(p_starts, now() + interval '24 hours'), left(coalesce(p_explanation, ''), 300))
  on conflict (id) do nothing;                      -- duplicate-proof
  insert into proposal_participants(proposal_id, user_id)
  select p_id, x from unnest(p_participants) x on conflict do nothing;
  select * into pr from proposals where id = p_id;
  return pr;
end $$;

create or replace function public.expire_proposals() returns int language sql security definer set search_path = public as $$
  with e as (
    update proposals set status = 'expired', version = version + 1
    where status in ('suggested','pending') and (expires_at <= now() or starts_at <= now()) returning 1)
  select count(*)::int from e;
$$;
-- Schedule with pg_cron:  select cron.schedule('expire-proposals', '*/5 * * * *', 'select public.expire_proposals()');

create or replace function public.confirm_proposal(p_id text) returns public.proposals
language plpgsql security definer set search_path = public as $$
declare pr proposals; remaining int;
begin
  select * into pr from proposals where id = p_id for update;          -- serializes concurrent confirmations
  if not found or not exists (select 1 from proposal_participants where proposal_id = p_id and user_id = auth.uid())
    then raise exception 'not a participant' using errcode = '42501'; end if;
  if pr.status in ('suggested','pending') and (pr.expires_at <= now() or pr.starts_at <= now()) then
    update proposals set status = 'expired', version = version + 1 where id = p_id returning * into pr;
    raise exception 'proposal expired' using errcode = 'P0001';
  end if;
  if pr.status = 'confirmed' then return pr; end if;                     -- idempotent
  if pr.status not in ('suggested','pending') then raise exception 'proposal is %', pr.status using errcode = 'P0001'; end if;
  update proposal_participants set confirmed_at = now()
   where proposal_id = p_id and user_id = auth.uid() and confirmed_at is null;
  select count(*) into remaining from proposal_participants where proposal_id = p_id and confirmed_at is null;
  update proposals set status = case when remaining = 0 then 'confirmed' else 'pending' end,
                       version = version + case when found then 1 else 0 end
   where id = p_id returning * into pr;
  return pr;
end $$;

create or replace function public.decline_proposal(p_id text) returns public.proposals
language plpgsql security definer set search_path = public as $$
declare pr proposals;
begin
  select * into pr from proposals where id = p_id for update;
  if not found or not exists (select 1 from proposal_participants where proposal_id = p_id and user_id = auth.uid())
    then raise exception 'not a participant' using errcode = '42501'; end if;
  if pr.status = 'declined' then return pr; end if;
  if pr.status not in ('suggested','pending') then raise exception 'proposal is %', pr.status using errcode = 'P0001'; end if;
  update proposals set status = 'declined', version = version + 1 where id = p_id returning * into pr;
  return pr;
end $$;

create or replace function public.cancel_proposal(p_id text) returns public.proposals
language plpgsql security definer set search_path = public as $$
declare pr proposals;
begin
  select * into pr from proposals where id = p_id for update;
  if not found or not exists (select 1 from proposal_participants where proposal_id = p_id and user_id = auth.uid())
    then raise exception 'not a participant' using errcode = '42501'; end if;
  if pr.status = 'canceled' then return pr; end if;
  if pr.status not in ('suggested','pending','confirmed') then raise exception 'proposal is %', pr.status using errcode = 'P0001'; end if;
  update proposals set status = 'canceled', version = version + 1 where id = p_id returning * into pr;
  return pr;
end $$;

grant execute on function public.create_proposal, public.confirm_proposal, public.decline_proposal,
  public.cancel_proposal to authenticated;
revoke execute on function public.expire_proposals() from public, anon, authenticated;
