import express from "express";
import crypto from "crypto";
import cors from "cors";
import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";
import pg from "pg";

const { Pool } = pg;
const __dirname = path.dirname(fileURLToPath(import.meta.url));

console.log("GhostGuard backend starting...");
const app = express();

/* ================= CONFIG ================= */
const PORT = process.env.PORT || 3000;
const DATABASE_URL = process.env.DATABASE_URL;
const LICENSE_SECRET = process.env.LICENSE_SECRET || "change_me";
const PUBLIC_URL = process.env.PUBLIC_URL || "";
const DASHBOARD_ORIGIN = process.env.DASHBOARD_ORIGIN || null;

const DISCORD_CLIENT_ID = process.env.DISCORD_CLIENT_ID || "";
const DISCORD_CLIENT_SECRET = process.env.DISCORD_CLIENT_SECRET || "";
const ADMIN_DISCORD_IDS = (process.env.ADMIN_DISCORD_IDS || "").split(",").map(s => s.trim()).filter(Boolean);

function discordRedirectUri(req) {
  const proto = req.headers["x-forwarded-proto"] || req.protocol || "https";
  const host = req.headers["x-forwarded-host"] || req.headers.host;
  return `${proto}://${host}/auth/discord/callback`;
}
const SESSION_SECRET = process.env.SESSION_SECRET || LICENSE_SECRET;
const SESSION_MAX_AGE_MS = 1000 * 60 * 60 * 24 * 30;

if (!DATABASE_URL) {
  console.warn("Missing DATABASE_URL. API will fail on DB calls.");
}

const pool = new Pool({
  connectionString: DATABASE_URL,
  ssl: DATABASE_URL && DATABASE_URL.includes("railway") ? { rejectUnauthorized: false } : false,
});

async function q(sql, params = []) {
  const res = await pool.query(sql, params);
  return res.rows;
}
async function qOne(sql, params = []) {
  const rows = await q(sql, params);
  return rows[0] || null;
}

async function runMigrations() {
  if (!DATABASE_URL) {
    console.warn("Skipping migrations: no DATABASE_URL");
    return;
  }
  const schemaPath = path.join(__dirname, "schema.sql");
  if (!fs.existsSync(schemaPath)) {
    console.warn("Skipping migrations: schema.sql not found");
    return;
  }
  const sql = fs.readFileSync(schemaPath, "utf8");
  try {
    await pool.query(sql);
    console.log("✓ Migrations applied");
  } catch (err) {
    console.error("Migration error:", err.message);
  }
}

/* ================= MIDDLEWARE ================= */
app.use(express.json({ limit: "15mb" }));

const corsOptions = {
  origin: DASHBOARD_ORIGIN ? [DASHBOARD_ORIGIN] : true,
  credentials: false,
  methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization"],
};
app.use(cors(corsOptions));
app.options("*", cors(corsOptions));

/* ================= HELPERS ================= */
function sha256(str) {
  return crypto.createHash("sha256").update(str).digest("hex");
}

function signSession(payload) {
  const data = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const sig = crypto.createHmac("sha256", SESSION_SECRET).update(data).digest("base64url");
  return `${data}.${sig}`;
}
function verifySession(cookieValue) {
  if (!cookieValue || !cookieValue.includes(".")) return null;
  const [data, sig] = cookieValue.split(".");
  const expected = crypto.createHmac("sha256", SESSION_SECRET).update(data).digest("base64url");
  if (sig !== expected) return null;
  try {
    const payload = JSON.parse(Buffer.from(data, "base64url").toString("utf8"));
    if (!payload.exp || payload.exp < Date.now()) return null;
    return payload;
  } catch { return null; }
}
function parseCookies(req) {
  const header = req.headers.cookie || "";
  const out = {};
  header.split(";").forEach(part => {
    const i = part.indexOf("=");
    if (i > -1) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  });
  return out;
}
function setSessionCookie(res, value) {
  const attrs = [
    `gg_admin=${value}`,
    `Max-Age=${Math.floor(SESSION_MAX_AGE_MS / 1000)}`,
    "Path=/",
    "HttpOnly",
    "Secure",
    "SameSite=Lax",
  ];
  res.setHeader("Set-Cookie", attrs.join("; "));
}
function clearSessionCookie(res) {
  res.setHeader("Set-Cookie", "gg_admin=; Max-Age=0; Path=/; HttpOnly; Secure; SameSite=Lax");
}

