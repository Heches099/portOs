import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/machine_selection_controller.dart';
import '../theme/industrial_theme.dart';
import '../utils/movement_calibration.dart';
import '../widgets/live_camera_panel.dart';
import '../widgets/machine_control_panel.dart';
import '../widgets/machine_sidebar.dart';
import '../widgets/telemetry_bar.dart';

/// Primary operational workspace.
///
/// Selecting a machine updates the shared [MachineSelectionController], which
/// re-drives the camera, the control panel, the telemetry bar and the AI
/// overlay simultaneously. The operator never navigates away to see a camera:
/// camera, control and telemetry live on the same screen.
class LiveOperationsScreen extends StatelessWidget {
  const LiveOperationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                child: _buildMainWorkspace(width, height),
              ),
              const SizedBox(height: 8),
              const TelemetryBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainWorkspace(double width, double height) {
    if (width >= 1280) {
      // Desktop: three-column operational layout.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MachineSidebar(),
          const SizedBox(width: 10),
          Expanded(child: _CameraColumn()),
          const SizedBox(width: 10),
          SizedBox(width: 380, child: _ControlColumn()),
        ],
      );
    }

    if (width >= 900) {
      // Tablet landscape: collapsed roster, camera + controls.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MachineSidebar(horizontal: true),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 6, child: _CameraColumn()),
                const SizedBox(width: 10),
                SizedBox(width: 360, child: _ControlColumn()),
              ],
            ),
          ),
        ],
      );
    }

    // Mobile / narrow tablet: stack camera, machine status, controls.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MachineSidebar(horizontal: true),
        const SizedBox(height: 8),
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              color: IndustrialTheme.panelDeep,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: IndustrialTheme.border),
            ),
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(8),
            child: const LiveCameraPanel(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              color: IndustrialTheme.panelDeep,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: IndustrialTheme.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: MachineControlPanel(showEStop: false),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _FloatingEstop(compact: true),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CameraColumn extends StatelessWidget {
  const _CameraColumn();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: IndustrialTheme.panelDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IndustrialTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(10),
      child: const LiveCameraPanel(),
    );
  }
}

class _ControlColumn extends StatelessWidget {
  const _ControlColumn();

  @override
  Widget build(BuildContext context) {
    return const MachineControlPanel();
  }
}

/// Always-visible emergency stop for stacked mobile layouts.
class _FloatingEstop extends StatelessWidget {
  const _FloatingEstop({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<MachineSelectionController>();

    return Material(
      color: IndustrialTheme.danger,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 6,
      shadowColor: IndustrialTheme.danger.withValues(alpha: 0.5),
      child: InkWell(
        onTap: () async {
          final confirmed = await confirmOperation(
            context,
            title: 'EMERGENCY STOP ${controller.selectedMachine.name}',
            message:
                'This immediately halts all movement and overrides any active command.',
            confirmLabel: 'STOP NOW',
          );
          if (confirmed && context.mounted) {
            await controller.emergencyStop();
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.stop_circle_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                compact ? 'E-STOP' : 'EMERGENCY STOP',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}