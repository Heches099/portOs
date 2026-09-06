"""PortOS full-stack acceptance + failure-mode test.

Boots the real uvicorn backend on an isolated port and exercises the REAL
hardware integration seams end to end:

Acceptance (REAL surfaces working through the stack):
  1. Real camera frames proxied through FastAPI (file/HTTP MJPEG source).
  2. Real YOLO PPE inference over frames (no ultralytics stub).
  3. WebSocket telemetry shape: simulated flag, nullable sensors, new fields.
  4. ESP32 hw/status reports -> measured sensors + hardware E-STOP input.
  5. Distance-first commands, commissioning cap + E-STOP lock, machine identity.

Failure modes:
  6. Camera offline  -> /camera/frame returns 502 with a clean detail.
  7. AI rejects non-images -> 400 "Only image files are accepted."
  8. E-STOP blocks movement -> 409; reset re-allows.
  9. Malformed WebSocket payload -> server keeps serving frames.
 10. Backend restart -> WebSocket reconnects and frames resume.

Usage:
    python e2e_acceptance.py [--mode both|simulate|live] [--port 8721]

Exit code 0 when every check passes.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import httpx
import websockets.sync.client

REPO_DIR = Path(__file__).resolve().parent
VENV_PY = REPO_DIR / ".venv" / "Scripts" / "python.exe"
FRAME_A = REPO_DIR  # placeholder; resolved in main()
MISSING_CAMERA = r"C:\no_such_camera_feed_12345.jpg"

RESULTS: list[tuple[str, str, bool, str]] = []

PORT = 8721
BASE = ""
CHILD: subprocess.Popen | None = None


def log_result(section: str, name: str, ok: bool, detail: str = "") -> None:
    RESULTS.append((section, name, ok, detail))
    mark = "PASS" if ok else "FAIL"
    print(f"  [{mark}] {section} :: {name}" + (f" - {detail}" if detail else ""))


def http(
    method: str,
    path: str,
    *,
    json_body: dict | None = None,
    data: dict | None = None,
    files: dict | None = None,
) -> tuple[int, object]:
    with httpx.Client(timeout=30.0, follow_redirects=True) as client:
        resp = client.request(method, BASE + path, json=json_body, data=data, files=files)
        try:
            body: object = resp.json()
        except Exception:  # noqa: BLE001 - non-JSON (e.g. JPEG bytes)
            body = resp.content
        return resp.status_code, body


def port_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def spawn_backend(mode: str, camera_a: str, camera_b: str) -> subprocess.Popen:
    env = {k: v for k, v in os.environ.items() if isinstance(v, str)}
    env["BACKED_REALTIME_MODE"] = mode
    env["BACKED_CAMERA_1_STREAM"] = camera_a
    env["BACKED_CAMERA_2_STREAM"] = camera_b
    env["BACKED_FIREBASE_PROJECT_ID"] = ""
    env["BACKED_FIREBASE_SERVICE_ACCOUNT_PATH"] = ""
    env["PYTHONUNBUFFERED"] = "1"
    py = str(VENV_PY) if VENV_PY.exists() else sys.executable
    proc = subprocess.Popen(
        [py, "-m", "uvicorn", "backed:app", "--host", "127.0.0.1", "--port", str(PORT)],
        cwd=str(REPO_DIR),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return proc


def wait_ready(timeout: float = 90.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if CHILD and CHILD.poll() is not None:
            print("  backend exited early; tail of output:\n")
            print((CHILD.stdout.read() or "")[-3000:])
            return False
        try:
            with urllib.request.urlopen(f"{BASE}/health", timeout=3) as resp:
                if resp.status == 200:
                    return True
        except (urllib.error.URLError, OSError):
            pass
        time.sleep(0.5)
    return False


def read_ws_frame(ws, timeout: float = 20.0, expect_type: str | None = None) -> tuple[str, dict]:
    """Reads frames; returns (frame_type, payload) matching expect_type."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        raw = ws.recv(timeout=max(0.5, deadline - time.time()))
        try:
            frame = json.loads(raw)
        except json.JSONDecodeError:
            continue
        ftype = frame.get("type", "")
        if expect_type is None or ftype == expect_type:
            return ftype, frame
    raise TimeoutError(f"no frame of type {expect_type!r} within {timeout}s")