function requireAdmin(req, res) {
  const cookies = parseCookies(req);
  const session = verifySession(cookies.gg_admin);
  if (session && ADMIN_DISCORD_IDS.includes(session.discord_id)) {
    req.admin = session;
    return true;
  }
  res.status(401).json({ success: false, error: "UNAUTHORIZED" });
  return false;
}

function generateLicenseKey() {
  const part = () => crypto.randomBytes(2).toString("hex").toUpperCase();
  return `GG-${part()}-${part()}`;
}

function computeExpiresAt(duration, explicitExpiresAt) {
  if (explicitExpiresAt) {
    const parsed = new Date(explicitExpiresAt);
    if (Number.isNaN(parsed.getTime())) return null;
    return parsed.toISOString();
  }
  const raw = String(duration || "P").trim().toLowerCase();
  if (raw === "p" || raw === "perm" || raw === "permanent") return null;
  const match = raw.match(/^(\d+)([mhd])$/);
  if (!match) return null;
  const amount = Number(match[1]);
  const unit = match[2];
  const ms = unit === "m" ? amount * 60_000 : unit === "h" ? amount * 3_600_000 : amount * 86_400_000;
  return new Date(Date.now() + ms).toISOString();
}

function normalizeDuration(duration) {
  const raw = String(duration || "P").trim().toLowerCase();
  if (raw === "p" || raw === "perm" || raw === "permanent") return { ok: true, value: "P" };
  const match = raw.match(/^(\d+)([mhd])$/);
  if (!match) return { ok: false, value: null };
  const amount = Number(match[1]);
  if (!Number.isFinite(amount) || amount <= 0) return { ok: false, value: null };
  return { ok: true, value: `${amount}${match[2]}` };
}

function normalizeIdentifiers(value) {
  if (!Array.isArray(value)) return [];
  const cleaned = value.map((x) => String(x || "").trim()).filter(Boolean);
  return [...new Set(cleaned)];
}

function extractDataUriParts(imageData) {
  const m = String(imageData || "").match(/^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/);
  if (!m) return null;
  return { mime: m[1], base64: m[2] };
}

async function resolvePanelIdentity(token) {
  if (!token) return null;
  const user = await qOne("SELECT * FROM customers WHERE id = $1", [token]);
  if (user) return { kind: "customer", license_key: user.license_key, user };
  return null;
}

/* ================= DISCORD OAUTH2 (admin) ================= */
app.get("/auth/discord", (req, res) => {
  if (!DISCORD_CLIENT_ID) return res.status(500).send("Discord OAuth not configured");
  const params = new URLSearchParams({
    client_id: DISCORD_CLIENT_ID,
    redirect_uri: discordRedirectUri(req),
    response_type: "code",
    scope: "identify",
  });
  res.redirect(`https://discord.com/api/oauth2/authorize?${params}`);
});

app.get("/auth/discord/callback", async (req, res) => {
  try {
    const code = req.query.code;
    if (!code) return res.status(400).send("Missing code");

    const tokenRes = await fetch("https://discord.com/api/oauth2/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: DISCORD_CLIENT_ID,
        client_secret: DISCORD_CLIENT_SECRET,
        grant_type: "authorization_code",
        code: String(code),
        redirect_uri: discordRedirectUri(req),
      }),
    });
    const tokenData = await tokenRes.json();
    if (!tokenData.access_token) {
      console.error("Discord token exchange failed:", tokenData);
      return res.status(401).send("Discord auth failed");
    }

    const userRes = await fetch("https://discord.com/api/users/@me", {
      headers: { Authorization: `Bearer ${tokenData.access_token}` },
    });
    const user = await userRes.json();
    if (!user.id) return res.status(401).send("Could not fetch Discord user");

    if (!ADMIN_DISCORD_IDS.includes(user.id)) {
      return res.status(403).send(`Access denied. Discord ID ${user.id} är inte admin.`);
    }

    const payload = {
      discord_id: user.id,
      username: user.username,
      avatar: user.avatar,
      iat: Date.now(),
      exp: Date.now() + SESSION_MAX_AGE_MS,
    };
    setSessionCookie(res, signSession(payload));
    res.redirect("/admin");
  } catch (e) {
    console.error("Discord callback error:", e);
    res.status(500).send("Server error");
  }
});

