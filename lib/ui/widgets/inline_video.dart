import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../core/media/rich_content.dart';
import '../strings.dart';
import '../theme/app_theme.dart';

/// YouTube player embedded in the card; the kiosk never leaves the app.
/// Mounted only after the user taps play, so it starts right away.
class InlineVideo extends StatefulWidget {
  const InlineVideo({super.key, required this.video});

  final YouTubeVideo video;

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  late final YoutubePlayerController _controller = YoutubePlayerController(
    initialVideoId: widget.video.id,
    flags: const YoutubePlayerFlags(enableCaption: true),
  );

  /// Continues in a full-screen route, then resumes here where it left off.
  Future<void> _openFullScreen() async {
    _controller.pause();
    final position = await Navigator.of(context).push<Duration>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenVideo(
          video: widget.video,
          startAt: _controller.value.position,
        ),
      ),
    );
    if (!mounted || position == null) {
      return;
    }
    _controller
      ..seekTo(position)
      ..play();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _player(
      _controller,
      icon: Icons.fullscreen_rounded,
      tooltip: AppStrings.tipFullScreen,
      onToggle: _openFullScreen,
    );
  }
}

class _FullScreenVideo extends StatefulWidget {
  const _FullScreenVideo({required this.video, required this.startAt});

  final YouTubeVideo video;
  final Duration startAt;

  @override
  State<_FullScreenVideo> createState() => _FullScreenVideoState();
}

class _FullScreenVideoState extends State<_FullScreenVideo> {
  late final YoutubePlayerController _controller = YoutubePlayerController(
    initialVideoId: widget.video.id,
    flags: YoutubePlayerFlags(
      enableCaption: true,
      startAt: widget.startAt.inSeconds,
    ),
  );

  void _close() => Navigator.of(context).pop(_controller.value.position);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.scrim,
      body: Center(
        child: _player(
          _controller,
          icon: Icons.fullscreen_exit_rounded,
          tooltip: AppStrings.tipExitFullScreen,
          onToggle: _close,
        ),
      ),
    );
  }
}

Widget _player(
  YoutubePlayerController controller, {
  required IconData icon,
  required String tooltip,
  required VoidCallback onToggle,
}) {
  return YoutubePlayer(
    controller: controller,
    progressIndicatorColor: AppPalette.accentWarm,
    bottomActions: [
      const CurrentPosition(),
      const SizedBox(width: Spacing.sm),
      ProgressBar(
        isExpanded: true,
        colors: const ProgressBarColors(
          playedColor: AppPalette.accentWarm,
          handleColor: AppPalette.accentWarm,
        ),
      ),
      const RemainingDuration(),
      IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: AppPalette.text),
        onPressed: onToggle,
      ),
    ],
  );
}
