import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/camera_feed.dart';
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
        child: AspectRatio(
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
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
                            value: hasPreview ? 'device' : 'mock',
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
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;

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
          child: Icon(icon, color: Colors.white, size: 18),
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
