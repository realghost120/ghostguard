create table if not exists public.licenses (
  id            uuid        primary key default gen_random_uuid(),
  license_key   text        not null unique,
  status        text        not null default 'ACTIVE'
                            check (status in ('ACTIVE', 'SUSPENDED', 'EXPIRED')),
  plan          text        not null default 'monthly'
                            check (plan in ('monthly', 'quarterly', 'lifetime')),
  server_name   text        null,
  expires_at    timestamptz null,
  hwid          text        null,
  notes         text        null,
  last_seen     timestamptz null,
  created_at    timestamptz not null default now()
);

create unique index if not exists uq_licenses_key
  on public.licenses (license_key);
create index if not exists idx_licenses_status
  on public.licenses (status);


create table if not exists public.customers (
  id            uuid        primary key default gen_random_uuid(),
  username      text        not null unique,
  password      text        not null,
  license_key   text        not null
                            references public.licenses (license_key)
                            on delete cascade,
  email         text        null,
  discord_id    text        null,
  active        boolean     not null default true,
  created_at    timestamptz not null default now(),
  last_login    timestamptz null
);

create index if not exists idx_customers_license_key
  on public.customers (license_key);
create index if not exists idx_customers_username
  on public.customers (username);


-- panel_admins: borttagen, admins hanteras via admins.json i FiveM-resursen


create table if not exists public.bans (
  ban_id        text        primary key,
  license_key   text        not null
                            references public.licenses (license_key)
                            on delete cascade,
  player_name   text        not null default 'Unknown',
  player_id     text        not null,
  identifiers   text[]      not null default '{}',
  reason        text        not null default 'No reason',
  duration      text        not null default 'P',
  banned_by     text        not null default 'GhostGuard',
  evidence_url  text        null,
  active        boolean     not null default true,
  expires_at    timestamptz null,
  unbanned_at   timestamptz null,
  unbanned_by   text        null,
  created_at    timestamptz not null default now()
);

create index if not exists idx_bans_license_key
  on public.bans (license_key);
create index if not exists idx_bans_player_id
  on public.bans (player_id);
create index if not exists idx_bans_active
  on public.bans (license_key, active);
create index if not exists idx_bans_created_at
  on public.bans (created_at desc);
create index if not exists idx_bans_identifiers
  on public.bans using gin (identifiers);


create table if not exists public.logs (
  id            uuid        primary key default gen_random_uuid(),
  license_key   text        not null
                            references public.licenses (license_key)
                            on delete cascade,
  level         text        not null default 'info'
                            check (level in ('info', 'warn', 'alert', 'error')),
  type          text        not null default 'log',
  title         text        not null default 'Server',
  message       text        not null,
  player_name   text        null,
  player_id     text        null,
  meta          jsonb       null,
  created_at    timestamptz not null default now()
);

create index if not exists idx_logs_license_key
  on public.logs (license_key);
create index if not exists idx_logs_license_created
  on public.logs (license_key, created_at desc);
create index if not exists idx_logs_level
  on public.logs (license_key, level);


create table if not exists public.detections (
  id              uuid        primary key default gen_random_uuid(),
  license_key     text        not null
                              references public.licenses (license_key)
                              on delete cascade,
  player_name     text        not null default 'Unknown',
  player_id       text        not null,
  identifiers     text[]      not null default '{}',
  detection_type  text        not null,
  details         text        null,
  action_taken    text        not null default 'alert'
                              check (action_taken in ('alert', 'ban', 'kick', 'warn')),
  ban_id          text        null
                              references public.bans (ban_id)
                              on delete set null,
  created_at      timestamptz not null default now()
);

create index if not exists idx_detections_license_key
  on public.detections (license_key);
create index if not exists idx_detections_player_id
  on public.detections (player_id);
create index if not exists idx_detections_license_created
  on public.detections (license_key, created_at desc);
create index if not exists idx_detections_type
  on public.detections (license_key, detection_type);


create table if not exists public.server_status (
  license_key   text        primary key
                            references public.licenses (license_key)
                            on delete cascade,
  online        boolean     not null default false,
  player_count  integer     not null default 0,
  max_players   integer     not null default 64,
  version       text        null,
  uptime        bigint      not null default 0,
  last_seen     timestamptz not null default now()
);


-- detection_settings hanteras i config.lua, inte i databasen


create or replace function check_player_banned(
  p_license_key  text,
  p_identifiers  text[]
)
returns table (
  ban_id       text,
  player_name  text,
  reason       text,
  banned_by    text,
  expires_at   timestamptz
)
language sql stable
as $$
  select
    ban_id,
    player_name,
    reason,
    banned_by,
    expires_at
  from public.bans
  where license_key = p_license_key
    and active      = true
    and (expires_at is null or expires_at > now())
    and identifiers && p_identifiers
  limit 1;
$$;


create or replace view public.active_bans as
  select *
  from public.bans
  where active = true
    and (expires_at is null or expires_at > now());

create or replace view public.server_overview as
  select
    l.license_key,
    l.status          as license_status,
    l.plan,
    l.server_name,
    l.expires_at      as license_expires_at,
    l.last_seen       as license_last_seen,
    ss.online,
    ss.player_count,
    ss.max_players,
    ss.version,
    ss.uptime,
    ss.last_seen      as server_last_seen,
    (
      select count(*) from public.bans b
      where  b.license_key = l.license_key
        and  b.active      = true
        and  (b.expires_at is null or b.expires_at > now())
    ) as active_bans,
    (
      select count(*) from public.logs lg
      where  lg.license_key = l.license_key
        and  lg.created_at  > now() - interval '24 hours'
    ) as logs_24h,
    (
      select count(*) from public.detections d
      where  d.license_key = l.license_key
        and  d.created_at  > now() - interval '24 hours'
    ) as detections_24h
  from  public.licenses l
  left join public.server_status ss on ss.license_key = l.license_key;

create or replace view public.player_stats as
  select
    license_key,
    player_id,
    max(player_name)                             as player_name,
    count(*)                                     as total_detections,
    count(*) filter (where action_taken = 'ban') as times_banned,
    max(created_at)                              as last_seen,
    min(created_at)                              as first_seen,
    array_agg(distinct detection_type)           as detection_types
  from public.detections
  group by license_key, player_id;


alter table public.licenses           disable row level security;
alter table public.customers          disable row level security;
-- panel_admins: borttagen
alter table public.bans               disable row level security;
alter table public.logs               disable row level security;
alter table public.detections         disable row level security;
alter table public.server_status      disable row level security;
-- detection_settings: borttagen, hanteras i config.lua
