-- A family's shared group-call link (FaceTime, Google Meet, Zoom…). Everyone's Group call button opens it.
-- The api function only accepts https links from known call services.
alter table families add column if not exists call_link text
  check (call_link is null or (char_length(call_link) <= 500 and call_link like 'https://%'));
