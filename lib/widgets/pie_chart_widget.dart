import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';

class PieChartWidget extends StatelessWidget {
  const PieChartWidget({super.key, required this.data});

  final Map<String, double> data;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((entry) => entry.value > 0).toList();
    final colors = <Color>[
      AppPalette.accent,
      AppPalette.sky,
      AppPalette.mint,
      AppPalette.coral,
    ];

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 36,
              sectionsSpace: 2,
              pieTouchData: PieTouchData(enabled: false),
              sections: [
                for (var index = 0; index < entries.length; index++)
                  PieChartSectionData(
                    value: entries[index].value,
                    color: colors[index % colors.length],
                    radius: 52,
                    title: entries[index].value.toStringAsFixed(0),
                    titleStyle:
                        Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (var index = 0; index < entries.length; index++)
              _LegendChip(
                label: entries[index].key,
                color: colors[index % colors.length],
              ),
          ],
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}