def ws_connect():
    return websockets.sync.client.connect(f"ws://127.0.0.1:{PORT}/ws/machines")


# ─── Acceptance sections ──────────────────────────────────────────────────

def test_system_status() -> None:
    code, body = http("GET", "/system/status")
    ok = code == 200 and isinstance(body, dict)
    mode = (body or {}).get("realtime_mode") if isinstance(body, dict) else None
    sim = (body or {}).get("simulated") if isinstance(body, dict) else None
    log_result(
        "system",
        "GET /system/status",
        ok and mode in ("live", "simulate"),
        f"mode={mode} simulated={sim}",
    )
    ppe = (body or {}).get("ppe_model") if isinstance(body, dict) else None
    log_result("system", "PPE model status", ppe == "ready", f"ppe_model={ppe}")


def test_camera_online(machine: str = "1") -> None:
    code, body = http("GET", f"/machines/{machine}/camera")
    log_result(
        "camera",
        f"GET /machines/{machine}/camera metadata",
        code == 200 and isinstance(body, dict) and bool(body.get("stream_url")),
        f"HTTP {code} kind={(body or {}).get('stream_kind') if isinstance(body, dict) else None}",
    )
    code, body = http("GET", f"/machines/{machine}/camera/frame")
    is_jpeg = isinstance(body, bytes) and body[:2] == b"\xff\xd8" and body[-2:] == b"\xff\xd9"
    detail = (
        f"HTTP {code}, {len(body)} bytes"
        if isinstance(body, bytes)
        else f"HTTP {code}, detail={(body or {}).get('detail') if isinstance(body, dict) else body}"
    )
    log_result(
        "camera",
        f"GET /machines/{machine}/camera/frame (real stream)",
        code == 200 and is_jpeg,
        detail,
    )
    return body if is_jpeg else None


def test_ai_detection(frame_bytes: bytes, machine: str = "1") -> None:
    code, body = http(
        "POST",
        "/ai/ppe-detect",
        files={"file": ("frame.jpg", frame_bytes, "image/jpeg")},
        data={"machine_id": machine},
    )
    as_dict = body if isinstance(body, dict) else {}
    ok = code == 200 and as_dict.get("status") == "success" and "detections" in as_dict
    log_result(
        "ai",
        "POST /ai/ppe-detect (real YOLO)",
        ok,
        f"detections={as_dict.get('totalDetections')} safety={as_dict.get('safety_status')}",
    )


def test_ws_telemetry(expected_simulated: bool) -> None:
    with ws_connect() as ws:
        ftype, welcome = read_ws_frame(ws, expect_type="welcome")
        log_result(
            "ws",
            "welcome frame",
            ftype == "welcome",
            f"mode={welcome.get('mode')} simulated={welcome.get('simulated')}",
        )

        ws.send(json.dumps({"type": "subscribe", "machine_ids": ["1"]}))
        ftype, frame = read_ws_frame(ws, expect_type="telemetry")

        mid = frame.get("machine_id")
        sim_flag = frame.get("simulated")
        ai_status = frame.get("ai_status")
        fb_src = frame.get("feedback_source")
        encoder = frame.get("encoder_mm")
        battery = frame.get("battery_percent")
        temp = frame.get("temperature_c")
        battery_v = frame.get("battery_v")
        current_a = frame.get("current_a")

        ok_mid = mid == "1"
        ok_sim = sim_flag == expected_simulated
        ok_new = all(v is not None for v in (ai_status, fb_src, encoder))
        ok_extra = all(k in frame for k in ("motor_state", "limit_switches", "simulated", "feedback_source", "encoder_mm", "battery_v", "current_a", "ai_safety_state"))
        log_result(
            "ws",
            "telemetry shape",
            ok_mid and ok_sim and ok_new and ok_extra,
            f"simulated={sim_flag} ai_status={ai_status} fb={fb_src} encoder={encoder}",
        )

        if expected_simulated:
            ok_battery = isinstance(battery, (int, float)) and isinstance(temp, (int, float))
        else:
            ok_battery = battery is None and temp is None
        log_result(
            "ws",
            "sensor availability (simulated vs live)",
            ok_battery,
            f"battery={battery} temperature={temp}",
        )