app.post("/auth/logout", (_req, res) => {
  clearSessionCookie(res);
  res.json({ success: true });
});

app.get("/admin/me", (req, res) => {
  const cookies = parseCookies(req);
  const session = verifySession(cookies.gg_admin);
  if (!session || !ADMIN_DISCORD_IDS.includes(session.discord_id)) {
    return res.status(401).json({ success: false });
  }
  res.json({
    success: true,
    user: {
      discord_id: session.discord_id,
      username: session.username,
      avatar: session.avatar,
    },
  });
});

/* ================= STATIC FILES ================= */
app.get("/admin", (_req, res) => res.sendFile(path.join(__dirname, "admin.html")));
app.get("/dashboard", (_req, res) => res.sendFile(path.join(__dirname, "dashboard.html")));

app.use("/download", express.static(path.join(__dirname, "download")));

/* ================= ROOT ================= */
app.get("/", (_req, res) => res.send("GhostGuard Backend OK"));
app.get("/health", (_req, res) => res.json({ ok: true, ts: Date.now() }));

/* ================= LICENSE VERIFY ================= */
app.post("/api/license/verify", async (req, res) => {
  try {
    const { license_key, hwid } = req.body || {};
    if (!license_key) return res.status(400).json({ valid: false, reason: "MISSING_KEY" });

    const lic = await qOne("SELECT * FROM licenses WHERE license_key = $1", [license_key]);
    if (!lic) return res.json({ valid: false, reason: "NOT_FOUND" });
    if (lic.status !== "ACTIVE") return res.json({ valid: false, reason: lic.status });

    if (lic.expires_at && new Date(lic.expires_at) < new Date()) {
      return res.json({ valid: false, reason: "EXPIRED" });
    }

    if (lic.hwid) {
      if (hwid && lic.hwid !== hwid) return res.json({ valid: false, reason: "HWID_MISMATCH" });
    } else if (hwid) {
      await q("UPDATE licenses SET hwid = $1 WHERE id = $2", [hwid, lic.id]);
    }

    await q("UPDATE licenses SET last_seen = now() WHERE id = $1", [lic.id]);

    const payload = JSON.stringify({
      license_key,
      status: lic.status,
      expires_at: lic.expires_at,
      issued_at: Date.now(),
    });
    const signature = crypto.createHmac("sha256", LICENSE_SECRET).update(payload).digest("hex");

    return res.json({ valid: true, payload, signature });
  } catch (err) {
    console.error("verify error:", err);
    return res.status(500).json({ valid: false, reason: "SERVER_ERROR" });
  }
});

/* ================= BANS ================= */
app.post("/api/server/ban", async (req, res) => {
  try {
    const {
      license_key, player, player_name, identifiers, reason,
      duration, banned_by, ban_id, created_at, expires_at,
    } = req.body || {};

    if (!license_key || !player) {
      return res.status(400).json({ success: false, error: "MISSING_FIELDS" });
    }

    const durationInfo = normalizeDuration(duration || "P");
    if (!durationInfo.ok) return res.status(400).json({ success: false, error: "INVALID_DURATION" });

    const finalBanId = ban_id || ("GG-" + Date.now());
    const finalCreated = created_at ? new Date(created_at).toISOString() : new Date().toISOString();
    const finalExpires = computeExpiresAt(durationInfo.value, expires_at);

    await q(
      `INSERT INTO bans (ban_id, license_key, player_id, player_name, identifiers, reason, duration, banned_by, active, created_at, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true, $9, $10)`,
      [
        finalBanId, license_key, String(player), player_name || null,
        normalizeIdentifiers(identifiers), reason || "No reason",
        durationInfo.value, banned_by || "GhostGuard(Auto)",
        finalCreated, finalExpires,
      ]
    );

    return res.json({ success: true, ban_id: finalBanId });
  } catch (e) {
    console.error("BAN ERROR:", e);
    return res.status(500).json({ success: false });
  }
});

