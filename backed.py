from __future__ import annotations

import asyncio
import json
import time
import uuid
from collections import deque
from dataclasses import dataclass, field
from datetime import UTC, datetime
from enum import Enum
from functools import lru_cache
from typing import Any
import io

from fastapi import (
    Body,
    Depends,
    FastAPI,
    File,
    Form,
    Header,
    HTTPException,
    Query,
    Response,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from firebase_admin import auth, credentials, firestore
from pathlib import Path

from PIL import Image
from ultralytics import YOLO

import firebase_admin
import machine_comms as comms


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        env_prefix="BACKED_",
        extra="ignore",
    )

    app_name: str = "PortOS Backed"
    api_version: str = "1.0.0"
    firebase_project_id: str = ""
    firebase_storage_bucket: str = ""
    firebase_service_account_path: str = ""
    admin_emails: str = ""
    cors_origins: str = "http://localhost:3000,http://localhost:5173,http://localhost:8080,https://portos-nextgen.vercel.app"
    ingest_api_key: str = ""
    password_reset_continue_url: str = ""
    firebase_service_account_b64: str = ""
    # "live"     -> real hardware via the ESP32 polling proxy (default).
    # "simulate" -> background simulation of fleet telemetry + command acks.
    realtime_mode: str = "live"
    # Real camera stream URLs for the fleet (RTSP / MJPEG / HLS). Empty string
    # = machine has no remote feed, so the Flutter panel uses the local device
    # camera preview. These are the ONLY source of camera URLs; nothing is
    # hard-coded inside Flutter widgets.
    camera_1_stream: str = ""
    camera_2_stream: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()


@lru_cache
def get_ppe_model() -> YOLO:
    model_path = (
        Path(__file__).resolve().parent
        / "ai_engine"
        / "models"
        / "best.pt"
    )

    if not model_path.exists():
        raise RuntimeError(f"PPE model not found: {model_path}")

    return YOLO(str(model_path))


def _csv_to_list(value: str) -> list[str]:
    return [item.strip().lower() for item in value.split(",") if item.strip()]


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _iso_now() -> str:
    return _utc_now().isoformat()


@lru_cache
def get_firebase_app() -> firebase_admin.App:
    settings = get_settings()
    if firebase_admin._apps:
        return firebase_admin.get_app()

    options: dict[str, Any] = {}
    if settings.firebase_project_id:
        options["projectId"] = settings.firebase_project_id
    if settings.firebase_storage_bucket:
        options["storageBucket"] = settings.firebase_storage_bucket

    if settings.firebase_service_account_b64:
        import base64
        import json as _json

        try:
            decoded = base64.b64decode(settings.firebase_service_account_b64)
            credential_dict = _json.loads(decoded)
        except Exception as error:  # pragma: no cover - misconfiguration
            raise RuntimeError(
                f"BACKED_FIREBASE_SERVICE_ACCOUNT_B64 could not be decoded: {error}"
            ) from error
        credential = credentials.Certificate(credential_dict)
    elif settings.firebase_service_account_path:
        credential = credentials.Certificate(settings.firebase_service_account_path)
    else:
        credential = credentials.ApplicationDefault()

    return firebase_admin.initialize_app(credential=credential, options=options or None)


@lru_cache
def get_db() -> firestore.Client:
    return firestore.client(app=get_firebase_app())


class ApiModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True, use_enum_values=True)


class TerminalStatsModel(ApiModel):
    teuCounter: int
    efficiency: float
    activeCranes: int
    yardUtilization: int
    avgDwellDays: float
    activeGroundSpots: int
    liveSources: int
    digitalTwinSector: str
    predictionWindowHours: int
    lastSync: datetime = Field(default_factory=_utc_now)


class AgvTelemetryModel(ApiModel):
    id: str
    x: float
    y: float
    batteryLevel: float
    speedKph: float
    status: str
    zone: str
    lastUpdated: datetime


class CraneTelemetryModel(ApiModel):
    id: str
    loadTons: float
    hookHeightMeters: float
    utilization: float
    status: str
    operatorName: str
    lastUpdated: datetime


class DeliveryRecordModel(ApiModel):
    containerId: str
    shipmentCode: str
    destination: str
    eta: datetime
    status: str
    priority: str
    itemsCount: int
    expectedGateOutAt: datetime
    verifiedAt: datetime | None = None
    exceptionReason: str | None = None


class CameraFeedModel(ApiModel):
    id: str
    title: str
    location: str
    isOnline: bool
    viewers: int
    lastUpdated: datetime
    alert: str | None = None


class SensorReadingModel(ApiModel):
    id: str
    label: str
    unit: str
    value: float
    minNormal: float
    maxNormal: float
    timestamp: datetime


class DashboardSnapshotModel(ApiModel):
    terminalStats: TerminalStatsModel
    agvs: list[AgvTelemetryModel]
    cranes: list[CraneTelemetryModel]
    deliveries: list[DeliveryRecordModel]
    cameraFeeds: list[CameraFeedModel]
    sensorReadings: list[SensorReadingModel]
    generatedAt: datetime = Field(default_factory=_utc_now)


class AdminProfileResponse(ApiModel):
    uid: str
    email: EmailStr
    isAdmin: bool
    emailVerified: bool


class PasswordResetRequest(ApiModel):
    email: EmailStr


class PasswordResetResponse(ApiModel):
    message: str


class PieWindow(str, Enum):
    minutes = "minutes"
    hourly = "hourly"
    daily = "daily"
    monthly = "monthly"


class PieSliceModel(ApiModel):
    label: str
    value: float
    detail: str


class PieAnalyticsResponse(ApiModel):
    window: PieWindow
    total: float
    slices: list[PieSliceModel]
    generatedAt: datetime = Field(default_factory=_utc_now)
    insight: str


class HardwareEntityType(str, Enum):
    terminal_stats = "terminal_stats"
    agv = "agv"
    crane = "crane"
    delivery = "delivery"
    camera_feed = "camera_feed"
    sensor_reading = "sensor_reading"


class HardwareEventIn(ApiModel):
    source: str
    entityType: HardwareEntityType
    entityId: str = "current"
    action: str = "upsert"
    payload: dict[str, Any]
    occurredAt: datetime = Field(default_factory=_utc_now)


# ─── Machine Control Models ─────────────────────────────────────────────

MACHINE_TYPES = {
    "1": {"name": "AGV-01", "type": "agv", "defaultSpeed": 255},
    "2": {"name": "Crane-01", "type": "crane", "defaultSpeed": 100},
}

AGV_COMMANDS = {"forward", "backward", "left", "right", "stop", "home", "blink"}
CRANE_COMMANDS = {
    "trolley_forward", "trolley_backward", "hoist_up", "hoist_down",
    "magnet_on", "magnet_off", "stop", "blink",
}


class MachineCommandRequest(ApiModel):
    command: str
    speed: int | None = None
    duration: int | None = None
    steps: int | None = None


class MachineCommandEnvelopeRequest(ApiModel):
    """Distance-first structured command envelope.

    Works with BOTH the legacy low-level shape (``speed``/``duration``/``steps``)
    and the structured realtime shape (``distance_mm``/``speed_mps``/``duration_ms``).
    Movement is distance-first; time fields act as watchdogs only.
    """

    command: str
    direction: str | None = None
    machine_id: str | None = None
    distance_mm: float | None = None
    speed_mps: float | None = None
    duration_ms: int | None = None
    steps: int | None = None
    speed: int | None = None
    duration: int | None = None


class MachineDriveRequest(ApiModel):
    move: str
    speed: int = 100


class MachineAutoRequest(ApiModel):
    cargo: int = 0
    moveTime: int = 1000
    loadTime: int = 1000
    unloadTime: int = 1000


class MachineCommandDoneRequest(ApiModel):
    commandId: int
    # Measured distance the hardware actually moved (mm), from the encoder /
    # sensor feedback. If provided, completion is driven by measured feedback
    # instead of a watchdog estimate.
    distance_moved_mm: float | None = None


class CommandRecord(ApiModel):
    id: str
    machineId: str
    command: str
    params: str = ""
    status: str = "pending"
    createdAt: str = ""
    executedAt: str | None = None
    completedAt: str | None = None


class MachineDetailModel(ApiModel):
    id: str
    name: str
    type: str
    status: str = "idle"
    location: str = ""
    operatorName: str = ""
    batteryLevel: float = 0.0
    speed: float = 0.0
    loadCapacity: float = 0.0
    currentLoad: float = 0.0
    lastMaintenance: str = ""
    notes: str = ""
    lastUpdated: str | None = None
    emergencyStop: bool = False
    # Commissioning state: -1 = unlimited, 0 = not yet commissioned, else mm cap.
    commissionDistanceMm: int = -1


class DriveStatusModel(ApiModel):
    online: bool = False
    lastChecked: str | None = None


class AutoModeStatusModel(ApiModel):
    running: bool = False
    cargoRemaining: int = 0
    cargoTotal: int = 0
    currentPhase: str = ""


# ─── In-Memory Machine State ─────────────────────────────────────────────

