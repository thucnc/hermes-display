import 'package:flutter/material.dart';
import '../../core/chat/chat_thread.dart';
import '../../core/state/display_controller.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';

class HistorySheet extends StatefulWidget {
  const HistorySheet({super.key, required this.controller});

  final DisplayController controller;

  static Future<void> show(BuildContext context, DisplayController controller) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HistorySheet(controller: controller),
    );
  }

  @override
  State<HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<HistorySheet> {
  List<ChatThread> _threads = [];
  ChatThread? _selectedThread;
  List<ChatMessage> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  Future<void> _loadThreads() async {
    setState(() => _loading = true);
    final list = await widget.controller.threadService.listThreads(
      memberId: widget.controller.member.id,
    );
    if (!mounted) return;
    setState(() {
      _threads = list;
      _loading = false;
      if (_threads.isNotEmpty && _selectedThread == null) {
        _selectThread(_threads.first);
      }
    });
  }

  Future<void> _selectThread(ChatThread thread) async {
    setState(() => _selectedThread = thread);
    final msgs = await widget.controller.threadService.getMessages(thread.id);
    if (!mounted) return;
    setState(() => _messages = msgs);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height),
      child: GlassSurface(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded, color: AppPalette.accentWarm),
                const SizedBox(width: Spacing.md),
                const Text(
                  'Lịch sử trò chuyện',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await widget.controller.startNewThread();
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.add_comment_rounded),
                  label: const Text('Cuộc trò chuyện mới'),
                ),
                const SizedBox(width: Spacing.sm),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Divider(height: Spacing.xl),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _threads.isEmpty
                      ? const Center(
                          child: Text(
                            'Chưa có cuộc trò chuyện nào',
                            style: TextStyle(color: AppPalette.textMuted),
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 320,
                              child: ListView.separated(
                                itemCount: _threads.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: Spacing.sm),
                                itemBuilder: (context, i) {
                                  final t = _threads[i];
                                  final isSelected = t.id == _selectedThread?.id;
                                  return ListTile(
                                    selected: isSelected,
                                    selectedTileColor:
                                        AppPalette.accent.withValues(alpha: 0.15),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    title: Text(
                                      t.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${t.updatedAt.hour}:${t.updatedAt.minute.toString().padLeft(2, '0')} - ${t.updatedAt.day}/${t.updatedAt.month}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppPalette.textMuted,
                                      ),
                                    ),
                                    onTap: () => _selectThread(t),
                                  );
                                },
                              ),
                            ),
                            const VerticalDivider(width: Spacing.xl),
                            Expanded(child: _buildChatPane()),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatPane() {
    final selected = _selectedThread;
    if (selected == null) {
      return const Center(child: Text('Chọn một cuộc trò chuyện'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                selected.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            FilledButton.icon(
              onPressed: () async {
                await widget.controller.resumeThread(selected);
                if (!mounted) return;
                Navigator.of(context).pop();
                // Start listening immediately
                widget.controller.listen();
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Tiếp tục trò chuyện'),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        Expanded(
          child: _messages.isEmpty
              ? const Center(child: Text('Không có tin nhắn nào'))
              : ListView.separated(
                  reverse: false,
                  itemCount: _messages.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: Spacing.md),
                  itemBuilder: (context, i) {
                    final msg = _messages[i];
                    final isUser = msg.role == 'user';
                    return Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 500),
                        padding: const EdgeInsets.all(Spacing.md),
                        decoration: BoxDecoration(
                          color: isUser
                              ? AppPalette.accent.withValues(alpha: 0.25)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isUser ? 'Bạn' : 'Bé Sen',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isUser
                                    ? AppPalette.accent
                                    : AppPalette.accentWarm,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              msg.text,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
