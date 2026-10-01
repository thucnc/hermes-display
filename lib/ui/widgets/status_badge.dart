import 'package:flutter/material.dart';

import '../../core/state/connection_status.dart';
import '../strings.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    required this.address,
    this.onTap,
  });

  final ConnectionStatus status;
  final String address;
  final VoidCallback? onTap;

  static const double _dotSize = 10;
  static const double _glowBlur = 10;
  static const double _labelSize = 14;
  static const double _addressSize = 12;
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: Spacing.md,
    vertical: Spacing.sm,
  );

  Color get _color => switch (status) {
    ConnectionStatus.connected => AppPalette.online,
    ConnectionStatus.connecting => AppPalette.pending,
    ConnectionStatus.disconnected => AppPalette.offline,
  };

  String get _label => switch (status) {
    ConnectionStatus.connected => AppStrings.statusConnected,
    ConnectionStatus.connecting => AppStrings.statusConnecting,
    ConnectionStatus.disconnected => AppStrings.statusDisconnected,
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        radius: Radii.pill,
        padding: _padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: Motion.quick,
              width: _dotSize,
              height: _dotSize,
              decoration: BoxDecoration(
                color: _color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _color, blurRadius: _glowBlur)],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              _label,
              style: const TextStyle(
                fontSize: _labelSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              address,
              style: const TextStyle(
                fontSize: _addressSize,
                color: AppPalette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