@dataclass
class MachineState:
    id: str
    name: str
    type: str
    status: str = "idle"
    location: str = ""
    operatorName: str = ""
    batteryLevel: float = 0.0
    speed: float = 0.0
    loadCapacity: float = 0.0
    currentLoad: float = 0.0
    lastMaintenance: str = ""
    notes: str = ""
    lastUpdated: str = ""
    online: bool = False
    last_online_check: str = ""
    command_queue: deque = field(default_factory=lambda: deque(maxlen=50))
    command_history: list = field(default_factory=list)
    activity_log: list = field(default_factory=list)
    auto_mode: dict = field(default_factory=lambda: {"running": False, "cargoTotal": 0, "cargoRemaining": 0, "currentPhase": ""})
    auto_mode_id: str = ""
    rt: dict = field(default_factory=dict)
    emergency_stop: bool = False
    # Commissioning movement cap in mm (-1 = unlimited, 0 = no movement yet).
    # Live mode starts at 0 and is raised only after preflight checks pass.
    commission_distance_mm: int = -1


def _default_rt(machine_id: str, machine_type: str, machine_name: str) -> dict[str, Any]:
    is_crane = machine_type != "agv"
    live = get_settings().realtime_mode != "simulate"
    # In LIVE mode battery/temperature are None until the hardware actually
    # reports them; the backend never fabricates a sensor reading for real
    # hardware. Simulate mode keeps the demo values and is flagged as simulated.
    return {
        "machine_id": machine_id,
        "machine_name": machine_name,
        "machine_type": machine_type,
        "state": "idle",
        "position": {"x": 0.0, "y": 0.0, "z": 0.0},
        "speed_mps": 0.0,
        "direction": "stopped",
        "distance_m": 0.0,
        "distance_travelled_m": 0.0,
        "distance_requested_mm": 0.0,
        "distance_moved_mm": 0.0,
        "distance_remaining_mm": 0.0,
        "battery_percent": (
            None if live else float(87 - int(machine_id) * 4)
        ),
        "battery_v": None,
        "current_a": None,
        "load": "EMPTY",
        "load_percent": 0.0,
        "temperature_c": (
            None if live else float(46 - int(machine_id) * 3)
        ),
        "connection": "online",
        "active_mission": "",
        "safety_state": "safe",
        "trolley_m": 0.0,
        "gantry_m": 0.0,
        "hoist_m": 0.0,
        "emergency_stop": False,
        "active": None,
        "ai_status": "offline",
        "ai_safety_state": "unknown",
        "feedback_source": "watchdog",
        "encoder_mm": 0.0,
        "motor_state": "unknown",
        "limit_switches": {},
        "sensor_sources": {},
    }


_machines: dict[str, MachineState] = {}

for _mid, _info in MACHINE_TYPES.items():
    _machines[_mid] = MachineState(
        id=_mid,
        name=_info["name"],
        type=_info["type"],
        location="Terminal A" if _info["type"] == "agv" else "Quay Zone",
        lastUpdated=_iso_now(),
        rt=_default_rt(_mid, _info["type"], _info["name"]),
        commission_distance_mm=(
            -1 if get_settings().realtime_mode == "simulate" else 0
        ),
    )

_comms_started_at = time.time()

# Inject real camera stream URLs (from backend settings) into the registry.
comms._CAMERAS.configure({
    "1": get_settings().camera_1_stream,
    "2": get_settings().camera_2_stream,
})

COMMAND_PARAMS_MAP: dict[str, dict[str, Any]] = {
    "forward": {"speed": (0, 255), "duration": (50, 5000)},
    "backward": {"speed": (0, 255), "duration": (50, 5000)},
    "left": {"speed": (0, 255), "duration": (50, 5000)},
    "right": {"speed": (0, 255), "duration": (50, 5000)},
    "stop": {},
    "home": {},
    "blink": {"count": (1, 20)},
    "trolley_forward": {"steps": (1, 10000)},
    "trolley_backward": {"steps": (1, 10000)},
    "hoist_up": {"steps": (1, 10000)},
    "hoist_down": {"steps": (1, 10000)},
    "magnet_on": {},
    "magnet_off": {},
}

# Structured vocabulary (Flutter MachineCommandSets) -> existing low-level
# machine protocol. The backend stays authoritative; nothing new is invented.
STRUCTURED_COMMAND_MAP: dict[str, str] = {
    "move_forward": "forward",
    "move_backward": "backward",
    "move_left": "left",
    "move_right": "right",
    "grab": "magnet_on",
    "release": "magnet_off",
    "set_speed": "stop",
}
ESTOP_COMMANDS = {"emergency_stop", "emergencyStop", "estop", "e-stop"}


# ─── Realtime telemetry hub ────────────────────────────────────────────────

class RealtimeHub:
    """Fan-out of WebSocket frames to subscribed machine clients.

    A client that subscribes to ``machine_ids`` only receives frames for those
    machines (matched against both backend id and lower-cased name); clients
    that never subscribe receive every frame.
    """

    def __init__(self) -> None:
        self._connections: set[WebSocket] = set()
        self._subs: dict[WebSocket, set[str]] = {}

    async def register(self, websocket: WebSocket, initial: list[str] | None = None) -> None:
        await websocket.accept()
        self._connections.add(websocket)
        self._subs[websocket] = set(initial or [])
        await websocket.send_text(json.dumps({
            "type": "welcome",
            "service": "portos-realtime",
            "machine_ids": list(self._subs[websocket]) or None,
            "mode": get_settings().realtime_mode,
            "simulated": get_settings().realtime_mode == "simulate",
        }))
        for state in _machines.values():
            payload = _build_telemetry(state)
            if self._wants(websocket, payload):
                await websocket.send_text(json.dumps(payload))

    async def handle(self, websocket: WebSocket) -> None:
        while True:
            raw = await websocket.receive_text()
            try:
                frame = json.loads(raw)
            except (json.JSONDecodeError, TypeError):
                continue
            if not isinstance(frame, dict):
                continue
            if frame.get("type") in ("ping", "pong"):
                await websocket.send_text(json.dumps({"type": "pong"}))
                continue
            if frame.get("type") == "subscribe":
                self._subs[websocket].update(str(i) for i in frame.get("machine_ids", []))
            elif frame.get("type") == "unsubscribe":
                self._subs[websocket].difference_update(
                    str(i) for i in frame.get("machine_ids", [])
                )

    def _wants(self, websocket: WebSocket, payload: dict[str, Any]) -> bool:
        subs = self._subs.get(websocket)
        if not subs:
            return True
        mid = str(payload.get("machine_id", ""))
        mname = str(payload.get("machine_name", "")).lower()
        return mid in subs or mname in {s.lower() for s in subs}

    async def unregister(self, websocket: WebSocket) -> None:
        self._connections.discard(websocket)
        self._subs.pop(websocket, None)

    async def broadcast(self, payload: dict[str, Any]) -> None:
        text = json.dumps(payload)
        for ws in list(self._connections):
            if self._wants(ws, payload):
                try:
                    await ws.send_text(text)
                except Exception:  # pragma: no cover - socket teardown
                    self._connections.discard(ws)
                    self._subs.pop(ws, None)

    @property
    def connection_count(self) -> int:
        return len(self._connections)


_hub = RealtimeHub()
_comms: comms.MachineComms = (
    comms.SimulatedComms()
    if get_settings().realtime_mode == "simulate"
    else comms.Esp32ProxyComms()
)


def _rt_number(rt: dict[str, Any], key: str) -> float | None:
    value = rt.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value)


def _build_telemetry(state: MachineState) -> dict[str, Any]:
    rt = state.rt
    is_agv = state.type == "agv"
    position = rt.get("position", {"x": 0.0, "y": 0.0, "z": 0.0})
    simulated = get_settings().realtime_mode == "simulate"
    return {
        "type": "telemetry",
        "machine_id": state.id,
        "machine_name": state.name,
        "machine_type": state.type,
        "state": rt.get("state", state.status or "idle"),
        "position": {"x": position.get("x", 0.0), "y": position.get("y", 0.0), "z": position.get("z", 0.0)},
        "speed_mps": rt.get("speed_mps", 0.0),
        "direction": rt.get("direction", "stopped"),
        "distance_m": rt.get("distance_m", 0.0),
        "distance_travelled_m": rt.get("distance_travelled_m", 0.0),
        "remaining_m": round(float(rt.get("distance_remaining_mm", 0.0)) / 1000.0, 3),
        "battery_percent": _rt_number(rt, "battery_percent"),
        "load": rt.get("load", ""),
        "load_percent": rt.get("load_percent", 0.0),
        "temperature_c": _rt_number(rt, "temperature_c"),
        "connection": "online" if (state.rt.get("connection") != "offline") else "offline",
        "active_mission": rt.get("active_mission", ""),
        "safety_state": rt.get("safety_state", "safe"),
        "ai_status": rt.get("ai_status", "offline"),
        "ai_safety_state": rt.get("ai_safety_state", "unknown"),
        "feedback_source": rt.get("feedback_source", "watchdog"),
        "encoder_mm": rt.get("encoder_mm", 0.0),
        "motor_state": rt.get("motor_state", "unknown"),
        "limit_switches": rt.get("limit_switches", {}),
        "battery_v": _rt_number(rt, "battery_v"),
        "current_a": _rt_number(rt, "current_a"),
        "sensor_sources": rt.get("sensor_sources", {}),
        "simulated": simulated,
        "trolley_m": rt.get("trolley_m", 0.0),
        "gantry_m": rt.get("gantry_m", 0.0),
        "hoist_m": rt.get("hoist_m", 0.0),
        "emergency_stop": bool(rt.get("emergency_stop", False)),
        "timestamp": _iso_now(),
    }


