-- ============================================================
-- GhostGuard PostgreSQL schema (Railway)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- licenses
-- ============================================================
CREATE TABLE IF NOT EXISTS licenses (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  license_key   text        NOT NULL UNIQUE,
  status        text        NOT NULL DEFAULT 'ACTIVE'
                            CHECK (status IN ('ACTIVE', 'SUSPENDED', 'EXPIRED')),
  plan          text        NOT NULL DEFAULT 'monthly'
                            CHECK (plan IN ('monthly', 'quarterly', 'lifetime')),
  server_name   text,
  expires_at    timestamptz,
  hwid          text,
  notes         text,
  last_seen     timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_licenses_status ON licenses (status);

-- ============================================================
-- customers
-- ============================================================
CREATE TABLE IF NOT EXISTS customers (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  username      text,
  password      text,
  license_key   text        NOT NULL REFERENCES licenses(license_key) ON DELETE CASCADE,
  email         text,
  discord_id    text,
  discord_name  text,
  discord_avatar text,
  active        boolean     NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_login    timestamptz
);

ALTER TABLE customers ALTER COLUMN username DROP NOT NULL;
ALTER TABLE customers ALTER COLUMN password DROP NOT NULL;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS discord_name text;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS discord_avatar text;

CREATE INDEX IF NOT EXISTS idx_customers_license_key ON customers (license_key);
CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_discord_id ON customers (discord_id) WHERE discord_id IS NOT NULL;

-- ============================================================
-- bans (evidence lagras som bytea direkt i DB)
-- ============================================================
CREATE TABLE IF NOT EXISTS bans (
  ban_id        text        PRIMARY KEY,
  license_key   text        NOT NULL REFERENCES licenses(license_key) ON DELETE CASCADE,
  player_name   text        NOT NULL DEFAULT 'Unknown',
  player_id     text        NOT NULL,
  identifiers   text[]      NOT NULL DEFAULT '{}',
  reason        text        NOT NULL DEFAULT 'No reason',
  duration      text        NOT NULL DEFAULT 'P',
  banned_by     text        NOT NULL DEFAULT 'GhostGuard',
  evidence      bytea,
  evidence_mime text,
  evidence_url  text,
  active        boolean     NOT NULL DEFAULT true,
  expires_at    timestamptz,
  unbanned_at   timestamptz,
  unbanned_by   text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bans_license_key ON bans (license_key);
CREATE INDEX IF NOT EXISTS idx_bans_player_id ON bans (player_id);
CREATE INDEX IF NOT EXISTS idx_bans_active ON bans (license_key, active);
CREATE INDEX IF NOT EXISTS idx_bans_created_at ON bans (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bans_identifiers ON bans USING gin (identifiers);

-- ============================================================
-- logs
-- ============================================================
CREATE TABLE IF NOT EXISTS logs (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  license_key   text        NOT NULL REFERENCES licenses(license_key) ON DELETE CASCADE,
  level         text        NOT NULL DEFAULT 'info'
                            CHECK (level IN ('info', 'warn', 'alert', 'error')),
  type          text        NOT NULL DEFAULT 'log',
  title         text        NOT NULL DEFAULT 'Server',
  message       text        NOT NULL,
  player_name   text,
  player_id     text,
  meta          jsonb,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_logs_license_created ON logs (license_key, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_logs_level ON logs (license_key, level);

-- ============================================================
-- detections
-- ============================================================
CREATE TABLE IF NOT EXISTS detections (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  license_key     text        NOT NULL REFERENCES licenses(license_key) ON DELETE CASCADE,
  player_name     text        NOT NULL DEFAULT 'Unknown',
  player_id       text        NOT NULL,
  identifiers     text[]      NOT NULL DEFAULT '{}',
  detection_type  text        NOT NULL,
  details         text,
  action_taken    text        NOT NULL DEFAULT 'alert'
                              CHECK (action_taken IN ('alert', 'ban', 'kick', 'warn')),
  ban_id          text        REFERENCES bans(ban_id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_detections_license_created ON detections (license_key, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_detections_player_id ON detections (player_id);
CREATE INDEX IF NOT EXISTS idx_detections_type ON detections (license_key, detection_type);

-- ============================================================
-- server_status
-- ============================================================
CREATE TABLE IF NOT EXISTS server_status (
  license_key   text        PRIMARY KEY REFERENCES licenses(license_key) ON DELETE CASCADE,
  online        boolean     NOT NULL DEFAULT false,
  player_count  integer     NOT NULL DEFAULT 0,
  max_players   integer     NOT NULL DEFAULT 64,
  version       text,
  uptime        bigint      NOT NULL DEFAULT 0,
  last_seen     timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- check_player_banned function
-- ============================================================
CREATE OR REPLACE FUNCTION check_player_banned(
  p_license_key  text,
  p_identifiers  text[]
)
RETURNS TABLE (
  ban_id       text,
  player_name  text,
  reason       text,
  banned_by    text,
  expires_at   timestamptz
)
LANGUAGE sql STABLE AS $$
  SELECT ban_id, player_name, reason, banned_by, expires_at
  FROM bans
  WHERE license_key = p_license_key
    AND active = true
    AND (expires_at IS NULL OR expires_at > now())
    AND identifiers && p_identifiers
  LIMIT 1;
$$;

-- ============================================================
-- Views
-- ============================================================
CREATE OR REPLACE VIEW server_overview AS
  SELECT
    l.license_key,
    l.status      AS license_status,
    l.plan,
    l.server_name,
    l.expires_at  AS license_expires_at,
    l.last_seen   AS license_last_seen,
    ss.online,
    ss.player_count,
    ss.max_players,
    ss.version,
    ss.uptime,
    ss.last_seen  AS server_last_seen,
    (SELECT count(*) FROM bans b
      WHERE b.license_key = l.license_key
        AND b.active = true
        AND (b.expires_at IS NULL OR b.expires_at > now())
    ) AS active_bans,
    (SELECT count(*) FROM logs lg
      WHERE lg.license_key = l.license_key
        AND lg.created_at > now() - interval '24 hours'
    ) AS logs_24h,
    (SELECT count(*) FROM detections d
      WHERE d.license_key = l.license_key
        AND d.created_at > now() - interval '24 hours'
    ) AS detections_24h
  FROM licenses l
  LEFT JOIN server_status ss ON ss.license_key = l.license_key;