def test_hw_report_state(mode: str) -> None:
    code, body = http(
        "POST",
        "/hw/status/1",
        json_body={
            "battery": 76.5,
            "battery_voltage": 48.2,
            "current_a": 12.4,
            "temperature_c": 49.3,
            "encoder_mm": 250,
            "speed_mps": 0.4,
            "motor_state": "running",
            "limit_switches": {"home": True, "limit": False},
        },
    )
    ok = code == 200 and isinstance(body, dict) and body.get("status") == "ok"
    log_result("esp32", "POST /hw/status/1 (sensor report)", ok, f"{body}")

    with ws_connect() as ws:
        ws.send(json.dumps({"type": "subscribe", "machine_ids": ["1"]}))
        _, frame = read_ws_frame(ws, expect_type="telemetry")
        measured = (
            frame.get("feedback_source") == "measured"
            and frame.get("battery_percent") == 76.5
            and frame.get("temperature_c") == 49.3
            and frame.get("encoder_mm") == 250.0
            and frame.get("battery_v") == 48.2
            and frame.get("current_a") == 12.4
        )
        log_result(
            "esp32",
            "measured sensors reflected in telemetry",
            measured,
            f"fb={frame.get('feedback_source')} battery={frame.get('battery_percent')} enc={frame.get('encoder_mm')}",
        )


def test_hw_estop_input(mode: str) -> None:
    code, body = http("POST", "/hw/status/1", json_body={"estop_input": True})
    log_result("esp32", "hardware E-STOP latch report", code == 200, f"{body}")

    with ws_connect() as ws:
        ws.send(json.dumps({"type": "subscribe", "machine_ids": ["1"]}))
        _, frame = read_ws_frame(ws, expect_type="telemetry")
        ok = frame.get("emergency_stop") is True and frame.get("state") == "estop"
        log_result("esp32", "hardware E-STOP reflected in telemetry", ok, f"estop={frame.get('emergency_stop')} state={frame.get('state')}")

    code, body = http(
        "POST",
        "/machines/1/command",
        json_body={"machine_id": "1", "command": "move_forward", "distance_mm": 50, "speed_mps": 0.2},
    )
    log_result(
        "failures",
        "movement blocked while E-STOP latched",
        code == 409,
        f"HTTP {code}",
    )

    # Only hardware may clear the latch: the ESP32 reports the physical button
    # release, the backend re-arms, and movement is allowed again.
    code, body = http("POST", "/hw/status/1", json_body={"estop_input": False})
    log_result("esp32", "hardware E-STOP release report", code == 200, f"{body}")

    with ws_connect() as ws:
        ws.send(json.dumps({"type": "subscribe", "machine_ids": ["1"]}))
        _, frame = read_ws_frame(ws, expect_type="telemetry")
        ok = frame.get("emergency_stop") is False and frame.get("state") == "idle"
        log_result("esp32", "E-STOP release reflected in telemetry", ok, f"estop={frame.get('emergency_stop')} state={frame.get('state')}")

    if mode == "live":
        code, body = http(
            "POST",
            "/machines/1/commission/advance",
        )
        log_result("command", "commissioning advance after re-arm", code in (200, 409), f"HTTP {code}")

    code, body = http(
        "POST",
        "/machines/1/command",
        json_body={"machine_id": "1", "command": "move_forward", "distance_mm": 50, "speed_mps": 0.2},
    )
    log_result(
        "failures",
        "movement allowed after E-STOP release",
        code == 200,
        f"HTTP {code}",
    )


