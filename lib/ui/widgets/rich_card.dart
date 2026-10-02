import 'package:flutter/material.dart';

import '../../core/media/rich_content.dart';
import '../../core/skills/skill_content.dart';
import '../../services/hermes_sync_service.dart';
import '../strings.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';
import 'inline_video.dart';
import 'quiz_card.dart';
import 'roleplay_card.dart';

typedef VideoBuilder = Widget Function(YouTubeVideo video);

Widget _inlineVideo(YouTubeVideo video) => InlineVideo(video: video);

/// Reply card with an inline YouTube player, numbered steps and
/// "Save to Hermes"; skill replies render their own interactive card.
class RichCard extends StatefulWidget {
  const RichCard({
    super.key,
    required this.content,
    required this.onSave,
    required this.onClose,
    this.playerBuilder = _inlineVideo,
    this.quizPick,
    this.onQuizPick,
  });

  final RichContent content;

  /// Builds the player once play is tapped; tests swap in a stand-in
  /// because the real one needs a native WebView.
  final VideoBuilder playerBuilder;
  final Future<SaveResult> Function() onSave;
  final VoidCallback onClose;

  /// Chosen quiz option, null until answered.
  final int? quizPick;
  final ValueChanged<int>? onQuizPick;

  @override
  State<RichCard> createState() => _RichCardState();
}

class _RichCardState extends State<RichCard> {
  static const double _maxWidth = 760;
  static const double _heightFraction = 0.72;
  static const double _labelSize = 13;
  static const double _labelSpacing = 1.6;
  static const double _titleSize = 22;
  static const double _bodySize = 20;
  static const double _stepSize = 22;
  static const double _lineHeight = 1.35;
  static const double _thumbWidth = 240;
  static const double _thumbRatio = 16 / 9;
  static const double _thumbRadius = 16;
  static const double _playIconSize = 48;
  static const double _badgeSize = 34;
  static const double _badgeTextSize = 16;

  bool _saving = false;
  bool _playing = false;

  void _play() => setState(() => _playing = true);

  Future<void> _save() async {
    setState(() => _saving = true);
    final result = await widget.onSave();
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    final message = result == SaveResult.saved
        ? AppStrings.savedToBrain
        : AppStrings.saveFailed;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final video = content.video;
    final maxHeight = MediaQuery.sizeOf(context).height * _heightFraction;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _maxWidth, maxHeight: maxHeight),
      child: GlassSurface(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(content.title),
            const SizedBox(height: Spacing.md),
            Flexible(
              child: SingleChildScrollView(
                child:
                    _skillBody(content.skill) ??
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (video != null) ...[
                          _videoTile(video),
                          const SizedBox(height: Spacing.lg),
                        ],
                        if (content.steps.isEmpty)
                          Text(
                            content.body,
                            style: const TextStyle(
                              fontSize: _bodySize,
                              height: _lineHeight,
                            ),
                          )
                        else
                          ..._steps(content.steps),
                      ],
                    ),
              ),
            ),
            if (content.skill == null) ...[
              const SizedBox(height: Spacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _saving ? AppStrings.saving : AppStrings.saveToHermes,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _skillBody(SkillContent? skill) {
    return switch (skill) {
      null => null,
      QuizContent() => QuizCard(
        quiz: skill,
        picked: widget.quizPick,
        onPick: (index) => widget.onQuizPick?.call(index),
      ),
      RoleplayContent() => RoleplayCard(roleplay: skill),
    };
  }

  Widget _header(String title) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.assistantName.toUpperCase(),
                style: const TextStyle(
                  fontSize: _labelSize,
                  letterSpacing: _labelSpacing,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.accentWarm,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                title,
                style: const TextStyle(
                  fontSize: _titleSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: AppStrings.tipClose,
          icon: const Icon(Icons.close_rounded),
          onPressed: widget.onClose,
        ),
      ],
    );
  }

  Widget _videoTile(YouTubeVideo video) {
    if (_playing) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(_thumbRadius),
        child: widget.playerBuilder(video),
      );
    }
    return Row(
      children: [
        GestureDetector(
          onTap: _play,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_thumbRadius),
            child: SizedBox(
              width: _thumbWidth,
              child: AspectRatio(
                aspectRatio: _thumbRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      video.thumbnail.toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: AppPalette.glass),
                    ),
                    const Icon(
                      Icons.play_circle_fill_rounded,
                      size: _playIconSize,
                      color: AppPalette.text,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                video.title ?? AppStrings.videoFallbackTitle,
                style: const TextStyle(
                  fontSize: _bodySize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              FilledButton.icon(
                onPressed: _play,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text(AppStrings.playVideo),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _steps(List<String> steps) {
    return [
      const Text(
        AppStrings.stepsTitle,
        style: TextStyle(fontSize: _labelSize, color: AppPalette.textMuted),
      ),
      const SizedBox(height: Spacing.sm),
      for (final (index, step) in steps.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _badge(index + 1),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  step,
                  style: const TextStyle(
                    fontSize: _stepSize,
                    height: _lineHeight,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _badge(int number) {
    return Container(
      width: _badgeSize,
      height: _badgeSize,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppPalette.accentWarm,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: const TextStyle(
          fontSize: _badgeTextSize,
          fontWeight: FontWeight.w700,
          color: AppPalette.ink,
        ),
      ),
    );
  }
}
