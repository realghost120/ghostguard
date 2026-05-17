# GhostGuard — Deploy Guide

## Arkitektur

- **labbet.se** → endast `index.html` (landningssida)
- **Railway** → backend API + admin-panel + customer dashboard + PostgreSQL
- **FiveM-resurs** → ligger på kundens server, pekar mot Railway-domänen

---

## 1. Railway-setup

### a) Skapa projekt
1. Gå till https://railway.app → New Project → Deploy from GitHub repo
2. Välj `realghost120/ghostguard-hemisda`
3. Railway upptäcker Node.js automatiskt och kör `npm start`

### b) Lägg till PostgreSQL
1. I projektet → "+ New" → Database → PostgreSQL
2. Railway sätter automatiskt `DATABASE_URL` som env var

### c) Kör schemat
1. Öppna PostgreSQL i Railway → Query
2. Klistra in hela `schema.sql` och kör

### d) Sätt environment variables
I Railway → Variables, lägg till:

| Variabel              | Värde                                       |
|----------------------|---------------------------------------------|
| `DATABASE_URL`       | (automatisk från Railway PG)                |
| `LICENSE_SECRET`     | Slumpmässig hex-sträng (32+ tecken)         |
| `ADMIN_SECRET`       | Slumpmässig hex-sträng (32+ tecken)         |
| `PUBLIC_URL`         | `https://din-domän.se` (efter custom domain)|
| `DASHBOARD_ORIGIN`   | `https://labbet.se` (valfritt, CORS-lås)    |

Generera secrets med PowerShell:
```powershell
-join ((1..32) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
```

### e) Custom domain
1. Railway → Settings → Networking → Add Custom Domain
2. Lägg till `api.dindomän.se` (eller vad du vill)
3. Sätt CNAME hos din DNS-leverantör enligt Railway

---

## 2. Uppdatera URL:er i frontend & FiveM

Efter att Railway-domänen finns, kör i denna mapp:

```bash
# Byt ut placeholder mot din riktiga Railway-URL
grep -rl "api.ghostguardac.se" . | xargs sed -i 's|https://api.ghostguardac.se|https://DIN-RAILWAY-URL|g'
```

Filer som påverkas:
- `admin.html` — `API_BASE`
- `dashboard.html` — `API`
- `index.html` — `API`
- `GhostGuard-Anticheat/config.lua` — `Config.BackendURL`
- `GhostGuard-Anticheat/server/update.lua` — `VERSION_URL`

---

## 3. labbet.se (landningssida)

Ladda upp endast `index.html` + ev. `preview.png` till labbet.se via FTP/cPanel.

---

## 4. FiveM-resursen

`GhostGuard-Anticheat/`-mappen ska till **kundens** FiveM-server:
1. Kopiera mappen till `resources/`
2. Lägg `ensure GhostGuard-Anticheat` i `server.cfg`
3. Sätt rätt `LicenseKey` i `config.lua`

---

## 5. Endpoints (snabbreferens)

- `GET  /` → health check
- `GET  /admin` → admin-panel (HTML)
- `GET  /dashboard` → kund-dashboard (HTML)
- `POST /api/license/verify` → FiveM licensvalidering
- `POST /api/server/ban` → registrera ban
- `GET  /api/server/ban/evidence/:banId` → hämta bevisbild (bytea→stream)
- `POST /api/server/heartbeat` → server keep-alive
- Admin endpoints kräver `Authorization: Bearer <ADMIN_SECRET>`