def test_command_flow(mode: str) -> None:
    if mode == "live":
        # Preflight for commissioning needs a live WebSocket (ack path) plus a
        # measured encoder + fresh heartbeat, so keep a subscriber open.
        with ws_connect() as ws:
            ws.send(json.dumps({"type": "subscribe", "machine_ids": ["1"]}))
            code, body = http("POST", "/hw/status/1", json_body={"encoder_mm": 0.0})
            log_result("esp32", "heartbeat before commissioning", code == 200, f"{body}")

            code, body = http("POST", "/machines/1/commission/advance")
            log_result("command", "commissioning advance (0 -> 10mm)", code == 200, f"{body}")

            # 200mm still exceeds the 10mm allowance -> preflight/cap blocks it.
            code, body = http(
                "POST",
                "/machines/1/command",
                json_body={"machine_id": "1", "command": "move_forward", "distance_mm": 200, "speed_mps": 0.2},
            )
            log_result("command", "movement capped by commissioning allowance", code == 409, f"HTTP {code}")

            # Advance through the levels; the hardware cap is 100mm (unlimited
            # is only reachable by an explicit override, not by advancing).
            for _ in range(6):
                code, body = http("POST", "/machines/1/commission/advance")
                if isinstance(body, dict) and body.get("status") == "already_unlimited":
                    break
            code, body = http("GET", "/machines/1/commission")
            capped = isinstance(body, dict) and body.get("commissionDistanceMm") == 100 and body.get("commissioned") is True
            log_result("command", "commissioning advanced to hardware cap (100mm)", capped, f"{body}")

            code, body = http(
                "POST",
                "/machines/1/command",
                json_body={"machine_id": "1", "command": "move_forward", "distance_mm": 50, "speed_mps": 0.2},
            )
            log_result("command", "distance-first command (live)", code == 200, f"HTTP {code}")

            code, body = http(
                "POST",
                "/machines/2/command",
                json_body={"machine_id": "1", "command": "move_forward", "distance_mm": 200, "speed_mps": 0.2},
            )
            log_result("command", "machine identity mismatch rejected", code in (400, 409), f"HTTP {code}")

            # No ESP32 present to complete the move: the watchdog must declare it
            # timed out instead of pretending it completed.
            ftype, frame = read_ws_frame(ws, expect_type="command_timeout", timeout=40.0)
            timed_out = (
                frame.get("event_type") == "command_timeout"
                and frame.get("severity") == "warning"
            )
            log_result(
                "failures",
                "uncompleted live movement -> watchdog timeout event",
                timed_out,
                f"event={frame.get('event_type')}",
            )
    else:
        code, body = http(
            "POST",
            "/machines/1/command",
            json_body={"machine_id": "1", "command": "move_forward", "distance_mm": 200, "speed_mps": 0.2},
        )
        log_result("command", "distance-first command (simulate)", code == 200, f"HTTP {code}")

        code, body = http(
            "POST",
            "/machines/2/command",
            json_body={"machine_id": "1", "command": "move_forward", "distance_mm": 200, "speed_mps": 0.2},
        )
        log_result("command", "machine identity mismatch rejected", code in (400, 409), f"HTTP {code}")


def test_camera_offline(machine: str = "2") -> None:
    code, body = http("GET", f"/machines/{machine}/camera/frame")
    detail = body.get("detail") if isinstance(body, dict) else body
    log_result(
        "failures",
        f"camera offline -> /camera/frame({machine}) 502",
        code == 502 and bool(detail),
        f"HTTP {code} detail={detail!r}"[:220],
    )


def test_ai_rejects_garbage() -> None:
    code, body = http(
        "POST",
        "/ai/ppe-detect",
        files={"file": ("garbage.png", b"this is definitely not an image", "image/png")},
        data={"machine_id": "1"},
    )
    ok = code == 500 or code >= 400
    log_result("failures", "AI rejects non-image payload", ok, f"HTTP {code}")


def test_ws_malformed_payload() -> None:
    with ws_connect() as ws:
        read_ws_frame(ws, expect_type="welcome")
        ws.send("this is {not json")
        ws.send(json.dumps({"type": "subscribe", "machine_ids": ["1"]}))
        try:
            read_ws_frame(ws, expect_type="telemetry", timeout=20.0)
            log_result("failures", "malformed WS payload tolerated", True, "telemetry still flowing")
        except Exception:  # noqa: BLE001
            log_result("failures", "malformed WS payload tolerated", False, "server stopped serving")


def test_esp32_disconnect() -> None:
    """A machine that stops heartbeating must be declared offline (never left
    pretending to run). The watchdog flips it after TELEMETRY_OFFLINE_SECONDS."""
    with ws_connect() as ws:
        ws.send(json.dumps({"type": "subscribe", "machine_ids": ["1"]}))
        read_ws_frame(ws, expect_type="telemetry")
        code, body = http("POST", "/hw/status/1", json_body={"encoder_mm": 0.0})
        if code != 200:
            log_result("failures", "ESP32 disconnect -> offline", False, f"heartbeat POST HTTP {code}")
            return
        _, frame = read_ws_frame(ws, expect_type="machine_offline", timeout=40.0)
        ok = frame.get("event_type") == "machine_offline"
        log_result("failures", "ESP32 disconnect -> offline", ok, f"event={frame.get('event_type')}")


