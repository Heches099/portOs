import 'package:flutter/material.dart';

import '../models/agv_telemetry.dart';
import '../providers/theme_provider.dart';

class AgvMapPainter extends CustomPainter {
  AgvMapPainter({required this.agvs});

  final List<AgvTelemetry> agvs;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = AppPalette.steel.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var index = 1; index < 6; index++) {
      final dx = size.width * index / 6;
      final dy = size.height * index / 6;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), backgroundPaint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), backgroundPaint);
    }

    final routePaint = Paint()
      ..color = AppPalette.accent.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.12, size.height * 0.25),
      Offset(size.width * 0.84, size.height * 0.78),
      routePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.72),
      Offset(size.width * 0.72, size.height * 0.22),
      routePaint,
    );

    for (final agv in agvs) {
      final position = Offset(size.width * agv.x, size.height * agv.y);
      final color = switch (agv.status) {
        'Charging' => AppPalette.accent,
        'Idle' => AppPalette.sky,
        _ => AppPalette.mint,
      };

      final glowPaint = Paint()..color = color.withValues(alpha: 0.18);
      canvas.drawCircle(position, 20, glowPaint);

      final pointPaint = Paint()..color = color;
      canvas.drawCircle(position, 9, pointPaint);

      final labelPainter = TextPainter(
        text: TextSpan(
          text: agv.id,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(canvas, position.translate(-14, 14));
    }
  }

  @override
  bool shouldRepaint(covariant AgvMapPainter oldDelegate) =>
      oldDelegate.agvs != agvs;
}
