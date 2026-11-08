-- Who last started the family's group call and when, so everyone else sees "Join" for 45 minutes.
alter table families add column if not exists call_started_at timestamptz;
alter table families add column if not exists call_started_by text;
