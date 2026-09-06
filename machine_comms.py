"""ESP32 / hardware communication abstraction for the PortOS realtime gateway.

This is the single seam between FastAPI and the physical (or simulated)
machine layer:

  * ``SimulatedComms``   - moves a virtual machine when
                           ``BACKED_REALTIME_MODE=simulate``.
  * ``Esp32ProxyComms``  - delegates to the existing ESP8266/ESP32 polling
                           proxy (``/hw/command/*``). Real hardware flow stays
                           exactly as it is today.

Movement is distance-first: the primary input is ``distance_mm``; the
low-level timed / stepper magnitude is derived from the operator calibration
(AGV ≈ 200 mm/s at full speed, crane/trolley 10 steps/mm). Time is only the
watchdog / expiry window - never the primary control.
"""
from __future__ import annotations

import abc
import io
import os
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

try:
    import requests
except ImportError:  # pragma: no cover - optional HTTP dependency
    requests = None  # type: ignore[assignment]

# Operator calibration - mirrors lib/utils/movement_calibration.dart.
AGV_MM_PER_SEC_FULL = 200.0
CRANE_STEPS_PER_MM = 10.0
MIN_DISTANCE_MM = 10.0
MAX_DISTANCE_MM = 50_000.0
MIN_DURATION_MS = 100
MAX_DURATION_MS = 60_000

AGV_DISPLACEMENTS: dict[str, tuple[float, float]] = {
    "forward": (1.0, 0.0),
    "backward": (-1.0, 0.0),
    "left": (0.0, -1.0),
    "right": (0.0, 1.0),
}

CRANE_AXES = {"hoist_up": 1.0, "hoist_down": -1.0}
TROLLEY_AXES = {"trolley_forward": 1.0, "trolley_backward": -1.0}


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _iso_now() -> str:
    return _utc_now().isoformat()


class MachineCommsError(Exception):
    """Raised when a command cannot be handed to the machine safely."""


@dataclass
class CommsOutcome:
    accepted: bool
    message: str = ""
    moved_mm: float = 0.0
    remaining_mm: float = 0.0
    estimated_duration_ms: int | None = None

    @property
    def ok(self) -> bool:
        return self.accepted


def validate_distance(distance_mm: float | None) -> float:
    if distance_mm is None:
        raise MachineCommsError("distance_mm is required for movement commands")
    if distance_mm < MIN_DISTANCE_MM:
        raise MachineCommsError(
            f"Distance below physical minimum ({MIN_DISTANCE_MM:.0f} mm)."
        )
    if distance_mm > MAX_DISTANCE_MM:
        raise MachineCommsError(
            f"Distance above physical maximum ({MAX_DISTANCE_MM:.0f} mm)."
        )
    return distance_mm


def watchdog_ms_for_distance(distance_mm: float, speed_mps: float | None) -> int:
    """Watchdog / expiry window derived from a physical distance."""
    speed_mm_s = (speed_mps or 0.2) * 1000.0
    ms = int(round(distance_mm / max(speed_mm_s, 1.0) * 1000.0))
    return max(MIN_DURATION_MS, min(MAX_DURATION_MS, ms))


def steps_for_distance(distance_mm: float) -> int:
    return max(1, min(10000, int(round(distance_mm * CRANE_STEPS_PER_MM))))


def distance_for_steps(steps: int) -> float:
    """Inverse of steps_for_distance - measured distance the steps represent."""
    return round(max(0.0, float(steps) / CRANE_STEPS_PER_MM), 1)


class MachineComms(abc.ABC):
    """Interface implemented by every machine communication backend."""

    name: str = "base"

    @abc.abstractmethod
    def start(
        self,
        rt: dict[str, Any],
        command: str,
        *,
        direction: str | None = None,
        distance_mm: float | None = None,
        speed_mps: float | None = None,
        duration_ms: int | None = None,
        steps: int | None = None,
    ) -> CommsOutcome:
        """Begin executing a command, mutating ``rt`` as needed."""

    def step(self, rt: dict[str, Any], dt_seconds: float) -> tuple[float, bool]:
        """Advance an in-flight command. Returns (moved_mm, finished)."""
        raise MachineCommsError(f"{self.name} cannot advance in-flight commands")

    def release(self) -> None:
        pass


