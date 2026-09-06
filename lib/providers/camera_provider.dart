import '../models/machine_camera.dart';
import '../models/operational_machine.dart';
import '../models/realtime_telemetry.dart';
import '../services/machine_control_service.dart';

/// Camera source abstraction for the Live Operations workspace.
///
/// The workspace only ever asks "what camera belongs to the selected machine?"
/// and renders whatever the provider returns:
///   - [MockCameraProvider]  - no hardware, `streamUrl == null`, so the panel
///     falls back to the local device camera preview.
///   - [LiveCameraProvider]  - reads `GET /machines/{id}/camera` from FastAPI.
abstract class CameraProvider {
  bool get isMock;

  Future<MachineCameraConfig?> resolve(OperationalMachine machine);

  void dispose();
}

/// Development provider: always resolves the machine to the local device
/// camera. No stream URLs are hard-coded here.
class MockCameraProvider implements CameraProvider {
  @override
  bool get isMock => true;

  @override
  Future<MachineCameraConfig?> resolve(OperationalMachine machine) async {
    return MachineCameraConfig(
      cameraId: 'device-cam-${machine.id}',
      machineId: machine.id,
      name: '${machine.name} DEVICE CAMERA',
      aiEnabled: true,
    );
  }

  /// Fires when a resolve of the same machine is needed again.
  @override
  void dispose() {}
}

/// Production provider backed by the FastAPI camera registry.
class LiveCameraProvider implements CameraProvider {
  LiveCameraProvider({required MachineControlService controlService})
      : _control = controlService;

  final MachineControlService _control;

  @override
  bool get isMock => false;

  @override
  Future<MachineCameraConfig?> resolve(OperationalMachine machine) async {
    try {
      final json = await _control.fetchMachineCamera(machine.backendId ?? machine.id);
      return MachineCameraConfig.fromJson(json);
    } catch (_) {
      // Camera registry unreachable: fall back to a device-camera mapping so
      // the workspace keeps working; the panel surface marks it DEGRADED.
      return MachineCameraConfig(
        cameraId: 'device-cam-${machine.id}',
        machineId: machine.id,
        name: '${machine.name} DEVICE CAMERA',
        aiEnabled: true,
        connection: MachineConnectionState.degraded,
      );
    }
  }

  @override
  void dispose() {}
}

/// Builds the provider matching the active realtime config mode.
CameraProvider createDefaultCameraProvider({required MachineControlService service}) {
  const String mode = String.fromEnvironment(
    'PORT_REALTIME_MODE',
    defaultValue: 'mock',
  );
  if (mode == 'websocket' || mode == 'live') {
    // Real backend: the camera registry is the single source of truth. When a
    // machine has no remote stream configured the backing LiveCameraProvider
    // still resolves to the local device camera so the workspace stays usable.
    return LiveCameraProvider(controlService: service);
  }
  // Development mode: always the local device camera (webcam / phone lens).
  return MockCameraProvider();
}