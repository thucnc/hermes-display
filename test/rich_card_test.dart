import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/media/rich_content.dart';
import 'package:hermes_display/services/hermes_sync_service.dart';
import 'package:hermes_display/ui/strings.dart';
import 'package:hermes_display/ui/widgets/rich_card.dart';

void main() {
  const reply = '''Trứng chiên:
1. Đập trứng.
2. Chiên vàng.
[Trứng chiên ngon](https://youtu.be/abcdefghijk)''';
  final content = RichContent.parse(question: 'trứng chiên', reply: reply)!;

  Future<void> pump(
    WidgetTester tester, {
    required RichContent rich,
    SaveResult result = SaveResult.saved,
    List<int>? saves,
    List<int>? closes,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RichCard(
              content: rich,
              playerBuilder: (video) => Text('player:${video.id}'),
              onSave: () async {
                saves?.add(1);
                return result;
              },
              onClose: () => closes?.add(1),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('video card, numbered steps and inline play', (tester) async {
    await pump(tester, rich: content);
    expect(find.text('Trứng chiên ngon'), findsOneWidget);
    expect(find.text('Đập trứng.'), findsOneWidget);
    expect(find.text('Chiên vàng.'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    expect(find.text('player:abcdefghijk'), findsNothing);

    await tester.tap(find.text(AppStrings.playVideo));
    await tester.pump();
    expect(find.text('player:abcdefghijk'), findsOneWidget);
    expect(find.text(AppStrings.playVideo), findsNothing);
  });

  testWidgets('save shows a confirmation snackbar', (tester) async {
    final saves = <int>[];
    await pump(tester, rich: content, saves: saves);
    await tester.tap(find.text(AppStrings.saveToHermes));
    await tester.pump();
    await tester.pump();
    expect(saves, hasLength(1));
    expect(find.text(AppStrings.savedToBrain), findsOneWidget);
  });

  testWidgets('failed save says so', (tester) async {
    await pump(tester, rich: content, result: SaveResult.failed);
    await tester.tap(find.text(AppStrings.saveToHermes));
    await tester.pump();
    await tester.pump();
    expect(find.text(AppStrings.saveFailed), findsOneWidget);
  });

  testWidgets('close button and reply without video', (tester) async {
    final closes = <int>[];
    final stepsOnly = RichContent.parse(
      question: 'q',
      reply: '1. Một.\n2. Hai.',
    )!;
    await pump(tester, rich: stepsOnly, closes: closes);
    expect(find.text(AppStrings.playVideo), findsNothing);
    await tester.tap(find.byTooltip(AppStrings.tipClose));
    expect(closes, hasLength(1));
  });
}
