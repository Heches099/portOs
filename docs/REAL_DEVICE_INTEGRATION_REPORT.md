# PortOS — Real Device Integration: Final Acceptance Report

**Date:** 2026-09-06
**Host:** Windows 11 desktop, no GPU (CPU-only), repo `C:\Users\HECHES\Desktop\Hamis\port0s_recervry\PortOs`
**Runtime:** Python 3.13.14 (`.venv`), torch 2.13.0+cpu, ultralytics 8.4.137, fastapi 0.141.1, uvicorn 0.52.4, opencv-python 5.0.0.93, httpx + websockets (test client), Flutter web build (Chrome WASM dry-run ok).

**Acceptance result: `e2e_acceptance.py --mode both` → 41/41 checks passed, 0 failed.**

---

## 1. REAL vs SIMULATED vs NOT AVAILABLE

| Surface | Verdict | Evidence |
|---|---|---|
| YOLO PPE inference (`ai_engine/models/best.pt`, classes `0:helmet 1:head 2:vest`) | **REAL** | `GET /system/status` reports `ppe_model=ready`; `POST /ai/ppe-detect` returns real detections (model loads ~0.23s, CPU predict ~0.36s). No stub. |
| Camera frame proxy (`GET /machines/{id}/camera/frame`) | **REAL (server seam)** | File source served as `image/jpeg` (5932 bytes) through FastAPI in both simulate and live modes; HTTP/MJPEG source supported server-side. |
| Live-telemetry honesty (`battery_percent`, `temperature_c`) | **REAL** | LIVE mode broadcasts `null` until the ESP32 reports; simulate mode serves demo values and flags `simulated=true`. Verified over WebSocket in both modes. |
| ESP32 wire protocol (`/hw/status`, `/hw/estop`, `/hw/command/*`) | **REAL (wire seam)** | `POST /hw/status/1` → `feedback_source=measured`, battery 76.5, temp 49.3, encoder 250.0 reflected in telemetry. Hardware E-STOP latch **and release** reflected. Commissioning preflight passes only on measured encoder + fresh heartbeat. |
| E-STOP hardware path | **REAL (logic)** | Latch (`estop_input:true` / `POST /hw/estop/{id}`), telemetry `state=estop`, movement blocked HTTP 409, release (`estop_input:false`), re-arm, movement allowed. |
| Distance-first movement + commissioning cap (live) | **REAL (logic)** | Live starts BLOCKED (0 mm); moves capped at the approved allowance (409); advances 0→10→25→50→100 mm; movement accepted when ≤ cap. |
| WebSocket fan-out + machine identity enforcement | **REAL** | Commands targeting machine 2 while claiming machine 1 rejected HTTP 400; malformed WS payloads tolerated. |
| Machine health watchdog (command timeout, heartbeat loss) | **REAL** | Unfinished live move → `command_timeout` event; 15 s without heartbeat → `machine_offline` event. |
| Flutter Live Camera remote-stream rendering + per-machine AI | **REAL (UI)** | Polls backend frames, renders `CAMERA ● LIVE/OFFLINE`, runs real YOLO over remote frames; SYSTEM MODE badge shows SIMULATED vs REAL HARDWARE. `flutter build web` + `flutter analyze` clean. |
| Flutter local device preview (`camera` plugin) | **SIMULATED/EMULATED** | Webcam preview works in Chrome; native preview only on Android/iOS builds. |
| `BACKED_REALTIME_MODE=simulate` fleet + fake sensors | **SIMULATED** | Watchdog simulates movement/acks; `simulated=true` throughout; battery/temp demo values. |
| Real ESP32 hardware / physical E-STOP button | **NOT AVAILABLE** | No microcontroller connected on this dev machine. The wire protocol was exercised with the documented HTTP messages; genuine device traffic is untested here. |
| Real IP/MJPEG camera hardware | **NOT AVAILABLE** | Only `file://`/local-path sources exercised. RTSP is deliberately unsupported (needs an on-prem decode gateway / MJPEG bridge). |
| CUDA/GPU acceleration | **NOT AVAILABLE** | `torch.cuda.is_available() == False`; inference is CPU-only. |

