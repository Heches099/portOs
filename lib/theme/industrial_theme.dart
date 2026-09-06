import 'package:flutter/material.dart';

/// Central industrial SCADA visual language for the PortOS control center.
///
/// All operational panels, the camera overlays, machine controls and the
/// telemetry bar share these tones so the workspace reads as one coherent
/// industrial system rather than a collection of dashboard cards.
class IndustrialTheme {
  IndustrialTheme._();

  // Backgrounds ------------------------------------------------------
  static const Color bg = Color(0xFF030B16);
  static const Color panel = Color(0xFF0A1524);
  static const Color panelAlt = Color(0xFF0E1D30);
  static const Color panelDeep = Color(0xFF08111F);

  // Borders ----------------------------------------------------------
  static const Color border = Color(0xFF1B2C42);
  static const Color borderHi = Color(0xFF29415F);

  // Text -------------------------------------------------------------
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB8C4D4);
  static const Color textMuted = Color(0xFF5F718A);

  // Functional tones -------------------------------------------------
  static const Color control = Color(0xFF38BDF8); // cyan   active / interaction
  static const Color ready = Color(0xFF22C55E); // green  online / healthy
  static const Color warn = Color(0xFFF5A524); // amber  warning / degraded
  static const Color danger = Color(0xFFEF4444); // red    error / emergency
  static const Color idle = Color(0xFF7C8AA3); // gray   offline / disabled
  static const Color violet = Color(0xFF8B5CF6); // accented aux feature
  static const Color teal = Color(0xFF2DD4BF); // AI vision accent

  static const String mono = 'monospace';

  static String pad(double value, [int decimals = 1]) =>
      value.toStringAsFixed(decimals);
}