app.get("/api/server/bans/:license", async (req, res) => {
  try {
    const data = await q(
      "SELECT ban_id, license_key, player_id, player_name, identifiers, reason, duration, banned_by, evidence_url, active, expires_at, unbanned_at, unbanned_by, created_at FROM bans WHERE license_key = $1 ORDER BY created_at DESC",
      [req.params.license]
    );
    res.json({ success: true, bans: data });
  } catch (e) {
    console.error(e);
    res.status(500).json({ success: false });
  }
});

app.post("/api/server/ban/check", async (req, res) => {
  try {
    const { license_key, identifiers } = req.body || {};
    if (!license_key) return res.status(400).json({ success: false, error: "MISSING_LICENSE" });

    const ids = normalizeIdentifiers(identifiers);
    if (ids.length === 0) return res.json({ success: true, banned: false });

    const rows = await q("SELECT * FROM check_player_banned($1, $2)", [license_key, ids]);
    if (rows.length > 0) return res.json({ success: true, banned: true, ban: rows[0] });
    return res.json({ success: true, banned: false });
  } catch (e) {
    console.error("ban/check error:", e);
    return res.status(500).json({ success: false });
  }
});

app.delete("/api/server/unban/:banId", async (req, res) => {
  try {
    const { banId } = req.params;
    const bearer = req.headers.authorization || "";
    const token = bearer.startsWith("Bearer ") ? bearer.slice(7) : null;
    const identity = await resolvePanelIdentity(token);
    if (!identity) return res.status(401).json({ success: false, error: "UNAUTHORIZED" });

    const ban = await qOne("SELECT * FROM bans WHERE ban_id = $1", [banId]);
    if (!ban) return res.json({ success: false });
    if (ban.license_key !== identity.license_key) {
      return res.status(403).json({ success: false, error: "FORBIDDEN" });
    }

    const unbannedBy = identity.user.username;
    await q(
      "UPDATE bans SET active = false, unbanned_at = now(), unbanned_by = $1 WHERE ban_id = $2",
      [unbannedBy, banId]
    );

    pushAction(ban.license_key, {
      id: "ACT-" + Date.now(),
      type: "unban",
      payload: { ban_id: banId },
      created_at: new Date().toISOString(),
    });

    return res.json({ success: true });
  } catch (e) {
    console.error("UNBAN ERROR:", e);
    return res.status(500).json({ success: false });
  }
});

app.post("/api/server/unban", async (req, res) => {
  try {
    const { license_key, ban_id, unbanned_by } = req.body || {};
    if (!license_key || !ban_id) return res.status(400).json({ success: false, error: "MISSING_FIELDS" });

    const lic = await qOne(
      "SELECT license_key FROM licenses WHERE license_key = $1 AND status = 'ACTIVE'",
      [license_key]
    );
    if (!lic) return res.status(401).json({ success: false, error: "INVALID_LICENSE" });

    const ban = await qOne(
      "SELECT ban_id FROM bans WHERE ban_id = $1 AND license_key = $2",
      [ban_id, license_key]
    );
    if (!ban) return res.json({ success: false, error: "BAN_NOT_FOUND" });

    await q(
      "UPDATE bans SET active = false, unbanned_at = now(), unbanned_by = $1 WHERE ban_id = $2",
      [unbanned_by || "In-Game Admin", ban_id]
    );
    return res.json({ success: true });
  } catch (e) {
    console.error("server/unban error:", e);
    return res.status(500).json({ success: false });
  }
});

app.delete("/api/server/ban/:banId", async (req, res) => {
  try {
    await q("UPDATE bans SET expires_at = now() WHERE ban_id = $1", [req.params.banId]);
    return res.json({ success: true });
  } catch (e) {
    console.error("UNBAN LEGACY ERROR:", e);
    return res.status(500).json({ success: false });
  }
});

