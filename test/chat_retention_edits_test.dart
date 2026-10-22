import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_scroll_fixture.dart';
import 'support/chat_shell.dart';

void main() {
  testWidgets('offscreen cooked edits preserve FIFO retention order', (
    tester,
  ) async {
    final fixture = await _RetentionFixture.open(tester);
    try {
      final rows = fixture.newestRows(4);
      await fixture.scrollUntilRetained(rows.values);
      final ordinary = fixture.tiles.values.toSet().difference(
        rows.values.toSet(),
      );
      expect(ordinary, isNotEmpty);

      fixture.edit(rows.keys.first, '<p>An ordinary cooked-only edit.</p>');
      await fixture.frames();
      for (final id in rows.keys) {
        fixture.edit(id, _largeHtml(id));
        await fixture.frames();
      }

      expect(rows.values.first.mounted, isFalse);
      for (final row in rows.values.skip(1)) {
        expect(row.mounted, isTrue);
        expect(_isRetained(row), isTrue);
      }
      for (final row in ordinary) {
        expect(row.mounted, isTrue);
      }
      fixture.edit(rows.keys.first, '<p>A later edit to the evicted row.</p>');
      await fixture.frames();
      expect(rows.values.first.mounted, isFalse);
      expect(fixture.tiles.containsKey(rows.keys.first), isFalse);
    } finally {
      await fixture.close();
    }
  });

  testWidgets('an oversized visible row cannot readmit itself after an edit', (
    tester,
  ) async {
    final fixture = await _RetentionFixture.open(tester);
    try {
      final rows = fixture.newestRows(4);
      final oversized = rows.values.first;
      final id = rows.keys.first;
      fixture.edit(id, '<p title="${'x' * (256 * 1024)}">Oversized body.</p>');
      await fixture.frames();
      expect(oversized.mounted, isTrue);
      expect(_isRetained(oversized), isFalse);

      fixture.edit(id, '<p>Ordinary again while still visible.</p>');
      await fixture.frames();
      await fixture.scrollUntilRetained(rows.values.skip(1));
      expect(oversized.mounted, isFalse);
      for (final row in rows.values.skip(1)) {
        expect(row.mounted, isTrue);
        expect(_isRetained(row), isTrue);
      }
    } finally {
      await fixture.close();
    }
  });

  testWidgets('a collapsed deleted run retains no giant body content', (
    tester,
  ) async {
    final fixture = await _RetentionFixture.open(tester, deletedRun: true);
    try {
      final label = find.text('4 messages were deleted. [view all]');
      expect(label, findsOneWidget);
      final collapsed = tester.element(label);
      expect(fixture.tiles.keys.where((id) => id >= 97), isEmpty);
      await fixture.scrollUntilRetained([collapsed]);
      expect(collapsed.mounted, isTrue);
      expect(_isRetained(collapsed), isTrue);
    } finally {
      await fixture.close();
    }
  });

  testWidgets(
    'a non-first deleted body edit releases its entire expanded row',
    (tester) async {
      final fixture = await _RetentionFixture.open(
        tester,
        deletedRun: true,
        ordinaryDeletedId: 99,
      );
      try {
        await tester.tap(find.text('4 messages were deleted. [view all]'));
        await fixture.frames();
        final deleted = {
          for (final id in [97, 98, 99, 100]) id: fixture.tiles[id]!,
        };
        await fixture.scrollUntilRetained(deleted.values);
        fixture.edit(99, _largeHtml(99));
        await fixture.frames();
        for (final row in deleted.values) {
          expect(row.mounted, isFalse);
        }
        expect(fixture.tiles.keys.where((id) => id >= 97), isEmpty);
      } finally {
        await fixture.close();
      }
    },
  );
}

String _largeHtml(int id) {
  final html =
      '<p>Message $id <span data-details="${'x' * 4500}">'
      '${List.filled(250, '<strong><em>x</em></strong>').join()}'
      '</span></p>';
  expect(CookedHtml.buildsAsynchronously(html), isTrue);
  return html;
}

bool _isRetained(Element element) {
  RenderObject? render = element.renderObject;
  while (render != null &&
      render.parentData is! SliverMultiBoxAdaptorParentData) {
    render = render.parent;
  }
  expect(render, isNotNull);
  return (render!.parentData! as SliverMultiBoxAdaptorParentData).keptAlive;
}

class _RetentionFixture {
  _RetentionFixture(this.tester, this.controller);

  final WidgetTester tester;
  final ShellController controller;

  static Future<_RetentionFixture> open(
    WidgetTester tester, {
    bool deletedRun = false,
    int? ordinaryDeletedId,
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController(
      count: 100,
      configureApi: (api) {
        final page = api.chatMessagesByKey['9']!;
        api.chatMessagesByKey['9'] = (
          messages: [
            for (final message in page.messages)
              ChatMessage(
                id: message.id,
                channelId: 9,
                cooked:
                    deletedRun &&
                        message.id >= 97 &&
                        message.id != ordinaryDeletedId
                    ? _largeHtml(message.id)
                    : '<p>Message ${message.id}: an ordinary reply.</p>',
                author: message.author,
                createdAt: DateTime.utc(2026, 8, 1, 12, message.id),
                deletedAt: deletedRun && message.id >= 97
                    ? DateTime.utc(2026, 8, 2)
                    : null,
              ),
          ],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
          targetMessageId: null,
        );
      },
    );
    addTearDown(controller.dispose);

    final fixture = _RetentionFixture(tester, controller);
    await tester.pumpWidget(ChatScrollFixture(controller: controller));
    await fixture.frames();
    final scrollable = find.descendant(
      of: find.byType(ChatMessageStream),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
      ),
    );
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await fixture.frames();
    return fixture;
  }

  Map<int, Element> get tiles => {
    for (final element
        in find.byType(ChatMessageTile, skipOffstage: false).evaluate())
      (element.widget as ChatMessageTile).messageId: element,
  };

  Map<int, Element> newestRows(int count) {
    final mounted = tiles;
    final ids = mounted.keys.toList()..sort((a, b) => b.compareTo(a));
    expect(ids.length, greaterThanOrEqualTo(count));
    return {for (final id in ids.take(count)) id: mounted[id]!};
  }

  Future<void> frames() async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find
              .byType(CircularProgressIndicator, skipOffstage: false)
              .evaluate()
              .isEmpty &&
          !tester.binding.hasScheduledFrame) {
        return;
      }
    }
    fail('Chat bodies did not finish rendering.');
  }

  Future<void> scrollUntilRetained(Iterable<Element> rows) async {
    final scrollable = find.descendant(
      of: find.byType(ChatMessageStream),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
      ),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    for (var step = 0; step < 20; step++) {
      if (rows.every((row) => row.mounted && _isRetained(row))) return;
      position.pointerScroll(100);
      await frames();
    }
    fail(
      'Expected the original rows to remain mounted in the offscreen cache.',
    );
  }

  void edit(int id, String html) {
    final chat = controller.pluginSession.require(chatControllerService);
    final message = chat.messageRef(chatScrollSite, id).value!;
    controller.chatRecords.put(
      chatScrollSite,
      message.withContentOf(
        ChatMessage(id: id, channelId: 9, cooked: html, author: message.author),
      ),
    );
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
  }
}
