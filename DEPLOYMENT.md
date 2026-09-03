# PortOS Deployment Guide (Vercel + Render)

This project is split into two hosted services:

| Service | Host | What it is |
|---------|------|------------|
| Flutter web app | Vercel | Firebase Auth + reads live data straight from Firestore |
| FastAPI backend | Render | `/ai/ppe-detect` (YOLO PPE), orchestration, ingest |
| Firebase | Google | Auth + Firestore (single source of truth for live data) |

The Flutter frontend **never calls the FastAPI REST endpoints for dashboard data**.
It reads live data directly from Firestore (real-time). The FastAPI backend is
only used for PPE AI detection and data ingest/orchestration.

---

## 1. Render — FastAPI backend

### Manual setup (recommended)

1. Push this repo to GitHub and connect it to a new **Render Web Service**.
   - **Runtime:** Python
   - **Build command:**
     ```
     pip install -r requirements-backend.txt
     ```
   - **Start command:**
     ```
     uvicorn backed:app --host 0.0.0.0 --port $PORT
     ```
   - **Plan:** a paid plan is strongly recommended. The free tier is too slow
     for YOLO image inference (can hit the cold-start/request limits).

2. Add the following **Environment Variables** in Render:

   | Key | Value |
   |-----|-------|
   | `BACKED_FIREBASE_PROJECT_ID` | `portos-nextgen-harris-20260328` |
   | `BACKED_FIREBASE_STORAGE_BUCKET` | `portos-nextgen-harris-20260328.firebasestorage.app` |
   | `BACKED_FIREBASE_SERVICE_ACCOUNT_B64` | base64 of `firebase-service-account.json` (see below) |
   | `BACKED_ADMIN_EMAILS` | your admin emails, comma separated |
   | `BACKED_INGEST_API_KEY` | a long random secret |
   | `BACKED_CORS_ORIGINS` | `https://<your-vercel-app>.vercel.app` |

   > `firebase-service-account.json` is **gitignored** (it must never be
   > committed). That's why the base64 env-var is used instead.

   **Generate the base64 value** (POSIX / Git Bash):
   ```bash
   base64 -w0 firebase-service-account.json
   ```
   (Windows PowerShell alternative: `certutil -encode firebase-service-account.json sa.b64`, then paste the body minus the header/footer lines.)

3. Deploy. Render will automatically install the Python requirements and start
   Uvicorn.

### Blueprint (alternative)

A `render.yaml` is included at the repo root if you prefer blueprint-based
deploys. The env vars marked `sync: false` must be filled in once in the Render
dashboard after the first deploy.

---

## 2. Vercel — Flutter web app

Vercel builds the Flutter web app and serves the static output.

### Setup

1. In your repo, create/commit:
   - `vercel.json` (already in repo):
     ```json
     {
       "outputDirectory": "build/web",
       "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }]
     }
     ```
2. Configure **Project Settings → Environment Variables** in Vercel so the build
   can bake in the values. These map to the Flutter `--dart-define` flags:

   | Env var (Vercel) | `--dart-define` | Value |
   |------------------|-----------------|-------|
   | `FIREBASE_API_KEY` | `FIREBASE_API_KEY` | your web API key |
   | `FIREBASE_PROJECT_ID` | `FIREBASE_PROJECT_ID` | `portos-nextgen-harris-20260328` |
   | `FIREBASE_MESSAGING_SENDER_ID` | `FIREBASE_MESSAGING_SENDER_ID` | `877769589306` |
   | `FIREBASE_WEB_APP_ID` | `FIREBASE_WEB_APP_ID` | your web app id |
   | `FIREBASE_AUTH_DOMAIN` | `FIREBASE_AUTH_DOMAIN` | `portos-nextgen-harris-20260328.firebaseapp.com` |
   | `FIREBASE_STORAGE_BUCKET` | `FIREBASE_STORAGE_BUCKET` | `portos-nextgen-harris-20260328.firebasestorage.app` |
   | `PORT_API_BASE_URL` | `PORT_API_BASE_URL` | `https://<your-backend>.onrender.com` |

3. Set the **Build Command**:
   ```bash
   flutter build web \
     --dart-define=FIREBASE_API_KEY=$FIREBASE_API_KEY \
     --dart-define=FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID \
     --dart-define=FIREBASE_MESSAGING_SENDER_ID=$FIREBASE_MESSAGING_SENDER_ID \
     --dart-define=FIREBASE_WEB_APP_ID=$FIREBASE_WEB_APP_ID \
     --dart-define=FIREBASE_AUTH_DOMAIN=$FIREBASE_AUTH_DOMAIN \
     --dart-define=FIREBASE_STORAGE_BUCKET=$FIREBASE_STORAGE_BUCKET \
     --dart-define=PORT_API_BASE_URL=$PORT_API_BASE_URL
   ```
   > Vercel needs Flutter on the build image. Add a Vercel **Build Settings →
   > Install Command** (`fluttium`/Nix or a Docker build) or build locally and
   > drag-drop `build/web` via Vercel's static deploy if you can't get Flutter
   > on the CI image.

### Firebase authorized domains

In Firebase Console → Authentication → Settings → Authorized domains, add:
- `https://<your-vercel-app>.vercel.app`
- Your custom domain if you add one.

Otherwise Firebase Auth will reject sign-in from the hosted app
(`app-not-authorized` error).

---

## 3. Local development

```bash
# Terminal 1 — backend
.venv\Scripts\python.exe backed.py          # or: uvicorn backed:app --reload

# Terminal 2 — frontend (reads .env.local)
run_web_firebase.bat
```

`run_web_firebase.bat` / `run_web_firebase.sh` read `.env.local` (including
`PORT_API_BASE_URL`) and pass everything as `--dart-define` flags.

---

## Connection checklist

- [ ] Render env: `BACKED_FIREBASE_SERVICE_ACCOUNT_B64` set (or path works)
- [ ] Render env: `BACKED_CORS_ORIGINS` includes the Vercel origin
- [ ] Vercel env: all Firebase web defines set
- [ ] Vercel env: `PORT_API_BASE_URL` set to `https://<backend>.onrender.com`
- [ ] Firebase Auth authorized domains include the Vercel app origin
- [ ] Firestore collection data is present (`terminal_stats/current`, `agvs`, …)

### Verify after deploy

- Backend: open `https://<backend>.onrender.com/health` → `{"status":"ok", ...}`
- Frontend: sign in, dismiss any connection warnings, confirm the dashboard
  `FastAPI orchestration` row shows "configured API endpoint".
