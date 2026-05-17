# GhostGuard — Deploy Guide

## Arkitektur

| Vad                                            | Var                                   |
|-----------------------------------------------|---------------------------------------|
| Landing + om-oss + pricing + faq + terms etc  | `ghostguardac.se` (FTP via labbet.se) |
| Backend API + admin + customer dashboard      | `panel.ghostguardac.se` (Railway)     |
| PostgreSQL                                     | Railway managed                       |
| FiveM anticheat-resurs                         | Kundens FiveM-server                  |

**Login-flöde:** Kund går till `ghostguardac.se` → klickar Sign in → form postar till `panel.ghostguardac.se/api/login` → vid success redirectas till `panel.ghostguardac.se/dashboard?token=...&license_key=...` → dashboarden plockar upp token från URL och sparar i localStorage.

## Innehåll i detta repo

```
.
├── index.js                        # Backend (Express + pg)
├── package.json
├── schema.sql                      # PostgreSQL-schema (körs automatiskt)
├── Procfile                        # Railway start command
├── admin.html                      # Serveras på /admin
├── dashboard.html                  # Serveras på /dashboard
├── download/
│   └── GhostGuard-Anticheat.zip    # Serveras på /download/...
└── GhostGuard-Anticheat/           # FiveM-resurs (källkod)
```

---

## 1. Railway-setup

### a) Skapa projekt
1. Gå till https://railway.app → New Project → Deploy from GitHub repo
2. Välj `realghost120/ghostguard-hemisda`
3. Railway kör `npm install` + `npm start` automatiskt

### b) PostgreSQL
- "+ New" → Database → PostgreSQL
- `DATABASE_URL` sätts automatiskt

### c) Schemat körs automatiskt
Backend kör `schema.sql` vid uppstart (idempotent — `CREATE IF NOT EXISTS`).

### d) Environment variables

| Variabel              | Värde                                       |
|----------------------|---------------------------------------------|
| `DATABASE_URL`       | (automatisk)                                |
| `LICENSE_SECRET`     | Slumpmässig hex (32+ tecken)                |
| `ADMIN_SECRET`       | Slumpmässig hex (32+ tecken)                |
| `PUBLIC_URL`         | `https://panel.ghostguardac.se`             |
| `DASHBOARD_ORIGIN`   | `https://ghostguardac.se` (CORS-lås)        |

Generera secret (PowerShell):
```powershell
-join ((1..32) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
```

### e) Custom domain
1. Railway → Settings → Networking → Add Custom Domain
2. Lägg till `panel.ghostguardac.se`
3. DNS hos labbet.se: skapa CNAME för `panel` → Railways angivna värde

---

## 2. labbet.se-FTP (ghostguardac.se)

**Ta bort** från FTP:n:
- `admin.html` (gamla statiska — nya ligger på Railway)
- `dashboard.html` (gamla statiska — nya ligger på Railway)

**Behåll** på FTP:n:
- `index.html` (landing)
- `about-us/`, `pricing/`, `faq/`, `terms/`, `refund/`, `security/`, `License/`, `download/`, `preview.png`
- `.htaccess`, `.well-known/`, `.ftpquota` (server-konfig)

I `index.html` på FTP:n: konstanten `API` ska peka mot `https://panel.ghostguardac.se`.

---

## 3. FiveM-resursen

Distribueras via `https://panel.ghostguardac.se/download/GhostGuard-Anticheat.zip`.

Kund:
1. Laddar ner zippen
2. Extraherar till `resources/GhostGuard-Anticheat`
3. `ensure GhostGuard-Anticheat` i `server.cfg`
4. Sätter `LicenseKey` i `config.lua`

---

## 4. Endpoints

| Route                                       | Beskrivning                            |
|--------------------------------------------|----------------------------------------|
| `GET  /health`                              | Health JSON                            |
| `GET  /admin`                               | Admin-panel (HTML)                     |
| `GET  /dashboard`                           | Kund-dashboard (HTML)                  |
| `GET  /download/GhostGuard-Anticheat.zip`   | FiveM-resurs                           |
| `GET  /version`                             | Version + download-länk                |
| `POST /api/license/verify`                  | FiveM licensvalidering                 |
| `POST /api/server/ban`                      | Registrera ban                         |
| `GET  /api/server/ban/evidence/:banId`      | Hämta bevisbild                        |
| `POST /api/server/heartbeat`                | Server keep-alive                      |
| `POST /api/login`                           | Kund-login                             |

Admin-endpoints kräver `Authorization: Bearer <ADMIN_SECRET>`.
