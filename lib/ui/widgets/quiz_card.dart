import 'package:flutter/material.dart';

import '../../core/skills/skill_content.dart';
import '../strings.dart';
import '../theme/app_theme.dart';

/// Quiz question with four tappable choices; after a pick the right one
/// turns green and a wrong pick red.
class QuizCard extends StatelessWidget {
  const QuizCard({
    super.key,
    required this.quiz,
    required this.picked,
    required this.onPick,
  });

  final QuizContent quiz;

  /// Null until answered; further taps are ignored.
  final int? picked;
  final ValueChanged<int> onPick;

  static const double _questionSize = 24;
  static const double _optionSize = 20;
  static const double _resultSize = 20;
  static const double _badgeSize = 36;
  static const double _badgeTextSize = 16;
  static const double _optionRadius = 18;
  static const double _fillAlpha = 0.3;
  static const double _lineHeight = 1.35;

  static final Color correctFill = AppPalette.online.withValues(
    alpha: _fillAlpha,
  );
  static final Color wrongFill = AppPalette.offline.withValues(
    alpha: _fillAlpha,
  );

  static Key optionKey(int index) => ValueKey('quiz-option-$index');

  @override
  Widget build(BuildContext context) {
    final picked = this.picked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          quiz.question,
          style: const TextStyle(
            fontSize: _questionSize,
            fontWeight: FontWeight.w600,
            height: _lineHeight,
          ),
        ),
        const SizedBox(height: Spacing.md),
        for (final (index, option) in quiz.options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _option(index, option),
          ),
        if (picked != null) ..._result(picked),
      ],
    );
  }

  Widget _option(int index, String option) {
    final fill = _fillFor(index);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: picked == null ? () => onPick(index) : null,
      child: AnimatedContainer(
        key: optionKey(index),
        duration: Motion.quick,
        padding: const EdgeInsets.all(Spacing.sm),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(_optionRadius),
          border: Border.all(color: AppPalette.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              width: _badgeSize,
              height: _badgeSize,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppPalette.accent,
                shape: BoxShape.circle,
              ),
              child: Text(
                QuizContent.letters[index],
                style: const TextStyle(
                  fontSize: _badgeTextSize,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.ink,
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                option,
                style: const TextStyle(fontSize: _optionSize),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _fillFor(int index) {
    final picked = this.picked;
    if (picked == null) {
      return AppPalette.glass;
    }
    if (quiz.isCorrect(index)) {
      return correctFill;
    }
    return index == picked ? wrongFill : AppPalette.glass;
  }

  List<Widget> _result(int picked) {
    final right = quiz.isCorrect(picked);
    final letter = QuizContent.letters[quiz.answer];
    return [
      const SizedBox(height: Spacing.sm),
      Text(
        right ? AppStrings.quizCorrect : '${AppStrings.quizWrong} $letter',
        style: TextStyle(
          fontSize: _resultSize,
          fontWeight: FontWeight.w700,
          color: right ? AppPalette.online : AppPalette.offline,
        ),
      ),
      if (quiz.explanation.isNotEmpty) ...[
        const SizedBox(height: Spacing.xs),
        Text(
          quiz.explanation,
          style: const TextStyle(
            fontSize: _optionSize,
            color: AppPalette.textMuted,
            height: _lineHeight,
          ),
        ),
      ],
    ];
  }
}