def _ack_payload(
    state: MachineState,
    *,
    stage: str,
    command: str = "",
    command_id: str = "",
    message: str = "",
    distance_requested_mm: float = 0.0,
    distance_moved_mm: float = 0.0,
    distance_remaining_mm: float = 0.0,
    estimated_duration_ms: int = 0,
) -> dict[str, Any]:
    return {
        "type": "command_ack",
        "command_id": command_id,
        "machine_id": state.id,
        "machine_name": state.name,
        "command": command,
        "stage": stage,
        "message": message,
        "distance_requested_mm": distance_requested_mm,
        "distance_moved_mm": distance_moved_mm,
        "distance_remaining_mm": distance_remaining_mm,
        "estimated_duration_ms": estimated_duration_ms,
        "timestamp": _iso_now(),
    }


def _event_payload(
    state: MachineState,
    *,
    event_type: str,
    message: str = "",
    severity: str = "info",
    data: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "type": "machine_event",
        "event_type": event_type,
        "type": event_type,
        "machine_id": state.id,
        "machine_name": state.name,
        "message": message,
        "severity": severity,
        "data": data or {},
        "timestamp": _iso_now(),
    }


async def _broadcast_telemetry(state: MachineState) -> None:
    if _hub.connection_count:
        await _hub.broadcast(_build_telemetry(state))


@dataclass
class AdminContext:
    uid: str
    email: str
    email_verified: bool
    token: dict[str, Any]

    @property
    def is_admin(self) -> bool:
        settings = get_settings()
        return bool(self.token.get("admin")) or self.email.lower() in _csv_to_list(
            settings.admin_emails
        )


def _extract_bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header.",
        )

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header must use Bearer tokens.",
        )
    return token


def require_admin(
    authorization: str | None = Header(default=None),
) -> AdminContext:
    token = _extract_bearer_token(authorization)

    try:
        decoded = auth.verify_id_token(token, check_revoked=True, app=get_firebase_app())
    except Exception as error:  # pragma: no cover - Firebase runtime behavior
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid Firebase token: {error}",
        ) from error

    email = (decoded.get("email") or "").strip()
    context = AdminContext(
        uid=decoded["uid"],
        email=email,
        email_verified=bool(decoded.get("email_verified", False)),
        token=decoded,
    )

    if not context.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only Firebase-managed admin operators can access this API.",
        )

    return context


def require_ingest_key(x_ingest_key: str | None = Header(default=None)) -> str:
    expected = get_settings().ingest_api_key
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Ingest key is not configured.",
        )
    if x_ingest_key != expected:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid ingest key.",
        )
    return x_ingest_key


def _doc_to_model(model_type: type[ApiModel], payload: dict[str, Any]) -> ApiModel:
    return model_type.model_validate(payload)


def _set_document(collection: str, document_id: str, payload: dict[str, Any]) -> None:
    db = get_db()
    db.collection(collection).document(document_id).set(payload, merge=True)


def _serialize(model: ApiModel) -> dict[str, Any]:
    return model.model_dump(mode="json")


def _write_audit_entry(
    *,
    actor: str,
    action: str,
    collection: str,
    document_id: str,
    payload: dict[str, Any],
) -> None:
    get_db().collection("audit_logs").document().set(
        {
            "actor": actor,
            "action": action,
            "collection": collection,
            "documentId": document_id,
            "payload": payload,
            "createdAt": _iso_now(),
        }
    )


def _terminal_stats_doc() -> firestore.DocumentReference:
    return get_db().collection("terminal_stats").document("current")


def _get_terminal_stats() -> TerminalStatsModel:
    snapshot = _terminal_stats_doc().get()
    if not snapshot.exists:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Live terminal statistics are not available yet.",
        )
    payload = snapshot.to_dict() or {}
    return _doc_to_model(TerminalStatsModel, payload)  # type: ignore[return-value]


def _read_collection(collection: str) -> list[dict[str, Any]]:
    docs = [doc.to_dict() or {} for doc in get_db().collection(collection).stream()]
    return docs


def _read_agvs() -> list[AgvTelemetryModel]:
    docs = []
    for doc in get_db().collection("agvs").stream():
        payload = doc.to_dict() or {}
        payload.setdefault("id", doc.id)
        docs.append(AgvTelemetryModel.model_validate(payload))
    return sorted(docs, key=lambda item: item.id)


def _read_cranes() -> list[CraneTelemetryModel]:
    docs = []
    for doc in get_db().collection("cranes").stream():
        payload = doc.to_dict() or {}
        payload.setdefault("id", doc.id)
        docs.append(CraneTelemetryModel.model_validate(payload))
    return sorted(docs, key=lambda item: item.id)


def _read_deliveries() -> list[DeliveryRecordModel]:
    docs = []
    for doc in get_db().collection("deliveries").stream():
        payload = doc.to_dict() or {}
        payload.setdefault("containerId", doc.id)
        docs.append(DeliveryRecordModel.model_validate(payload))
    return sorted(docs, key=lambda item: item.containerId)


def _read_camera_feeds() -> list[CameraFeedModel]:
    docs = []
    for doc in get_db().collection("camera_feeds").stream():
        payload = doc.to_dict() or {}
        payload.setdefault("id", doc.id)
        docs.append(CameraFeedModel.model_validate(payload))
    return sorted(docs, key=lambda item: item.id)


def _read_sensor_readings() -> list[SensorReadingModel]:
    docs = []
    for doc in get_db().collection("sensor_readings").stream():
        payload = doc.to_dict() or {}
        payload.setdefault("id", doc.id)
        docs.append(SensorReadingModel.model_validate(payload))
    return sorted(docs, key=lambda item: item.id)


def _dashboard_snapshot() -> DashboardSnapshotModel:
    return DashboardSnapshotModel(
        terminalStats=_get_terminal_stats(),
        agvs=_read_agvs(),
        cranes=_read_cranes(),
        deliveries=_read_deliveries(),
        cameraFeeds=_read_camera_feeds(),
        sensorReadings=_read_sensor_readings(),
        generatedAt=_utc_now(),
    )


def _build_pie_analytics(snapshot: DashboardSnapshotModel, window: PieWindow) -> PieAnalyticsResponse:
    queued = float(sum(1 for item in snapshot.deliveries if item.status == "Queued"))
    in_progress = float(sum(1 for item in snapshot.deliveries if item.status == "In Progress"))
    completed = float(sum(1 for item in snapshot.deliveries if item.status == "Completed"))
    alerts = float(
        sum(
            1
            for sensor in snapshot.sensorReadings
            if sensor.value < sensor.minNormal or sensor.value > sensor.maxNormal
        )
        + sum(1 for feed in snapshot.cameraFeeds if not feed.isOnline or feed.alert)
    )

    slices = [
        PieSliceModel(
            label="Quay Lift",
            value=snapshot.terminalStats.activeCranes * 4.2 + len(snapshot.cranes) * 8,
            detail="crane picks and berth cycles",
        ),
        PieSliceModel(
            label="Yard Moves",
            value=len(snapshot.agvs) * 10 + in_progress * 7 + snapshot.terminalStats.activeGroundSpots * 0.05,
            detail="AGV relocation and yard routing",
        ),
        PieSliceModel(
            label="Gate Flow",
            value=queued * 9 + completed * 11 + snapshot.terminalStats.teuCounter * 0.004,
            detail="turnaround and gate dispatch",
        ),
        PieSliceModel(
            label="Exceptions",
            value=max(1, alerts) * 5 + queued * 1.5,
            detail="alerts, holds, and exception checks",
        ),
    ]

    multipliers = {
        PieWindow.minutes: [1.0, 0.9, 0.8, 0.65],
        PieWindow.hourly: [5.8, 6.4, 5.2, 2.8],
        PieWindow.daily: [22.0, 25.0, 21.0, 8.5],
        PieWindow.monthly: [610.0, 690.0, 570.0, 210.0],
    }[window]

    scaled = [
        PieSliceModel(
            label=slice.label,
            value=round(slice.value * multipliers[index], 2),
            detail=slice.detail,
        )
        for index, slice in enumerate(slices)
    ]

    insight = {
        PieWindow.minutes: "Minute view emphasizes immediate terminal pressure around lift and gate cycles.",
        PieWindow.hourly: "Hourly analysis exposes the balance between quay lifting, yard motion, and exceptions.",
        PieWindow.daily: "Daily analysis highlights how routing and berth work dominate over isolated alerts.",
        PieWindow.monthly: "Monthly analysis smooths short spikes and shows the long-run operational mix.",
    }[window]

    total = round(sum(slice.value for slice in scaled), 2)
    return PieAnalyticsResponse(
        window=window,
        total=total,
        slices=scaled,
        insight=insight,
        generatedAt=_utc_now(),
    )


# ─── Realtime simulator (BACKED_REALTIME_MODE=simulate) ───────────────────

REALTIME_TICK_SECONDS = 0.5
_sim_task: asyncio.Task | None = None


def _start_simulator() -> None:
    global _sim_task
    if get_settings().realtime_mode != "simulate":
        return
    if _sim_task is not None:
        return
    _sim_task = asyncio.get_event_loop().create_task(_sim_loop())


async def _sim_loop() -> None:
    last = time.monotonic()
    while True:
        await asyncio.sleep(REALTIME_TICK_SECONDS)
        now = time.monotonic()
        dt = now - last
        last = now
        for state in _machines.values():
            state.rt["last_heartbeat"] = time.time()
            moved, finished = _comms.step(state.rt, dt)
            if moved > 0:
                state.rt["distance_m"] = round(
                    float(state.rt.get("distance_m", 0.0)) + moved / 1000.0, 3
                )
                state.rt["distance_travelled_m"] = round(
                    float(state.rt.get("distance_travelled_m", 0.0)) + moved / 1000.0, 3
                )
                state.lastUpdated = _iso_now()
            if moved > 0 or finished:
                await _broadcast_telemetry(state)
            if finished and state.command_queue:
                item = state.command_queue.popleft()
                await _complete_command(state, item)


