import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/media_pipeline.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/shell/quote.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/shell/stream_day_separator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'support/chat_scroll_fixture.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/topic_scroll_capture.dart';

void main() {
  testWidgets('hover and scroll suppression do not rebuild message bodies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController();
    addTearDown(controller.dispose);
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
    );
    addTearDown(diagnostics.close);
    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(
        ChatScrollFixture(
          controller: controller,
          diagnostics: diagnostics,
          width: 800,
        ),
      );
      await tester.pumpAndSettle();
      final body = find.byType(CookedHtml).hitTestable().first;
      final bodyElement = tester.element(body);
      final tile = find.ancestor(
        of: body,
        matching: find.byType(ChatMessageTile),
      );
      final id = tester.widget<ChatMessageTile>(tile).messageId;
      final more = find.byKey(ValueKey('chat-message-more-actions-$id'));
      final scrollable = find.descendant(
        of: find.byType(ChatMessageStream),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
        ),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      final rebuilt = <Element>[];
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (identical(element, bodyElement)) rebuilt.add(element);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(body));
      await tester.pumpAndSettle();
      expect(more.hitTestable(), findsOneWidget);
      expect(
        rebuilt,
        isEmpty,
        reason: 'hover only changes the controls and surface',
      );

      position.pointerScroll(10);
      await tester.pumpAndSettle();
      expect(bodyElement.mounted, isTrue);
      expect(more.hitTestable(), findsNothing);
      expect(
        rebuilt,
        isEmpty,
        reason: 'scroll suppression must leave HTML alone',
      );

      // Moving the pointer again restores the controls without reconstructing HTML.
      await mouse.moveTo(tester.getCenter(body) + const Offset(1, 0));
      await tester.pumpAndSettle();
      expect(more.hitTestable(), findsOneWidget);
      expect(rebuilt, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await diagnostics.close();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'recent rich rows survive reversals with bounded retention and live data',
    (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _useStaticImagePlaceholders();
      MediaPipeline.replace(chatScrollMediaPipeline());
      addTearDown(() => MediaPipeline.replace(MediaPipeline()));
      final controller = await chatScrollController(rich: true);
      addTearDown(controller.dispose);
      final diagnostics = DiagnosticsController.start(
        persistence: MemoryDiagnosticsPersistence(),
      );
      addTearDown(diagnostics.close);
      // Close under the fake clock even when the body fails: a close first
      // reached from a tearDown never completes, because it waits on futures
      // created under the fake clock, which nothing drives once the body has
      // returned.
      try {
        await tester.pumpWidget(
          ChatScrollFixture(
            controller: controller,
            diagnostics: diagnostics,
            width: 800,
          ),
        );
        await tester.pumpAndSettle();
        final scrollable = find.descendant(
          of: find.byType(ChatMessageStream),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          ),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        final tiles = find.byType(ChatMessageTile, skipOffstage: false);
        final pill = find.byType(ReactionPill).hitTestable().last;
        final hoveredElement = tester.element(pill);
        final preview = tester
            .widget<DHoverCard>(
              find.descendant(of: pill, matching: find.byType(DHoverCard)),
            )
            .controller!;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(pill));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(preview.isOpen, isTrue);
        for (var step = 0; step < 4; step++) {
          position.pointerScroll(350);
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();
        expect(hoveredElement.mounted, isTrue);
        expect(
          preview.isOpen,
          isFalse,
          reason: 'retaining a row must not strand its hover preview',
        );
        await mouse.removePointer();
        position.jumpTo(0);
        await tester.pumpAndSettle();
        final initial = tiles.evaluate().toSet();
        for (var step = 0; step < 200; step++) {
          position.pointerScroll(120);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        final held = tiles.evaluate().toSet();
        expect(held.length, inInclusiveRange(20, 24));
        expect(
          held.intersection(initial),
          isEmpty,
          reason: 'old rows must be evicted',
        );
        for (var step = 0; step < 60; step++) {
          position.pointerScroll(-40);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        expect(
          tiles.evaluate().toSet(),
          held,
          reason: 'a local reversal reuses the actual elements',
        );

        final tile = tester.widgetList<ChatMessageTile>(tiles).first;
        final chat = controller.pluginSession.require(chatControllerService);
        final message = chat.messageRef(chatScrollSite, tile.messageId).value!;
        controller.chatRecords.put(
          chatScrollSite,
          message.withReactions(const [
            ChatReaction(emoji: 'heart', count: 101),
          ]),
        );
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) => widget is ReactionPill && widget.count == 101,
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        position.pointerScroll(12000);
        await tester.pumpAndSettle();
        expect(
          tiles.evaluate().toSet().intersection(held),
          isEmpty,
          reason: 'long jumps discard the previous retention window',
        );
        expect(tiles.evaluate().length, lessThanOrEqualTo(4));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await diagnostics.close();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a live arrival keeps held rows and their HTML mounted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController();
    addTearDown(controller.dispose);
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
    );
    addTearDown(diagnostics.close);
    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(
        ChatScrollFixture(
          controller: controller,
          diagnostics: diagnostics,
          width: 800,
        ),
      );
      await tester.pumpAndSettle();
      final chat = controller.pluginSession.require(chatControllerService);
      final tiles = find.byType(ChatMessageTile, skipOffstage: false);
      final html = find.byType(HtmlWidget, skipOffstage: false);
      final heldTiles = {
        for (final element in tiles.evaluate())
          element: (element.widget as ChatMessageTile).messageId,
      };
      final heldHtml = html.evaluate().toSet();
      expect(heldTiles.length, greaterThan(2));

      // Inserting the newest row at index zero shifts every held row by one;
      // the arrival must mount only its own row.
      final newestAt = chat.messageRef(chatScrollSite, 500).value!.createdAt!;
      FakeSiteTracker.built
          .lastWhere((tracker) => tracker.siteUrl == chatScrollSite)
          .deliverPluginMessage('/chat/9', {
            'type': 'sent',
            'chat_message': {
              'id': 501,
              'chat_channel_id': 9,
              'cooked': '<p>A live arrival.</p>',
              'created_at': newestAt
                  .add(const Duration(minutes: 1))
                  .toUtc()
                  .toIso8601String(),
              'user': {'id': 2, 'username': 'sam'},
            },
          });
      await tester.pumpAndSettle();

      expect(chat.stream(chatScrollSite, 9).messageIds.last, 501);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ChatMessageTile && widget.messageId == 501,
        ),
        findsOneWidget,
      );
      for (final MapEntry(key: element, value: id) in heldTiles.entries) {
        expect(element.mounted, isTrue, reason: 'message $id was remounted');
      }
      expect(tiles.evaluate().toSet(), containsAll(heldTiles.keys));
      expect(html.evaluate().toSet().difference(heldHtml), hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await diagnostics.close();
    }
  });

  final richLayouts = ValueVariant({
    (width: 800.0, dark: false, directMessage: false),
    (width: 360.0, dark: true, directMessage: false),
    (width: 800.0, dark: false, directMessage: true),
    (width: 360.0, dark: true, directMessage: true),
  });
  testWidgets(
    'rich channel fixture scrolls through images, previews and quotes',
    (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _useStaticImagePlaceholders();
      MediaPipeline.replace(chatScrollMediaPipeline());
      addTearDown(() => MediaPipeline.replace(MediaPipeline()));
      final layout = richLayouts.currentValue!;
      final controller = await chatScrollController(
        rich: true,
        directMessage: layout.directMessage,
      );
      final capture = topicScrollCaptureWithoutVm();
      final diagnostics = DiagnosticsController.start(
        persistence: MemoryDiagnosticsPersistence(),
        topicScrollCapture: capture,
      );
      addTearDown(controller.dispose);
      addTearDown(diagnostics.close);
      // Close under the fake clock even when the body fails: a close first
      // reached from a tearDown never completes, because it waits on futures
      // created under the fake clock, which nothing drives once the body has
      // returned.
      try {
        await tester.pumpWidget(
          ChatScrollFixture(
            controller: controller,
            diagnostics: diagnostics,
            width: layout.width,
            dark: layout.dark,
          ),
        );
        await tester.pumpAndSettle();
        final scrollable = find.descendant(
          of: find.byType(ChatMessageStream),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          ),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        final seen = <Type>{};
        capture.start();
        for (final delta in [40.0, 1200.0, -1200.0]) {
          for (var step = 0; step < 40; step++) {
            for (final type in [SiteImage, OneboxCard, QuoteBlock]) {
              if (find.byType(type).evaluate().isNotEmpty) seen.add(type);
            }
            position.pointerScroll(delta);
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.takeException(), isNull);
          }
        }
        await tester.pumpAndSettle();
        capture.stop();
        final activity = <String, int>{};
        for (final event in capture.events) {
          activity.update(event.name, (count) => count + 1, ifAbsent: () => 1);
        }
        debugPrint('CHAT_RICH_COUNTS ${jsonEncode(activity)}');
        expect(seen, containsAll([SiteImage, OneboxCard, QuoteBlock]));
        expect(
          capture.events.where((event) => event.name == 'chat.stream.built'),
          isEmpty,
        );
      } finally {
        capture.stop();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await diagnostics.close();
      }
    },
    variant: richLayouts,
  );

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
    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(
        ChatScrollFixture(
          controller: controller,
          diagnostics: diagnostics,
          width: layouts.currentValue!.width,
          dark: layouts.currentValue!.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DBubble), findsWidgets);
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

  testWidgets('channel read-state updates do not rebuild held message bodies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController();
    final capture = topicScrollCaptureWithoutVm();
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
      topicScrollCapture: capture,
    );
    addTearDown(controller.dispose);
    addTearDown(diagnostics.close);
    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(
        ChatScrollFixture(controller: controller, diagnostics: diagnostics),
      );
      await tester.pumpAndSettle();
      final held = await _fillRetentionWindow(tester);
      expect(held.length, greaterThanOrEqualTo(20));
      final chat = controller.pluginSession.require(chatControllerService);
      final channelRef = chat.channelRef(chatScrollSite, 9);
      ChatChannel channel() => channelRef.value!;
      var channelChanges = 0;
      void countChannelChange() => channelChanges++;
      channelRef.addListener(countChannelChange);
      addTearDown(() => channelRef.removeListener(countChannelChange));
      final rebuilt = _recordMessageRebuilds();
      capture.start();

      // The reader's dwell credits the visible edge every half second.
      controller.chatRecords.put(
        chatScrollSite,
        channel()
            .withLastRead(500, caughtUp: true)
            .withLastViewedAt(DateTime.utc(2026, 9, 1)),
      );
      await tester.pumpAndSettle();
      controller.chatRecords.put(
        chatScrollSite,
        channel().withMembershipsCount(channel().membershipsCount + 1),
      );
      await tester.pumpAndSettle();
      // A delayed aggregate still restoring unread after that credit makes
      // the stream recheck its visible edge, which clears the stale count.
      controller.chatRecords.put(
        chatScrollSite,
        channel().withTrackingState(
          tracking: const ChatTracking(unreadCount: 1),
        ),
      );
      await tester.pumpAndSettle();
      capture.stop();

      expect(channelChanges, greaterThanOrEqualTo(3));
      expect(channel().tracking.unreadCount, 0);
      expect(rebuilt, isEmpty);
      expect(find.byType(CookedHtml, skipOffstage: false).evaluate().toSet(), {
        ...held,
      });
      expect(
        capture.events.where((event) => event.name == 'chat.stream.built'),
        isEmpty,
      );
    } finally {
      capture.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await diagnostics.close();
    }
  });

  testWidgets('a forum totals change does not rebuild held message bodies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController();
    addTearDown(controller.dispose);
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
    );
    addTearDown(diagnostics.close);
    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(
        ChatScrollFixture(controller: controller, diagnostics: diagnostics),
      );
      await tester.pumpAndSettle();
      final held = await _fillRetentionWindow(tester);
      final shell = controller.pluginSession.require(chatShellService);
      var shellChanges = 0;
      void countShellChange() => shellChanges++;
      shell.addListener(countShellChange);
      addTearDown(() => shell.removeListener(countShellChange));
      final rebuilt = _recordMessageRebuilds();

      FakeSiteTracker.built
          .lastWhere((tracker) => tracker.siteUrl == chatScrollSite)
          .deliverNotification(const {'all_unread_notifications_count': 3});
      // New totals reach Chat with the shell's next notification, whatever
      // that notification was for.
      controller.notifyListeners();
      await tester.pumpAndSettle();

      expect(shellChanges, 1);
      expect(rebuilt, isEmpty);
      expect(find.byType(CookedHtml, skipOffstage: false).evaluate().toSet(), {
        ...held,
      });
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await diagnostics.close();
    }
  });

  testWidgets('account changes rows do not read keep held message bodies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const reader = DiscourseUser(id: 1, username: 'reader1');
    final controller = await chatScrollController(reader: reader);
    addTearDown(controller.dispose);
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
    );
    addTearDown(diagnostics.close);
    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(
        ChatScrollFixture(controller: controller, diagnostics: diagnostics),
      );
      await tester.pumpAndSettle();
      final held = await _fillRetentionWindow(tester);
      final shell = controller.pluginSession.require(chatShellService);
      var shellChanges = 0;
      void countShellChange() => shellChanges++;
      shell.addListener(countShellChange);
      addTearDown(() => shell.removeListener(countShellChange));
      final tracker = FakeSiteTracker.built.lastWhere(
        (tracker) => tracker.siteUrl == chatScrollSite,
      );
      final rebuilt = _recordMessageRebuilds();

      // Each replaces the account record the rows' permission checks read.
      tracker.deliverPluginMessage('/user-drafts/1', const {'draft_count': 4});
      await tester.pumpAndSettle();
      tracker.deliverPluginMessage('/user-status', const {
        '1': {'description': 'In a meeting', 'emoji': 'calendar'},
      });
      await tester.pumpAndSettle();

      expect(shell.currentUser?.draftCount, 4);
      expect(shell.currentUser?.status?.description, 'In a meeting');
      expect(shellChanges, 2);
      expect(rebuilt, isEmpty);
      expect(find.byType(CookedHtml, skipOffstage: false).evaluate().toSet(), {
        ...held,
      });
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await diagnostics.close();
    }
  });

  testWidgets('an account change rows read updates held message actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sessionUser = Completer<DiscourseUser>();
    final controller = await chatScrollController(
      reader: const DiscourseUser(id: 1, username: 'reader1'),
      sessionUser: sessionUser,
    );
    addTearDown(controller.dispose);
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
    );
    addTearDown(diagnostics.close);
    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(
        ChatScrollFixture(controller: controller, diagnostics: diagnostics),
      );
      await tester.pumpAndSettle();
      await _fillRetentionWindow(tester);
      final held = [
        for (final tile in tester.widgetList<ChatMessageTile>(
          find.byType(ChatMessageTile, skipOffstage: false),
        ))
          tile.messageId,
      ];
      expect(held.length, greaterThanOrEqualTo(20));
      Set<String?> actionsOf(int id) => {
        for (final semantics in tester.widgetList<Semantics>(
          find.descendant(
            of: find.byKey(ChatMessageTile.actionsKey(id), skipOffstage: false),
            matching: find.byType(Semantics, skipOffstage: false),
          ),
        ))
          ...?semantics.properties.customSemanticsActions?.keys.map(
            (action) => action.label,
          ),
      };
      for (final id in held) {
        expect(actionsOf(id), contains('Reply'));
        expect(actionsOf(id), isNot(contains('Rebuild HTML')));
      }

      // The session refresh finds the stored account is now staff.
      sessionUser.complete(
        const DiscourseUser(id: 1, username: 'reader1', staff: true),
      );
      await tester.pumpAndSettle();

      for (final id in held) {
        expect(actionsOf(id), contains('Rebuild HTML'));
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await diagnostics.close();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a channel permission change updates held message actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const reader = DiscourseUser(id: 1, username: 'reader1');
    final controller = await chatScrollController(reader: reader);
    addTearDown(controller.dispose);
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
    );
    addTearDown(diagnostics.close);
    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(
        ChatScrollFixture(controller: controller, diagnostics: diagnostics),
      );
      await tester.pumpAndSettle();
      await _fillRetentionWindow(tester);
      final chat = controller.pluginSession.require(chatControllerService);
      expect(chat.currentUserFor(chatScrollSite)?.id, reader.id);
      final held = [
        for (final tile in tester.widgetList<ChatMessageTile>(
          find.byType(ChatMessageTile, skipOffstage: false),
        ))
          tile.messageId,
      ];
      expect(held.length, greaterThanOrEqualTo(20));
      final own = held.firstWhere(
        (id) => chat.messageRef(chatScrollSite, id).value!.author.id == 1,
      );
      Finder reply(int id) => find.byKey(
        ValueKey('chat-message-reply-action-$id'),
        skipOffstage: false,
      );
      Finder react(int id) =>
          find.byKey(ValueKey('chat-message-react-$id'), skipOffstage: false);
      Set<String?> actionsOf(int id) => {
        for (final semantics in tester.widgetList<Semantics>(
          find.descendant(
            of: find.byKey(ChatMessageTile.actionsKey(id), skipOffstage: false),
            matching: find.byType(Semantics, skipOffstage: false),
          ),
        ))
          ...?semantics.properties.customSemanticsActions?.keys.map(
            (action) => action.label,
          ),
      };
      final opened = chat.channelRef(chatScrollSite, 9).value!;

      for (final id in held) {
        expect(reply(id), findsOneWidget);
        expect(react(id), findsOneWidget);
      }
      expect(actionsOf(own), isNot(contains('Delete')));

      controller.chatRecords.put(
        chatScrollSite,
        ChatChannel(
          id: opened.id,
          title: opened.title,
          kind: opened.kind,
          canDeleteSelf: true,
          membership: opened.membership,
          tracking: opened.tracking,
        ),
      );
      await tester.pumpAndSettle();
      expect(actionsOf(own), containsAll(['Reply', 'Delete']));

      controller.chatRecords.put(
        chatScrollSite,
        chat
            .channelRef(chatScrollSite, 9)
            .value!
            .withRemoteStatus(ChatChannelStatus.readOnly),
      );
      await tester.pumpAndSettle();
      for (final id in held) {
        expect(reply(id), findsNothing);
        expect(react(id), findsNothing);
        expect(actionsOf(id), isNot(contains('Reply')));
      }
      expect(actionsOf(own), isNot(contains('Delete')));

      controller.chatRecords.put(
        chatScrollSite,
        chat
            .channelRef(chatScrollSite, 9)
            .value!
            .withRemoteStatus(ChatChannelStatus.open),
      );
      await tester.pumpAndSettle();
      for (final id in held) {
        expect(reply(id), findsOneWidget);
        expect(react(id), findsOneWidget);
      }
      expect(actionsOf(own), containsAll(['Reply', 'Delete']));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await diagnostics.close();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final paginated in [false, true]) {
    testWidgets('floating date jumps to day start (paginated: $paginated)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = await chatScrollController(
        count: paginated ? 120 : 48,
        configureApi: (api) {
          if (!paginated) return;
          final page = api.chatMessagesByKey['9']!;
          final messages = page.messages
              .map(
                (message) => ChatMessage(
                  id: message.id,
                  channelId: message.channelId,
                  author: message.author,
                  cooked: message.cooked,
                  createdAt: DateTime(2026, 8, 1, 0, message.id),
                ),
              )
              .toList();
          api.chatMessagesByKey['9'] = (
            messages: messages.where((message) => message.id >= 31).toList(),
            canLoadMorePast: true,
            canLoadMoreFuture: false,
            targetMessageId: null,
          );
          api.chatMessagesByKey[FakeDiscourseApi.chatMessagesKey(
            9,
            before: 31,
          )] = (
            messages: messages.where((message) => message.id < 31).toList(),
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          );
        },
      );
      addTearDown(controller.dispose);
      final diagnostics = DiagnosticsController.start(
        persistence: MemoryDiagnosticsPersistence(),
      );
      addTearDown(diagnostics.close);
      // Close under the fake clock even when the body fails: a close first
      // reached from a tearDown never completes, because it waits on futures
      // created under the fake clock, which nothing drives once the body has
      // returned.
      try {
        await tester.pumpWidget(
          ChatScrollFixture(controller: controller, diagnostics: diagnostics),
        );
        await tester.pumpAndSettle();

        final floating = find.byWidgetPredicate(
          (widget) => widget is StreamDaySeparator && widget.floating,
        );
        final day = tester.widget<StreamDaySeparator>(floating).day;
        final firstId = 1 + day.difference(DateTime(2026, 8, 1)).inDays * 12;
        final firstMessage = find.byWidgetPredicate(
          (widget) => widget is ChatMessageTile && widget.messageId == firstId,
        );
        expect(firstMessage.hitTestable(), findsNothing);
        if (paginated) {
          expect(
            tester
                .widget<ChatMessageStream>(find.byType(ChatMessageStream))
                .stream
                .canLoadMorePast,
            isTrue,
          );
        }
        await tester.tap(floating);
        await tester.pumpAndSettle();

        expect(firstMessage.hitTestable(), findsOneWidget);
        final viewport = tester.getRect(find.byType(ChatMessageStream));
        expect(
          tester.getTopLeft(find.byKey(ValueKey(('chat-day', day)))).dy,
          closeTo(viewport.top, 1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await diagnostics.close();
      }
    });
  }

  testWidgets('date extents refresh after a visible edit and viewport resize', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController(
      count: 14,
      directMessage: true,
    );
    final capture = topicScrollCaptureWithoutVm();
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
      topicScrollCapture: capture,
    );
    addTearDown(controller.dispose);
    addTearDown(diagnostics.close);
    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
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
      final original = controller.chat.messageRef(chatScrollSite, 14).value!;
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
        capture.events.where(
          (event) => event.name == 'chat.dayExtents.scanned',
        ),
        isNotEmpty,
      );
      capture.start();
      await mount(360);
      expect(find.byKey(secondDay), findsOneWidget);
      expect(
        capture.events.where(
          (event) => event.name == 'chat.dayExtents.scanned',
        ),
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    } finally {
      capture.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await diagnostics.close();
    }
  });
}

