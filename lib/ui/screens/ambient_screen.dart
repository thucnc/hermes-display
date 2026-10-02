import 'package:flutter/material.dart';

import '../../core/state/display_controller.dart';
import '../../core/state/display_state.dart';
import '../../services/wake_word_service.dart';
import '../strings.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_clock.dart';
import '../widgets/legibility_scrim.dart';
import '../widgets/photo_slideshow.dart';
import '../widgets/quick_input_bar.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/status_badge.dart';
import '../widgets/voice_overlay.dart';

class AmbientScreen extends StatelessWidget {
  const AmbientScreen({
    super.key,
    required this.controller,
    this.photos = SlideDeck.defaultPhotos,
  });

  final DisplayController controller;
  final List<String> photos;

  static const double _clockLandscape = 0.24;
  static const double _clockPortrait = 0.28;
  static const double _dimmedOpacity = 0.35;

  /// Slideshow/clock opacity inside the night dim window.
  static const double nightOpacity = 0.7;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => controller.touch(),
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, controller.nightDimmed]),
          builder: (context, _) => _layers(context),
        ),
      ),
    );
  }

  Widget _layers(BuildContext context) {
    final state = controller.state;
    final active = state != DisplayState.idle;
    final settings = controller.settings;
    final night = controller.nightDimmed.value ? nightOpacity : 1.0;
    return LayoutBuilder(
      builder: (context, box) {
        final landscape = box.maxWidth > box.maxHeight;
        final ratio = landscape ? _clockLandscape : _clockPortrait;
        final clockSize = box.biggest.shortestSide * ratio;
        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedOpacity(
              duration: Motion.overlay,
              opacity: night,
              child: PhotoSlideshow(
                interval: settings.slideInterval,
                photos: photos,
              ),
            ),
            LegibilityScrim(
              level: active ? ScrimLevel.focused : ScrimLevel.ambient,
            ),
            SafeArea(
              minimum: const EdgeInsets.all(Spacing.xl),
              child: Stack(
                children: [
                  _overlay(state),
                  Align(
                    alignment: Alignment.topLeft,
                    child: StatusBadge(
                      status: controller.connection,
                      address: '${settings.host}:${settings.port}',
                      onTap: controller.reconnect,
                      mic: _micFor(controller.voiceStatus),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      tooltip: AppStrings.tipSettings,
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: () => showSettingsSheet(context, controller),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: AnimatedOpacity(
                      duration: Motion.overlay,
                      opacity: active ? _dimmedOpacity : night,
                      child: AmbientClock(timeSize: clockSize),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: QuickInputBar(
                      onSubmit: controller.sendText,
                      onMic: controller.listen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static MicIndicator? _micFor(VoiceStatus? status) => switch (status) {
    null => null,
    VoiceStatus.ready => MicIndicator.armed,
    VoiceStatus.manualOnly => MicIndicator.manual,
    _ => MicIndicator.unavailable,
  };

  Widget _overlay(DisplayState state) {
    return IgnorePointer(
      ignoring: state == DisplayState.idle,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: controller.cancel,
        child: Center(
          child: VoiceOverlay(
            state: state,
            transcript: controller.transcript,
            reply: controller.reply,
            level: controller.level,
          ),
        ),
      ),
    );
  }
}
