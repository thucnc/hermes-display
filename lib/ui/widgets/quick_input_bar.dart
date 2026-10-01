import 'package:flutter/material.dart';

import '../../core/state/display_controller.dart';
import '../strings.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';

enum _BarMode { collapsed, expanded }

/// Collapsible text entry for silent interaction.
class QuickInputBar extends StatefulWidget {
  const QuickInputBar({super.key, required this.onSubmit, this.onMic});

  final SendResult Function(String text) onSubmit;
  final Future<ListenResult> Function()? onMic;

  @override
  State<QuickInputBar> createState() => _QuickInputBarState();
}

class _QuickInputBarState extends State<QuickInputBar> {
  static const double _expandedWidth = 560;
  static const EdgeInsets _pillPadding = EdgeInsets.symmetric(
    horizontal: Spacing.sm,
  );

  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  _BarMode _mode = _BarMode.collapsed;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setMode(_BarMode mode) {
    setState(() => _mode = mode);
    if (mode == _BarMode.expanded) {
      _focus.requestFocus();
      return;
    }
    _focus.unfocus();
  }

  void _submit() {
    final result = widget.onSubmit(_text.text);
    if (result == SendResult.empty) {
      return;
    }
    if (result == SendResult.offline) {
      _notify(AppStrings.sendOffline);
      return;
    }
    _text.clear();
    _setMode(_BarMode.collapsed);
  }

  Future<void> _mic(Future<ListenResult> Function() onMic) async {
    final result = await onMic();
    if (!mounted) {
      return;
    }
    final message = switch (result) {
      ListenResult.offline => AppStrings.sendOffline,
      ListenResult.noPermission => AppStrings.micDenied,
      ListenResult.micUnavailable => AppStrings.micUnavailable,
      ListenResult.started || ListenResult.busy => null,
    };
    if (message == null) {
      return;
    }
    _notify(message);
  }

  void _notify(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.quick,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          axis: Axis.horizontal,
          axisAlignment: 1,
          fixedCrossAxisSizeFactor: 1,
          child: child,
        ),
      ),
      child: _mode == _BarMode.collapsed ? _collapsed() : _expanded(),
    );
  }

  Widget _collapsed() {
    final onMic = widget.onMic;
    return Row(
      key: const ValueKey(_BarMode.collapsed),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onMic != null) ...[
          _RoundButton(
            icon: Icons.mic_none_rounded,
            tooltip: AppStrings.tipMic,
            onPressed: () => _mic(onMic),
          ),
          const SizedBox(width: Spacing.sm),
        ],
        _RoundButton(
          icon: Icons.keyboard_alt_outlined,
          tooltip: AppStrings.tipKeyboard,
          onPressed: () => _setMode(_BarMode.expanded),
        ),
      ],
    );
  }

  Widget _expanded() {
    return ConstrainedBox(
      key: const ValueKey(_BarMode.expanded),
      constraints: const BoxConstraints(maxWidth: _expandedWidth),
      child: GlassSurface(
        radius: Radii.pill,
        padding: _pillPadding,
        child: Row(
          children: [
            IconButton(
              tooltip: AppStrings.tipClose,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _setMode(_BarMode.collapsed),
            ),
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _focus,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: AppStrings.inputHint,
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              tooltip: AppStrings.tipSend,
              icon: const Icon(Icons.arrow_upward_rounded),
              color: AppPalette.accent,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: Radii.pill,
      padding: EdgeInsets.zero,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}
