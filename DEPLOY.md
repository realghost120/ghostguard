# GhostGuard — Deploy Guide

## Arkitektur

- **labbet.se** → `index.html` + `preview.png` (endast landningssida, ligger utanför detta repo)
- **Railway** → backend API + admin-panel + customer dashboard + PostgreSQL + zip-download
- **FiveM-resurs** (`GhostGuard-Anticheat/`) → ligger på kundens server, pekar mot Railway-domänen

## Innehåll i repo

```
.
├── index.js                    # Backend (Express + pg)
├── package.json
├── schema.sql                  # PostgreSQL-schema
├── Procfile                    # Railway start command
├── admin.html                  # Serveras på /admin
├── dashboard.html              # Serveras på /dashboard
├── download/
│   └── GhostGuard-Anticheat.zip   # Serveras på /download/...
└── GhostGuard-Anticheat/       # FiveM-resurs (källkod)
```

---

## 1. Railway-setup

### a) Skapa projekt
1. Gå till https://railway.app → New Project → Deploy from GitHub repo
2. Välj `realghost120/ghostguard-hemisda`
3. Railway upptäcker Node.js automatiskt och kör `npm start`

### b) Lägg till PostgreSQL
1. I projektet → "+ New" → Database → PostgreSQL
2. Railway sätter automatiskt `DATABASE_URL` som env var

### c) Schemat körs automatiskt
Backend kör `schema.sql` vid uppstart (idempotent — `CREATE IF NOT EXISTS`).
Vid varje deploy applicerar Railway eventuella schemaändringar automatiskt.

### d) Sätt environment variables
I Railway → Variables:

| Variabel              | Värde                                       |
|----------------------|---------------------------------------------|
| `DATABASE_URL`       | (automatisk från Railway PG)                |
| `LICENSE_SECRET`     | Slumpmässig hex-sträng (32+ tecken)         |
| `ADMIN_SECRET`       | Slumpmässig hex-sträng (32+ tecken)         |
| `PUBLIC_URL`         | `https://din-domän.se` (efter custom domain)|
| `DASHBOARD_ORIGIN`   | `https://labbet.se` (CORS-lås)              |

Generera secret (PowerShell):
```powershell
-join ((1..32) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
```

### e) Custom domain
1. Railway → Settings → Networking → Add Custom Domain
2. Lägg till `api.dindomän.se`
3. Sätt CNAME hos DNS-leverantör enligt Railway

---

## 2. URL:er

Alla filer pekar mot `https://ghostguardac.se`:
- `admin.html` (API_BASE)
- `dashboard.html` (API)
- `GhostGuard-Anticheat/config.lua` (Config.BackendURL)
- `GhostGuard-Anticheat/server/update.lua` (VERSION_URL)
- `landing/index.html` på labbet.se (API-konstant)

Om domänen ändras: sök/ersätt `https://ghostguardac.se` i ovanstående filer.

---

## 3. labbet.se (landningssida)

`index.html` + `preview.png` ligger inte i detta repo. Ladda upp via FTP/cPanel till labbet.se.

I `index.html` ska konstanten `API` peka mot Railway-domänen.

---

## 4. FiveM-resursen

`GhostGuard-Anticheat/`-mappen distribueras till kunder via `/download/GhostGuard-Anticheat.zip`.

Kunden:
1. Laddar ner zippen
2. Extraherar till `resources/GhostGuard-Anticheat`
3. Lägger `ensure GhostGuard-Anticheat` i `server.cfg`
4. Sätter rätt `LicenseKey` i `config.lua`

---

## 5. Endpoints (snabbreferens)

| Route                                    | Beskrivning                            |
|-----------------------------------------|----------------------------------------|
| `GET  /`                                 | Health check                           |
| `GET  /health`                           | Health JSON                            |
| `GET  /admin`                            | Admin-panel (HTML)                     |
| `GET  /dashboard`                        | Kund-dashboard (HTML)                  |
| `GET  /download/GhostGuard-Anticheat.zip`| FiveM-resurs download                  |
| `GET  /version`                          | Version + download-länk                |
| `POST /api/license/verify`               | FiveM licensvalidering                 |
| `POST /api/server/ban`                   | Registrera ban                         |
| `GET  /api/server/ban/evidence/:banId`   | Hämta bevisbild (bytea→stream)         |
| `POST /api/server/heartbeat`             | Server keep-alive                      |
| `POST /api/login`                        | Kund-login                             |

Admin-endpoints kräver `Authorization: Bearer <ADMIN_SECRET>`.
