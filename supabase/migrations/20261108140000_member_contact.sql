-- Each person's phone number and connected call apps (WhatsApp, WeChat…), shown only to their own families.
-- Stored on every family row of that person; the api function keeps them in step.
alter table members add column if not exists contact jsonb not null default '{}'::jsonb;
