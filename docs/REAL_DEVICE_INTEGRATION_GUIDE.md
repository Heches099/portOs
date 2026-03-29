# Real Device Integration Guide

This guide maps the current PortOS codebase to the exact places where real AGV, crane, camera, Arduino, Raspberry Pi, PLC, and sensor data should be connected.

Line numbers below are current for this workspace on 2026-03-28. If files move later, re-run `nl -ba <file>` before editing.

## 1. Recommended architecture

For this project, the safest and cleanest production path is:

```text
Real device
  -> Raspberry Pi / edge gateway / vendor adapter
  -> FastAPI ingest endpoint
  -> Firestore collections
  -> Flutter stream watchers
  -> Providers
  -> Dashboard widgets
```

That path already matches the current app structure:

- `backed.py:722-759` accepts hardware events through `POST /ingest/events`.
- `lib/services/port_api_service.dart:41-132` watches Firestore collections and converts them into Flutter models.
- `lib/providers/operations_repository.dart:91-147` and `lib/providers/terminal_state_provider.dart:36-63` subscribe to those streams and push live updates into the UI.

## 2. The exact files that already control live data

### App entry and dependency wiring

- `lib/main.dart:28-53`
  This is where `PortApiService`, `OperationsRepository`, and `TerminalStateProvider` are created. If you later add a new device bridge service or backend client, register it here.

- `lib/app_bootstrap.dart:15-44`
  Firebase is initialized here. If Firebase is not available, the app falls back to demo mode, so real hardware data will never reach the dashboard until this bootstrap succeeds.

### The main live-data service

- `lib/services/port_api_service.dart:18-21`
  `PORT_API_BASE_URL` is declared here.

- `lib/services/port_api_service.dart:41-55`
  `getLiveTerminalStats()` streams the `terminal_stats/current` document.

- `lib/services/port_api_service.dart:57-70`
  `watchAgvs()` streams the `agvs` collection.

- `lib/services/port_api_service.dart:72-85`
  `watchCranes()` streams the `cranes` collection.

- `lib/services/port_api_service.dart:87-102`
  `watchDeliveries()` streams the `deliveries` collection.

- `lib/services/port_api_service.dart:104-117`
  `watchCameraFeeds()` streams the `camera_feeds` collection.

- `lib/services/port_api_service.dart:119-132`
  `watchSensorReadings()` streams the `sensor_readings` collection.

- `lib/services/port_api_service.dart:146-199`
  Demo seed data is written here when Firestore is empty. Once you depend on real devices, this is the section to keep in mind if mock data appears unexpectedly.

- `lib/services/port_api_service.dart:201-226`
  These helper methods define the exact Firestore collections the app reads from.

Important inference from the codebase:

- `PORT_API_BASE_URL` is declared, but there is no HTTP client code in `PortApiService` yet. The current Flutter app is Firestore-first, not FastAPI-polling. For now, hardware should write to Firestore directly or through `backed.py`, and the app will read from Firestore.

### The provider layer that turns streams into dashboard state

- `lib/providers/operations_repository.dart:91-147`
  This is the core subscription point for AGV, crane, delivery, camera, and sensor streams. If a real device feed updates Firestore correctly, the dashboard updates from here.

- `lib/providers/operations_repository.dart:158-167`
  This activates demo data. If you are troubleshooting why real hardware is not appearing, check whether the app is falling back here.

- `lib/providers/terminal_state_provider.dart:36-63`
  This is the live terminal stats connection.

- `lib/providers/terminal_state_provider.dart:70-78`
  Delivery status updates from the app are written back to Firestore here.

### Current mock source

- `lib/services/demo_port_data.dart:27-236`
  This file shows the exact sample payload shapes used today for AGVs, cranes, deliveries, camera feeds, and sensors. It is the quickest reference for what real payloads need to look like.

## 3. Exact UI files that consume real data

These files do not connect to hardware directly. They display whatever the provider layer gives them.

- `lib/screens/home_screen.dart:494-572`
  CCTV page. It reads `operations.cameraFeeds`.

- `lib/screens/home_screen.dart:575-683`
  IoT page. It reads `operations.sensorReadings`, `operations.agvs`, and `operations.cranes`.

- `lib/screens/home_screen.dart:1349-1353`
  Radar stage uses AGV and delivery data.

- `lib/screens/home_screen.dart:1472-1482`
  Predictive dispatch panel uses AGV speed and delivery priority data.

- `lib/screens/home_screen.dart:1922-1965`
  Anomaly deck flags out-of-range sensors and camera issues.

### Current camera panel behavior

