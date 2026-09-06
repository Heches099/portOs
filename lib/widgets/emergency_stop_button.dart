import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';

class EmergencyStopButton extends StatelessWidget {
  const EmergencyStopButton({super.key, required this.onPressed, this.isExecuting = false});

  final VoidCallback onPressed;
  final bool isExecuting;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isExecuting ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.coral,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
          shadowColor: AppPalette.coral.withValues(alpha: 0.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isExecuting)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              const Icon(Icons.stop_rounded, size: 22),
            const SizedBox(width: 8),
            Text(
              isExecuting ? 'STOPPING...' : 'EMERGENCY STOP',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
