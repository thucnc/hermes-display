import 'package:flutter/material.dart';

import '../../core/members/member_profile.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';

/// One-tap avatar row choosing who Sen is talking to.
class MemberSwitcher extends StatelessWidget {
  const MemberSwitcher({
    super.key,
    required this.members,
    required this.activeId,
    required this.onSelect,
  });

  final List<MemberProfile> members;
  final String activeId;
  final ValueChanged<String> onSelect;

  static const double _avatarSize = 40;
  static const double _initialSize = 17;
  static const double _nameSize = 12;
  static const double _ringWidth = 2;
  static const double _glowBlur = 14;
  static const double _glowAlpha = 0.6;
  static const double _activeFillAlpha = 0.25;

  static Key keyFor(String id) => ValueKey('member-$id');

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: Radii.pill,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, member) in members.indexed) ...[
            if (index > 0) const SizedBox(width: Spacing.md),
            _chip(member),
          ],
        ],
      ),
    );
  }

  Widget _chip(MemberProfile member) {
    final active = member.id == activeId;
    return Semantics(
      button: true,
      selected: active,
      label: member.name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(member.id),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              key: keyFor(member.id),
              duration: Motion.quick,
              width: _avatarSize,
              height: _avatarSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? AppPalette.accent.withValues(alpha: _activeFillAlpha)
                    : AppPalette.glass,
                border: Border.all(
                  color: active ? AppPalette.accent : AppPalette.glassBorder,
                  width: _ringWidth,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: AppPalette.accent.withValues(
                            alpha: _glowAlpha,
                          ),
                          blurRadius: _glowBlur,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                member.initial,
                style: const TextStyle(
                  fontSize: _initialSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              member.name,
              style: TextStyle(
                fontSize: _nameSize,
                color: active ? AppPalette.text : AppPalette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