- `lib/widgets/live_camera_spotlight.dart:69-142`
  The app initializes the local device camera here with `availableCameras()`.

- `lib/widgets/live_camera_spotlight.dart:324-326`
  Camera preview is rendered here.

- `lib/widgets/live_camera_spotlight.dart:468-490`
  The overlay text explicitly describes the source as the current device camera.

- `lib/widgets/live_camera_spotlight.dart:529-560`
  `CameraPreview(controller)` is the final live preview widget.

Important inference from the codebase:

- The current CCTV spotlight is not showing IP camera, NVR, RTSP, or HLS streams yet. It is showing the phone/tablet/webcam camera from the device running the app.

## 4. Exact model files that define the real payload shape

Your external systems must match these models.

- `lib/models/agv_telemetry.dart:4-48`
  Required AGV fields: `id`, `x`, `y`, `batteryLevel`, `speedKph`, `status`, `zone`, `lastUpdated`.

- `lib/models/crane_telemetry.dart:4-45`
  Required crane fields: `id`, `loadTons`, `hookHeightMeters`, `utilization`, `status`, `operatorName`, `lastUpdated`.

- `lib/models/camera_feed.dart:4-45`
  Required camera fields today: `id`, `title`, `location`, `isOnline`, `viewers`, `lastUpdated`, `alert`.

- `lib/models/sensor_reading.dart:4-45`
  Required sensor fields: `id`, `label`, `unit`, `value`, `minNormal`, `maxNormal`, `timestamp`.

- `lib/models/terminal_stats.dart:4-109`
  Required terminal KPI fields: `teuCounter`, `efficiency`, `activeCranes`, `yardUtilization`, `avgDwellDays`, `activeGroundSpots`, `liveSources`, `digitalTwinSector`, `predictionWindowHours`, `lastSync`.

- `lib/models/model_parsers.dart:22-41`
  Timestamps can arrive as Firestore `Timestamp`, Dart `DateTime`, ISO-8601 string, or epoch milliseconds.

- `lib/utils/extensions.dart:10-12`
  Sensor alarms are currently decided by `value >= minNormal && value <= maxNormal`.

## 5. Exact backend files for real hardware ingestion

If you want real equipment data to flow safely into the app, this backend is already the best insertion point.

- `backed.py:83-157`
  Pydantic models define the backend payload schema for terminal stats, AGVs, cranes, deliveries, cameras, and sensors.

- `backed.py:196-212`
  `HardwareEntityType` and `HardwareEventIn` define the generic ingest event format for external hardware.

- `backed.py:329-410`
  These functions read Firestore collections and build the dashboard snapshot.

- `backed.py:576-711`
  These are direct admin upsert endpoints for terminal stats, AGVs, cranes, deliveries, camera feeds, and sensor readings.

- `backed.py:722-759`
  This is the hardware/event ingest endpoint:
  `POST /ingest/events`

- `.env.example:1-9`
  Backend environment variables live here, including `BACKED_INGEST_API_KEY`.

- `BACKED_SETUP.md:5-11`
  High-level summary of what the backend already supports.

## 6. Which exact collection each real device should write to

### AGV telemetry

Write to:

- Firestore collection `agvs`
- Or backend entity type `agv`

Relevant code:

- `backed.py:96-105`
- `backed.py:597-617`
- `backed.py:727-735`
- `lib/services/port_api_service.dart:57-70`
- `lib/providers/operations_repository.dart:105-112`
- `lib/models/agv_telemetry.dart:4-48`

Best for:

- AGV GPS or indoor position
- Battery
- Speed
- Zone
- State such as `Idle`, `Charging`, `Delivering`

### Crane telemetry

Write to:

- Firestore collection `cranes`
- Or backend entity type `crane`

Relevant code:

- `backed.py:107-115`
- `backed.py:620-640`
- `backed.py:729-730`
- `lib/services/port_api_service.dart:72-85`
- `lib/providers/operations_repository.dart:113-120`
- `lib/models/crane_telemetry.dart:4-45`

Best for:

- Hook height
- Load tonnage
- Utilization
- Operator or assigned crew
- Status such as `Active`, `Standby`, `Fault`

### Camera health and stream metadata

Write to:

- Firestore collection `camera_feeds`
- Or backend entity type `camera_feed`

Relevant code:

- `backed.py:130-138`
- `backed.py:666-686`
- `backed.py:732-733`
- `lib/services/port_api_service.dart:104-117`
- `lib/providers/operations_repository.dart:129-136`
- `lib/models/camera_feed.dart:4-45`
- `lib/screens/home_screen.dart:494-572`
- `lib/widgets/live_camera_spotlight.dart:69-142`

