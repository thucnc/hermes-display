import 'package:flutter/material.dart';

import '../../core/state/connection_status.dart';
import '../strings.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';

/// Wake-word microphone state shown beside the connection status.
enum MicIndicator {
  /// Spotter armed: "Hey Sen" works.
  armed,

  /// No keyword model; only the mic button starts a turn.
  manual,

  /// Permission missing or hardware busy/failed.
  unavailable,
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    required this.address,
    this.onTap,
    this.mic,
  });

  final ConnectionStatus status;
  final String address;
  final VoidCallback? onTap;

  /// Null hides the mic icon (no voice pipeline).
  final MicIndicator? mic;

  static const Key micKey = ValueKey<String>('status-mic');

  static const double _dotSize = 10;
  static const double _glowBlur = 10;
  static const double _labelSize = 14;
  static const double _addressSize = 12;
  static const double _micSize = 16;
  static const double _micGlowAlpha = 0.45;
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

  static IconData iconFor(MicIndicator mic) => switch (mic) {
    MicIndicator.armed => Icons.mic_rounded,
    MicIndicator.manual => Icons.mic_none_rounded,
    MicIndicator.unavailable => Icons.mic_off_rounded,
  };

  static Color _micColor(MicIndicator mic) => switch (mic) {
    MicIndicator.armed => AppPalette.online,
    MicIndicator.manual => AppPalette.textMuted,
    MicIndicator.unavailable => AppPalette.pending,
  };

  static String _micLabel(MicIndicator mic) => switch (mic) {
    MicIndicator.armed => AppStrings.micArmed,
    MicIndicator.manual => AppStrings.micManual,
    MicIndicator.unavailable => AppStrings.micOff,
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
            ..._micIcon(),
          ],
        ),
      ),
    );
  }

  List<Widget> _micIcon() {
    final current = mic;
    if (current == null) {
      return const [];
    }
    final color = _micColor(current);
    return [
      const SizedBox(width: Spacing.sm),
      Semantics(
        label: _micLabel(current),
        child: AnimatedSwitcher(
          duration: Motion.quick,
          child: Icon(
            iconFor(current),
            key: micKey,
            size: _micSize,
            color: color,
            shadows: [
              Shadow(
                color: color.withValues(alpha: _micGlowAlpha),
                blurRadius: _glowBlur,
              ),
            ],
          ),
        ),
      ),
    ];
  }
}
