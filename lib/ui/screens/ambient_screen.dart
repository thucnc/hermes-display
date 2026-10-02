import 'package:flutter/material.dart';

import '../../core/state/display_controller.dart';
import '../../core/state/display_state.dart';
import '../../services/update/app_platform.dart';
import '../../services/update/app_updater.dart';
import '../../services/wake_word_service.dart';
import '../strings.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_clock.dart';
import '../widgets/legibility_scrim.dart';
import '../widgets/member_switcher.dart';
import '../widgets/photo_caption.dart';
import '../widgets/photo_slideshow.dart';
import '../widgets/quick_input_bar.dart';
import '../widgets/rich_card.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/status_badge.dart';
import '../widgets/update_badge.dart';
import '../widgets/voice_overlay.dart';

class AmbientScreen extends StatelessWidget {
  const AmbientScreen({super.key, required this.controller});

  final DisplayController controller;

  static const double _clockLandscape = 0.24;
  static const double _clockPortrait = 0.28;
  static const double _dimmedOpacity = 0.35;

  /// Photo caption sits below the member switcher.
  static const double _captionTop = 96;

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
    final card = _richCard(context, state);
    final active = state != DisplayState.idle || card != null;
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
                frame: controller.photos,
              ),
            ),
            LegibilityScrim(
              level: active ? ScrimLevel.focused : ScrimLevel.ambient,
            ),
            SafeArea(
              minimum: const EdgeInsets.all(Spacing.xl),
              child: Stack(
                children: [
                  if (card == null) _overlay(state),
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
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MemberSwitcher(
                          members: controller.members,
                          activeId: controller.member.id,
                          onSelect: controller.selectMember,
                        ),
                        _updateBadge(context),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: _captionTop),
                      child: AnimatedOpacity(
                        duration: Motion.overlay,
                        opacity: active ? 0 : night,
                        child: PhotoCaption(frame: controller.photos),
                      ),
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
                  ?card,
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _updateBadge(BuildContext context) {
    return ValueListenableBuilder<UpdateState>(
      valueListenable: controller.update,
      builder: (context, update, _) {
        final release = update.release;
        if (update.phase != UpdatePhase.ready || release == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: Spacing.sm),
          child: UpdateBadge(release: release, onTap: () => _install(context)),
        );
      },
    );
  }

  Future<void> _install(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = switch (await controller.installUpdate()) {
      InstallResult.started => null,
      InstallResult.needsPermission => AppStrings.updateNeedsPermission,
      InstallResult.unsupported ||
      InstallResult.failed => AppStrings.updateInstallFailed,
    };
    if (message == null) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  static MicIndicator? _micFor(VoiceStatus? status) => switch (status) {
    null => null,
    VoiceStatus.ready => MicIndicator.armed,
    VoiceStatus.manualOnly => MicIndicator.manual,
    _ => MicIndicator.unavailable,
  };

  /// Replaces the subtitle while speaking and stays on the idle screen
  /// until dismissed or the next turn starts. Topmost so the clock never
  /// takes its taps.
  Widget? _richCard(BuildContext context, DisplayState state) {
    final rich = controller.rich;
    final showRich =
        state == DisplayState.speaking || state == DisplayState.idle;
    if (rich == null || !showRich) {
      return null;
    }
    return Center(
      child: RichCard(
        key: ValueKey(rich),
        content: rich,
        onSave: controller.saveRich,
        onClose: controller.dismissRich,
        quizPick: controller.quizPick,
        onQuizPick: controller.pickQuiz,
      ),
    );
  }

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
