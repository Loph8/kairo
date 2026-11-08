-- One account can now belong to several families (up to 5, enforced in the api function).
-- Before: members.user_id was unique, so one family per account.
-- After: one row per person per family.
alter table members drop constraint if exists members_user_id_key;
alter table members drop constraint if exists members_family_user_key;
alter table members add constraint members_family_user_key unique (family_id, user_id);
create index if not exists members_user_id_idx on members (user_id);