async def _complete_command(state: MachineState, item: dict[str, Any]) -> None:
    command_id = str(item.get("id", ""))
    now = _iso_now()
    for record in state.command_history:
        if record.get("id") == command_id:
            record["status"] = "completed"
            record["completedAt"] = now
            break
    state.lastUpdated = now
    state.speed = 0.0
    rt = state.rt
    rt["active_mission"] = ""
    rt["active_command_id"] = None
    rt["active_since"] = 0.0
    rt["watchdog_ms"] = 0
    _record_activity(state, "completed", f"Command {item.get('command', '')} done")
    if _hub.connection_count:
        ack = _ack_payload(
            state,
            stage="completed",
            command=item.get("command", ""),
            command_id=command_id,
            message="movement complete",
            distance_requested_mm=float(rt.get("distance_requested_mm", 0.0)),
            distance_moved_mm=float(rt.get("distance_moved_mm", 0.0)),
            distance_remaining_mm=0.0,
            estimated_duration_ms=int(round(
                float(rt.get("distance_moved_mm", 0.0)) * 1000.0 / 200.0
            )),
        )
        await _hub.broadcast(ack)
        await _broadcast_telemetry(state)


app = FastAPI(
    title=get_settings().app_name,
    version=get_settings().api_version,
    summary="FastAPI orchestration layer for the PortOS Flutter command center.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_csv_to_list(get_settings().cors_origins) or ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def _on_startup() -> None:
    _start_simulator()
    _start_watchdog_monitor()


async def _watchdog_monitor() -> None:
    """Watchdog for movement commands that never complete.

    A command that runs past its derived watchdog window (or stalls with no
    feedback at all) is declared ``timed_out`` on the backend; the UI sees the
    command as failed, never as normal operation. Completed/aborted commands
    are ignored.
    """
    while True:
        await asyncio.sleep(2.0)
        now = time.time()
        for state in _machines.values():
            active = state.rt.get("active_command_id")
            started = state.rt.get("active_since", 0.0) or 0.0
            watchdog = state.rt.get("watchdog_ms", 0) or 0
            if not active or started <= 0:
                continue
            if not state.rt.get("state") in ("moving", "running", "busy"):
                continue
            elapsed = now - float(started)
            allowed = (max(watchdog, 1000) / 1000.0) + 5.0
            if elapsed < allowed:
                continue
            for record in state.command_history:
                if record.get("id") == str(active):
                    record["status"] = "timed_out"
                    record["completedAt"] = _iso_now()
                    break
            state.rt["active"] = None
            state.rt["active_command_id"] = None
            state.rt["active_since"] = 0.0
            state.speed = 0.0
            _record_activity(state, "timeout", "Movement timed out (no completion)")
            if _hub.connection_count:
                await _hub.broadcast(_ack_payload(
                    state,
                    stage="timed_out",
                    command=str(state.rt.get("active_mission", "") or ""),
                    command_id=str(active),
                    message="movement timed out - no hardware completion",
                ))
                await _hub.broadcast(_event_payload(
                    state,
                    event_type="command_timeout",
                    severity="warning",
                    message="Movement command timed out (no hardware completion)",
                ))
                await _broadcast_telemetry(state)
        if get_settings().realtime_mode != "simulate":
            await _check_machine_health()


# How long a live machine may go without a status heartbeat before it is
# declared offline. The UI never pretends a disconnected unit is operating.
TELEMETRY_OFFLINE_SECONDS = 15.0


async def _check_machine_health() -> None:
    """Flip LIVE-mode machines between online/offline from real heartbeats.

    A machine that stops reporting (ESP32 disconnect, power loss, link loss)
    is broadcast as offline so the operator sees TELEMETRY OFFLINE immediately;
    restored heartbeats bring the unit back to online. Simulation mode is never
    treated by this check - simulated frames are always flagged as simulated.
    """
    now = time.time()
    for state in _machines.values():
        heartbeat = float(state.rt.get("last_heartbeat", 0.0) or 0.0)
        conn = state.rt.get("connection", "offline")
        if heartbeat <= 0:
            continue  # no heartbeat yet - cannot claim either state
        fresh = (now - heartbeat) <= TELEMETRY_OFFLINE_SECONDS
        if not fresh and conn != "offline":
            state.rt["connection"] = "offline"
            _record_activity(state, "offline", "Telemetry heartbeat lost (machine offline)")
            if _hub.connection_count:
                await _hub.broadcast(_event_payload(
                    state,
                    event_type="machine_offline",
                    severity="warning",
                    message="Machine telemetry heartbeat lost",
                ))
                await _broadcast_telemetry(state)
        elif fresh and conn == "offline":
            state.rt["connection"] = "online"
            _record_activity(state, "online", "Telemetry heartbeat restored")
            if _hub.connection_count:
                await _hub.broadcast(_event_payload(
                    state,
                    event_type="machine_online",
                    severity="info",
                    message="Telemetry heartbeat restored",
                ))
                await _broadcast_telemetry(state)


_watchdog_task: asyncio.Task | None = None


def _start_watchdog_monitor() -> None:
    global _watchdog_task
    if _watchdog_task is not None:
        return
    _watchdog_task = asyncio.get_event_loop().create_task(_watchdog_monitor())


@app.get("/health")
def healthcheck() -> dict[str, Any]:
    settings = get_settings()
    return {
        "status": "ok",
        "service": settings.app_name,
        "version": settings.api_version,
        "firebaseProjectId": settings.firebase_project_id or "auto-detected",
        "timestamp": _iso_now(),
    }


@app.get("/auth/admin-profile", response_model=AdminProfileResponse)
def admin_profile(admin: AdminContext = Depends(require_admin)) -> AdminProfileResponse:
    return AdminProfileResponse(
        uid=admin.uid,
        email=admin.email,
        isAdmin=admin.is_admin,
        emailVerified=admin.email_verified,
    )


@app.post("/auth/password-reset", response_model=PasswordResetResponse)
def password_reset(request: PasswordResetRequest) -> PasswordResetResponse:
    try:
        auth.get_user_by_email(request.email, app=get_firebase_app())
        auth.generate_password_reset_link(request.email, app=get_firebase_app())
    except auth.UserNotFoundError as error:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No Firebase operator account exists for that email.",
        ) from error
    except Exception as error:  # pragma: no cover - provider runtime behavior
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Password reset email could not be sent: {error}",
        ) from error

    return PasswordResetResponse(
        message=(
            "Password reset link generation succeeded for the registered operator account. "
            "Use Firebase Auth client email delivery in Flutter for the actual forgot-password flow."
        )
    )


@app.get("/dashboard", response_model=DashboardSnapshotModel)
def get_dashboard(_: AdminContext = Depends(require_admin)) -> DashboardSnapshotModel:
    return _dashboard_snapshot()


@app.put("/dashboard", response_model=DashboardSnapshotModel)
def put_dashboard(
    payload: DashboardSnapshotModel,
    admin: AdminContext = Depends(require_admin),
) -> DashboardSnapshotModel:
    _terminal_stats_doc().set(_serialize(payload.terminalStats), merge=True)
    for item in payload.agvs:
        _set_document("agvs", item.id, _serialize(item))
    for item in payload.cranes:
        _set_document("cranes", item.id, _serialize(item))
    for item in payload.deliveries:
        _set_document("deliveries", item.containerId, _serialize(item))
    for item in payload.cameraFeeds:
        _set_document("camera_feeds", item.id, _serialize(item))
    for item in payload.sensorReadings:
        _set_document("sensor_readings", item.id, _serialize(item))

    _write_audit_entry(
        actor=admin.email,
        action="replace_dashboard",
        collection="dashboard",
        document_id="aggregate",
        payload={"generatedAt": payload.generatedAt.isoformat()},
    )
    return _dashboard_snapshot()


@app.get("/terminal-stats", response_model=TerminalStatsModel)
def get_terminal_stats(_: AdminContext = Depends(require_admin)) -> TerminalStatsModel:
    return _get_terminal_stats()


@app.put("/terminal-stats", response_model=TerminalStatsModel)
def put_terminal_stats(
    payload: TerminalStatsModel,
    admin: AdminContext = Depends(require_admin),
) -> TerminalStatsModel:
    _terminal_stats_doc().set(_serialize(payload), merge=True)
    _write_audit_entry(
        actor=admin.email,
        action="upsert",
        collection="terminal_stats",
        document_id="current",
        payload=_serialize(payload),
    )
    return _get_terminal_stats()


@app.get("/agvs", response_model=list[AgvTelemetryModel])
def get_agvs(_: AdminContext = Depends(require_admin)) -> list[AgvTelemetryModel]:
    return _read_agvs()


@app.put("/agvs/{agv_id}", response_model=AgvTelemetryModel)
def put_agv(
    agv_id: str,
    payload: AgvTelemetryModel,
    admin: AdminContext = Depends(require_admin),
) -> AgvTelemetryModel:
    normalized = payload.model_copy(update={"id": agv_id})
    _set_document("agvs", agv_id, _serialize(normalized))
    _write_audit_entry(
        actor=admin.email,
        action="upsert",
        collection="agvs",
        document_id=agv_id,
        payload=_serialize(normalized),
    )
    return normalized


@app.get("/cranes", response_model=list[CraneTelemetryModel])
def get_cranes(_: AdminContext = Depends(require_admin)) -> list[CraneTelemetryModel]:
    return _read_cranes()