/* ================= BAN EVIDENCE (lagras som bytea i DB) ================= */
app.post("/api/server/ban/evidence", async (req, res) => {
  try {
    const { license_key, ban_id, image_data } = req.body || {};
    if (!license_key || !ban_id || !image_data) return res.status(400).json({ success: false });

    const parsed = extractDataUriParts(image_data);
    if (!parsed) return res.status(400).json({ success: false });

    const binary = Buffer.from(parsed.base64, "base64");
    const publicUrl = (PUBLIC_URL ? PUBLIC_URL.replace(/\/$/, "") : "") + `/api/server/ban/evidence/${ban_id}`;

    await q(
      "UPDATE bans SET evidence = $1, evidence_mime = $2, evidence_url = $3 WHERE ban_id = $4 AND license_key = $5",
      [binary, parsed.mime, publicUrl, ban_id, license_key]
    );

    res.json({ success: true, url: publicUrl });
  } catch (e) {
    console.error(e);
    res.status(500).json({ success: false });
  }
});

app.get("/api/server/ban/evidence/:banId", async (req, res) => {
  try {
    const row = await qOne(
      "SELECT evidence, evidence_mime FROM bans WHERE ban_id = $1",
      [req.params.banId]
    );
    if (!row || !row.evidence) return res.status(404).send("Not found");
    res.setHeader("Content-Type", row.evidence_mime || "image/png");
    res.setHeader("Cache-Control", "public, max-age=3600");
    res.send(row.evidence);
  } catch (e) {
    console.error("evidence get error:", e);
    res.status(500).send("error");
  }
});

/* ================= LIVE MEMORY (status + players) ================= */
const serverState = {};
const livePlayersByLicense = {};

app.post("/api/server/heartbeat", async (req, res) => {
  try {
    const { license_key, players, version, uptime } = req.body || {};
    if (!license_key) return res.status(400).json({ success: false, error: "MISSING_LICENSE" });

    livePlayersByLicense[license_key] = Array.isArray(players) ? players : [];
    serverState[license_key] = {
      last_seen: Date.now(),
      players: livePlayersByLicense[license_key].length,
      uptime: Number(uptime || 0),
      version: version || null,
    };

    try {
      await q(
        `INSERT INTO server_status (license_key, online, player_count, version, uptime, last_seen)
         VALUES ($1, true, $2, $3, $4, now())
         ON CONFLICT (license_key) DO UPDATE
         SET online = EXCLUDED.online, player_count = EXCLUDED.player_count,
             version = EXCLUDED.version, uptime = EXCLUDED.uptime, last_seen = EXCLUDED.last_seen`,
        [license_key, livePlayersByLicense[license_key].length, version || null, Number(uptime || 0)]
      );
    } catch (_) {}

    return res.json({ success: true });
  } catch (e) {
    console.error("heartbeat error:", e);
    return res.status(500).json({ success: false });
  }
});

app.get("/api/server/players/:license", (req, res) => {
  res.json({ success: true, players: livePlayersByLicense[req.params.license] || [] });
});

app.get("/api/server/status/:license", (req, res) => {
  const data = serverState[req.params.license];
  if (!data) return res.json({ online: false, players: 0, uptime: 0, version: null });
  const online = Date.now() - data.last_seen < 30000;
  return res.json({
    online,
    players: data.players || 0,
    uptime: data.uptime || 0,
    version: data.version || null,
    last_seen: data.last_seen,
  });
});

/* ================= ACTION QUEUE ================= */
const actionQueue = {};
function pushAction(license_key, action) {
  actionQueue[license_key] = actionQueue[license_key] || [];
  actionQueue[license_key].push(action);
  if (actionQueue[license_key].length > 200) actionQueue[license_key].splice(0, 50);
}

app.post("/api/dashboard/action", async (req, res) => {
  try {
    const { token, type, payload } = req.body || {};
    if (!token || !type) return res.status(400).json({ success: false, error: "MISSING_FIELDS" });

    const identity = await resolvePanelIdentity(token);
    if (!identity) return res.status(401).json({ success: false, error: "UNAUTHORIZED" });

    const id = "ACT-" + Date.now() + "-" + Math.floor(Math.random() * 9999);
    pushAction(identity.license_key, {
      id, type, payload: payload || {}, created_at: new Date().toISOString(),
    });
    return res.json({ success: true, id });
  } catch (e) {
    console.error("dashboard/action error:", e);
    return res.status(500).json({ success: false });
  }
});