class SimulatedComms(MachineComms):
    """Simulated machine physics for development / demo mode only.

    Distances here are plainly flagged by the UI side (mock frames carry
    ``mock=True``); production uses [Esp32ProxyComms] against real hardware.
    """

    name = "simulated"

    def start(
        self,
        rt: dict[str, Any],
        command: str,
        *,
        direction: str | None = None,
        distance_mm: float | None = None,
        speed_mps: float | None = None,
        duration_ms: int | None = None,
        steps: int | None = None,
    ) -> CommsOutcome:
        if command == "stop":
            rt["state"] = "idle"
            rt["direction"] = "stopped"
            rt["speed_mps"] = 0.0
            rt["distance_remaining_mm"] = 0.0
            rt["active"] = None
            return CommsOutcome(accepted=True, message="stopped")

        if command == "home":
            rt["position"] = {"x": 0.0, "y": 0.0, "z": 0.0}
            rt["state"] = "idle"
            rt["distance_remaining_mm"] = 0.0
            rt["active"] = None
            return CommsOutcome(accepted=True, message="homed")

        if command == "magnet_on" or command == "grab":
            rt["load"] = "CONTAINER"
            rt["load_percent"] = 100.0
            return CommsOutcome(accepted=True, message="container engaged")

        if command == "magnet_off" or command == "release":
            rt["load"] = "EMPTY"
            rt["load_percent"] = 0.0
            return CommsOutcome(accepted=True, message="container released")

        is_agv = rt.get("machine_type") == "agv"
        if command not in AGV_DISPLACEMENTS:
            # crane hoist / trolley movement - advanced incrementally by step()
            usable_steps = steps
            if usable_steps is None and distance_mm is not None:
                usable_steps = steps_for_distance(validate_distance(distance_mm))
            if usable_steps is None:
                raise MachineCommsError(
                    "crane movement requires steps or distance_mm"
                )
            rt["direction"] = command
            rt["state"] = "running"
            rt["distance_requested_mm"] = round(
                usable_steps / CRANE_STEPS_PER_MM, 3
            )
            rt["distance_moved_mm"] = 0.0
            rt["distance_remaining_mm"] = rt["distance_requested_mm"]
            rt["active"] = {
                "command": command,
                "steps": usable_steps,
                "remaining": usable_steps,
            }
            return CommsOutcome(
                accepted=True,
                remaining_mm=usable_steps / CRANE_STEPS_PER_MM,
                estimated_duration_ms=MAX_DURATION_MS,
            )

        requested = validate_distance(distance_mm)
        dx, dy = AGV_DISPLACEMENTS[command]
        rt["direction"] = command
        rt["speed_mps"] = speed_mps or 0.2
        rt["state"] = "moving"
        rt["distance_requested_mm"] = requested
        rt["distance_remaining_mm"] = requested
        rt["distance_moved_mm"] = 0.0
        rt["active"] = {
            "command": command,
            "dx": dx,
            "dy": dy,
            "remaining": requested,
            "speed_mm_s": (speed_mps or 0.2) * 1000.0,
            "duration_ms": (
                duration_ms or watchdog_ms_for_distance(requested, speed_mps)
            ),
        }
        return CommsOutcome(
            accepted=True,
            message=f"moving {command} {requested:.0f} mm",
            remaining_mm=requested,
            estimated_duration_ms=rt["active"]["duration_ms"],
        )

    def step(self, rt: dict[str, Any], dt_seconds: float) -> tuple[float, bool]:
        active = rt.get("active")
        if not active:
            return 0.0, False

        command = active["command"]
        if command in CRANE_AXES or command in TROLLEY_AXES:
            remaining_steps = int(active.get("remaining", 0))
            if remaining_steps <= 0:
                rt["state"] = "idle"
                rt["active"] = None
                return 0.0, True
            moved_steps = min(remaining_steps, max(1, int(220 * dt_seconds) + 1))
            active["remaining"] = remaining_steps - moved_steps
            delta_m = moved_steps / (CRANE_STEPS_PER_MM * 1000.0)
            rt["distance_moved_mm"] = round(
                float(rt.get("distance_moved_mm", 0.0)) + delta_m * 1000.0, 3
            )
            rt["distance_remaining_mm"] = round(
                float(rt.get("distance_requested_mm", 0.0))
                - float(rt.get("distance_moved_mm", 0.0)),
                3,
            )
            if command in CRANE_AXES:
                rt["hoist_m"] = round(
                    max(0.0, float(rt.get("hoist_m", 0.0)) + CRANE_AXES[command] * delta_m),
                    3,
                )
            else:
                rt["trolley_m"] = round(
                    max(0.0, float(rt.get("trolley_m", 0.0)) + TROLLEY_AXES[command] * delta_m),
                    3,
                )
            if active["remaining"] <= 0:
                rt["state"] = "idle"
                rt["active"] = None
                rt["distance_remaining_mm"] = 0.0
                return delta_m * 1000.0, True
            return delta_m * 1000.0, False

        remaining = float(active.get("remaining", 0.0))
        if remaining <= 0:
            rt["state"] = "idle"
            rt["rt_active_done"] = True
            rt["active"] = None
            return 0.0, True
        speed_mm_s = float(active.get("speed_mm_s", 200.0))
        moved = min(remaining, speed_mm_s * dt_seconds)
        dx, dy = active["dx"], active["dy"]
        pos = rt.get("position", {"x": 0.0, "y": 0.0, "z": 0.0})
        pos["x"] = round(pos["x"] + dx * moved / 1000.0, 3)
        pos["y"] = round(pos["y"] + dy * moved / 1000.0, 3)
        rt["position"] = pos
        remaining -= moved
        active["remaining"] = round(remaining, 3)
        rt["distance_remaining_mm"] = round(remaining, 3)
        rt["distance_moved_mm"] = round(
            float(rt.get("distance_requested_mm", 0.0)) - remaining, 3
        )
        if remaining <= 0.001:
            rt["state"] = "idle"
            rt["distance_remaining_mm"] = 0.0
            rt["active"] = None
            return moved, True
        return moved, False