Use this collection for:

- Camera online or offline state
- Viewer count
- Alert text
- Last heartbeat
- Stream URL metadata after you extend the model

Important note:

- To display real CCTV streams, `CameraFeed` should be extended with fields such as `streamUrl`, `thumbnailUrl`, `protocol`, and maybe `latencyMs`. Then `lib/widgets/live_camera_spotlight.dart` should be changed from `CameraController` to a network stream player such as `VideoPlayerController`.

### Sensors from Arduino, PLC, Modbus, GPIO, or Raspberry Pi

Write to:

- Firestore collection `sensor_readings`
- Or backend entity type `sensor_reading`

Relevant code:

- `backed.py:140-148`
- `backed.py:689-711`
- `backed.py:733-734`
- `lib/services/port_api_service.dart:119-132`
- `lib/providers/operations_repository.dart:137-144`
- `lib/models/sensor_reading.dart:4-45`
- `lib/screens/home_screen.dart:586-676`
- `lib/utils/extensions.dart:10-12`

Best for:

- Temperature
- Humidity
- Vibration
- Voltage
- Door state
- Load cell data
- Proximity and occupancy sensors

### Terminal-wide KPIs from PLC, TOS, ERP, or port middleware

Write to:

- Firestore document `terminal_stats/current`
- Or backend entity type `terminal_stats`

Relevant code:

- `backed.py:83-94`
- `backed.py:329-349`
- `backed.py:576-595`
- `backed.py:727-728`
- `lib/services/port_api_service.dart:41-55`
- `lib/providers/terminal_state_provider.dart:44-55`
- `lib/models/terminal_stats.dart:4-109`

Best for:

- TEU counter
- Yard utilization
- Active cranes
- Dwell time
- Live source count
- Digital twin sector

### Delivery and gate workflow data

Write to:

- Firestore collection `deliveries`
- Or backend entity type `delivery`

Relevant code:

- `backed.py:117-127`
- `backed.py:643-663`
- `backed.py:731-732`
- `lib/services/port_api_service.dart:87-102`
- `lib/services/port_api_service.dart:134-144`
- `lib/providers/terminal_state_provider.dart:70-78`

Best for:

- Container release status
- Gate-out ETA
- Verification status
- Exception reason

## 7. The best place for Arduino and Raspberry Pi specifically

### Best production pattern

For Arduino and Raspberry Pi, the best design is:

```text
Arduino sensor
  -> serial / Modbus / GPIO
  -> Raspberry Pi gateway service
  -> POST /ingest/events in backed.py
  -> Firestore
  -> Flutter watchers
```

Why this is best:

- The Flutter app already watches Firestore.
- The backend already has an ingest key mechanism in `backed.py:281-293`.
- You avoid putting hardware secrets or serial protocol logic into the mobile UI.
- A Raspberry Pi is a much better place than Flutter to run long-lived serial, MQTT, Modbus, CAN, or OPC-UA adapters.

### Minimal hardware event example

Endpoint defined in:

- `backed.py:722-759`

Example AGV payload:

```json
{
  "source": "pi-yard-gateway-01",
  "entityType": "agv",
  "entityId": "AGV-01",
  "action": "upsert",
  "payload": {
    "id": "AGV-01",
    "x": 0.42,
    "y": 0.61,
    "batteryLevel": 78.5,
    "speedKph": 9.2,
    "status": "Delivering",
    "zone": "Bay 02",
    "lastUpdated": "2026-03-28T15:30:00Z"
  }
}
```

Example sensor payload from Arduino through Raspberry Pi:

```json
{
  "source": "pi-sensor-gateway-02",
  "entityType": "sensor_reading",
  "entityId": "sensor-vibration-07",
  "action": "upsert",
  "payload": {
    "id": "sensor-vibration-07",
    "label": "Vibration",
    "unit": "Hz",
    "value": 14.7,
    "minNormal": 5.0,
    "maxNormal": 12.0,
    "timestamp": "2026-03-28T15:31:00Z"
  }
}
```

## 8. If you want direct native hardware connection inside the Flutter app

This is possible, but it should be reserved for kiosk or tablet scenarios where the device running Flutter is physically attached to the equipment.

### Where to add Flutter-side packages

- `pubspec.yaml:9-26`

This is where you would add packages for:

- serial or USB
- Bluetooth
- MQTT
- WebSocket
- OPC-UA bridge clients
- vendor camera SDK wrappers

Important observation:

- `pubspec.yaml:17-20` already includes `video_player` and `camera`.
- The codebase currently uses `camera` in `lib/widgets/live_camera_spotlight.dart`, but there is no `video_player` usage yet.

