import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/machine_camera.dart';
import '../models/ppe_detection_result.dart';
import '../providers/camera_provider.dart';
import '../providers/machine_selection_controller.dart';
import '../services/ppe_detection_service.dart';
import '../theme/industrial_theme.dart';

/// Embedded live camera workspace for the Live Operations screen.
///
/// The selected machine's camera is shown directly inside the operational
/// workspace. AI/PPE detections are drawn as bounding boxes over the live
/// frame and synchronised into the shared [MachineSelectionController] so the
/// telemetry bar and AI indicator react to the same results.
class LiveCameraPanel extends StatefulWidget {
  const LiveCameraPanel({super.key});

  @override
  State<LiveCameraPanel> createState() => _LiveCameraPanelState();
}

class _LiveCameraPanelState extends State<LiveCameraPanel>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _selectedCameraIndex = 0;
  ResolutionPreset _activePreset = ResolutionPreset.high;
  bool _isLoading = true;
  String? _errorMessage;

  final PpeDetectionService _ppeService = PpeDetectionService();
  bool _isScanningPpe = false;
  Timer? _scanTimer;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  CameraProvider? _cameraProvider;
  MachineCameraConfig? _cameraConfig;
  String? _resolvedMachineId;

  // Real remote stream state: when the machine has a configured camera
  // stream, frames are proxied through the backend (one JPEG at a time) and
  // rendered here. The stream URL itself never reaches this widget.
  bool _remoteMode = false;
  bool _remoteCameraOnline = false;
  bool _pollInFlight = false;
  Uint8List? _remoteFrameBytes;
  String? _remoteBackendId;
  Timer? _remotePollTimer;

  bool get _supportsNativePreview =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool get _canSwitchCamera => _cameras.length > 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _initializeCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<MachineSelectionController>();
    _cameraProvider ??= createDefaultCameraProvider(
      service: controller.controlService,
    );
    final machine = controller.selectedMachine;
    if (machine.id != _resolvedMachineId) {
      _resolvedMachineId = machine.id;
      _cameraConfig = null;
      _stopRemoteStream();
      _resolveMachineCamera(machine);
    }
  }

  Future<void> _resolveMachineCamera(OperationalMachine machine) async {
    final provider = _cameraProvider;
    if (provider == null) return;
    try {
      final config = await provider.resolve(machine);
      if (!mounted) return;
      if (context.read<MachineSelectionController>().selectedMachine.id !=
          machine.id) {
        return;
      }
      setState(() => _cameraConfig = config);
      _applyCameraConfig(config, machine);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cameraConfig = null);
      _applyCameraConfig(null, machine);
    }
  }

  void _applyCameraConfig(MachineCameraConfig? config, OperationalMachine machine) {
    final isRemote = config?.isRemote == true;
    final backendId = machine.backendId ?? machine.id;
    if (isRemote && backendId.isNotEmpty) {
      _startRemoteStream(backendId: backendId);
    } else {
      _stopRemoteStream();
      if (_controller == null) {
        _initializeCamera();
      }
    }
  }

  void _startRemoteStream({required String backendId}) {
    _remoteMode = true;
    _remoteBackendId = backendId;
    _remoteFrameBytes = null;
    _remoteCameraOnline = false;
    _disposeController();
    _scanTimer?.cancel();
    _scanTimer = null;
    _remotePollTimer?.cancel();
    _remotePollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollRemoteFrame(),
    );
    _pollRemoteFrame();
    _startScanLoop();
    context.read<MachineSelectionController>().setAiResult(null);
  }

  void _stopRemoteStream() {
    _remoteMode = false;
    _remoteBackendId = null;
    _remoteFrameBytes = null;
    _remoteCameraOnline = false;
    _remotePollTimer?.cancel();
    _remotePollTimer = null;
  }

  Future<void> _pollRemoteFrame({bool force = false}) async {
    if (!_remoteMode || _pollInFlight) return;
    final backendId = _remoteBackendId;
    if (backendId == null) return;
    final control = context.read<MachineSelectionController>().controlService;
    _pollInFlight = true;
    try {
      final bytes = await control.fetchCameraFrame(backendId);
      if (!mounted || !_remoteMode) return;
      setState(() {
        _remoteCameraOnline = true;
        if (bytes.isNotEmpty) _remoteFrameBytes = bytes;
      });
    } catch (_) {
      if (!mounted || !_remoteMode) return;
      setState(() => _remoteCameraOnline = false);
    } finally {
      _pollInFlight = false;
    }
  }

  /// Re-polls a remote stream or re-initializes the native camera depending on
  /// the active source (used by the header refresh button).
  Future<void> _refreshCamera() async {
    if (_remoteMode) {
      await _pollRemoteFrame(force: true);
      return;
    }
    await _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _scanTimer?.cancel();
    _remotePollTimer?.cancel();
    _cameraProvider?.dispose();
    _disposeController();
    _ppeService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _disposeController();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera(forcedIndex: _selectedCameraIndex);
    }
  }

  Future<void> _initializeCamera({int? forcedIndex}) async {
    final controllerRef = context.read<MachineSelectionController>();

    if (!_supportsNativePreview) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Direct camera preview is enabled on Android, iPhone and browser builds. '
              'For laptop testing, run the app in Chrome to use your webcam.';
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    controllerRef.setAiResult(null);

    try {
      final cameras = await availableCameras();
      if (!mounted) return;

      if (cameras.isEmpty) {
        setState(() {
          _cameras = const [];
          _isLoading = false;
          _errorMessage =
              'No usable camera was detected on this device or browser session.';
        });
        return;
      }

      final preferred = forcedIndex ?? _preferredCameraIndex(cameras);
      final safeIndex = preferred.clamp(0, cameras.length - 1);
      final description = cameras[safeIndex];

      await _disposeController();
      final configured = await _buildBestAvailableController(description);
      final controller = configured.controller;

      _controller = controller;
      _cameras = cameras;
      _selectedCameraIndex = safeIndex;
      _activePreset = configured.preset;

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() => _isLoading = false);
      _startScanLoop();
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _cameraErrorMessage(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'The device camera could not be started right now. Try refreshing the panel.';
      });
    }
  }

  void _startScanLoop() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _scanFrameForAi(),
    );
  }

  Future<void> _scanFrameForAi() async {
    final machineRef = context.read<MachineSelectionController>();
    if (_isScanningPpe || !mounted) {
      return;
    }
    _isScanningPpe = true;

    if (_remoteMode) {
      final bytes = _remoteFrameBytes;
      if (bytes == null || bytes.isEmpty) {
        _isScanningPpe = false;
        return;
      }
      await _runAiScan(bytes, machineRef);
      return;
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      _isScanningPpe = false;
      return;
    }

    try {
      final snapshot = await controller.takePicture();
      final frameBytes = await snapshot.readAsBytes();
      if (!mounted) return;
      await _runAiScan(frameBytes, machineRef);
    } catch (_) {
      _isScanningPpe = false;
      if (machineRef.aiScanning) {
        machineRef.setAiScanning(false);
      }
    }
  }

  Future<void> _runAiScan(
    Uint8List frameBytes,
    MachineSelectionController machineRef,
  ) async {
    machineRef.setAiScanning(true);
    machineRef.setAiResult(null);

    try {
      final result = await _ppeService.detectFromBytes(frameBytes);
      if (!mounted) return;
      machineRef.setAiResult(result);
    } catch (error) {
      if (!mounted) return;
      machineRef.setAiResult(null, error: error.toString());
    } finally {
      _isScanningPpe = false;
      if (machineRef.aiScanning) {
        machineRef.setAiScanning(false);
      }
    }
  }

  Future<void> _switchCamera() async {
    if (!_canSwitchCamera) return;
    final next = (_selectedCameraIndex + 1) % _cameras.length;
    await _initializeCamera(forcedIndex: next);
  }

  /// Opens the live frame in a fullscreen overlay using the same controller.
  void _openFullscreen() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => _FullscreenCameraView(panel: this),
    );
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  int _preferredCameraIndex(List<CameraDescription> cameras) {
    for (final len in [
      CameraLensDirection.external,
      CameraLensDirection.back,
      CameraLensDirection.front,
    ]) {
      final index = cameras.indexWhere((c) => c.lensDirection == len);
      if (index != -1) return index;
    }
    return 0;
  }

  Future<_ConfiguredCameraController> _buildBestAvailableController(
    CameraDescription description,
  ) async {
    final presets = kIsWeb
        ? const [ResolutionPreset.max, ResolutionPreset.veryHigh, ResolutionPreset.high]
        : const [ResolutionPreset.veryHigh, ResolutionPreset.high];

    CameraException? lastError;
    for (final preset in presets) {
      final controller = CameraController(description, preset, enableAudio: false);
      try {
        await controller.initialize();
        return _ConfiguredCameraController(controller: controller, preset: preset);
      } on CameraException catch (error) {
        lastError = error;
        await controller.dispose();
      }
    }
    throw lastError ??
        CameraException(
          'CameraInitializationFailed',
          'No supported preview resolution was accepted by the device.',
        );
  }

  String _qualityLabel() {
    switch (_activePreset) {
      case ResolutionPreset.max:
      case ResolutionPreset.ultraHigh:
        return '4K';
      case ResolutionPreset.veryHigh:
        return '1080p';
      case ResolutionPreset.high:
        return '720p';
      case ResolutionPreset.medium:
        return '480p';
      case ResolutionPreset.low:
        return '240p';
    }
  }

  String _cameraErrorMessage(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
        return 'Camera permission was denied. Allow access and try again.';
      case 'CameraAccessDeniedWithoutPrompt':
        return 'Camera access was denied earlier. Re-enable it from system settings.';
      case 'CameraAccessRestricted':
        return 'Camera access is restricted on this device.';
      default:
        return 'Camera error: ${error.description ?? error.code}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final machineRef = context.watch<MachineSelectionController>();
    final machine = machineRef.selectedMachine;
    final controller = _controller;
    final hasRemoteFrame = _remoteMode && _remoteFrameBytes != null;
    final hasPreview =
        hasRemoteFrame || (controller != null && controller.value.isInitialized);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF060D18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IndustrialTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CameraHeader(
            machineName: machine.name,
            machineKicker: machine.kicker,
            hasPreview: hasPreview,
            remoteMode: _remoteMode,
            remoteOnline: _remoteCameraOnline,
            isLoading: _isLoading,
            timestamp: _now,
            quality: _remoteMode && _remoteCameraOnline ? 'MEASURED' : _qualityLabel(),
            canSwitch: !_remoteMode && _canSwitchCamera,
            onSwitch: _switchCamera,
            onRefresh: _refreshCamera,
            onFullscreen: hasPreview ? _openFullscreen : null,
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CameraStage(
                  controller: controller,
                  hasPreview: hasPreview,
                  remoteMode: _remoteMode,
                  remoteBytes: _remoteFrameBytes,
                  remoteOnline: _remoteCameraOnline,
                  isLoading: _isLoading,
                  errorMessage: _errorMessage,
                  machineRef: machineRef,
                  aiOverlay: _AiOverlay(machineRef: machineRef),
                ),
                if (_cameraConfig?.isRemote == true)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _RemoteFeedBadge(
                        config: _cameraConfig!,
                        live: _remoteCameraOnline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraHeader extends StatelessWidget {
  const _CameraHeader({
    required this.machineName,
    required this.machineKicker,
    required this.hasPreview,
    required this.remoteMode,
    required this.remoteOnline,
    required this.isLoading,
    required this.timestamp,
    required this.quality,
    required this.canSwitch,
    required this.onSwitch,
    required this.onRefresh,
    required this.onFullscreen,
  });

  final String machineName;
  final String machineKicker;
  final bool hasPreview;
  final bool remoteMode;
  final bool remoteOnline;
  final bool isLoading;
  final DateTime timestamp;
  final String quality;
  final bool canSwitch;
  final Future<void> Function() onSwitch;
  final Future<void> Function() onRefresh;
  final VoidCallback? onFullscreen;

  bool get _live => remoteMode ? remoteOnline : hasPreview;

  @override
  Widget build(BuildContext context) {
    final time =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    final date =
        '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1524),
        border: const Border(bottom: BorderSide(color: IndustrialTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _live ? IndustrialTheme.ready : IndustrialTheme.warn,
              boxShadow: [
                BoxShadow(
                  color: (_live ? IndustrialTheme.ready : IndustrialTheme.warn)
                      .withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$machineName · LIVE CAMERA',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                machineKicker.isEmpty ? 'PORT YARD FEED' : machineKicker.toUpperCase(),
                style: const TextStyle(
                  color: IndustrialTheme.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const Spacer(),
          _HeaderBadge(
            label: _live ? 'LIVE' : 'STANDBY',
            color: _live ? IndustrialTheme.ready : IndustrialTheme.warn,
          ),
          const SizedBox(width: 8),
          _HeaderBadge(
            label: '$quality · $date $time',
            color: IndustrialTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          _HeaderIconButton(
            tooltip: 'Refresh camera',
            icon: Icons.refresh_rounded,
            onPressed: onRefresh,
          ),
          if (canSwitch) ...[
            const SizedBox(width: 6),
            _HeaderIconButton(
              tooltip: 'Switch camera',
              icon: Icons.cameraswitch_rounded,
              onPressed: onSwitch,
            ),
          ],
          const SizedBox(width: 6),
          _HeaderIconButton(
            tooltip: 'Fullscreen',
            icon: Icons.fullscreen_rounded,
            accent: IndustrialTheme.control,
            onPressed: onFullscreen,
            enabled: onFullscreen != null,
          ),
        ],
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.accent = Colors.white,
    this.enabled = true,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color accent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled && onPressed != null ? () => onPressed!() : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: IndustrialTheme.border),
          ),
          child: Icon(
            icon,
            color: enabled ? accent : IndustrialTheme.textMuted,
            size: 17,
          ),
        ),
      ),
    );
  }
}

class _CameraStage extends StatelessWidget {
  const _CameraStage({
    required this.controller,
    required this.hasPreview,
    required this.remoteMode,
    required this.remoteBytes,
    required this.remoteOnline,
    required this.isLoading,
    required this.errorMessage,
    required this.machineRef,
    required this.aiOverlay,
  });

  final CameraController? controller;
  final bool hasPreview;
  final bool remoteMode;
  final Uint8List? remoteBytes;
  final bool remoteOnline;
  final bool isLoading;
  final String? errorMessage;
  final MachineSelectionController machineRef;
  final Widget aiOverlay;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF040A13), Color(0xFF0A1C31), Color(0xFF060D18)],
            ),
          ),
        ),
        if (hasPreview && remoteMode)
          _RemoteCameraPreview(bytes: remoteBytes!)
        else if (hasPreview)
          _CameraPreviewSurface(controller: controller!)
        else
          Center(
            child: Icon(
              Icons.videocam_rounded,
              color: Colors.white.withValues(alpha: 0.07),
              size: 120,
            ),
          ),
        if (hasPreview) aiOverlay,
        if (remoteMode && !remoteOnline && !isLoading)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _CameraErrorCard(
              message:
                  'Camera stream offline — no frame received from the gateway. Check the machine connection.',
              muted: true,
            ),
          ),
        if (isLoading)
          const Center(
            child: SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        if (errorMessage != null && !isLoading)
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: _CameraErrorCard(message: errorMessage!),
          ),
      ],
    );
  }
}