class Esp32ProxyComms(MachineComms):
    """Real ESP32 path: enqueue low-level commands for hardware polling.

    The ESP8266/ESP32 keeps polling ``GET /hw/command/{id}`` exactly as today;
    the result/ack completion arrives through ``POST /hw/command/{id}/done``.
    """

    name = "esp32-proxy"

    def start(
        self,
        rt: dict[str, Any],
        command: str,
        *,
        direction: str | None = None,
        distance_mm: float | None = None,
        speed_mps: float | None = None,
        duration_ms: int | None = None,
        steps: int | None = None,
    ) -> CommsOutcome:
        return CommsOutcome(accepted=True, message="queued for hardware")


class CameraFeedError(Exception):
    """Raised when a machine camera frame cannot be fetched."""


def _is_jpeg(data: bytes) -> bool:
    return data[:2] == b"\xff\xd8" and data[-2:] == b"\xff\xd9"


def _to_jpeg_bytes(data: bytes) -> bytes:
    """Normalize any image bytes into a single JPEG frame."""
    if _is_jpeg(data):
        return data
    from PIL import Image

    image = Image.open(io.BytesIO(data)).convert("RGB")
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


def _grab_mjpeg_frame(response: Any) -> bytes:
    """Extract the first complete JPEG frame from an open MJPEG response."""
    buffer = bytearray()
    for chunk in response.iter_content(chunk_size=4096):
        buffer.extend(chunk)
        start = buffer.find(b"\xff\xd8")
        if start == -1:
            if len(buffer) > (2 << 20):
                buffer = bytearray(buffer[-4096:])
            continue
        end = buffer.find(b"\xff\xd9", start)
        if end != -1:
            return bytes(buffer[start : end + 2])
    raise CameraFeedError("no JPEG frame found in MJPEG stream")


