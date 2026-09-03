import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/camera_feed.dart';
import '../models/ppe_detection_result.dart';
import '../services/ppe_detection_service.dart';
import 'glass_card.dart';

class LiveCameraSpotlight extends StatefulWidget {
  const LiveCameraSpotlight({
    super.key,
    required this.feed,
    required this.liveSources,
  });

  final CameraFeed feed;
  final int liveSources;

  @override
  State<LiveCameraSpotlight> createState() => _LiveCameraSpotlightState();
}

class _LiveCameraSpotlightState extends State<LiveCameraSpotlight>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _selectedCameraIndex = 0;
  ResolutionPreset _activeResolutionPreset = ResolutionPreset.high;
  bool _isLoading = true;
  String? _errorMessage;

  final PpeDetectionService _ppeService = PpeDetectionService();
  bool _isScanningPpe = false;
  PpeDetectionResult? _ppeResult;
  String? _ppeError;

  bool get _supportsNativePreview =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool get _canSwitchCamera => _cameras.length > 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      _reinitializeSelectedCamera();
    }
  }

  Future<void> _initializeCamera({int? forcedIndex}) async {
    if (!_supportsNativePreview) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Direct camera preview is enabled on Android, iPhone, and browser builds. '
            'For laptop testing, run the app in Chrome to use your webcam.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final cameras = await availableCameras();
      if (!mounted) {
        return;
      }

      if (cameras.isEmpty) {
        setState(() {
          _cameras = const [];
          _isLoading = false;
          _errorMessage =
              'No usable camera was detected on this device or browser session.';
        });
        return;
      }

      final preferredIndex = forcedIndex ?? _preferredCameraIndex(cameras);
      final safeIndex = preferredIndex.clamp(0, cameras.length - 1);
      final description = cameras[safeIndex];

      await _disposeController();
      final configuredController = await _buildBestAvailableController(
        description,
      );
      final controller = configuredController.controller;

      _controller = controller;
      _cameras = cameras;
      _selectedCameraIndex = safeIndex;
      _activeResolutionPreset = configuredController.preset;

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _isLoading = false;
      });
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = _cameraErrorMessage(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage =
            'The device camera could not be started right now. Try refreshing the panel.';
      });
    }
  }

  Future<void> _reinitializeSelectedCamera() async {
    if (_cameras.isEmpty) {
      await _initializeCamera();
      return;
    }
    await _initializeCamera(forcedIndex: _selectedCameraIndex);
  }

  Future<void> _switchCamera() async {
    if (!_canSwitchCamera) {
      return;
    }
    final nextIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _initializeCamera(forcedIndex: nextIndex);
  }

  Future<void> _takeSnapshot() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    try {
      await controller.takePicture();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Snapshot captured from the live device camera.')),
      );
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cameraErrorMessage(error))),
      );
    }
  }

  Future<void> _scanFrameForPpe() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isScanningPpe) {
      return;
    }

    setState(() {
      _isScanningPpe = true;
      _ppeError = null;
    });

    try {
      final snapshot = await controller.takePicture();
      final frameBytes = await snapshot.readAsBytes();
      final result = await _ppeService.detectFromBytes(frameBytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _isScanningPpe = false;
        _ppeResult = result;
      });
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isScanningPpe = false;
        _ppeError = _cameraErrorMessage(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isScanningPpe = false;
        _ppeError = error.toString();
      });
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  int _preferredCameraIndex(List<CameraDescription> cameras) {
    final externalIndex = cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.external,
    );
    if (externalIndex != -1) {
      return externalIndex;
    }

    final backIndex = cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    if (backIndex != -1) {
      return backIndex;
    }

    final frontIndex = cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    if (frontIndex != -1) {
      return frontIndex;
    }
    return 0;
  }

  Future<_ConfiguredCameraController> _buildBestAvailableController(
    CameraDescription description,
  ) async {
    const presets = kIsWeb
        ? [
            ResolutionPreset.max,
            ResolutionPreset.veryHigh,
            ResolutionPreset.high,
          ]
        : [
            ResolutionPreset.veryHigh,
            ResolutionPreset.high,
          ];

    CameraException? lastError;

    for (final preset in presets) {
      final controller = CameraController(
        description,
        preset,
        enableAudio: false,
      );

      try {
        await controller.initialize();
        return _ConfiguredCameraController(
          controller: controller,
          preset: preset,
        );
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

  String _previewQualityLabel() {
    switch (_activeResolutionPreset) {
      case ResolutionPreset.max:
      case ResolutionPreset.ultraHigh:
        return '4K target';
      case ResolutionPreset.veryHigh:
        return '1080p target';
      case ResolutionPreset.high:
        return '720p target';
      case ResolutionPreset.medium:
        return '480p target';
      case ResolutionPreset.low:
        return '240p target';
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
    final controller = _controller;
    final hasPreview = controller != null && controller.value.isInitialized;

    return GlassCard(
      padding: EdgeInsets.zero,
      color: const Color(0xCC050B15),
      borderRadius: 34,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1.65,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: hasPreview
                              ? const [
                                  Color(0xFF030B13),
                                  Color(0xFF0A1C31),
                                  Color(0xFF07111E),
                                ]
                              : const [
                                  Color(0xFF08111F),
                                  Color(0xFF11253E),
                                  Color(0xFF050B15),
                                ],
                        ),
                      ),
                    ),
                  ),
                  if (hasPreview)
                    Positioned.fill(
                        child: _CameraPreviewSurface(controller: controller))
                  else
                    Positioned.fill(
                      child: Center(
                        child: Icon(
                          Icons.videocam_rounded,
                          color: Colors.white.withValues(alpha: 0.08),
                          size: 150,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 22,
                    left: 22,
                    right: 22,
                    child: Row(
                      children: [
                        const _OverlayPulse(color: Color(0xFFFB7185)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hasPreview
                                ? 'LIVE DEVICE CAMERA'
                                : 'PRIMARY VISION STREAM',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                          ),
                        ),
                        _OverlayChip(
                          label: '${widget.liveSources} feeds active',
                          accent: const Color(0xFF2DD4BF),
                        ),
                        if (hasPreview) ...[
                          const SizedBox(width: 10),
                          _OverlayChip(
                            label: _previewQualityLabel(),
                            accent: const Color(0xFFBAE6FD),
                          ),
                        ],
                        const SizedBox(width: 10),
                        _CameraActionButton(
                          tooltip: 'Refresh camera',
                          icon: Icons.refresh_rounded,
                          onPressed: () => _initializeCamera(),
                        ),
                        if (_canSwitchCamera) ...[
                          const SizedBox(width: 10),
                          _CameraActionButton(
                            tooltip: 'Switch camera',
                            icon: Icons.cameraswitch_rounded,
                            onPressed: _switchCamera,
                          ),
                        ],
                        if (hasPreview) ...[
                          const SizedBox(width: 10),
                          _CameraActionButton(
                            tooltip: 'Take snapshot',
                            icon: Icons.photo_camera_rounded,
                            onPressed: _takeSnapshot,
                          ),
                          const SizedBox(width: 10),
                          _CameraActionButton(
                            tooltip: 'Scan PPE',
                            icon: Icons.health_and_safety_rounded,
                            accent: _isScanningPpe
                                ? const Color(0xFF2DD4BF)
                                : Colors.white,
                            onPressed: () => _scanFrameForPpe(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_isLoading)
                    const Positioned.fill(
                      child: Center(
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(strokeWidth: 2.8),
                        ),
                      ),
                    ),
                  if (_errorMessage != null && !_isLoading)
                    Positioned(
                      left: 22,
                      right: 22,
                      top: 96,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          color: Colors.black.withValues(alpha: 0.44),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CAMERA ACCESS STATUS',
                              style: TextStyle(
                                color: Color(0xFFBAE6FD),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.white70,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    left: 22,
                    right: 22,
                    bottom: 22,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.78),
                            Colors.black.withValues(alpha: 0.22),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.feed.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  hasPreview
                                      ? 'Live device lens  |  ${widget.feed.location}'
                                      : '${widget.feed.location}  |  waiting for device permission',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  hasPreview
                                      ? 'This panel is now using your current device camera for live testing at the highest supported preview quality. '
                                          'Switch lenses or capture a quick snapshot from here.'
                                      : 'Use this panel to test real camera access. On desktop, open the app in Chrome for webcam support.',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _OverlayMetric(
                                label: 'source',
                                value: hasPreview ? 'device' : 'offline',
                              ),
                              const SizedBox(height: 12),
                              _OverlayMetric(
                                label: 'status',
                                value: hasPreview
                                    ? 'active'
                                    : (_isLoading ? 'loading' : 'standby'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _PpeStatusPanel(
              isScanning: _isScanningPpe,
              result: _ppeResult,
              error: _ppeError,
              onDismiss: () {
                setState(() {
                  _ppeResult = null;
                  _ppeError = null;
                });
              },
            ),
          ],
        ),
      ),
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
        final previewAspectRatio = _cameraPreviewAspectRatio(controller);

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

class _ConfiguredCameraController {
  const _ConfiguredCameraController({
    required this.controller,
    required this.preset,
  });

  final CameraController controller;
  final ResolutionPreset preset;
}

double _cameraPreviewAspectRatio(CameraController controller) {
  final value = controller.value;
  final orientation = value.isRecordingVideo
      ? value.recordingOrientation
      : (value.previewPauseOrientation ??
          value.lockedCaptureOrientation ??
          value.deviceOrientation);
  final isLandscape = orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight;

  return isLandscape ? value.aspectRatio : (1 / value.aspectRatio);
}

class _OverlayMetric extends StatelessWidget {
  const _OverlayMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _OverlayChip extends StatelessWidget {
  const _OverlayChip({
    required this.label,
    required this.accent,
  });

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _CameraActionButton extends StatelessWidget {
  const _CameraActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.accent = Colors.white,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          onPressed();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, color: accent, size: 18),
        ),
      ),
    );
  }
}

class _OverlayPulse extends StatelessWidget {
  const _OverlayPulse({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color, blurRadius: 12),
        ],
      ),
    );
  }
}

class _PpeStatusPanel extends StatelessWidget {
  const _PpeStatusPanel({
    required this.isScanning,
    required this.result,
    required this.error,
    required this.onDismiss,
  });

  final bool isScanning;
  final PpeDetectionResult? result;
  final String? error;
  final VoidCallback onDismiss;

  static const Color _accentTeal = Color(0xFF2DD4BF);
  static const Color _alertRose = Color(0xFFFB7185);

  @override
  Widget build(BuildContext context) {
    if (!isScanning && result == null && error == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'PPE STATUS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              if (result != null)
                _OverlayChip(
                  label: '${result!.detections.length} objects',
                  accent: const Color(0xFFBAE6FD),
                ),
              if (result != null || error != null) ...[
                const SizedBox(width: 10),
                _CameraActionButton(
                  tooltip: 'Dismiss',
                  icon: Icons.close_rounded,
                  onPressed: () async {
                    onDismiss();
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (isScanning)
            const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                SizedBox(width: 12),
                Text(
                  'Analyzing frame with YOLO...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            )
          else if (error != null)
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: _alertRose,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                ),
              ],
            )
          else
            _buildResultRows(),
        ],
      ),
    );
  }

  Widget _buildResultRows() {
    final detectionResult = result!;
    final rows = <Widget>[
      for (final className in PpeDetectionResult.trackedClasses)
        _PpeStatusRow(
          className: className,
          detected: detectionResult.isDetected(className),
          count: detectionResult.countFor(className),
          isSafetyEquipment: true,
        ),
      for (final className in detectionResult.extraClassNames)
        _PpeStatusRow(
          className: className,
          detected: detectionResult.isDetected(className),
          count: detectionResult.countFor(className),
          isSafetyEquipment: false,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rows,
        const SizedBox(height: 14),
        Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
        const SizedBox(height: 12),
        Text(
          'TOP CONFIDENCE '
          '${(detectionResult.topConfidence * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
            color: _accentTeal,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

class _PpeStatusRow extends StatelessWidget {
  const _PpeStatusRow({
    required this.className,
    required this.detected,
    required this.count,
    required this.isSafetyEquipment,
  });

  final String className;
  final bool detected;
  final int count;
  final bool isSafetyEquipment;

  static const Color _accentTeal = Color(0xFF2DD4BF);
  static const Color _alertRose = Color(0xFFFB7185);

  IconData get _icon {
    switch (className) {
      case 'helmet':
        return Icons.engineering_rounded;
      case 'vest':
        return Icons.checkroom_rounded;
      case 'head':
        return Icons.face_retouching_natural_rounded;
      case 'person':
        return Icons.person_search_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  String get _statusLabel {
    if (detected) {
      return isSafetyEquipment ? 'Detected' : 'Visible';
    }
    return isSafetyEquipment ? 'Missing' : '--';
  }

  Color get _statusColor {
    if (detected) {
      return isSafetyEquipment ? _accentTeal : const Color(0xFFBAE6FD);
    }
    return isSafetyEquipment ? _alertRose : Colors.white38;
  }

  IconData get _statusIcon {
    if (detected) {
      return Icons.check_circle_rounded;
    }
    return isSafetyEquipment
        ? Icons.cancel_rounded
        : Icons.remove_circle_outline;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _statusColor.withValues(alpha: 0.12),
              border: Border.all(color: _statusColor.withValues(alpha: 0.24)),
            ),
            child: Icon(_icon, color: _statusColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              className[0].toUpperCase() + className.substring(1),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            count > 0 ? 'x$count' : '',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(width: 10),
          Icon(_statusIcon, color: _statusColor, size: 16),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: Text(
              _statusLabel,
              style: TextStyle(
                color: _statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
