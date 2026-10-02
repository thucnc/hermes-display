import 'package:flutter/material.dart';

import '../../core/skills/skill_content.dart';
import '../strings.dart';
import '../theme/app_theme.dart';

/// English roleplay turn: scenario badge, Sen's line with its Vietnamese
/// hint, and vocabulary tips.
class RoleplayCard extends StatelessWidget {
  const RoleplayCard({super.key, required this.roleplay});

  final RoleplayContent roleplay;

  static const double _badgeSize = 14;
  static const double _lineSize = 26;
  static const double _hintSize = 19;
  static const double _labelSize = 13;
  static const double _vocabSize = 19;
  static const double _lineHeight = 1.35;
  static const double _badgeAlpha = 0.25;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (roleplay.scenario.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppPalette.accentWarm.withValues(alpha: _badgeAlpha),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Text(
              roleplay.scenario,
              style: const TextStyle(
                fontSize: _badgeSize,
                fontWeight: FontWeight.w600,
                color: AppPalette.accentWarm,
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
        ],
        Text(
          roleplay.line,
          style: const TextStyle(
            fontSize: _lineSize,
            fontWeight: FontWeight.w600,
            height: _lineHeight,
          ),
        ),
        if (roleplay.translation.isNotEmpty) ...[
          const SizedBox(height: Spacing.sm),
          Text(
            '(${roleplay.translation})',
            style: const TextStyle(
              fontSize: _hintSize,
              color: AppPalette.textMuted,
              fontStyle: FontStyle.italic,
              height: _lineHeight,
            ),
          ),
        ],
        if (roleplay.vocab.isNotEmpty) ..._vocab(),
      ],
    );
  }

  List<Widget> _vocab() {
    return [
      const SizedBox(height: Spacing.lg),
      const Text(
        AppStrings.vocabTitle,
        style: TextStyle(fontSize: _labelSize, color: AppPalette.textMuted),
      ),
      const SizedBox(height: Spacing.sm),
      for (final tip in roleplay.vocab)
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tip.word,
                style: const TextStyle(
                  fontSize: _vocabSize,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.accent,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  tip.meaning,
                  style: const TextStyle(fontSize: _vocabSize),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}