app.get("/api/server/actions/:license", (req, res) => {
  const license_key = req.params.license;
  const list = actionQueue[license_key] || [];
  actionQueue[license_key] = [];
  return res.json({ success: true, actions: list });
});

/* ================= LOGS ================= */
const serverLogs = {};
function pushServerLog(license_key, item) {
  serverLogs[license_key] = serverLogs[license_key] || [];
  serverLogs[license_key].unshift(item);
  if (serverLogs[license_key].length > 300) serverLogs[license_key].length = 300;
}

app.post("/api/server/log", async (req, res) => {
  try {
    const { license_key, level, type, title, message, meta } = req.body || {};
    if (!license_key || !message) {
      return res.status(400).json({ success: false, error: "MISSING_LICENSE_OR_MESSAGE" });
    }

    const resolvedLevel = level || "info";
    const resolvedType = type || "log";
    const playerName = meta?.name || null;
    const playerId = meta?.server_id != null ? String(meta.server_id) : null;

    const item = {
      id: "LOG-" + Date.now() + "-" + Math.floor(Math.random() * 9999),
      time: new Date().toISOString(),
      level: resolvedLevel,
      type: resolvedType,
      title: title || "Server",
      message,
      meta: meta || null,
    };
    pushServerLog(license_key, item);

    try {
      await q(
        `INSERT INTO logs (license_key, level, type, title, message, player_name, player_id, meta)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [license_key, resolvedLevel, resolvedType, item.title, item.message, playerName, playerId, meta || null]
      );
    } catch (_) {}

    if (resolvedLevel === "alert" && playerId) {
      const identifiersRaw = meta?.identifiers ? Object.values(meta.identifiers).filter(Boolean) : [];
      try {
        await q(
          `INSERT INTO detections (license_key, player_name, player_id, identifiers, detection_type, details, action_taken)
           VALUES ($1, $2, $3, $4, $5, $6, 'alert')`,
          [license_key, playerName || "Unknown", playerId, identifiersRaw, resolvedType, message]
        );
      } catch (_) {}
    }

    return res.json({ success: true });
  } catch (e) {
    console.error("server/log error:", e);
    return res.status(500).json({ success: false });
  }
});

app.post("/api/server/detection", async (req, res) => {
  try {
    const {
      license_key, player_name, player_id, identifiers,
      detection_type, details, action_taken, ban_id,
    } = req.body || {};

    if (!license_key || !player_id || !detection_type) {
      return res.status(400).json({ success: false, error: "MISSING_FIELDS" });
    }

    await q(
      `INSERT INTO detections (license_key, player_name, player_id, identifiers, detection_type, details, action_taken, ban_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        license_key, player_name || "Unknown", String(player_id),
        normalizeIdentifiers(identifiers), detection_type,
        details || null, action_taken || "alert", ban_id || null,
      ]
    );
    return res.json({ success: true });
  } catch (e) {
    console.error("server/detection error:", e);
    return res.status(500).json({ success: false });
  }
});

app.get("/api/server/logs/:license", async (req, res) => {
  const license_key = req.params.license;
  const limit = Math.min(parseInt(req.query.limit || "200", 10), 500);

  try {
    const data = await q(
      `SELECT id, license_key, level, type, title, message, meta, created_at
       FROM logs WHERE license_key = $1
       ORDER BY created_at DESC LIMIT $2`,
      [license_key, limit]
    );
    const mapped = data.map((x) => ({
      id: x.id || "DB-" + x.created_at,
      time: x.created_at,
      level: x.level || "info",
      type: x.type || "log",
      title: x.title || "Server",
      message: x.message,
      meta: x.meta ?? null,
    }));
    return res.json({ success: true, data: mapped, logs: mapped });
  } catch (_) {
    const mem = (serverLogs[license_key] || []).slice(0, limit);
    return res.json({ success: true, data: mem, logs: mem });
  }
});

app.get("/api/server/detections/events/:license", async (req, res) => {
  try {
    const license_key = req.params.license;
    const limit = Math.min(parseInt(req.query.limit || "200", 10), 500);
    const data = await q(
      "SELECT * FROM detections WHERE license_key = $1 ORDER BY created_at DESC LIMIT $2",
      [license_key, limit]
    );
    return res.json({ success: true, data });
  } catch (e) {
    console.error("detections/events error:", e);
    return res.status(500).json({ success: false });
  }
});

/* ================= LOGIN ================= */
app.post("/api/login", async (req, res) => {
  try {
    const { username, password } = req.body || {};
    if (!username || !password) return res.json({ success: false });

    const hash = sha256(password);
    const user = await qOne(
      "SELECT * FROM customers WHERE username = $1 AND password = $2 AND active = true",
      [username, hash]
    );
    if (!user) return res.json({ success: false });
    return res.json({ success: true, license_key: user.license_key, token: user.id });
  } catch (err) {
    console.error("login error:", err);
    return res.status(500).json({ success: false });
  }
});

/* ================= CUSTOMER ================= */
app.post("/customer/dashboard", async (req, res) => {
  try {
    const { token } = req.body || {};
    if (!token) return res.status(401).json({ success: false });

    const user = await qOne("SELECT * FROM customers WHERE id = $1", [token]);
    if (!user) return res.status(401).json({ success: false });

    const lic = await qOne("SELECT * FROM licenses WHERE license_key = $1", [user.license_key]);
    if (!lic) return res.status(404).json({ success: false });

    return res.json({
      success: true,
      data: { license_key: lic.license_key, status: lic.status, expires_at: lic.expires_at },
    });
  } catch (err) {
    console.error("customer/dashboard error:", err);
    return res.status(500).json({ success: false });
  }
});

app.post("/customer/toggle", async (req, res) => {
  try {
    const { token, status } = req.body || {};
    if (!token || !status) return res.status(400).json({ success: false });

    const user = await qOne("SELECT * FROM customers WHERE id = $1", [token]);
    if (!user) return res.status(401).json({ success: false });

    await q("UPDATE licenses SET status = $1 WHERE license_key = $2", [status, user.license_key]);
    return res.json({ success: true });
  } catch (err) {
    console.error("customer/toggle error:", err);
    return res.status(500).json({ success: false });
  }
});

/* ================= ADMIN ================= */
app.post("/admin/create-license", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    const { days_valid, lifetime, duration } = req.body || {};

    let expires_at = null;
    let plan = "lifetime";

    if (duration === "lifetime" || lifetime) {
      expires_at = null;
      plan = "lifetime";
    } else {
      const days = Number(days_valid || duration);
      if (days > 0) {
        const d = new Date();
        d.setDate(d.getDate() + days);
        expires_at = d.toISOString();
        plan = days <= 31 ? "monthly" : "quarterly";
      }
    }

    const license_key = generateLicenseKey();
    await q(
      "INSERT INTO licenses (license_key, status, plan, expires_at, hwid) VALUES ($1, 'ACTIVE', $2, $3, NULL)",
      [license_key, plan, expires_at]
    );
    return res.json({ success: true, license_key });
  } catch (err) {
    console.error("admin/create-license error:", err);
    return res.status(500).json({ success: false });
  }
});