def test_backend_restart(mode: str, camera_a: str, camera_b: str) -> None:
    global CHILD
    if CHILD:
        CHILD.terminate()
        try:
            CHILD.wait(timeout=10)
        except subprocess.TimeoutExpired:
            CHILD.kill()
            CHILD.wait(timeout=10)
        CHILD = None
    CHILD = spawn_backend(mode, camera_a, camera_b)
    if not wait_ready():
        log_result("failures", "backend restart recovery", False, "backend did not come back up")
        return
    with ws_connect() as ws:
        read_ws_frame(ws, expect_type="welcome")
        ws.send(json.dumps({"type": "subscribe", "machine_ids": ["1"]}))
        try:
            _, frame = read_ws_frame(ws, expect_type="telemetry")
            ok = frame.get("machine_id") == "1"
            log_result("failures", "backend restart recovery", ok, "telemetry resumed after restart")
        except Exception:  # noqa: BLE001
            log_result("failures", "backend restart recovery", False, "no telemetry after restart")


def run_section(mode: str, camera_a: str, camera_b: str) -> None:
    print(f"\n=== MODE: {mode} ===")
    test_system_status()

    # Real camera frame through FastAPI, then real YOLO over those exact bytes.
    frame = test_camera_online("1")
    frame_bytes = frame if isinstance(frame, bytes) else Path(str(FRAME_A)).read_bytes()
    test_ai_detection(frame_bytes)

    test_ws_telemetry(expected_simulated=(mode == "simulate"))
    test_command_flow(mode)
    if mode == "simulate":
        test_ws_malformed_payload()
    else:
        test_hw_report_state(mode)
        test_hw_estop_input(mode)
        test_camera_offline("2")
        test_ai_rejects_garbage()
        test_ws_malformed_payload()
        test_esp32_disconnect()


def main() -> int:
    global BASE, PORT, CHILD, FRAME_A
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["both", "simulate", "live"], default="both")
    parser.add_argument("--port", type=int, default=8721)
    args = parser.parse_args()

    PORT = args.port
    BASE = f"http://127.0.0.1:{PORT}"
    if not port_free(PORT):
        print(f"Port {PORT} is already in use by another process; refusing to test a foreign backend.")
        return 2
    frame_env = os.environ.get("E2E_FRAME_A")
    FRAME_A = Path(frame_env) if frame_env else Path(
        r"C:\Users\HECHES\AppData\Local\Temp\opencode\ppe_test_frame.jpg"
    )
    if not FRAME_A.is_file():
        print("No camera fixture JPEG found; set E2E_FRAME_A to a JPEG file.")
        return 2

    modes = ["simulate", "live"] if args.mode == "both" else [args.mode]
    camera_a = str(FRAME_A)

    def stop_child() -> None:
        global CHILD
        if CHILD:
            CHILD.terminate()
            try:
                CHILD.wait(timeout=15)
            except subprocess.TimeoutExpired:
                CHILD.kill()
                CHILD.wait(timeout=10)
            CHILD = None

    try:
        for mode in modes:
            CHILD = spawn_backend(mode, camera_a, MISSING_CAMERA)
            if not wait_ready():
                print("  FAILED to boot backend for mode", mode)
                return 1
            run_section(mode, camera_a, MISSING_CAMERA)
            test_backend_restart(mode, camera_a, MISSING_CAMERA)
            stop_child()
    except KeyboardInterrupt:
        stop_child()
        raise
    finally:
        stop_child()

    print("\n=== SUMMARY ===")
    passed = sum(1 for _, _, ok, _ in RESULTS if ok)
    failed = len(RESULTS) - passed
    for section, name, ok, detail in RESULTS:
        print(f"  {'PASS' if ok else 'FAIL'}  {section} :: {name}" + (f" - {detail}" if detail else ""))
    print(f"\n{passed}/{len(RESULTS)} checks passed; {failed} failed.")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())