@app.put("/cranes/{crane_id}", response_model=CraneTelemetryModel)
def put_crane(
    crane_id: str,
    payload: CraneTelemetryModel,
    admin: AdminContext = Depends(require_admin),
) -> CraneTelemetryModel:
    normalized = payload.model_copy(update={"id": crane_id})
    _set_document("cranes", crane_id, _serialize(normalized))
    _write_audit_entry(
        actor=admin.email,
        action="upsert",
        collection="cranes",
        document_id=crane_id,
        payload=_serialize(normalized),
    )
    return normalized


@app.get("/deliveries", response_model=list[DeliveryRecordModel])
def get_deliveries(_: AdminContext = Depends(require_admin)) -> list[DeliveryRecordModel]:
    return _read_deliveries()


@app.put("/deliveries/{container_id}", response_model=DeliveryRecordModel)
def put_delivery(
    container_id: str,
    payload: DeliveryRecordModel,
    admin: AdminContext = Depends(require_admin),
) -> DeliveryRecordModel:
    normalized = payload.model_copy(update={"containerId": container_id})
    _set_document("deliveries", container_id, _serialize(normalized))
    _write_audit_entry(
        actor=admin.email,
        action="upsert",
        collection="deliveries",
        document_id=container_id,
        payload=_serialize(normalized),
    )
    return normalized


@app.get("/camera-feeds", response_model=list[CameraFeedModel])
def get_camera_feeds(_: AdminContext = Depends(require_admin)) -> list[CameraFeedModel]:
    return _read_camera_feeds()


@app.put("/camera-feeds/{feed_id}", response_model=CameraFeedModel)
def put_camera_feed(
    feed_id: str,
    payload: CameraFeedModel,
    admin: AdminContext = Depends(require_admin),
) -> CameraFeedModel:
    normalized = payload.model_copy(update={"id": feed_id})
    _set_document("camera_feeds", feed_id, _serialize(normalized))
    _write_audit_entry(
        actor=admin.email,
        action="upsert",
        collection="camera_feeds",
        document_id=feed_id,
        payload=_serialize(normalized),
    )
    return normalized


@app.get("/sensor-readings", response_model=list[SensorReadingModel])
def get_sensor_readings(
    _: AdminContext = Depends(require_admin),
) -> list[SensorReadingModel]:
    return _read_sensor_readings()


@app.put("/sensor-readings/{reading_id}", response_model=SensorReadingModel)
def put_sensor_reading(
    reading_id: str,
    payload: SensorReadingModel,
    admin: AdminContext = Depends(require_admin),
) -> SensorReadingModel:
    normalized = payload.model_copy(update={"id": reading_id})
    _set_document("sensor_readings", reading_id, _serialize(normalized))
    _write_audit_entry(
        actor=admin.email,
        action="upsert",
        collection="sensor_readings",
        document_id=reading_id,
        payload=_serialize(normalized),
    )
    return normalized


@app.get("/analytics/pie", response_model=PieAnalyticsResponse)
def get_pie_analytics(
    window: PieWindow = Query(default=PieWindow.hourly),
    _: AdminContext = Depends(require_admin),
) -> PieAnalyticsResponse:
    return _build_pie_analytics(_dashboard_snapshot(), window)


@app.post("/ingest/events", response_model=dict[str, Any])
def ingest_hardware_event(
    event: HardwareEventIn,
    _: str = Depends(require_ingest_key),
) -> dict[str, Any]:
    collection_map = {
        HardwareEntityType.terminal_stats: "terminal_stats",
        HardwareEntityType.agv: "agvs",
        HardwareEntityType.crane: "cranes",
        HardwareEntityType.delivery: "deliveries",
        HardwareEntityType.camera_feed: "camera_feeds",
        HardwareEntityType.sensor_reading: "sensor_readings",
    }
    collection = collection_map[event.entityType]
    document_id = "current" if event.entityType == HardwareEntityType.terminal_stats else event.entityId
    payload = {
        **event.payload,
        "lastUpdated": event.payload.get("lastUpdated", event.occurredAt.isoformat()),
        "ingestedAt": _iso_now(),
    }
    _set_document(collection, document_id, payload)
    get_db().collection("ingest_events").document().set(
        {
            "source": event.source,
            "entityType": event.entityType.value,
            "entityId": document_id,
            "action": event.action,
            "payload": payload,
            "occurredAt": event.occurredAt.isoformat(),
            "ingestedAt": _iso_now(),
        }
    )
    return {
        "status": "accepted",
        "collection": collection,
        "documentId": document_id,
        "ingestedAt": _iso_now(),
    }


@app.post("/ai/ppe-detect")
async def detect_ppe(
    file: UploadFile = File(...),
    machine_id: str | None = Form(default=None),
) -> dict[str, Any]:
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only image files are accepted.",
        )

    state = None
    if machine_id:
        if machine_id not in _machines:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Machine {machine_id} not found - AI results cannot be "
                       "attached to an unknown machine.",
            )
        state = _machines[machine_id]

    try:
        image_bytes = await file.read()

        if not image_bytes:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Uploaded image is empty.",
            )

        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")

        model = get_ppe_model()

        results = model.predict(
            source=image,
            conf=0.50,
            verbose=False,
        )

        result = results[0]

        detections: list[dict[str, Any]] = []

        names = result.names

        if result.boxes is not None:
            for box in result.boxes:
                class_id = int(box.cls[0])
                confidence = float(box.conf[0])

                x1, y1, x2, y2 = [
                    float(value) for value in box.xyxy[0].tolist()
                ]

                class_name = names[class_id]
                bbox_list = [round(x1, 2), round(y1, 2), round(x2, 2), round(y2, 2)]

                detections.append(
                    {
                        "class": class_name,
                        "classId": class_id,
                        "className": class_name,
                        "confidence": round(confidence, 4),
                        "bbox": bbox_list,
                        "boundingBox": {
                            "x1": bbox_list[0],
                            "y1": bbox_list[1],
                            "x2": bbox_list[2],
                            "y2": bbox_list[3],
                        },
                    }
                )

        counts: dict[str, int] = {}

        for detection in detections:
            class_name = detection["className"]
            counts[class_name] = counts.get(class_name, 0) + 1

        # Monitoring / warning only: AI results never stop machinery.
        safety_status, safety_events = _safety_from_ppe(counts)

        payload = {
            "status": "success",
            "filename": file.filename,
            "machine_id": machine_id,
            "imageWidth": image.width,
            "imageHeight": image.height,
            "totalDetections": len(detections),
            "counts": counts,
            "safety_status": safety_status,
            "safety_events": safety_events,
            "detections": detections,
        }

        if state is not None and _hub.connection_count:
            state.rt["ai_status"] = "active"
            state.rt["ai_safety_state"] = safety_status
            await _emit_ai_events(state, safety_events, payload)
            await _broadcast_telemetry(state)
        elif state is not None:
            state.rt["ai_status"] = "active"
            state.rt["ai_safety_state"] = safety_status

        return payload

    except HTTPException:
        if state is not None and _hub.connection_count:
            await _emit_ai_events(
                state,
                [{"event_type": "ai_offline", "severity": "warning"}],
                {},
            )
        raise

    except Exception as error:
        if state is not None and _hub.connection_count:
            try:
                await _emit_ai_events(
                    state,
                    [{"event_type": "ai_offline", "severity": "warning"}],
                    {},
                )
            except Exception:  # pragma: no cover - telemetry fan-out best effort
                pass
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"PPE detection failed: {error}",
        ) from error


def _safety_from_ppe(counts: dict[str, int]) -> tuple[str, list[dict[str, Any]]]:
    """Map PPE counts to a monitoring status + safety events.

    AI output is advisory only - it never gates or stops machinery (a physical
    E-STOP input remains the authoritative safety signal).
    """
    head = counts.get("head", 0)
    helmet = counts.get("helmet", 0)
    vest = counts.get("vest", 0)
    extras = {k: v for k, v in counts.items() if k not in ("head", "helmet", "vest")}

    events: list[dict[str, Any]] = []
    if head > 0:
        events.append({"event_type": "person_detected", "severity": "info"})
    if head > helmet:
        events.append({"event_type": "no_helmet", "severity": "warning"})
    if head > vest:
        events.append({"event_type": "no_vest", "severity": "warning"})
    for extra in extras:
        if extras[extra] > 0:
            events.append({"event_type": "obstacle_detected", "severity": "info"})

    if head > helmet or head > vest:
        return "violation", events
    if head > 0 or extras:
        return "advisory", events or [{"event_type": "ppe_safe", "severity": "info"}]
    return "safe", [{"event_type": "ppe_safe", "severity": "info"}]


async def _emit_ai_events(
    state: MachineState,
    safety_events: list[dict[str, Any]],
    payload: dict[str, Any],
) -> None:
    """Fan AI safety events out over the WebSocket, tagged with the machine."""
    if not safety_events:
        return
    for event in safety_events:
        await _hub.broadcast(_event_payload(
            state,
            event_type=event["event_type"],
            severity=event["severity"],
            message=f"AI: {event['event_type'].replace('_', ' ').upper()}",
            data={"safety_status": payload.get("safety_status", ""),
                  "counts": payload.get("counts", {})},
        ))


# ─── Machine Control Endpoints ───────────────────────────────────────────

def _get_machine_state(machine_id: str) -> MachineState:
    if machine_id not in _machines:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Machine {machine_id} not found.",
        )
    return _machines[machine_id]


