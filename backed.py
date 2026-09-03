from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from enum import Enum
from functools import lru_cache
from typing import Any
import io

import firebase_admin
from fastapi import Depends, FastAPI, Header, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from firebase_admin import auth, credentials, firestore
from pathlib import Path

from fastapi import File, UploadFile
from PIL import Image
from ultralytics import YOLO


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
) -> dict[str, Any]:
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only image files are accepted.",
        )

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

                detections.append(
                    {
                        "classId": class_id,
                        "className": names[class_id],
                        "confidence": round(confidence, 4),
                        "boundingBox": {
                            "x1": round(x1, 2),
                            "y1": round(y1, 2),
                            "x2": round(x2, 2),
                            "y2": round(y2, 2),
                        },
                    }
                )

        counts: dict[str, int] = {}

        for detection in detections:
            class_name = detection["className"]
            counts[class_name] = counts.get(class_name, 0) + 1

        return {
            "status": "success",
            "filename": file.filename,
            "imageWidth": image.width,
            "imageHeight": image.height,
            "totalDetections": len(detections),
            "counts": counts,
            "detections": detections,
        }

    except HTTPException:
        raise

    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"PPE detection failed: {error}",
        ) from error


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

    uvicorn.run("backed:app", host="0.0.0.0", port=8000, reload=False)


if __name__ == "__main__":
    main()