/// Scrolls outward and back so the retention window holds rows beyond the
/// viewport, lets the landing edge's read dwell complete, and answers the
/// message bodies it holds.
Future<Set<Element>> _fillRetentionWindow(WidgetTester tester) async {
  final scrollable = find.descendant(
    of: find.byType(ChatMessageStream),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
    ),
  );
  final position = tester.state<ScrollableState>(scrollable).position;
  for (final delta in [60.0, -60.0]) {
    for (var step = 0; step < 30; step++) {
      position.pointerScroll(delta);
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  return find.byType(CookedHtml, skipOffstage: false).evaluate().toSet();
}

/// Message tiles and bodies whose elements build from now on, whether
/// rebuilt in place or mounted afresh.
List<Element> _recordMessageRebuilds() {
  final rebuilt = <Element>[];
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    if (element.widget is ChatMessageTile || element.widget is CookedHtml) {
      rebuilt.add(element);
    }
  };
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  return rebuilt;
}

/// Draws the HTML package's static loading placeholder instead of its spinner
/// for the rest of the test.
///
/// `SiteImage` keeps its loading builder until an image's first frame is
/// decoded, and an engine decode only completes on the real event loop, which
/// a body under the fake clock never yields to. The spinner would animate for
/// as long as the test runs, so `pumpAndSettle` could never return. Each image
/// still reserves its final geometry.
void _useStaticImagePlaceholders() {
  final previous = WidgetFactory.debugDeterministicLoadingWidget;
  WidgetFactory.debugDeterministicLoadingWidget = true;
  addTearDown(() => WidgetFactory.debugDeterministicLoadingWidget = previous);
}
