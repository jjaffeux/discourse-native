import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/media_pipeline.dart';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/shell/quote.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/shell/stream_day_separator.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'support/chat_scroll_fixture.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('hover and scroll suppression do not rebuild message bodies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController();
    addTearDown(controller.dispose);

    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(
        ChatScrollFixture(controller: controller, width: 800),
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

      // Close under the fake clock even when the body fails: a close first
      // reached from a tearDown never completes, because it waits on futures
      // created under the fake clock, which nothing drives once the body has
      // returned.
      try {
        await tester.pumpWidget(
          ChatScrollFixture(controller: controller, width: 800),
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
        await tester.pump(const Duration(milliseconds: 650));
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
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('a live arrival keeps held rows and their HTML mounted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController();
    addTearDown(controller.dispose);

    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(
        ChatScrollFixture(controller: controller, width: 800),
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

      addTearDown(controller.dispose);

      // Close under the fake clock even when the body fails: a close first
      // reached from a tearDown never completes, because it waits on futures
      // created under the fake clock, which nothing drives once the body has
      // returned.
      try {
        await tester.pumpWidget(
          ChatScrollFixture(
            controller: controller,

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

        expect(seen, containsAll([SiteImage, OneboxCard, QuoteBlock]));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
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

    addTearDown(controller.dispose);

    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(
        ChatScrollFixture(
          controller: controller,

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

      expect(rebuiltMessages, isEmpty);

      for (final (delta, steps) in [(10.0, 360), (1200.0, 12), (-1200.0, 12)]) {
        for (var step = 0; step < steps; step++) {
          final before = rebuiltMessages.length;

          position.pointerScroll(delta);
          await tester.pump(const Duration(milliseconds: 16));
          // Fast jumps can detach and reactivate an edge row as the virtualizer
          // corrects estimated heights. Steady scrolling retains every row.
          expect(
            rebuiltMessages.length - before,
            lessThanOrEqualTo(delta.abs() > 10 ? 2 : 0),
          );
        }
      }
      await tester.pumpAndSettle();

      expect(find.byType(StreamDaySeparator), findsWidgets);

      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  }, variant: layouts);

  testWidgets('channel read-state updates do not rebuild held message bodies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController();

    addTearDown(controller.dispose);

    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(ChatScrollFixture(controller: controller));
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

      expect(channelChanges, greaterThanOrEqualTo(3));
      expect(channel().tracking.unreadCount, 0);
      expect(rebuilt, isEmpty);
      expect(find.byType(CookedHtml, skipOffstage: false).evaluate().toSet(), {
        ...held,
      });
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
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

    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(ChatScrollFixture(controller: controller));
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

    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(ChatScrollFixture(controller: controller));
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

    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(ChatScrollFixture(controller: controller));
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

    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      await tester.pumpWidget(ChatScrollFixture(controller: controller));
      await tester.pumpAndSettle();
      await _fillRetentionWindow(tester);
      final chat = controller.pluginSession.require(chatControllerService);
      expect(chat.currentUserFor(chatScrollSite)?.id, reader.id);
      final tiles = find.byType(ChatMessageTile, skipOffstage: false);
      Map<int, Element> heldTiles() => {
        for (final element in tiles.evaluate())
          (element.widget as ChatMessageTile).messageId: element,
      };
      final held = heldTiles();
      expect(held.length, greaterThanOrEqualTo(20));
      final own = held.keys.firstWhere(
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

      void expectHeldActions({required bool writable}) {
        final current = heldTiles();
        // Permission changes resize the action slots and composer, so an edge
        // row may leave the bounded cache. The rows that remain must update in
        // place, including those outside the viewport.
        final retained = current.keys.toSet().intersection(held.keys.toSet());
        expect(retained.length, greaterThanOrEqualTo(20));
        expect(retained, contains(own));
        for (final id in retained) {
          expect(current[id], same(held[id]));
        }
        for (final id in current.keys) {
          expect(reply(id), writable ? findsOneWidget : findsNothing);
          expect(react(id), writable ? findsOneWidget : findsNothing);
          expect(
            actionsOf(id),
            writable ? contains('Reply') : isNot(contains('Reply')),
          );
        }
      }

      expectHeldActions(writable: true);
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
      expectHeldActions(writable: false);
      expect(actionsOf(own), isNot(contains('Delete')));

      controller.chatRecords.put(
        chatScrollSite,
        chat
            .channelRef(chatScrollSite, 9)
            .value!
            .withRemoteStatus(ChatChannelStatus.open),
      );
      await tester.pumpAndSettle();
      expectHeldActions(writable: true);
      expect(actionsOf(own), containsAll(['Reply', 'Delete']));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
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

      // Close under the fake clock even when the body fails: a close first
      // reached from a tearDown never completes, because it waits on futures
      // created under the fake clock, which nothing drives once the body has
      // returned.
      try {
        await tester.pumpWidget(ChatScrollFixture(controller: controller));
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
      }
    });
  }

  testWidgets('floating dates follow row rekeys, arrivals, and loading rows', (
    tester,
  ) async {
    final controller = await chatScrollController(count: 48);
    addTearDown(controller.dispose);
    var messages = [
      for (var id = 1; id <= 48; id++)
        controller.chat.messageRef(chatScrollSite, id).value!,
    ];
    var items = buildChatStream(messages);
    Future<void> mount({bool loadingNewer = false}) async {
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: PluginUiScope.own(
            chatPluginId,
            MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: SizedBox(
                  width: 700.25,
                  height: 500.75,
                  child: ChatMessageStream(
                    siteUrl: chatScrollSite,
                    target: const ChatChannelTarget(9),
                    items: items,
                    stream: ChatStreamState(
                      messageIds: [for (final message in messages) message.id],
                      fetchedOnce: true,
                      fetches: 1,
                      loadingNewer: loadingNewer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (loadingNewer) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
      } else {
        await tester.pumpAndSettle();
      }
      _expectChatFloatingMatchesFullScan(tester);
    }

    await mount();
    final previousLength = items.length;
    messages = [
      for (final message in messages)
        ChatMessage(
          id: message.id + 1000,
          channelId: message.channelId,
          author: message.author,
          cooked: '<p>Replacement ${message.id}</p>',
          createdAt: message.createdAt,
        ),
    ];
    controller.chatRecords.putAll(chatScrollSite, messages);
    items = buildChatStream(messages);
    expect(items.length, previousLength);
    await mount();
    await mount(loadingNewer: true);
    await mount();

    messages = [
      ...messages,
      ChatMessage(
        id: 1049,
        channelId: 9,
        author: messages.last.author,
        cooked: '<p>A newest row with a different day.</p>',
        createdAt: DateTime(2026, 8, 5),
      ),
    ];
    controller.chatRecords.put(chatScrollSite, messages.last);
    items = buildChatStream(messages);
    await mount();
    final list = tester.widget<DMessageScrollerViewport>(
      find.byType(DMessageScrollerViewport),
    );
    for (var step = 0; step < 30; step++) {
      list.scrollController!.position.pointerScroll(17.5);
      await tester.pump();
      await tester.pump();
      _expectChatFloatingMatchesFullScan(tester);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating date motion retains artwork and isolates its paint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController(count: 48);
    addTearDown(controller.dispose);

    try {
      await tester.pumpWidget(ChatScrollFixture(controller: controller));
      await tester.pumpAndSettle();
      final list = tester.widget<DMessageScrollerViewport>(
        find.byType(DMessageScrollerViewport),
      );
      final floating = find.byWidgetPredicate(
        (widget) => widget is StreamDaySeparator && widget.floating,
      );
      var paints = 0;
      final previousPaint = debugOnProfilePaint;
      debugOnProfilePaint = (object) {
        previousPaint?.call(object);
        if (object is! RenderParagraph) return;
        if (object.debugCreator case final DebugCreator creator) {
          creator.element.visitAncestorElements((ancestor) {
            if (ancestor.widget case StreamDaySeparator(:final floating)) {
              if (floating) paints++;
              return false;
            }
            return true;
          });
        }
      };
      var moved = 0;
      var stationary = 0;
      try {
        for (var step = 0; step < 400; step++) {
          final before = tester.widget<StreamDaySeparator>(floating);
          final beforeElement = tester.element(floating);
          final beforeTop = tester.getTopLeft(floating).dy;
          final beforePaints = paints;
          list.scrollController!.position.pointerScroll(4);
          await tester.pump(const Duration(milliseconds: 16));
          await tester.pump();
          _expectChatFloatingMatchesFullScan(tester);
          if (floating.evaluate().isEmpty) continue;
          final after = tester.widget<StreamDaySeparator>(floating);
          if (before.day != after.day) continue;
          final movedThisFrame =
              (tester.getTopLeft(floating).dy - beforeTop).abs() > .1;
          if (movedThisFrame) {
            moved++;
            expect(after, same(before));
            expect(tester.element(floating), same(beforeElement));
          } else {
            stationary++;
            expect(paints, beforePaints);
          }
        }
      } finally {
        debugOnProfilePaint = previousPaint;
      }
      expect(moved, greaterThan(0));
      expect(stationary, greaterThan(0));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

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

    addTearDown(controller.dispose);

    // Close under the fake clock even when the body fails: a close first
    // reached from a tearDown never completes, because it waits on futures
    // created under the fake clock, which nothing drives once the body has
    // returned.
    try {
      Future<void> mount(double width) async {
        await tester.pumpWidget(
          ChatScrollFixture(controller: controller, width: width),
        );
        await tester.pumpAndSettle();
      }

      await mount(800);
      _expectChatFloatingMatchesFullScan(tester);
      final firstDay = ValueKey(('chat-floating-day', DateTime(2026, 8, 1)));
      final secondDay = ValueKey(('chat-floating-day', DateTime(2026, 8, 2)));
      expect(find.byKey(firstDay), findsOneWidget);

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
      _expectChatFloatingMatchesFullScan(tester);

      await mount(360);
      expect(find.byKey(secondDay), findsOneWidget);
      _expectChatFloatingMatchesFullScan(tester);

      tester.platformDispatcher.textScaleFactorTestValue = 1.35;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      _expectChatFloatingMatchesFullScan(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

void _expectChatFloatingMatchesFullScan(WidgetTester tester) {
  final stream = tester.widget<ChatMessageStream>(
    find.byType(ChatMessageStream),
  );
  final header = DPageSurface.headerGeometryOf(
    tester.element(find.byType(ChatMessageStream)),
  );
  final list = tester.widget<DMessageScrollerViewport>(
    find.byType(DMessageScrollerViewport),
  );
  final leading = stream.stream.loadingNewer ? 1 : 0;
  final days = [
    for (var index = 0; index < stream.items.length; index++)
      if (stream.items[index] case ChatStreamDay(:final day))
        (day: day, row: leading + stream.items.length - 1 - index),
  ];
  final sums = <int, double>{};
  var sum = 0.0;
  for (var row = 0; row <= days.first.row; row++) {
    sum += list.listController!.extentForIndex(row).$1;
    sums[row] = sum;
  }
  final position = list.scrollController!.position;
  final fromBottom =
      position.viewportDimension -
      8 -
      (header?.footerExtent ?? 0) +
      position.pixels;
  final headerExtent = header?.visibleExtent ?? 0;
  var candidate = -1;
  for (var index = 0; index < days.length; index++) {
    if (fromBottom - sums[days[index].row]! > headerExtent) break;
    candidate = index;
  }
  final floating = find.byWidgetPredicate(
    (widget) => widget is StreamDaySeparator && widget.floating,
  );
  if (candidate < 0) {
    expect(floating, findsNothing);
    return;
  }
  var offset = 0.0;
  if (candidate + 1 < days.length) {
    final nextTop = fromBottom - sums[days[candidate + 1].row]!;
    if (nextTop < headerExtent + StreamDaySeparator.height) {
      offset = nextTop - headerExtent - StreamDaySeparator.height;
    }
  }
  expect(
    tester.widget<StreamDaySeparator>(floating).day,
    days[candidate].day,
    reason:
        'pixels ${position.pixels}, tops '
        '${[for (final day in days) (day.day, fromBottom - sums[day.row]!)]}',
  );
  final positioned = tester.widget<Positioned>(
    find.ancestor(of: floating, matching: find.byType(Positioned)).first,
  );
  expect(positioned.top, closeTo(offset, .1));
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
