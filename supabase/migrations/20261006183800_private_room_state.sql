-- Authoritative room state is never a Data API table. The persistent Node
-- rule service owns one dedicated database session and namespace advisory lock.
create schema if not exists game_private;
revoke all on schema game_private from public, anon, authenticated;

create table game_private.room_worlds (
  namespace text primary key check (namespace ~ '^[a-z0-9][a-z0-9_-]{0,63}$'),
  version bigint not null check (version > 0),
  snapshot jsonb not null check (coalesce(
    jsonb_typeof(snapshot) = 'object'
    and snapshot ->> 'schema' = '1'
    and snapshot ->> 'profile' = 'local-room-rehearsal-1'
    and jsonb_typeof(snapshot -> 'rooms') = 'array'
    and jsonb_typeof(snapshot -> 'requests') = 'array', false)),
  updated_at timestamptz not null default now()
);

alter table game_private.room_worlds enable row level security;
revoke all on table game_private.room_worlds from public, anon, authenticated;
-- No client policies. The migration/table owner connection is used only by
-- the backend; do not expose DATABASE_URL or add this schema to api.schemas.
comment on table game_private.room_worlds is
  'Private canonical snapshots and command receipts. Backend session only; never exposed to clients.';
