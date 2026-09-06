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

## Realtime mode (real vs simulated)

The backend runs in one of two realtime modes, selected with `BACKED_REALTIME_MODE`
(default `live`; values: `live | simulate`):

| Mode        | Data source                          | WebSocket hub | Movement acks                 |
| ----------- | ------------------------------------ | ------------- | ----------------------------- |
| `live`      | Real ESP32 via the `/hw/*` proxy     | broadcasts telemetry + acks   | from `POST /hw/.../done`     |
| `simulate`  | Background simulator (dev/demo only) | broadcasts telemetry + acks   | auto-completed by simulator   |

- The Flutter side selects the matching client data source with
  `--dart-define=PORT_REALTIME_MODE=mock|websocket` (default `mock`).
- Start the simulator demo with: `BACKED_REALTIME_MODE=simulate uvicorn backed:app --port 8000`.
- Start real hardware: `BACKED_REALTIME_MODE=live` (the ESP8266/ESP32 keeps
  polling `GET /hw/command/{machine_id}` and posting `POST /hw/command/{machine_id}/done`).

### New realtime surface

- `GET /ws/machines` / `GET /ws/machines/{machine_id}` — WebSocket fan-out of
  `telemetry`, `command_ack`, and `machine_event` frames (subscribe with
  `{"type":"subscribe","machine_ids":[...]}`, heartbeat with `{"type":"ping"}`).
- `POST /machines/{machine_id}/command` — now accepts the distance-first
  structured envelope in addition to the legacy shape
  (`command`, `direction`, `distance_mm`, `speed_mps`, `duration_ms`, `steps`,
  plus legacy `speed`/`duration`). `emergency_stop` is handled server-side and
  blocks movement until the machine is re-commanded.
- `GET /machines/{machine_id}/camera` — camera registry for the machine
  (`stream_url == null` means the native device camera is used).
- Movement is distance-first; time fields are treated purely as watchdog /
  expiry windows. The low-level AGV/crane protocol is unchanged.

## Firebase policy

- Self-service registration is disabled in the Flutter app.
- Password reset is allowed only for already registered Firebase emails.
- Verified email is required before the Flutter app grants live Firebase access.
- Backend admin APIs still require verified admin users, while `firestore.rules` and `storage.rules` currently allow verified Firebase operators.