app.get("/admin/licenses", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    const data = await q("SELECT * FROM licenses ORDER BY created_at DESC");
    return res.json({ success: true, data });
  } catch (err) {
    console.error("admin/licenses error:", err);
    return res.status(500).json({ success: false });
  }
});

app.post("/admin/toggle-license", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    const { license_key, status } = req.body || {};
    if (!license_key || !status) return res.status(400).json({ success: false });
    await q("UPDATE licenses SET status = $1 WHERE license_key = $2", [status, license_key]);
    return res.json({ success: true });
  } catch (err) {
    console.error("admin/toggle-license error:", err);
    return res.status(500).json({ success: false });
  }
});

app.delete("/admin/delete-license/:license_key", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    const { license_key } = req.params;
    if (!license_key) return res.status(400).json({ success: false });

    await q("DELETE FROM customers WHERE license_key = $1", [license_key]);
    await q("DELETE FROM licenses WHERE license_key = $1", [license_key]);
    return res.json({ success: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ success: false });
  }
});

app.post("/admin/create-customer", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    const { username, password, license_key } = req.body || {};
    if (!username || !password || !license_key) {
      return res.status(400).json({ success: false, error: "MISSING_FIELDS" });
    }

    const lic = await qOne("SELECT * FROM licenses WHERE license_key = $1", [license_key]);
    if (!lic) return res.status(404).json({ success: false, error: "LICENSE_NOT_FOUND" });

    const password_hash = sha256(password);
    const customer = await qOne(
      "INSERT INTO customers (username, password, license_key) VALUES ($1, $2, $3) RETURNING *",
      [username, password_hash, license_key]
    );
    return res.json({ success: true, customer });
  } catch (err) {
    console.error("admin/create-customer error:", err);
    return res.status(500).json({ success: false });
  }
});

