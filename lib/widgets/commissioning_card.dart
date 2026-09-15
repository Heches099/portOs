import 'dart:async';

import 'package:flutter/material.dart';

import '../models/commission_status.dart';
import '../providers/theme_provider.dart';
import '../services/machine_control_service.dart';
import 'glass_card.dart';

/// Commissioning-mode card: current movement level, the safety preflight
/// breakdown, and the advance/reset actions that the live backend gates
/// movement behind (default = BLOCKED until a commissioning level is reached).
class CommissioningCard extends StatefulWidget {
  const CommissioningCard({
    super.key,
    required this.machineId,
    required this.service,
  });

  final String machineId;
  final MachineControlService service;

  @override
  State<CommissioningCard> createState() => _CommissioningCardState();
}

class _CommissioningCardState extends State<CommissioningCard> {
  CommissionStatus? _status;
  bool _loaded = false;
  bool _busy = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final status = await widget.service.fetchCommissionStatus(widget.machineId);
      if (mounted) {
        setState(() {
          _status = status;
          _loaded = true;
          if (!silent) _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          if (!silent) _error = e.toString();
        });
      }
    }
  }

  Future<void> _advance() async {
    await _runAction(() => widget.service.advanceCommission(widget.machineId));
  }

  Future<void> _reset() async {
    await _runAction(() => widget.service.resetCommission(widget.machineId));
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _levelColor(CommissionStatus s) {
    if (s.unlimited) return AppPalette.success;
    if (s.commissioned) return AppPalette.warning;
    return AppPalette.coral;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _status;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: AppPalette.accent, size: 20),
              const SizedBox(width: 8),
              Text('Commissioning', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (status != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _levelColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.levelDisplay.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: _levelColor(status),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Live movement is distance-gated. Advance a level to unlock more travel; '
            'UNLIMITED disables the cap.',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: isDark ? Colors.white54 : Colors.grey[600],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppPalette.coral.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: AppPalette.coral, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppPalette.coral, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (status != null && !status.unlimited && status.nextLevelMm != null) ...[
            const SizedBox(height: 10),
            Text(
              'Next level: ${status.nextLevelMm == -1 ? 'UNLIMITED' : '${status.nextLevelMm!.toStringAsFixed(0)} mm'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.grey[800],
              ),
            ),
          ],

          if (!_loaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),

          if (status != null) ...[
            const SizedBox(height: 10),
            Text(
              'Preflight',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.grey[600],
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            if (status.preflight.isEmpty)
              Text(
                'No preflight data reported by the backend.',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey[500]),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: status.preflight.map((check) {
                  return _PreflightChip(check: check);
                }).toList(),
              ),
          ],

          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || (status?.unlimited ?? false) ? null : _advance,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_upward_rounded, size: 16),
                  label: Text(
                    status?.unlimited == true ? 'Unlimited' : 'Advance',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.success,
                    side: BorderSide(color: AppPalette.success.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || (status?.commissionDistanceMm ?? 0) <= 0 ? null : _reset,
                  icon: const Icon(Icons.lock_reset_rounded, size: 16),
                  label: const Text('Reset', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.warning,
                    side: BorderSide(color: AppPalette.warning.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreflightChip extends StatelessWidget {
  const _PreflightChip({required this.check});

  final PreflightCheck check;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = check.passed ? AppPalette.success : AppPalette.coral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(check.passed ? Icons.check_rounded : Icons.close_rounded, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            check.label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}