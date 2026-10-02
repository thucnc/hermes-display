import 'package:flutter/material.dart';

import '../../core/update/app_release.dart';
import '../strings.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';

/// Ambient prompt for a downloaded, verified APK.
class UpdateBadge extends StatelessWidget {
  const UpdateBadge({super.key, required this.release, required this.onTap});

  final AppRelease release;
  final VoidCallback onTap;

  static const double _iconSize = 18;
  static const double _labelSize = 14;
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: Spacing.md,
    vertical: Spacing.sm,
  );

  static String label(AppRelease release) {
    return '${AppStrings.updateAvailable} v${release.versionName} — '
        '${AppStrings.updateTapToInstall}';
  }

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
            const Icon(
              Icons.system_update_rounded,
              size: _iconSize,
              color: AppPalette.online,
            ),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                label(release),
                style: const TextStyle(
                  fontSize: _labelSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