---

## 2. End-to-end loop verified (both modes)

Fetch → camera metadata/JPEG frame → real YOLO → WebSocket telemetry (simulated flag, null sensors in live) → ESP32 hw report → distance-first command → commissioning cap → hardware E-STOP latch → blocked movement → hardware release → movement → restart recovery.

## 3. Failure tests (all pass)

1. Camera offline → `GET /machines/2/camera/frame` → HTTP **502** with clean detail (fast fail; no DNS hang).
2. AI rejects non-image → HTTP 400/500 (route guards `image/*`).
3. E-STOP blocks movement → HTTP 409 while latched; 50 mm move accepted after release.
4. Malformed WebSocket payload → server keeps serving telemetry.
5. Uncompleted live move (no ESP32) → watchdog `command_timeout` event (never faked as "completed").
6. ESP32 heartbeat loss → `machine_offline` event after 15 s.
7. Backend restart → WebSocket reconnects and telemetry resumes.
8. Machine identity mismatch → HTTP 400.

## 4. Bugs found and fixed during acceptance

- `_watchdog_monitor` referenced undefined `record` → the asyncio task died silently on the first stale command (never emitted `command_timeout`; health checks also stopped). Fixed (`backed.py`).
- Hardware E-STOP was latch-only — no release/re-arm path existed. Added symmetric release via `hw/status.estop_input=false` and `POST /hw/estop/{id}` with body `{"estop_input": false}` (`backed.py`).
- Camera fetch on a missing local path was treated as an HTTP URL (slow DNS hang). Now fails fast with `CameraFeedError` → 502 (`machine_comms.py`).
- Flutter web camera provider forced `MockCameraProvider` on `kIsWeb`. Now websocket/live mode uses the backend registry on web too (`camera_provider.dart`).

## 5. Exact startup commands (PowerShell, repo root)

```powershell
# Backend — REAL HARDWARE mode (default; commissioning starts BLOCKED at 0 mm)
$env:BACKED_REALTIME_MODE='live'
$env:BACKED_CAMERA_1_STREAM='C:\path\to\agv01.mjpg'   # MJPEG/HTTP or a local JPEG path
$env:BACKED_CAMERA_2_STREAM='C:\path\to\crane01.mjpg'
& .\.venv\Scripts\python.exe -m uvicorn backed:app --host 0.0.0.0 --port 8000

# Backend — SIMULATE mode (demo fleet, fake sensors, unlimited)
$env:BACKED_REALTIME_MODE='simulate'
& .\.venv\Scripts\python.exe -m uvicorn backed:app --host 0.0.0.0 --port 8000

# Flutter web — live WebSocket mode (backend + camera registry)
flutter run -d chrome --dart-define=PORT_REALTIME_MODE=websocket

# Flutter web — mock mode (standalone, local webcam preview)
flutter run -d chrome --dart-define=PORT_REALTIME_MODE=mock

# Full-stack acceptance + failure suite (spawns its own isolated backend on :8721)
& .\.venv\Scripts\python.exe e2e_acceptance.py --mode both
```

## 6. Requirements for full hardware acceptance

Plug an ESP32 into the polling proxy (`GET /hw/command/{id}`, `POST /hw/status/{id}`, `POST /hw/command/{id}/done`, `POST /hw/estop/{id}`) and assign real MJPEG/IP camera URLs via `BACKED_CAMERA_1_STREAM`/`BACKED_CAMERA_2_STREAM`. Re-run `e2e_acceptance.py --mode live` and the hardware rows above change from `NOT AVAILABLE` to `REAL`. The wire protocol and every integration seam they touch are already under test and green.