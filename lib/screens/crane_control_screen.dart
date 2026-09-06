import 'dart:async';

import 'package:flutter/material.dart';

import '../models/machine_status.dart';
import '../providers/theme_provider.dart';
import '../services/machine_control_service.dart';
import '../widgets/command_history_table.dart';
import '../widgets/crane_drive_card.dart';
import '../widgets/machine_control_widgets.dart';
import '../widgets/trolley_control_card.dart';

class CraneControlScreen extends StatefulWidget {
  const CraneControlScreen({super.key});

  @override
  State<CraneControlScreen> createState() => _CraneControlScreenState();
}

class _CraneControlScreenState extends State<CraneControlScreen> {
  static const _craneId = '2';
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
      final detail = await _service.fetchMachineDetail(_craneId);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CraneHeading(title: 'Crane Control', isDark: isDark),
          const SizedBox(height: 16),
          if (_error != null) ...[
            _ErrorBanner(error: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            }),
            const SizedBox(height: 12),
          ],
          MachineSimulationBanner(machineId: _craneId, service: _service),
          const SizedBox(height: 12),
          MachineInfoBar(machine: _machine),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 980;
              final controls = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CraneDriveCard(machineId: _craneId, service: _service),
                  const SizedBox(height: 16),
                  TrolleyControlCard(machineId: _craneId, service: _service),
                  const SizedBox(height: 16),
                  AutoModeCard(
                    machineId: _craneId,
                    service: _service,
                    machineType: 'crane',
                  ),
                ],
              );
              final history = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CommandHistoryTable(machineId: _craneId, service: _service),
                  const SizedBox(height: 16),
                  MachineActivityFeed(machineId: _craneId, service: _service),
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

class _CraneHeading extends StatelessWidget {
  const _CraneHeading({required this.title, required this.isDark});

  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF472B6).withValues(alpha: 0.15),
          ),
          child: const Icon(Icons.construction_rounded, color: Color(0xFFF472B6), size: 22),
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
                'Whole-crane drive, trolley traverse, hoist lift, electromagnet, and auto-mode for Crane-01.',
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
              'Crane telemetry unavailable: $error',
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