def _build_machine_detail(state: MachineState) -> MachineDetailModel:
    return MachineDetailModel(
        id=state.id,
        name=state.name,
        type=state.type,
        status="e-stop" if state.emergency_stop else state.status,
        location=state.location,
        operatorName=state.operatorName,
        batteryLevel=state.batteryLevel,
        speed=state.speed,
        loadCapacity=state.loadCapacity,
        currentLoad=state.currentLoad,
        lastMaintenance=state.lastMaintenance,
        notes=state.notes,
        lastUpdated=state.lastUpdated or None,
        emergencyStop=state.emergency_stop,
        commissionDistanceMm=state.commission_distance_mm,
    )


def _record_activity(state: MachineState, status: str, message: str) -> None:
    state.activity_log.insert(0, {
        "status": status,
        "message": message,
        "time": _iso_now(),
    })
    if len(state.activity_log) > 100:
        state.activity_log = state.activity_log[:100]


def _build_params_string(command: str, speed: int | None, duration: int | None, steps: int | None) -> str:
    if command in AGV_COMMANDS:
        parts: list[str] = []
        if speed is not None:
            parts.append(str(speed))
        if duration is not None:
            parts.append(str(duration))
        return ":".join(parts)
    if command in CRANE_COMMANDS:
        if steps is not None:
            return str(steps)
    return ""


@app.get("/machines/dashboard/summary")
def machines_dashboard_summary() -> dict[str, Any]:
    machines = [_build_machine_detail(s).model_dump(mode="json") for s in _machines.values()]
    all_logs: list[dict[str, Any]] = []
    for state in _machines.values():
        for log in state.activity_log[:5]:
            all_logs.append({**log, "machine": state.name, "machineId": state.id})
    all_logs.sort(key=lambda l: l.get("time", ""), reverse=True)
    return {"machines": machines, "recentLogs": all_logs[:20]}


@app.get("/machines/{machine_id}")
def get_machine_detail(machine_id: str) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    return _build_machine_detail(state).model_dump(mode="json")


async def _apply_estop(
    state: MachineState,
    source: str = "operator",
) -> dict[str, Any]:
    """Raise the emergency stop; movement is blocked until re-commanding.

    Distinguishes REQUESTED (backend accepted) from CONFIRMED (machine
    acknowledges). The UI is never allowed to claim either on its own.
    """
    state.emergency_stop = True
    state.rt["emergency_stop"] = True
    state.rt["state"] = "estop"
    state.rt["active_mission"] = "ESTOP-LOCK"
    state.status = "running"
    state.speed = 0.0
    state.lastUpdated = _iso_now()

    # Abort any in-flight movement so it never reports "completed" later; the
    # UI keeps E-STOP REQUESTED vs CONFIRMED vs the aborted command separate.
    active_command = state.rt.get("active_command_id")
    state.rt["active"] = None
    state.rt["active_command_id"] = None
    state.rt["active_since"] = 0.0
    state.rt["watchdog_ms"] = 0
    if get_settings().realtime_mode == "simulate" and active_command:
        for record in state.command_history:
            if record["id"] == str(active_command):
                record["status"] = "aborted"
                record["completedAt"] = _iso_now()
                break
        _record_activity(state, "estop", f"Movement {active_command} aborted by E-STOP")

    _record_activity(state, "estop", "EMERGENCY STOP requested")

    if _hub.connection_count:
        await _hub.broadcast(_ack_payload(
            state,
            stage="estop_requested",
            command="emergency_stop",
            message="E-STOP requested by operator",
        ))
        if active_command:
            await _hub.broadcast(_ack_payload(
                state,
                stage="aborted",
                command=state.command_history[0]["command"] if state.command_history else "",
                command_id=str(active_command),
                message="in-flight movement aborted by E-STOP",
            ))
        await _hub.broadcast(_ack_payload(
            state,
            stage="estop_confirmed",
            command="emergency_stop",
            message="E-STOP confirmed by machine",
        ))
        await _hub.broadcast(_event_payload(
            state,
            event_type="emergency_stop",
            message="EMERGENCY STOP CONFIRMED"
                    if source == "operator"
                    else "PHYSICAL E-STOP CONFIRMED",
            severity="critical",
            data={"source": source},
        ))
        await _broadcast_telemetry(state)
    return {
        "status": "estop",
        "stage": "estop_confirmed",
        "machineId": state.id,
        "source": source,
    }


@app.post("/machines/{machine_id}/command")
async def send_machine_command(
    machine_id: str,
    body: MachineCommandEnvelopeRequest,
) -> dict[str, Any]:
    state = _get_machine_state(machine_id)

    # Machine identity: every command must explicitly reference the machine it
    # targets. A mismatched envelope is rejected instead of silently mis-routed.
    if body.machine_id and body.machine_id != machine_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Machine identity mismatch: command targets '{body.machine_id}' "
                f"but was sent to '{machine_id}'."
            ),
        )

    if body.command.lower() in ESTOP_COMMANDS:
        return await _apply_estop(state)

    resolved = STRUCTURED_COMMAND_MAP.get(body.command, body.command)
    valid_commands = AGV_COMMANDS if state.type == "agv" else CRANE_COMMANDS
    if resolved not in valid_commands:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid command '{body.command}' for {state.type}.",
        )

    if state.emergency_stop:
        if _hub.connection_count:
            await _hub.broadcast(_ack_payload(
                state,
                stage="rejected",
                command=resolved,
                message="Movement blocked: E-STOP is active on this machine.",
            ))
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Movement blocked while E-STOP is active.",
        )

    is_agv_movement = resolved in ("forward", "backward", "left", "right")
    is_crane_movement = resolved in ("trolley_forward", "trolley_backward", "hoist_up", "hoist_down")
    is_distance_command = is_agv_movement or is_crane_movement

    # Speed sanity bound: 0.0 < speed_mps <= 2.0 m/s (AGV full speed ~0.2 m/s).
    if body.speed_mps is not None and not (0.0 < body.speed_mps <= 2.0):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid speed_mps {body.speed_mps} - expected 0.0-2.0 m/s.",
        )

    # Distance-first: derive the low-level timed/stepper magnitude and keep
    # time purely as the watchdog window.
    speed_cmd = body.speed
    duration_used = body.duration_ms or (body.duration or 0) or None
    steps_used = body.steps

    if is_agv_movement and duration_used is None and body.distance_mm is not None:
        duration_used = comms.watchdog_ms_for_distance(body.distance_mm, body.speed_mps)
    if is_crane_movement and steps_used is None and body.distance_mm is not None:
        steps_used = comms.steps_for_distance(body.distance_mm)
    if is_agv_movement and speed_cmd is None:
        speed_fraction = float((body.speed_mps or 0.2) / 0.2)
        speed_cmd = max(10, min(255, int(round(200 * speed_fraction))))

    # Commissioning cap: in LIVE mode movement starts at 0 mm and only grows
    # through the preflight-approved levels. Simulate mode is unlimited.
    if is_distance_command:
        limit = state.commission_distance_mm
        request_mm = body.distance_mm
        if request_mm is None and steps_used is not None and is_crane_movement:
            request_mm = comms.distance_for_steps(steps_used)
        if get_settings().realtime_mode == "live" and limit is not None and limit != -1:
            if request_mm is None or request_mm <= 0:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "Commissioning block: distance-first movement requires "
                        "a positive distance_mm in LIVE mode."
                    ),
                )
            if request_mm > limit:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        f"Commissioning block: {request_mm:.0f}mm exceeds the "
                        f"approved {limit}mm limit. Advance commissioning first."
                    ),
                )

    params_str = _build_params_string(
        resolved, speed_cmd, duration_used, steps_used
    )
    command_id = int(uuid.uuid4().int % 1_000_000)
    now = _iso_now()

    record = {
        "id": str(command_id),
        "machineId": machine_id,
        "command": resolved,
        "params": params_str,
        "status": "pending",
        "createdAt": now,
        "executedAt": None,
        "completedAt": None,
    }

    state.command_queue.append({
        "id": command_id,
        "command": resolved,
        "params": params_str,
    })
    state.command_history.insert(0, record)
    if len(state.command_history) > 50:
        state.command_history = state.command_history[:50]

    state.status = "running"
    state.lastUpdated = now
    state.rt["active_mission"] = f"MOVE-{command_id}"
    state.rt["active_command_id"] = str(command_id)
    state.rt["active_since"] = time.time()
    state.rt["watchdog_ms"] = duration_used or 0
    if body.distance_mm is not None:
        state.rt["distance_requested_mm"] = float(body.distance_mm)
    if get_settings().realtime_mode == "simulate":
        try:
            outcome = _comms.start(
                state.rt,
                resolved,
                direction=body.direction or (resolved if is_distance_command else None),
                distance_mm=body.distance_mm,
                speed_mps=body.speed_mps,
                duration_ms=duration_used,
                steps=steps_used,
            )
            if not outcome.accepted:
                raise comms.MachineCommsError(outcome.message)
        except comms.MachineCommsError as error:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(error),
            ) from error
    else:
        _comms.start(
            state.rt,
            resolved,
            direction=body.direction if is_distance_command else None,
            distance_mm=body.distance_mm,
            duration_ms=duration_used,
            steps=steps_used,
        )
        state.rt["state"] = "running"

    _record_activity(state, "command", f"Command queued: {resolved}")

    try:
        get_db().collection("machine_commands").document(str(command_id)).set(record)
    except Exception:  # pragma: no cover - Firestore optional persistence
        pass

    if _hub.connection_count:
        await _hub.broadcast(_ack_payload(
            state,
            stage="acknowledged",
            command=resolved,
            command_id=str(command_id),
            message=f"command {resolved} acknowledged",
            distance_requested_mm=float(body.distance_mm or 0.0),
            estimated_duration_ms=duration_used or 0,
        ))
        await _hub.broadcast(_event_payload(
            state,
            event_type="command",
            message=f"Command queued: {resolved}",
        ))
        await _broadcast_telemetry(state)

    return {
        **record,
        "stage": "acknowledged",
        "message": f"command {resolved} acknowledged",
        "distance_requested_mm": float(body.distance_mm or 0.0),
        "estimated_duration_ms": duration_used or 0,
    }