### Android native bridge

- `android/app/src/main/kotlin/com/example/tech/MainActivity.kt:1-5`

This file is currently an empty `FlutterActivity`. This is the exact place to add:

- `MethodChannel`
- `EventChannel`
- native USB serial bridge
- Bluetooth bridge
- vendor SDK bridge

### Android permissions and features

- `android/app/src/main/AndroidManifest.xml:1-35`
  Main manifest currently declares only `CAMERA`.

- `android/app/src/debug/AndroidManifest.xml:1-6`
  Development build declares `INTERNET`.

- `android/app/src/profile/AndroidManifest.xml:1-6`
  Profile build declares `INTERNET`.

Important note:

- If you want real backend traffic, RTSP/HLS camera streams, MQTT, or device APIs in release builds, add `android.permission.INTERNET` to `android/app/src/main/AndroidManifest.xml` too. Right now release traffic depends on debug/profile manifests, which is not enough for production.

### Android build configuration

- `android/app/build.gradle.kts:13-44`

Use this file if a hardware SDK requires:

- a higher `minSdk`
- extra Gradle dependencies
- packaging options
- ABI settings

### iOS native bridge

- `ios/Runner/AppDelegate.swift:5-15`

This is the matching iOS location for native channel integration.

### iOS permissions

- `ios/Runner/Info.plist:29-32`
  Camera and microphone usage descriptions already exist.

If you add direct Bluetooth, local network, or vendor discovery flows, this is also where the extra iOS permission keys should be added.

## 9. Current security and operations files that matter

- `firestore.rules:4-10`
  Firestore currently allows read and write for any signed-in verified operator.

- `backed.py:281-293`
  Hardware ingest is protected by `X-Ingest-Key`.

- `README.md:115-125`
  Documents the Firestore collections that the app seeds and watches.

Operational recommendation:

- For real AGV, crane, PLC, Arduino, and Raspberry Pi integrations, prefer writing through `backed.py` or through a trusted service account. Avoid putting raw hardware write access in the client app.

## 10. The most important gaps before full real-device integration

### Gap 1: CCTV stream URLs are not modeled yet

Current blocker:

- `lib/models/camera_feed.dart:4-45` has no `streamUrl`, `thumbnailUrl`, or `protocol`.

Impact:

- The dashboard can display camera status, but not a true IP camera stream yet.

### Gap 2: The main camera widget uses the local device lens

Current blocker:

- `lib/widgets/live_camera_spotlight.dart:69-142`
- `lib/widgets/live_camera_spotlight.dart:529-560`

Impact:

- This is good for camera-permission testing, but not yet for port CCTV ingest.

### Gap 3: Flutter does not call FastAPI directly yet

Current blocker:

- `lib/services/port_api_service.dart:18-21`

Impact:

- The live path is currently Firestore-based. That is fine for production if hardware writes to Firestore through the backend, but the app is not yet using `PORT_API_BASE_URL` for REST polling or writes.

### Gap 4: Android main manifest does not yet declare production internet access

Current blocker:

- `android/app/src/main/AndroidManifest.xml:1-35`

Impact:

- Release network traffic can fail unless `INTERNET` is added in the main manifest.

## 11. Practical integration order for this project

1. Connect external devices to a Raspberry Pi or industrial gateway first.
2. Post normalized events from that gateway into `backed.py:722-759`.
3. Store normalized records in the existing Firestore collections already watched by `PortApiService`.
4. Extend the camera model and `LiveCameraSpotlight` only when you are ready for real CCTV streaming.
5. Use direct Flutter native bridging only for kiosk-only or locally attached devices.

## 12. Best single insertion point by device type

- Real AGV data: `backed.py:722-759` plus `agvs` collection and `lib/services/port_api_service.dart:57-70`
- Real crane data: `backed.py:722-759` plus `cranes` collection and `lib/services/port_api_service.dart:72-85`
- Real Arduino sensor data: Raspberry Pi gateway to `backed.py:722-759`, then `sensor_readings` and `lib/services/port_api_service.dart:119-132`
- Real Raspberry Pi data: use the Pi as edge gateway, then write to `backed.py:722-759`
- Real camera status data: `camera_feeds` and `lib/services/port_api_service.dart:104-117`
- Real CCTV video stream: extend `lib/models/camera_feed.dart:4-45` and replace the local-device preview logic in `lib/widgets/live_camera_spotlight.dart:69-142` and `lib/widgets/live_camera_spotlight.dart:529-560`
- Real terminal KPIs: `terminal_stats/current` through `backed.py:576-595` and `lib/services/port_api_service.dart:41-55`

