import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/state/display_state.dart';
import '../strings.dart';
import '../theme/app_theme.dart';
import 'pulse_glow.dart';
import 'subtitle_card.dart';
import 'waveform_visualizer.dart';

/// Center stage visuals for every non-idle state.
class VoiceOverlay extends StatelessWidget {
  const VoiceOverlay({
    super.key,
    required this.state,
    required this.transcript,
    required this.reply,
    required this.level,
  });

  final DisplayState state;
  final String transcript;
  final String reply;
  final ValueListenable<double> level;

  static const double _maxWidth = 760;
  static const double _captionSize = 15;
  static const double _transcriptSize = 24;
  static const double _replyWaveHeight = 36;
  static const int _replyWaveBars = 36;
  static const double _slideFraction = 0.06;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.overlay,
      switchInCurve: Motion.emphasized,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, _slideFraction),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(state), child: _content()),
    );
  }

  Widget _content() {
    switch (state) {
      case DisplayState.idle:
        return const SizedBox.shrink();
      case DisplayState.listening:
        return _stage(
          visual: WaveformVisualizer(level: level, color: AppPalette.accent),
          caption: AppStrings.listening,
        );
      case DisplayState.thinking:
        return _stage(
          visual: const PulseGlow(color: AppPalette.accentWarm),
          caption: AppStrings.thinking,
        );
      case DisplayState.speaking:
        return SubtitleCard(
          text: reply,
          footer: WaveformVisualizer(
            level: level,
            color: AppPalette.accentWarm,
            height: _replyWaveHeight,
            barCount: _replyWaveBars,
          ),
        );
    }
  }

  Widget _stage({required Widget visual, required String caption}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          visual,
          const SizedBox(height: Spacing.lg),
          Text(
            caption,
            style: const TextStyle(
              fontSize: _captionSize,
              color: AppPalette.textMuted,
            ),
          ),
          if (transcript.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              transcript,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: _transcriptSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
