import 'package:flutter/material.dart';

import '../models/camera_feed.dart';
import '../providers/theme_provider.dart';
import '../utils/extensions.dart';

class CameraThumbnail extends StatelessWidget {
  const CameraThumbnail({super.key, required this.feed});

  final CameraFeed feed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppPalette.steel.withValues(alpha: 0.88),
            AppPalette.navy.withValues(alpha: 0.94),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusChip(isOnline: feed.isOnline),
                const Spacer(),
                Text(
                  '${feed.viewers} viewers',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              feed.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              feed.location,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (feed.alert != null)
              Text(
                feed.alert!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppPalette.accent,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            const SizedBox(height: 12),
            Text(
              'Last ping ${feed.lastUpdated.shortTimestamp}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppPalette.mint : AppPalette.coral;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          isOnline ? 'Online' : 'Offline',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
