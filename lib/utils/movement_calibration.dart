import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';

/// Open-loop calibration helpers for distance-based machine movement.
///
/// The backend only supports *timed* commands today:
///   - AGV `/command` accepts `speed` plus `duration` (milliseconds).
///   - Crane/Trolley `/command` accepts `steps` (stepper magnitude).
///
/// It does not natively accept a physical distance. Distance mode therefore
/// converts internally using an operator-calibrated value so the operator can
/// reason in mm/cm while the machine keeps receiving the existing timed API:
///
///   AGV:            distance = speed x time   =>  time = distance / speed
///   Crane/Trolley:  distance_steps = distance_mm x steps_per_mm
///
/// The calibration is NOT a fake universal speed; it is explicitly editable by
/// the operator per machine so the conversion reflects real hardware.
class MovementCalibration {
  const MovementCalibration({
    this.mmPerSecondAtFullSpeed = 0,
    this.stepsPerMm = 0,
    this.minTimeMs = 250,
    this.maxTimeMs = 30000,
    this.minSteps = 1,
    this.maxSteps = 10000,
  });

  /// Maximum physical speed in millimetres/second when the machine command
  /// speed is at 100%. Used to derive a timed duration for AGV-style commands.
  final double mmPerSecondAtFullSpeed;

  /// Stepper steps required to move one millimetre. Used for crane/trolley
  /// hoist and traverse commands that natively speak in `steps`.
  final double stepsPerMm;

  final int minTimeMs;
  final int maxTimeMs;
  final int minSteps;
  final int maxSteps;

  bool get supportsDuration => mmPerSecondAtFullSpeed > 0;

  bool get supportsSteps => stepsPerMm > 0;

  /// Convert a desired distance in millimetres into a timed command duration
  /// in milliseconds at the given command speed (0..1 fraction of full speed).
  int distanceMmToDurationMs({
    required double distanceMm,
    double speedFraction = 1.0,
  }) {
    if (!supportsDuration) return minTimeMs;
    final effectiveSpeed = mmPerSecondAtFullSpeed * speedFraction.clamp(0.1, 1.0);
    final seconds = distanceMm / effectiveSpeed;
    final ms = (seconds * 1000).round();
    return ms.clamp(minTimeMs, maxTimeMs);
  }

  /// Convert a desired distance in millimetres into a stepper `steps` value.
  int distanceMmToSteps({required double distanceMm}) {
    if (!supportsSteps) return minSteps;
    final steps = (distanceMm * stepsPerMm).round();
    return steps.clamp(minSteps, maxSteps);
  }

  String get calibrationLabel {
    if (supportsDuration && supportsSteps) {
      return '${mmPerSecondAtFullSpeed.toStringAsFixed(0)} mm/s · ${stepsPerMm.toStringAsFixed(1)} steps/mm';
    }
    if (supportsDuration) {
      return '${mmPerSecondAtFullSpeed.toStringAsFixed(0)} mm/s';
    }
    if (supportsSteps) {
      return '${stepsPerMm.toStringAsFixed(1)} steps/mm';
    }
    return 'not calibrated';
  }

  static double cmToMm(double cm) => cm * 10;

  static double mmToCm(double mm) => mm / 10;
}

/// Per-machine calibration presets. These are starting defaults and remain
/// editable by the operator in the UI.
const agvCalibration = MovementCalibration(mmPerSecondAtFullSpeed: 200);
const craneCalibration = MovementCalibration(stepsPerMm: 10);
const trolleyCalibration = MovementCalibration(stepsPerMm: 10);

/// Run a confirmation dialog for a potentially dangerous operation.
/// Returns true when the operator confirmed.
Future<bool> confirmOperation(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'EXECUTE',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppPalette.coral,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}