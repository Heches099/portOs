import 'dart:async';
import 'package:flutter/material.dart';

import '../models/machine_command.dart';
import '../services/machine_control_service.dart';
import 'glass_card.dart';

class CommandHistoryTable extends StatefulWidget {
  const CommandHistoryTable({super.key, required this.machineId, required this.service});

  final String machineId;
  final MachineControlService service;

  @override
  State<CommandHistoryTable> createState() => _CommandHistoryTableState();
}

class _CommandHistoryTableState extends State<CommandHistoryTable> {
  List<MachineCommand> _commands = [];
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadCommands();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _loadCommands());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadCommands() async {
    try {
      final commands = await widget.service.fetchCommandHistory(widget.machineId);
      if (mounted) setState(() { _commands = commands; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, color: isDark ? Colors.white70 : Colors.grey[700], size: 18),
              const SizedBox(width: 8),
              Text(
                'Command History',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
          else if (_commands.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No commands sent yet.',
                  style: TextStyle(color: isDark ? Colors.white38 : Colors.grey[500]),
                ),
              ),
            )
          else
            SizedBox(
              height: 240,
              child: ListView.separated(
                itemCount: _commands.take(20).length,
                separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey[200]),
                itemBuilder: (context, index) {
                  final cmd = _commands[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            cmd.command,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            cmd.params.isEmpty ? '-' : cmd.params,
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600]),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _StatusChip(status: cmd.status),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            cmd.executedAt != null ? _formatTime(cmd.executedAt!) : '-',
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey[500]),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final CommandStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      CommandStatus.pending => (Colors.orange, 'Pending'),
      CommandStatus.inProgress => (Colors.blue, 'Running'),
      CommandStatus.completed => (Colors.green, 'Done'),
      CommandStatus.failed => (Colors.red, 'Failed'),
      CommandStatus.cancelled => (Colors.grey, 'Cancelled'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