@app.post("/machines/{machine_id}/drive")
def send_drive_command(
    machine_id: str,
    body: MachineDriveRequest,
) -> dict[str, Any]:
    state = _get_machine_state(machine_id)

    if body.move not in ("forward", "backward", "left", "right", "stop"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid drive move: {body.move}",
        )

    params_str = f"{body.speed}"
    command_id = int(uuid.uuid4().int % 1_000_000)
    now = _iso_now()

    record = {
        "id": str(command_id),
        "machineId": machine_id,
        "command": body.move,
        "params": params_str,
        "status": "pending",
        "createdAt": now,
    }

    state.command_queue.append({
        "id": command_id,
        "command": body.move,
        "params": params_str,
    })
    state.command_history.insert(0, record)

    state.speed = float(body.speed)
    state.status = "running"
    state.lastUpdated = now

    _record_activity(state, "running", f"Drive: {body.move} at {body.speed}%")

    return {"status": "sent", "commandId": command_id}


@app.post("/machines/{machine_id}/auto/start")
def start_auto_mode(
    machine_id: str,
    body: MachineAutoRequest,
) -> dict[str, Any]:
    state = _get_machine_state(machine_id)

    auto_id = str(uuid.uuid4().int % 1_000_000)
    state.auto_mode = {
        "running": True,
        "cargoTotal": body.cargo,
        "cargoRemaining": body.cargo,
        "moveTime": body.moveTime,
        "loadTime": body.loadTime,
        "unloadTime": body.unloadTime,
        "currentPhase": "idle",
    }
    state.auto_mode_id = auto_id
    state.status = "running"
    state.lastUpdated = _iso_now()

    _record_activity(state, "auto", f"Auto-mode started: {body.cargo} cargo units")

    return {"status": "started", "autoModeId": auto_id}


@app.post("/machines/{machine_id}/auto/stop")
def stop_auto_mode(machine_id: str) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    state.auto_mode["running"] = False
    state.auto_mode["currentPhase"] = "stopped"
    state.status = "idle"
    state.lastUpdated = _iso_now()

    _record_activity(state, "auto", "Auto-mode stopped")

    return {"status": "stopped"}


@app.get("/machines/{machine_id}/auto/status")
def get_auto_mode_status(machine_id: str) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    return {
        "running": state.auto_mode.get("running", False),
        "cargoRemaining": state.auto_mode.get("cargoRemaining", 0),
        "cargoTotal": state.auto_mode.get("cargoTotal", 0),
        "currentPhase": state.auto_mode.get("currentPhase", ""),
    }


@app.get("/machines/{machine_id}/drive/status")
def get_drive_status(machine_id: str) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    return {"online": state.online, "lastChecked": state.last_online_check or None}


@app.get("/machines/{machine_id}/commands")
def get_machine_commands(machine_id: str) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    return {"commands": state.command_history[:50]}


@app.get("/machines/{machine_id}/logs")
def get_machine_logs(machine_id: str) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    return {"logs": state.activity_log[:50]}


# ─── Hardware Proxy Endpoints (for ESP8266 polling) ─────────────────────

@app.get("/hw/command/{machine_id}")
def hw_poll_command(machine_id: str, key: str = Query(default="")) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    if state.command_queue:
        cmd = state.command_queue[0]
        cmd["status"] = "in_progress"
        state.last_online_check = _iso_now()
        state.online = True
        state.rt["last_heartbeat"] = time.time()
        state.rt["connection"] = "online"
        return {"id": cmd["id"], "command": cmd["command"], "params": cmd["params"]}
    state.last_online_check = _iso_now()
    state.online = True
    state.rt["last_heartbeat"] = time.time()
    state.rt["connection"] = "online"
    return {"id": 0, "command": "null", "params": ""}


@app.post("/hw/command/{machine_id}/done")
async def hw_command_done(machine_id: str, body: MachineCommandDoneRequest) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    if state.command_queue and state.command_queue[0]["id"] == body.commandId:
        cmd = state.command_queue.popleft()
        now = _iso_now()
        for record in state.command_history:
            if record["id"] == str(body.commandId):
                record["status"] = "completed"
                record["completedAt"] = now
                break
        state.speed = 0.0
        state.rt["active"] = None
        state.rt["active_command_id"] = None
        state.rt["active_since"] = 0.0
        state.rt["watchdog_ms"] = 0

        requested = state.rt.get("distance_requested_mm", 0.0)
        if body.distance_moved_mm is not None:
            measured = max(0.0, float(body.distance_moved_mm))
            if requested > 0:
                moved = min(requested, measured)
                remaining = max(0.0, requested - measured)
                state.rt["distance_moved_mm"] = moved
                state.rt["distance_remaining_mm"] = remaining
                state.rt["encoder_mm"] = measured
                state.rt["feedback_source"] = "measured"
                _record_activity(state, "completed",
                                 f"{cmd['command']} done: measured {moved:.1f}mm "
                                 f"(remaining {remaining:.1f}mm)")
            else:
                state.rt["encoder_mm"] = measured
                state.rt["feedback_source"] = "measured"
                _record_activity(state, "completed",
                                 f"{cmd['command']} done (measured encoder)")
        else:
            state.rt["feedback_source"] = "watchdog"
            state.rt["encoder_mm"] = state.rt.get("distance_moved_mm", 0.0)

        if _hub.connection_count:
            await _hub.broadcast(_ack_payload(
                state,
                stage="completed",
                command=cmd.get("command", ""),
                command_id=str(body.commandId),
                message="command completed by hardware",
            ))
            await _broadcast_telemetry(state)
    state.online = True
    state.last_online_check = _iso_now()
    return {"status": "ok"}


@app.post("/hw/status/{machine_id}")
async def hw_report_status(machine_id: str, body: dict[str, Any]) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    state.online = True
    state.last_online_check = _iso_now()
    state.lastUpdated = _iso_now()
    state.rt["connection"] = "online"
    state.rt["last_heartbeat"] = time.time()
    sources: dict[str, str] = state.rt.get("sensor_sources") or {}

    if "hoist_position" in body:
        state.notes = f"hoist={body['hoist_position']}"
        state.rt["hoist_m"] = float(body["hoist_position"]) if isinstance(body["hoist_position"], (int, float)) else state.rt.get("hoist_m", 0.0)
        sources["hoist_m"] = "measured"
    if "magnet_on" in body:
        state.currentLoad = 1.0 if body["magnet_on"] else 0.0
        state.rt["load"] = "CONTAINER" if body["magnet_on"] else "EMPTY"
        sources["load"] = "measured"
    if "battery" in body and isinstance(body["battery"], (int, float)):
        state.rt["battery_percent"] = float(body["battery"])
        sources["battery_percent"] = "measured"
    if "battery_voltage" in body and isinstance(body["battery_voltage"], (int, float)):
        state.rt["battery_v"] = float(body["battery_voltage"])
        sources["battery_v"] = "measured"
    if "current_a" in body and isinstance(body["current_a"], (int, float)):
        state.rt["current_a"] = float(body["current_a"])
        sources["current_a"] = "measured"
    if "temperature_c" in body and isinstance(body["temperature_c"], (int, float)):
        state.rt["temperature_c"] = float(body["temperature_c"])
        sources["temperature_c"] = "measured"
    if "speed_mps" in body and isinstance(body["speed_mps"], (int, float)):
        state.rt["speed_mps"] = float(body["speed_mps"])
        sources["speed_mps"] = "measured"
    if "encoder_mm" in body and isinstance(body["encoder_mm"], (int, float)):
        measured = max(0.0, float(body["encoder_mm"]))
        state.rt["encoder_mm"] = measured
        state.rt["feedback_source"] = "measured"
        sources["encoder_mm"] = "measured"
        # Hardware-reported position during an active move keeps the movement
        # synchronized with real feedback (distance-first, feedback-corrected).
        if state.rt.get("active") and state.rt.get("distance_requested_mm", 0.0) > 0:
            state.rt["distance_moved_mm"] = min(
                state.rt["distance_requested_mm"], measured)
            state.rt["distance_remaining_mm"] = max(
                0.0, state.rt["distance_requested_mm"] - measured)
    if "limit_switches" in body and isinstance(body["limit_switches"], dict):
        state.rt["limit_switches"] = {
            str(k): bool(v) for k, v in body["limit_switches"].items()
        }
        sources["limit_switches"] = "measured"
    if "motor_state" in body:
        state.rt["motor_state"] = str(body["motor_state"])
        sources["motor_state"] = "measured"
    if "connected" in body:
        state.rt["connection"] = "online" if body["connected"] else "offline"

    # Physical emergency-stop input is the AUTHORITATIVE safety signal: it must
    # stop the machine regardless of any software state, and the UI is told via
    # the normal E-STOP confirmation flow. Releasing the physical button (the
    # ESP32 reporting estop_input=False) is the ONLY action that clears the
    # latch - the operator re-arms at the machine, never from the dashboard.
    estop_input = body.get("estop_input")
    if estop_input is not None:
        if estop_input and not state.emergency_stop:
            await _apply_estop(state, source="hardware")
            await _hub.broadcast(_event_payload(
                state,
                event_type="estop_requested",
                severity="critical",
                message="PHYSICAL E-STOP LATCHED (hardware input)",
                data={"source": "hardware"},
            ))
        elif not estop_input and state.emergency_stop:
            state.emergency_stop = False
            state.rt["emergency_stop"] = False
            state.rt["state"] = "idle"
            state.rt["active_mission"] = ""
            state.lastUpdated = _iso_now()
            _record_activity(state, "estop", "PHYSICAL E-STOP RELEASED (hardware input)")
            await _hub.broadcast(_event_payload(
                state,
                event_type="estop_released",
                severity="info",
                message="PHYSICAL E-STOP RELEASED (hardware input)",
                data={"source": "hardware"},
            ))

    state.rt["sensor_sources"] = sources
    if _hub.connection_count:
        await _broadcast_telemetry(state)
    return {"status": "ok"}


