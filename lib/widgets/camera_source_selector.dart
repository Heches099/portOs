import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'glass_card.dart';

/// Lets an operator choose the source that should be added to the vision wall.
/// The device camera option opens a real, permission-backed camera preview.
class CameraSourceSelector extends StatefulWidget {
  const CameraSourceSelector({super.key});

  @override
  State<CameraSourceSelector> createState() => _CameraSourceSelectorState();
}

class _CameraSourceSelectorState extends State<CameraSourceSelector> {
  _CameraSource _selectedSource = _CameraSource.device;
  CameraController? _controller;
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _selectSource(_CameraSource source) async {
    setState(() {
      _selectedSource = source;
      _error = null;
    });

    if (source == _CameraSource.device) {
      await _startDeviceCamera();
    } else {
      await _controller?.dispose();
      if (mounted) {
        setState(() => _controller = null);
      }
    }
  }

  Future<void> _startDeviceCamera() async {
    if (_controller?.value.isInitialized ?? false) return;

    setState(() => _isLoading = true);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no-camera', 'No camera was found on this device.');
      }
      final preferred = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        preferred,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (exception) {
      if (mounted) setState(() => _error = exception.description ?? 'Camera access was not granted.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to start the device camera.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      color: const Color(0xCC08111F),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.add_to_queue_rounded, color: Color(0xFF2DD4BF)),
              const SizedBox(width: 10),
              Text('Connect a camera', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          const Text('Choose a source to add to the vision workspace.', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _CameraSource.values.map((source) => _SourceOption(
              source: source,
              selected: source == _selectedSource,
              onTap: () => _selectSource(source),
            )).toList(growable: false),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _selectedSource == _CameraSource.device
                ? _devicePreview()
                : _ConnectionHint(source: _selectedSource),
          ),
        ],
      ),
    );
  }

  Widget _devicePreview() {
    if (_isLoading) {
      return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return _CameraMessage(icon: Icons.camera_alt_outlined, message: _error!, actionLabel: 'Try again', onAction: _startDeviceCamera);
    }
    if (!(_controller?.value.isInitialized ?? false)) {
      return _CameraMessage(icon: Icons.camera_alt_rounded, message: 'Use this device\'s camera for an on-the-go live feed.', actionLabel: 'Start device camera', onAction: _startDeviceCamera);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: CameraPreview(_controller!),
      ),
    );
  }
}

enum _CameraSource { device, ipStream, onvif, nvr }

extension on _CameraSource {
  String get title => switch (this) {
    _CameraSource.device => 'This device',
    _CameraSource.ipStream => 'IP / RTSP stream',
    _CameraSource.onvif => 'ONVIF / USB camera',
    _CameraSource.nvr => 'NVR recorder',
  };

  String get detail => switch (this) {
    _CameraSource.device => 'Use the running device camera',
    _CameraSource.ipStream => 'Connect a network camera URL',
    _CameraSource.onvif => 'Discover a compatible camera',
    _CameraSource.nvr => 'Add a recorder channel',
  };

  IconData get icon => switch (this) {
    _CameraSource.device => Icons.phone_android_rounded,
    _CameraSource.ipStream => Icons.wifi_tethering_rounded,
    _CameraSource.onvif => Icons.usb_rounded,
    _CameraSource.nvr => Icons.dns_rounded,
  };
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({required this.source, required this.selected, required this.onTap});
  final _CameraSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: selected ? const Color(0xFF2DD4BF).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: selected ? const Color(0xFF2DD4BF) : Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(source.icon, color: selected ? const Color(0xFF5EEAD4) : Colors.white60),
        const SizedBox(height: 10),
        Text(source.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(source.detail, style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 2),
      ]),
    ),
  );
}

class _ConnectionHint extends StatelessWidget {
  const _ConnectionHint({required this.source});
  final _CameraSource source;

  @override
  Widget build(BuildContext context) => _CameraMessage(
    icon: source.icon,
    message: '${source.title} is ready to configure. Add its connection details in your camera integration to bring it online.',
    actionLabel: 'Configure connection',
    onAction: () => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${source.title} connection setup is ready for its endpoint details.')),
    ),
  );
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({required this.icon, required this.message, required this.actionLabel, required this.onAction});
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(18)),
    child: Row(children: [
      Icon(icon, color: const Color(0xFF5EEAD4), size: 30),
      const SizedBox(width: 14),
      Expanded(child: Text(message, style: const TextStyle(color: Colors.white70, height: 1.35))),
      const SizedBox(width: 14),
      FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
    ]),
  );
}