class _RemoteCameraPreview extends StatelessWidget {
  const _RemoteCameraPreview({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Image.memory(
              bytes,
              gaplessPlayback: true,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
      },
    );
  }
}

class _CameraPreviewSurface extends StatelessWidget {
  const _CameraPreviewSurface({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewAspectRatio = _previewAspectRatio(controller);
        var width = constraints.maxWidth;
        var height = width / previewAspectRatio;
        if (height < constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * previewAspectRatio;
        }
        return ClipRect(
          child: OverflowBox(
            maxWidth: width,
            maxHeight: height,
            child: SizedBox(
              width: width,
              height: height,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}

double _previewAspectRatio(CameraController controller) {
  final value = controller.value;
  final orientation = value.isRecordingVideo
      ? value.recordingOrientation
      : (value.previewPauseOrientation ??
          value.lockedCaptureOrientation ??
          value.deviceOrientation);
  final isLandscape =
      orientation == DeviceOrientation.landscapeLeft ||
          orientation == DeviceOrientation.landscapeRight;
  return isLandscape ? value.aspectRatio : (1 / value.aspectRatio);
}

class _CameraErrorCard extends StatelessWidget {
  const _CameraErrorCard({required this.message, this.muted = false});

  final String message;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final accentColor = muted ? IndustrialTheme.warn : IndustrialTheme.control;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: IndustrialTheme.borderHi),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            accentColor == IndustrialTheme.control
                ? 'CAMERA ACCESS STATUS'
                : 'CAMERA STREAM STATUS',
            style: TextStyle(
              color: accentColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _RemoteFeedBadge extends StatelessWidget {
  const _RemoteFeedBadge({required this.config, this.live = true});

  final MachineCameraConfig config;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final url = config.streamUrl;
    final statusColor = live ? IndustrialTheme.ready : IndustrialTheme.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: (live ? IndustrialTheme.ready : IndustrialTheme.danger)
              .withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.6),
                  blurRadius: 7,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            live ? 'CAMERA ● LIVE' : 'CAMERA ● OFFLINE',
            style: TextStyle(
              color: statusColor,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: url ?? 'Native device camera preview',
            child: Text(
              config.name.toUpperCase(),
              style: const TextStyle(
                color: IndustrialTheme.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfiguredCameraController {
  const _ConfiguredCameraController({required this.controller, required this.preset});

  final CameraController controller;
  final ResolutionPreset preset;
}

/// Draws AI detections and status indicators over the live video frame.
class _AiOverlay extends StatelessWidget {
  const _AiOverlay({required this.machineRef});

  final MachineSelectionController machineRef;

  @override
  Widget build(BuildContext context) {
    final result = machineRef.aiResult;
    final scanning = machineRef.aiScanning;
    final error = machineRef.aiError;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 12,
          left: 12,
          child: _AiStatusBadge(
            active: scanning || result != null,
            scanning: scanning,
          ),
        ),
        if (result != null)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _DetectionBoxLayer(
                  result: result,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                );
              },
            ),
          ),
        if (error != null && result == null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _SafetyBanner(
              message: 'AI analysis unavailable: $error',
              severity: SafetySeverity.info,
            ),
          ),
        if (result != null && _hasViolation(result))
          Positioned(
            left: 12,
            right: 12,
            bottom: 62,
            child: _SafetyBanner(
              message: _violationMessage(result),
              severity: SafetySeverity.warning,
            ),
          ),
        if (result != null)
          Positioned(
            left: 12,
            bottom: 12,
            child: _DetectionSummary(result: result),
          ),
      ],
    );
  }

  bool _hasViolation(PpeDetectionResult result) {
    final headCount = result.countFor('head');
    final helmetCount = result.countFor('helmet');
    final vestCount = result.countFor('vest');
    return headCount > helmetCount || headCount > vestCount;
  }

  String _violationMessage(PpeDetectionResult result) {
    final headCount = result.countFor('head');
    final helmetCount = result.countFor('helmet');
    final vestCount = result.countFor('vest');
    final messages = <String>[];
    if (headCount > helmetCount) {
      messages.add('person without helmet detected');
    }
    if (headCount > vestCount) {
      messages.add('person without vest detected');
    }
    return messages.isEmpty ? 'safety violation detected' : messages.join(' · ');
  }
}

enum SafetySeverity { warning, info }

class _AiStatusBadge extends StatelessWidget {
  const _AiStatusBadge({required this.active, required this.scanning});

  final bool active;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final color = active ? IndustrialTheme.teal : IndustrialTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (scanning)
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: IndustrialTheme.teal),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 7)],
              ),
            ),
          const SizedBox(width: 8),
          const Text(
            'AI VISION',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            active ? '● ACTIVE' : 'STANDBY',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectionBoxLayer extends StatelessWidget {
  const _DetectionBoxLayer({
    required this.result,
    required this.width,
    required this.height,
  });

  final PpeDetectionResult result;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final imageW = result.imageWidth <= 0 ? 1 : result.imageWidth;
    final imageH = result.imageHeight <= 0 ? 1 : result.imageHeight;
    final sx = width / imageW;
    final sy = height / imageH;

    return Stack(
      children: result.detections.map((detection) {
        final box = detection.boundingBox;
        final x1 = (box['x1'] ?? 0) * sx;
        final y1 = (box['y1'] ?? 0) * sy;
        final x2 = (box['x2'] ?? 0) * sx;
        final y2 = (box['y2'] ?? 0) * sy;
        final boxWidth = x2 - x1;
        final boxHeight = y2 - y1;
        if (boxWidth <= 0 || boxHeight <= 0) {
          return const SizedBox.shrink();
        }
        final label = _DetectionLabelResolver.labelFor(result, detection);
        final color = _boxColorFor(detection.className);
        return Positioned(
          left: x1.clamp(0, width - 1),
          top: y1.clamp(0, height - 1),
          width: boxWidth.clamp(0, width),
          height: boxHeight.clamp(0, height),
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DetectionBoxPainter(color: color),
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  margin: const EdgeInsets.only(left: 2, top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: Text(
                    '$label ${(detection.confidence * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _DetectionBoxPainter extends CustomPainter {
  const _DetectionBoxPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _DetectionBoxPainter oldDelegate) =>
      oldDelegate.color != color;
}

Color _boxColorFor(String className) {
  switch (className.toLowerCase()) {
    case 'helmet':
      return IndustrialTheme.ready;
    case 'vest':
      return IndustrialTheme.teal;
    case 'head':
      return IndustrialTheme.warn;
    case 'person':
      return IndustrialTheme.warn;
    case 'obstacle':
      return IndustrialTheme.danger;
    default:
      return IndustrialTheme.control;
  }
}

String _shortClassLabel(String className) {
  switch (className.toLowerCase()) {
    case 'helmet':
      return 'HELMET';
    case 'vest':
      return 'VEST';
    case 'head':
      return 'PERSON';
    case 'person':
      return 'PERSON';
    case 'obstacle':
      return 'OBSTACLE';
    default:
      return className.toUpperCase();
  }
}

/// Overrides the label used by the box painter: combines class label with the
/// protective-equipment interpretation ("NO HELMET" when a head is present
/// without a helmet).
class _DetectionLabelResolver {
  static String labelFor(PpeDetectionResult result, PpeDetection detection) {
    final base = detection.className.toLowerCase();
    if (base == 'head') {
      final helmetCount = result.countFor('helmet');
      if (helmetCount == 0) return 'NO HELMET';
      final vestCount = result.countFor('vest');
      if (vestCount == 0) return 'NO VEST';
      return 'PERSON';
    }
    return _shortClassLabel(detection.className);
  }
}

class _DetectionSummary extends StatelessWidget {
  const _DetectionSummary({required this.result});

  final PpeDetectionResult result;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    for (final className in ['person', 'head', 'helmet', 'vest']) {
      final count = result.countFor(className);
      if (count > 0) {
        parts.add('${_shortClassLabel(className)}x$count');
      }
    }
    for (final extra in result.extraClassNames) {
      final count = result.countFor(extra);
      if (count > 0) parts.add('${_shortClassLabel(extra)}x$count');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: IndustrialTheme.borderHi),
      ),
      child: Text(
        parts.isEmpty
            ? 'NO OBJECTS'
            : parts.take(4).join('  ·  '),
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner({required this.message, required this.severity});

  final String message;
  final SafetySeverity severity;

  @override
  Widget build(BuildContext context) {
    final color = severity == SafetySeverity.warning
        ? IndustrialTheme.danger
        : IndustrialTheme.warn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            severity == SafetySeverity.warning
                ? Icons.warning_amber_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  severity == SafetySeverity.warning
                      ? 'SAFETY WARNING'
                      : 'AI VISION',
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullscreenCameraView extends StatelessWidget {
  const _FullscreenCameraView({required this.panel});

  final _LiveCameraPanelState panel;

  @override
  Widget build(BuildContext context) {
    final machineRef = context.watch<MachineSelectionController>();
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    'FULLSCREEN CAMERA',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.fullscreen_exit_rounded,
                        color: Colors.white),
                    tooltip: 'Exit fullscreen',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: IndustrialTheme.borderHi),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (panel._remoteMode && panel._remoteFrameBytes != null)
                        _RemoteCameraPreview(bytes: panel._remoteFrameBytes!)
                      else if (panel._controller != null &&
                          panel._controller!.value.isInitialized)
                        _CameraPreviewSurface(controller: panel._controller!)
                      else
                        const Center(
                          child: Icon(Icons.videocam_rounded,
                              color: Colors.white24, size: 120),
                        ),
                      _AiOverlay(machineRef: machineRef),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}