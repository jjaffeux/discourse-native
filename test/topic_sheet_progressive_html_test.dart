import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_post_list.dart';
import 'support/topic_sheet_scroll_fixture.dart';

void main() {
  testWidgets('mobile topic sheet pauses a retained long post until return', (
    tester,
  ) async {
    const channel = MethodChannel('org.discourse.native/notification_opens');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = await pumpTopicSheetScrollFixture(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    expect(find.byType(DSheetViewport), findsOneWidget);
    controller.store.update<Post>(
      controller.currentInstance!.url,
      20,
      (post) => post.copyWith(
        cooked: [
          for (var i = 0; i < 450; i++) '<p>Sheet paragraph $i.</p>',
        ].join(),
      ),
    );
    final list = topicPostList(tester);
    void jump(int index) => list.listController!.jumpToItem(
      index: index,
      scrollController: list.controller!,
      alignment: 0,
    );
    final paragraphs = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().startsWith('Sheet paragraph '),
      skipOffstage: false,
    );
    jump(38);
    await _until(tester, () => paragraphs.evaluate().isNotEmpty);
    final first = tester.element(paragraphs.first);
    expect(paragraphs.evaluate().length, inExclusiveRange(0, 450));
    jump(80);
    final retainedBody = find.byWidgetPredicate(
      (widget) => widget is CookedHtml && widget.post?.id == 20,
      skipOffstage: false,
    );
    await _until(
      tester,
      () => !TickerMode.getValuesNotifier(
        tester.element(retainedBody),
      ).value.enabled,
    );
    final target = find.byKey(const ValueKey(41));
    expect(target, findsOneWidget);
    final top = tester.getTopLeft(target).dy;
    final paused = paragraphs.evaluate().length;
    expect(paused, inExclusiveRange(0, 450));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(paragraphs.evaluate().length, paused);
      expect(tester.getTopLeft(target).dy, closeTo(top, 1));
    }
    jump(38);
    await tester.pumpAndSettle();
    expect(paragraphs, findsNWidgets(450));
    expect(tester.element(paragraphs.first), same(first));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 100 && !ready(); frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue);
}