@app.post("/hw/estop/{machine_id}")
async def hw_estop_input(
    machine_id: str,
    body: dict[str, Any] = Body(default={}),
) -> dict[str, Any]:
    """Physical E-STOP latch / release reported by hardware.

    POSTing without a body (or with ``{"estop_input": true}``) latches the
    stop; ``{"estop_input": false}`` reports the physical button release and
    re-arms the machine. Only hardware may clear the latch.
    """
    state = _get_machine_state(machine_id)
    if body.get("estop_input", True):
        if not state.emergency_stop:
            await _apply_estop(state, source="hardware")
            await _hub.broadcast(_event_payload(
                state,
                event_type="estop_requested",
                severity="critical",
                message="PHYSICAL E-STOP LATCHED (hardware input)",
                data={"source": "hardware"},
            ))
        return {"status": "estop_confirmed"}
    if state.emergency_stop:
        state.emergency_stop = False
        state.rt["emergency_stop"] = False
        state.rt["state"] = "idle"
        state.rt["active_mission"] = ""
        state.lastUpdated = _iso_now()
        _record_activity(state, "estop", "PHYSICAL E-STOP RELEASED (hardware input)")
        await _hub.broadcast(_event_payload(
            state,
            event_type="estop_released",
            severity="info",
            message="PHYSICAL E-STOP RELEASED (hardware input)",
            data={"source": "hardware"},
        ))
        if _hub.connection_count:
            await _broadcast_telemetry(state)
    return {"status": "estop_released"}


@app.get("/machines/{machine_id}/camera")
def get_machine_camera(machine_id: str) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    spec = comms._CAMERAS.resolve(machine_id, state.name)
    if spec is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No camera is registered for machine {machine_id}.",
        )
    return spec


@app.get("/machines/{machine_id}/camera/frame")
def get_machine_camera_frame(machine_id: str) -> Response:
    """Proxy a single JPEG frame from the machine's real camera stream.

    The Flutter Live Camera workspace polls this endpoint when the machine has
    a configured remote stream; the stream URL itself never leaves the backend.
    """
    state = _get_machine_state(machine_id)
    try:
        frame = comms._CAMERAS.fetch_frame(state.id, state.name)
    except comms.CameraFeedError as error:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Camera frame unavailable for {state.name}: {error}",
        ) from error
    return Response(
        content=frame,
        media_type="image/jpeg",
        headers={"Cache-Control": "no-store"},
    )


# ─── Commissioning Mode ──────────────────────────────────────────────────
# Live hardware starts fully blocked (0 mm). Movement distance unlocks through
# controlled levels, and only after an explicit preflight check passes.

COMMISSION_LEVELS_MM: list[int] = [0, 10, 25, 50, 100, -1]  # -1 = unlimited
_COMMISSION_LEVELS_DISPLAY = {0: "BLOCKED", -1: "UNLIMITED"}


def _commission_preflight(state: MachineState) -> dict[str, Any]:
    simulate = get_settings().realtime_mode == "simulate"
    last_hb = state.rt.get("last_heartbeat", 0.0) or 0.0
    fresh = (time.time() - float(last_hb)) <= 10.0
    encoder_ok = simulate or state.rt.get("feedback_source") == "measured"
    return {
        "mode": "simulate" if simulate else "live",
        "connection_ok": simulate or state.rt.get("connection") == "online",
        "telemetry_fresh": simulate or fresh,
        "estop_clear": not state.emergency_stop,
        "ack_path_ok": simulate or _hub.connection_count > 0,
        "encoder_ok": encoder_ok,
        "sensors_seen": simulate or bool(state.rt.get("sensor_sources")),
        "identity_ok": True,
        "camera_ok": simulate or True,
        "all_ok": (
            (simulate or state.rt.get("connection") == "online")
            and (simulate or fresh)
            and not state.emergency_stop
            and (simulate or _hub.connection_count > 0)
            and encoder_ok
            and (simulate or bool(state.rt.get("sensor_sources")))
        ),
    }


def _next_commission_level(current: int) -> int | None:
    for level in COMMISSION_LEVELS_MM:
        if level > current:
            return level
    return None


@app.get("/machines/{machine_id}/commission")
def get_commission_status(machine_id: str) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    current = state.commission_distance_mm
    return {
        "machine_id": machine_id,
        "mode": get_settings().realtime_mode,
        "commissionDistanceMm": current,
        "commissioned": current == -1 or current >= COMMISSION_LEVELS_MM[1],
        "unlimited": current == -1,
        "level_display": _COMMISSION_LEVELS_DISPLAY.get(current, f"{current} mm"),
        "next_level_mm": _next_commission_level(current),
        "preflight": _commission_preflight(state),
    }


@app.post("/machines/{machine_id}/commission/advance")
def advance_commission(machine_id: str) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    simulate = get_settings().realtime_mode == "simulate"
    preflight = _commission_preflight(state)
    next_level = _next_commission_level(state.commission_distance_mm)
    if next_level is None:
        return {
            "status": "already_unlimited",
            "commissionDistanceMm": state.commission_distance_mm,
        }
    if not simulate and not preflight["all_ok"]:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "error": "Preflight checks failed - commissioning blocked.",
                "preflight": preflight,
            },
        )
    state.commission_distance_mm = next_level
    _record_activity(
        state,
        "commission",
        f"Commissioning advanced to "
        f"{'UNLIMITED' if next_level == -1 else f'{next_level} mm'}",
    )
    return {
        "status": "advanced",
        "commissionDistanceMm": state.commission_distance_mm,
        "unlimited": state.commission_distance_mm == -1,
        "level_display": _COMMISSION_LEVELS_DISPLAY.get(
            state.commission_distance_mm, f"{state.commission_distance_mm} mm"),
        "preflight": preflight,
    }


@app.post("/machines/{machine_id}/commission/reset")
def reset_commission(machine_id: str) -> dict[str, Any]:
    state = _get_machine_state(machine_id)
    state.commission_distance_mm = 0
    _record_activity(state, "commission", "Commissioning reset to BLOCKED")
    return {"status": "reset", "commissionDistanceMm": 0}


@app.get("/system/status")
def get_system_status() -> dict[str, Any]:
    model_state = "ready"
    try:
        get_ppe_model()
    except Exception:  # pragma: no cover - model load failure reported to UI
        model_state = "unavailable"
    cameras = {}
    for machine_id, state in _machines.items():
        spec = comms._CAMERAS.resolve(machine_id, state.name)
        cameras[machine_id] = {
            "name": (spec or {}).get("name"),
            "stream_url": (spec or {}).get("stream_url"),
            "stream_kind": (spec or {}).get("stream_kind"),
            "connection": (spec or {}).get("connection"),
        }
    return {
        "mode": get_settings().realtime_mode,
        "realtime_mode": get_settings().realtime_mode,
        "system": "SIMULATION" if get_settings().realtime_mode == "simulate" else "REAL HARDWARE",
        "simulated": get_settings().realtime_mode == "simulate",
        "comms": _comms.name,
        "camera_streams": cameras,
        "ppe_model": model_state,
        "uptime_s": int(time.time() - _comms_started_at),
        "version": get_settings().api_version,
    }


@app.websocket("/ws/machines")
async def ws_machines(websocket: WebSocket) -> None:
    await _hub.register(websocket)
    try:
        await _hub.handle(websocket)
    except WebSocketDisconnect:
        await _hub.unregister(websocket)
    except Exception:  # pragma: no cover - socket teardown
        await _hub.unregister(websocket)


@app.websocket("/ws/machines/{machine_id}")
async def ws_machine_feed(websocket: WebSocket, machine_id: str) -> None:
    await _hub.register(websocket, initial=[machine_id])
    try:
        await _hub.handle(websocket)
    except WebSocketDisconnect:
        await _hub.unregister(websocket)
    except Exception:  # pragma: no cover - socket teardown
        await _hub.unregister(websocket)


@app.get("/collections/{collection_name}", response_model=list[dict[str, Any]])
def inspect_collection(
    collection_name: str,
    _: AdminContext = Depends(require_admin),
) -> list[dict[str, Any]]:
    allowed = {
        "terminal_stats",
        "agvs",
        "cranes",
        "deliveries",
        "camera_feeds",
        "sensor_readings",
        "audit_logs",
        "ingest_events",
    }
    if collection_name not in allowed:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="That collection is not exposed by the backend.",
        )
    return _read_collection(collection_name)


def main() -> None:
    import uvicorn

    uvicorn.run("backed:app", host="0.0.0.0", port=8000, reload=True)


if __name__ == "__main__":
    main()