def _fetch_camera_frame(url: str, timeout: float = 10.0) -> bytes:
    """Fetch a single JPEG frame from a machine camera URL.

    Supported sources: MJPEG over HTTP(S), a static image over HTTP(S), or a
    local file path. RTSP is deliberately rejected here: it requires an on-prem
    decode gateway; configure an MJPEG/HTTP bridge URL instead.
    """
    rtsp_prefixes = ("rtsp://", "rtsps://", "rtspx://")
    if url.startswith(rtsp_prefixes):
        raise CameraFeedError(
            "RTSP needs an on-prem decode gateway - configure an MJPEG/HTTP bridge URL"
        )

    file_path: str | None = None
    low = url.lower()
    if url.startswith("file://"):
        file_path = url[len("file://") :]
    elif os.path.exists(url):
        file_path = url
    elif not low.startswith(("http://", "https://")):
        # A plain path that does not exist on disk: never attempt DNS for it
        # (that would hang until timeout). Fail fast with a clean 502 instead.
        raise CameraFeedError(f"camera file or stream unavailable: {url}")

    if file_path is not None:
        try:
            return _to_jpeg_bytes(Path(file_path).read_bytes())
        except OSError as error:
            raise CameraFeedError(f"cannot read camera file {file_path}: {error}") from error

    if requests is None:  # pragma: no cover - optional dependency
        raise CameraFeedError("the 'requests' library is not installed")

    with requests.get(url, stream=True, timeout=timeout) as response:
        response.raise_for_status()
        content_type = response.headers.get("Content-Type", "").lower()
        if "multipart/x-mixed-replace" in content_type:
            return _grab_mjpeg_frame(response)
        data = response.raw.read(2 << 20)

    if not data:
        raise CameraFeedError("camera returned an empty response")
    return _to_jpeg_bytes(data)


def _stream_kind(url: str | None) -> str:
    if not url:
        return "none"
    if url.startswith(("http://", "https://")):
        return "http"
    if url.startswith("rtsp"):
        return "rtsp"
    if url.startswith("file://") or os.path.exists(url):
        return "file"
    return "none"


class CameraStreamSpec:
    """Machine -> camera registry (single source of truth).

    ``stream_url is None`` means "the machine's camera is the local device
    camera" - the Flutter Live Camera panel renders the native preview and
    never needs a hard-coded URL from the client.

    When a stream URL is configured the panel renders frames proxied through
    the backend (``GET /machines/{id}/camera/frame``) so camera URLs stay on
    the server and machine identity is preserved.

    Stream URLs are injected at startup from backend settings, never declared
    inside Flutter widgets.
    """

    def __init__(self, streams: dict[str, str] | None = None) -> None:
        self._streams: dict[str, str] = dict(streams or {})
        self._registry: dict[str, dict[str, Any]] = {
            "1": {
                "camera_id": "agv-01-cam",
                "name": "AGV-01 FRONT CAMERA",
                "stream_url": None,
                "supports_ptz": False,
                "ai_enabled": True,
            },
            "2": {
                "camera_id": "crane-01-cam",
                "name": "CRANE-01 CAB CAMERA",
                "stream_url": None,
                "supports_ptz": False,
                "ai_enabled": True,
            },
        }

    def configure(self, streams: dict[str, str] | None) -> None:
        """Replace the machine -> stream URL mapping (from backend settings)."""
        self._streams = dict(streams or {})

    def resolve(self, machine_id: str, machine_name: str) -> dict[str, Any] | None:
        entry = self._registry.get(machine_id)
        if entry is None:
            return None
        stream_url = self._streams.get(machine_id) or None
        stream_configured = bool(stream_url)
        return {
            **entry,
            "machine_id": machine_id,
            "machine_name": machine_name,
            "stream_url": stream_url,
            "has_remote_stream": stream_configured,
            "stream_kind": _stream_kind(stream_url),
            "timestamp": _iso_now(),
            "connection": "online" if stream_configured else "unconfigured",
        }

    def fetch_frame(self, machine_id: str, machine_name: str) -> bytes:
        """Fetch a single JPEG frame for the machine's configured camera."""
        spec = self.resolve(machine_id, machine_name)
        if spec is None:
            raise CameraFeedError(f"no camera is registered for machine {machine_id}")
        stream_url = spec.get("stream_url")
        if not stream_url:
            raise CameraFeedError(
                f"{spec['name']} has no remote stream configured "
                "(fall back to the local device camera in the UI)"
            )
        return _fetch_camera_frame(stream_url)


_CAMERAS = CameraStreamSpec()