app.post("/admin/update-customer-password", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    const { id, new_password } = req.body || {};
    if (!id || !new_password) return res.status(400).json({ success: false });

    await q("UPDATE customers SET password = $1 WHERE id = $2", [sha256(new_password), id]);
    return res.json({ success: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ success: false });
  }
});

app.post("/admin/toggle-customer", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    const { id, active } = req.body;
    if (!id || typeof active !== "boolean") return res.status(400).json({ success: false });

    await q("UPDATE customers SET active = $1 WHERE id = $2", [active, id]);
    return res.json({ success: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ success: false });
  }
});

app.delete("/admin/delete-customer/:id", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    await q("DELETE FROM customers WHERE id = $1", [req.params.id]);
    return res.json({ success: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ success: false });
  }
});

app.get("/admin/customers", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    const data = await q("SELECT * FROM customers ORDER BY created_at DESC");
    return res.json({ success: true, data });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false });
  }
});

app.get("/version", (_req, res) => {
  res.json({
    version: "3.1.0",
    download: (PUBLIC_URL || "") + "/download/GhostGuard-Anticheat.zip",
    notes: "Stability improvements & detection optimizations",
  });
});

app.get("/admin/stats", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    const [tl, al, tc, ac, tb, ab] = await Promise.all([
      qOne("SELECT count(*)::int AS c FROM licenses"),
      qOne("SELECT count(*)::int AS c FROM licenses WHERE status = 'ACTIVE'"),
      qOne("SELECT count(*)::int AS c FROM customers"),
      qOne("SELECT count(*)::int AS c FROM customers WHERE active = true"),
      qOne("SELECT count(*)::int AS c FROM bans"),
      qOne("SELECT count(*)::int AS c FROM bans WHERE active = true"),
    ]);
    return res.json({
      success: true,
      stats: {
        totalLicenses: tl.c, activeLicenses: al.c,
        totalCustomers: tc.c, activeCustomers: ac.c,
        totalBans: tb.c, activeBans: ab.c,
      },
    });
  } catch (e) {
    console.error("admin/stats error:", e);
    return res.status(500).json({ success: false });
  }
});

app.get("/admin/bans", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    const data = await q(
      "SELECT ban_id, license_key, player_id, player_name, identifiers, reason, duration, banned_by, evidence_url, active, expires_at, unbanned_at, unbanned_by, created_at FROM bans ORDER BY created_at DESC LIMIT 500"
    );
    return res.json({ success: true, data });
  } catch (e) {
    console.error("admin/bans error:", e);
    return res.status(500).json({ success: false });
  }
});

app.post("/admin/unban", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    const { ban_id } = req.body || {};
    if (!ban_id) return res.status(400).json({ success: false, error: "MISSING_BAN_ID" });

    await q(
      "UPDATE bans SET active = false, unbanned_at = now(), unbanned_by = 'Admin Panel' WHERE ban_id = $1",
      [ban_id]
    );
    return res.json({ success: true });
  } catch (e) {
    console.error("admin/unban error:", e);
    return res.status(500).json({ success: false });
  }
});

app.get("/admin/servers", async (req, res) => {
  try {
    if (!requireAdmin(req, res)) return;
    const data = await q("SELECT * FROM server_overview");
    return res.json({ success: true, data });
  } catch (e) {
    console.error("admin/servers error:", e);
    return res.status(500).json({ success: false });
  }
});

/* ================= START ================= */
app.listen(PORT, async () => {
  console.log("GhostGuard backend running on", PORT);
  await runMigrations();
});
