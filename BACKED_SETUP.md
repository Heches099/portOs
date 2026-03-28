# PortOS Backed Setup

`backed.py` is the FastAPI orchestration layer for this Flutter project.

## What it does

- Verifies Firebase ID tokens on admin-only API routes.
- Accepts hardware/event ingestion through a separate ingest key.
- Reads and writes terminal stats, AGVs, cranes, deliveries, camera feeds, and sensor readings in Firestore.
- Exposes aggregate dashboard and pie-analysis endpoints for the Flutter app.
- Writes audit log entries for admin data changes.

## Install

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-backend.txt
```

## Configure

1. Copy `.env.example` to `.env`.
2. Add your Firebase project values.
3. Download a Firebase service account JSON file and point `BACKED_FIREBASE_SERVICE_ACCOUNT_PATH` to it.
4. Add admin emails to `BACKED_ADMIN_EMAILS`.
5. Set a strong `BACKED_INGEST_API_KEY`.
6. In Firebase Auth, create operator accounts manually and give admin users a custom claim of `admin=true` or include their email in `BACKED_ADMIN_EMAILS`.

## Run

```bash
uvicorn backed:app --reload --host 0.0.0.0 --port 8000
```

## Firebase policy

- Self-service registration is disabled in the Flutter app.
- Password reset is allowed only for already registered Firebase emails.
- Verified email is required before the Flutter app grants live Firebase access.
- Backend admin APIs still require verified admin users, while `firestore.rules` and `storage.rules` currently allow verified Firebase operators.
