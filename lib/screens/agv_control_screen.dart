import 'dart:async';

import 'package:flutter/material.dart';

import '../models/machine_status.dart';
import '../providers/theme_provider.dart';
import '../services/machine_control_service.dart';
import '../widgets/agv_control_card.dart';
import '../widgets/command_history_table.dart';
import '../widgets/commissioning_card.dart';
import '../widgets/machine_control_widgets.dart';

class AgvControlScreen extends StatefulWidget {
  const AgvControlScreen({super.key});

  @override
  State<AgvControlScreen> createState() => _AgvControlScreenState();
}

class _AgvControlScreenState extends State<AgvControlScreen> {
  static const _agvId = '1';
  late final MachineControlService _service;
  MachineDetail? _machine;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _service = MachineControlService();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final detail = await _service.fetchMachineDetail(_agvId);
      if (mounted) {
        setState(() {
          _machine = detail;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _error = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeading(
            icon: Icons.smart_toy_rounded,
            accent: const Color(0xFF38BDF8),
            title: 'AGV Control',
            subtitle:
                'Directional drive, speed, blink signalling, emergency stop, and auto-mode for AGV-01.',
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            _ErrorBanner(error: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            }),
            const SizedBox(height: 12),
          ],
          MachineSimulationBanner(machineId: _agvId, service: _service),
          const SizedBox(height: 12),
          MachineInfoBar(machine: _machine),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 980;
              final controls = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CommissioningCard(machineId: _agvId, service: _service),
                  const SizedBox(height: 16),
                  AgvControlCard(machineId: _agvId, service: _service),
                  const SizedBox(height: 16),
                  AutoModeCard(
                    machineId: _agvId,
                    service: _service,
                    machineType: 'agv',
                  ),
                ],
              );
              final history = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CommandHistoryTable(machineId: _agvId, service: _service),
                  const SizedBox(height: 16),
                  MachineActivityFeed(machineId: _agvId, service: _service),
                ],
              );

              if (!isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    controls,
                    const SizedBox(height: 16),
                    history,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: controls),
                  const SizedBox(width: 16),
                  Expanded(flex: 4, child: history),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.15),
          ),
          child: Icon(icon, color: accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppPalette.navy,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, height: 1.4, color: isDark ? Colors.white54 : Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.coral.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.coral.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppPalette.coral, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AGV telemetry unavailable: $error',
              style: const TextStyle(color: AppPalette.coral, fontSize: 12),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Retry', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: AppPalette.coral),
          ),
        ],
      ),
    );
  }
}