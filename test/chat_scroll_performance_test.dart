import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/shell/stream_day_separator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_scroll_fixture.dart';
import 'support/chat_shell.dart';
import 'support/topic_scroll_capture.dart';

void main() {
  final layouts = ValueVariant({
    for (final directMessage in [false, true])
      for (final group in directMessage ? [false, true] : [false])
        for (final layout in [
          (width: 800.0, dark: false),
          (width: 360.0, dark: true),
        ])
          (
            width: layout.width,
            dark: layout.dark,
            directMessage: directMessage,
            group: group,
          ),
  });
  testWidgets('scrolling updates chat chrome without rebuilding held messages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController(
      directMessage: layouts.currentValue!.directMessage,
      group: layouts.currentValue!.group,
    );
    final capture = topicScrollCaptureWithoutVm();
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
      topicScrollCapture: capture,
    );
    addTearDown(controller.dispose);
    addTearDown(diagnostics.close);
    await tester.pumpWidget(
      ChatScrollFixture(
        controller: controller,
        diagnostics: diagnostics,
        width: layouts.currentValue!.width,
        dark: layouts.currentValue!.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(DBubble),
      layouts.currentValue!.directMessage ? findsWidgets : findsNothing,
    );
    final scrollable = find.descendant(
      of: find.byType(ChatMessageStream),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
      ),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    final viewport = tester.getRect(scrollable);
    final rebuiltMessages = <Element>[];
    final seenMessages = find.byType(ChatMessageTile).evaluate().toSet();
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is ChatMessageTile && !seenMessages.add(element)) {
        rebuiltMessages.add(element);
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    try {
      for (var step = 0; step < 20; step++) {
        position.pointerScroll(10);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(capture.events, isEmpty);
      expect(rebuiltMessages, isEmpty);
      capture.start();
      for (final (delta, steps) in [(10.0, 360), (1200.0, 12), (-1200.0, 12)]) {
        for (var step = 0; step < steps; step++) {
          final before = rebuiltMessages.length;
          final beforeEvents = delta.abs() > 10 ? capture.events.length : 0;
          position.pointerScroll(delta);
          await tester.pump(const Duration(milliseconds: 16));
          // Fast jumps can detach and reactivate an edge row as the virtualizer
          // corrects estimated heights. Steady scrolling retains every row.
          expect(
            rebuiltMessages.length - before,
            lessThanOrEqualTo(delta.abs() > 10 ? 2 : 0),
          );
          if (delta.abs() > 10) {
            final visibleMessages = find
                .byType(ChatMessageTile)
                .evaluate()
                .where(
                  (element) => tester
                      .getRect(
                        find.byElementPredicate(
                          (candidate) => candidate == element,
                        ),
                      )
                      .overlaps(viewport),
                )
                .length;
            final builtRows = capture.events
                .skip(beforeEvents)
                .where((event) => event.name == 'chat.row.built')
                .length;
            // Allow date separators and an estimated edge, without constructing
            // another screen of rich messages outside the viewport.
            expect(builtRows, lessThanOrEqualTo(visibleMessages + 3));
          }
        }
      }
      await tester.pumpAndSettle();
      capture.stop();
      final counts = <String, int>{};
      for (final event in capture.events) {
        counts.update(event.name, (count) => count + 1, ifAbsent: () => 1);
      }
      // Useful for comparing the instrumented baseline with the fix.
      debugPrint(
        'CHAT_SCROLL_COUNTS ${jsonEncode({...counts, 'messageRebuilds': rebuiltMessages.length})}',
      );
      expect(find.byType(StreamDaySeparator), findsWidgets);
      expect(counts['chat.floatingDay.changed'], greaterThan(0));
      expect(counts['chat.capture.context'], 1);
      expect(counts['chat.scroll.notification'], greaterThan(0));
      expect(counts['chat.stream.built'] ?? 0, 0);
      expect(counts['chat.row.layout'], greaterThan(0));
      // Moving already measured rows must reuse the floating-date prefix sums.
      expect(counts['chat.dayExtents.scanned'] ?? 0, lessThan(100));
      final context = capture.events.singleWhere(
        (event) => event.name == 'chat.capture.context',
      );
      expect(
        context.data['directMessage'],
        layouts.currentValue!.directMessage,
      );
      expect(context.data['group'], layouts.currentValue!.group);
      expect(tester.takeException(), isNull);
    } finally {
      capture.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await diagnostics.close();
    }
  }, variant: layouts);

  testWidgets('date extents refresh after a visible edit and viewport resize', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController(
      count: 16,
      directMessage: true,
    );
    final capture = topicScrollCaptureWithoutVm();
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
      topicScrollCapture: capture,
    );
    addTearDown(controller.dispose);
    addTearDown(diagnostics.close);
    Future<void> mount(double width) async {
      await tester.pumpWidget(
        ChatScrollFixture(
          controller: controller,
          diagnostics: diagnostics,
          width: width,
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount(800);
    final firstDay = ValueKey(('chat-floating-day', DateTime(2026, 8, 1)));
    final secondDay = ValueKey(('chat-floating-day', DateTime(2026, 8, 2)));
    expect(find.byKey(firstDay), findsOneWidget);
    capture.start();
    final original = controller.chat.messageRef(chatScrollSite, 16).value!;
    controller.chatRecords.put(
      chatScrollSite,
      ChatMessage(
        id: original.id,
        channelId: original.channelId,
        author: original.author,
        createdAt: original.createdAt,
        cooked:
            '<p>${List.filled(200, 'A much longer edited message.').join(' ')}</p>',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(secondDay), findsOneWidget);
    expect(
      capture.events.where((event) => event.name == 'chat.dayExtents.scanned'),
      isNotEmpty,
    );
    capture.start();
    await mount(360);
    expect(find.byKey(secondDay), findsOneWidget);
    expect(
      capture.events.where((event) => event.name == 'chat.dayExtents.scanned'),
      isNotEmpty,
    );
    expect(tester.takeException(), isNull);
    capture.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await diagnostics.close();
  });
}
