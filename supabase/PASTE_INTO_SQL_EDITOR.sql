-- Run once in Supabase → SQL Editor. Safe to run again.

-- 20261108120000_many_families.sql
-- One account can now belong to several families (up to 5, enforced in the api function).
-- Before: members.user_id was unique, so one family per account.
-- After: one row per person per family.
alter table members drop constraint if exists members_user_id_key;
alter table members drop constraint if exists members_family_user_key;
alter table members add constraint members_family_user_key unique (family_id, user_id);
create index if not exists members_user_id_idx on members (user_id);

-- 20261108130000_family_call_link.sql
-- A family's shared group-call link (FaceTime, Google Meet, Zoom…). Everyone's Group call button opens it.
-- The api function only accepts https links from known call services.
alter table families add column if not exists call_link text
  check (call_link is null or (char_length(call_link) <= 500 and call_link like 'https://%'));

-- 20261108140000_member_contact.sql
-- Each person's phone number and connected call apps (WhatsApp, WeChat…), shown only to their own families.
-- Stored on every family row of that person; the api function keeps them in step.
alter table members add column if not exists contact jsonb not null default '{}'::jsonb;

-- 20261108150000_group_call_started.sql
-- Who last started the family's group call and when, so everyone else sees "Join" for 45 minutes.
alter table families add column if not exists call_started_at timestamptz;
alter table families add column if not exists call_started_by text;
