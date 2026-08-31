import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_pin.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/shell/loading_skeleton.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

void main() {
  const firstSite = 'https://one.example';
  const secondSite = 'https://two.example';

  group('window identity, selection, and paging', () {
    testWidgets('the same channel ID anchors independently on each site', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = _ChatApi(
        openPages: {
          firstSite: [_messagesPage(1, 40), _messagesPage(1, 40)],
          secondSite: [
            _messagesPage(1, 40),
            _messagesPage(1, 40),
            _messagesPage(1, 40),
          ],
        },
        gatedOpen: (siteUrl: secondSite, number: 3, gate: gate),
      );
      final controller = await _controller(api);
      addTearDown(controller.dispose);
      controller.chatRecords
        ..put(firstSite, _channel(lastRead: 5))
        ..put(secondSite, _channel(lastRead: 40));

      await controller.chat.openChannel(firstSite, 9);
      await controller.chat.openChannel(secondSite, 9);
      await controller.chat.openChannel(secondSite, 9);
      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pumpAndSettle();

      final scrollable = _verticalChatScroll();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(0),
      );

      controller.selectInstance(1);
      await tester.pump();
      await tester.pump();

      expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);

      gate.complete();
      await tester.pump();
    });

    testWidgets('fill-towards-present state is independent per site', (
      tester,
    ) async {
      final page = _messagesPage(1, 3, canLoadMoreFuture: true);
      final api = _ChatApi(
        openPages: {
          firstSite: [page, page],
          secondSite: [page, page, page],
        },
        failNewer: true,
        failedOpen: (siteUrl: secondSite, number: 3),
      );
      final controller = await _controller(api);
      addTearDown(controller.dispose);
      controller.chatRecords
        ..put(firstSite, _channel(lastRead: 3))
        ..put(secondSite, _channel(lastRead: 3));

      await controller.chat.openChannel(firstSite, 9);
      await controller.chat.openChannel(secondSite, 9);
      await controller.chat.openChannel(secondSite, 9);
      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pumpAndSettle();

      expect(api.newerSites, [firstSite]);

      controller.selectInstance(1);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(api.newerSites, [firstSite, secondSite]);
    });

    testWidgets('a nested code-block scroll does not page the chat stream', (
      tester,
    ) async {
      final messages = [
        for (var id = 1; id <= 80; id++)
          _message(
            id,
            cooked: id == 80
                ? '<pre><code>${List.filled(80, 'long-token').join()}</code></pre>'
                : '<p>Message $id</p>',
          ),
      ];
      final page = (
        messages: messages,
        canLoadMorePast: true,
        canLoadMoreFuture: false,
        targetMessageId: null,
      );
      final api = _ChatApi(
        openPages: {
          firstSite: [page, page],
          secondSite: const [],
        },
      );
      final controller = await _controller(api, sites: const [firstSite]);
      addTearDown(controller.dispose);
      controller.chatRecords.put(firstSite, _channel(lastRead: 80));
      await controller.chat.openChannel(firstSite, 9);

      final depths = <int>[];
      await tester.pumpWidget(
        _TestView(
          controller: controller,
          onScroll: (notification) {
            depths.add(notification.depth);
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(api.olderSites, isEmpty);
      depths.clear();

      final horizontal = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      );
      expect(horizontal, findsOneWidget);
      await tester.drag(horizontal, const Offset(-10000, 0));
      await tester.pump();

      expect(depths, contains(greaterThan(0)));
      expect(api.olderSites, isEmpty);
    });

    testWidgets('selects messages and copies core transcript Markdown', (
      tester,
    ) async {
      final copied = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final api = _ChatApi(
        openPages: {
          firstSite: [_messagesPage(1, 2)],
        },
        chatQuoteMarkdown: '[chat channel="Chat"]\nSelected\n[/chat]',
      );
      final controller = await _controller(api, sites: const [firstSite]);
      addTearDown(controller.dispose);
      controller.chatRecords.put(firstSite, _channel(lastRead: 2));

      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pumpAndSettle();
      await _startSelectingNewestMessage(tester);

      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('chat-message-selector-2')),
            )
            .value,
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('chat-message-selection-bar')),
        findsOne,
      );
      expect(find.byKey(const ValueKey('chat-quote-selection')), findsOne);
      expect(find.text('1 message selected'), findsOne);

      await tester.tap(find.byKey(const ValueKey('chat-message-selector-1')));
      await tester.pump();
      expect(find.text('2 messages selected'), findsOne);
      await tester.tap(find.byKey(const ValueKey('chat-copy-selection')));
      await tester.pumpAndSettle();

      expect(api.chatQuotesGenerated.single.channelId, 9);
      expect(api.chatQuotesGenerated.single.messageIds, [1, 2]);
      expect(copied, ['[chat channel="Chat"]\nSelected\n[/chat]']);
      expect(find.text('Messages copied!'), findsOne);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-cancel-selection')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('chat-message-selection-bar')),
        findsNothing,
      );
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('confirms and bulk-deletes an allowed message selection', (
      tester,
    ) async {
      const user = DiscourseUser(id: 2, username: 'sam');
      final api = _ChatApi(
        user: user,
        openPages: {
          firstSite: [_messagesPage(1, 2)],
        },
      );
      final controller = await _controller(
        api,
        sites: const [firstSite],
        user: user,
      );
      addTearDown(controller.dispose);
      controller.chatRecords.put(
        firstSite,
        _channel(lastRead: 2, canDeleteSelf: true),
      );

      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pumpAndSettle();
      await _startSelectingNewestMessage(tester);
      await tester.tap(find.byKey(const ValueKey('chat-message-selector-1')));
      await tester.pump();

      final deleteButton = find.byKey(const ValueKey('chat-delete-selection'));
      expect(tester.widget<IconButton>(deleteButton).onPressed, isNotNull);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(find.text('Delete selected messages?'), findsOne);
      expect(
        find.text('Are you sure you want to delete 2 messages?'),
        findsOne,
      );
      await tester.tap(
        find.byKey(const ValueKey('confirm-delete-chat-messages')),
      );
      await tester.pumpAndSettle();

      expect(api.chatMessageBatchesDeleted.single.channelId, 9);
      expect(api.chatMessageBatchesDeleted.single.messageIds, [1, 2]);
      expect(find.text('2 messages deleted'), findsOne);
      expect(find.text('Messages deleted.'), findsOne);
      expect(tester.widget<IconButton>(deleteButton).onPressed, isNull);
    });

    testWidgets('moves a moderator selection and opens its destination', (
      tester,
    ) async {
      const user = DiscourseUser(id: 7, username: 'moderator', staff: true);
      const source = ChatChannel(
        id: 9,
        title: 'Bugs',
        kind: ChatChannelKind.category,
        canModerate: true,
        membership: ChatMembership(following: true),
      );
      const destination = ChatChannel(
        id: 10,
        title: 'Support',
        kind: ChatChannelKind.category,
        membership: ChatMembership(following: true),
      );
      final api = _ChatApi(
        user: user,
        chatChannelsBySite: const {
          firstSite: ChatChannels(public: [source, destination], direct: []),
        },
        chatMoveFirstMessageId: 101,
        openPages: {
          firstSite: [_messagesPage(1, 2)],
        },
      );
      final controller = await _controller(
        api,
        sites: const [firstSite],
        user: user,
      );
      addTearDown(controller.dispose);
      await controller.chat.loadChannels(firstSite);
      expect(controller.openChatChannel(9), isTrue);

      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pumpAndSettle();
      await _startSelectingNewestMessage(tester);
      await tester.tap(find.byKey(const ValueKey('chat-message-selector-1')));
      await tester.pump();

      final moveButton = find.byKey(const ValueKey('chat-move-selection'));
      expect(tester.widget<IconButton>(moveButton).onPressed, isNotNull);
      await tester.tap(moveButton);
      await tester.pumpAndSettle();
      expect(find.text('Move messages'), findsOne);
      await tester.tap(find.byKey(const ValueKey('chat-move-destination')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Support').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-move-chat-messages')),
      );
      await tester.pumpAndSettle();

      expect(api.chatMessageMoves.single.channelId, 9);
      expect(api.chatMessageMoves.single.destinationChannelId, 10);
      expect(api.chatMessageMoves.single.messageIds, [1, 2]);
      expect(controller.currentContent?.id, 'chat-c-10');
      expect(
        find.byKey(const ValueKey('chat-message-selection-bar')),
        findsNothing,
      );
    });

    testWidgets('a queued history page cannot target a replacement window', (
      tester,
    ) async {
      final api = _ChatApi(
        openPages: {
          firstSite: [
            _messagesPage(1, 1, canLoadMorePast: true),
            _messagesPage(10, 1, canLoadMorePast: true),
            _messagesPage(20, 1, canLoadMorePast: true),
          ],
          secondSite: const [],
        },
      );
      final controller = await _controller(api, sites: const [firstSite]);
      addTearDown(controller.dispose);
      controller.chatRecords.put(firstSite, _channel(lastRead: 1));
      await controller.chat.openChannel(firstSite, 9);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        // The view's own rapid remount is cooled down. This callback models the
        // explicit replacement whose generation must invalidate queued paging.
        unawaited(controller.chat.openChannel(firstSite, 9, force: true));
      });
      await tester.pumpWidget(_TestView(controller: controller));

      expect(controller.chat.stream(firstSite, 9).oldestId, 10);
      expect(api.olderSites, isEmpty);
    });

    testWidgets('a paging flag does not reproject the whole message window', (
      tester,
    ) async {
      final older = Completer<ChatMessagePage>();
      final api = _ChatApi(
        openPages: {
          firstSite: [_messagesPage(1, 50, canLoadMorePast: true)],
        },
        gatedOlder: older,
      );
      final store = _CountingStore();
      final controller = await _controller(
        api,
        sites: const [firstSite],
        store: store,
      );
      addTearDown(controller.dispose);
      controller.chatRecords.put(firstSite, _channel(lastRead: 50));

      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pumpAndSettle();
      store.messageReads = 0;

      final request = controller.chat.loadOlder(firstSite, 9);
      await tester.pump();

      expect(controller.chat.stream(firstSite, 9).loadingOlder, isTrue);
      expect(store.messageReads, 0);

      older.complete(_messagesPage(-1, 1));
      await request;
      await tester.pump();

      // The page seam is resolved through the rows' stable refs; the fifty-message
      // window already projected is never scanned again. This is the bound that
      // keeps repeated backscrolling from becoming progressively more expensive.
      expect(store.messageReads, 0);
    });

    testWidgets('message skeletons represent paging in either direction', (
      tester,
    ) async {
      final api = _ChatApi(openPages: const {});
      final controller = await _controller(api, sites: const [firstSite]);
      addTearDown(controller.dispose);
      final message = _message(1);
      controller.chatRecords
        ..put(firstSite, _channel(lastRead: 1))
        ..put(firstSite, message);
      final semantics = tester.ensureSemantics();

      try {
        await tester.pumpWidget(
          _TestStreamView(
            controller: controller,
            messages: [message],
            stream: const ChatStreamState(
              messageIds: [1],
              loadingOlder: true,
              loadingNewer: true,
              fetchedOnce: true,
              fetches: 1,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final older = find.byKey(const ValueKey('chat-loading-older-skeleton'));
        final newer = find.byKey(const ValueKey('chat-loading-newer-skeleton'));
        expect(older, findsOneWidget);
        expect(newer, findsOneWidget);
        expect(
          find.descendant(
            of: older,
            matching: find.byType(LoadingSkeletonBlock),
          ),
          findsNWidgets(5),
        );
        expect(
          find.descendant(
            of: newer,
            matching: find.byType(LoadingSkeletonBlock),
          ),
          findsNWidgets(5),
        );
        expect(find.bySemanticsLabel('Loading older messages'), findsOneWidget);
        expect(find.bySemanticsLabel('Loading newer messages'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      } finally {
        semantics.dispose();
      }
    });
  });

  group('navigation and reading state', () {
    testWidgets('jump to latest is a named 44-pixel keyboard target', (
      tester,
    ) async {
      final api = _ChatApi(
        openPages: {
          firstSite: [
            _messagesPage(1, 40, canLoadMoreFuture: true),
            _messagesPage(80, 1),
          ],
        },
      );
      final controller = await _controller(api, sites: const [firstSite]);
      addTearDown(controller.dispose);
      controller.chatRecords.put(firstSite, _channel(lastRead: 1));
      final semantics = tester.ensureSemantics();

      try {
        await tester.pumpWidget(_TestView(controller: controller));
        await tester.pumpAndSettle();

        final icon = find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.chevronDown,
        );
        expect(icon, findsOneWidget);
        final target = find
            .ancestor(of: icon, matching: find.byType(InkWell))
            .last;
        expect(tester.getSize(target), const Size.square(44));
        expect(
          tester.getCenter(target).dx,
          tester.getCenter(find.byType(ChatChannelView)).dx,
        );
        expect(
          tester.getSemantics(target),
          isSemantics(
            label: 'Jump to latest messages',
            isButton: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );

        bool targetIsFocused() =>
            tester
                .getSemantics(target)
                .getSemanticsData()
                .flagsCollection
                .isFocused ==
            Tristate.isTrue;
        for (var step = 0; step < 10 && !targetIsFocused(); step++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(targetIsFocused(), isTrue);
        expect(
          tester.getSemantics(target),
          isSemantics(isFocusable: true, isFocused: true),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(icon, findsNothing);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
      'an explicit channel target is fetched and transiently highlighted',
      (tester) async {
        final api = _ChatApi(
          openPages: {
            firstSite: [_messagesPage(40, 5)],
          },
        );
        final controller = await _controller(api, sites: const [firstSite]);
        addTearDown(controller.dispose);
        controller.chatRecords.put(firstSite, _channel(lastRead: 40));
        controller.chatNavigation.offer(
          ChatNavigationTarget(
            siteUrl: 'https://one.example',
            route: ChatRoute.channel(9),
            messageId: 42,
          ),
        );

        await tester.pumpWidget(_TestView(controller: controller));
        await tester.pumpAndSettle();

        expect(api.targetMessageIds, [42]);
        expect(controller.chatNavigation.value, isNull);
        expect(
          find.byKey(const ValueKey('chat-message-highlight')),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('chat-message-highlight')),
          findsNothing,
        );
      },
    );

    testWidgets('a direct-reply indicator fetches and highlights its message', (
      tester,
    ) async {
      const reply = ChatReplyTo(
        id: 1,
        userId: 2,
        excerpt: 'Message 1',
        username: 'sam',
      );
      final page = (
        messages: [
          _message(1),
          _message(2, authorId: 3, replyTo: reply),
        ],
        canLoadMorePast: false,
        canLoadMoreFuture: false,
        targetMessageId: null,
      );
      final api = _ChatApi(
        openPages: {
          firstSite: [page, page],
        },
      );
      final controller = await _controller(api, sites: const [firstSite]);
      addTearDown(controller.dispose);
      controller.chatRecords.put(firstSite, _channel(lastRead: 2));

      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ChatMessageTile.replyIndicatorKey(reply.id)));
      await tester.pumpAndSettle();

      expect(api.targetMessageIds.last, reply.id);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('chat-message-highlight')),
          matching: find.byKey(const ValueKey('chat-message-1')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the pinned bar jumps to a pin and opens the complete list', (
      tester,
    ) async {
      final first = _message(2).withPinned(true);
      final second = _message(3).withPinned(true);
      final api = _ChatApi(
        user: const DiscourseUser(id: 7, username: 'reader'),
        openPages: {
          firstSite: [_messagesPage(1, 3), _messagesPage(1, 3)],
        },
        chatPinsByChannel: {
          9: (
            pins: [
              ChatPin(
                id: 91,
                messageId: 2,
                message: first,
                pinnedBy: const ChatMessageAuthor(id: 4, username: 'sam'),
                excerpt: 'First important answer',
              ),
              ChatPin(
                id: 92,
                messageId: 3,
                message: second,
                pinnedBy: const ChatMessageAuthor(id: 7, username: 'reader'),
                excerpt: 'Newest important answer',
              ),
            ],
            membership: const ChatMembership(
              following: true,
              hasUnseenPins: true,
            ),
          ),
        },
      );
      final controller = await _controller(
        api,
        sites: const [firstSite],
        user: const DiscourseUser(id: 7, username: 'reader'),
      );
      addTearDown(controller.dispose);
      controller.chatRecords.put(
        firstSite,
        _channel(lastRead: 3, pinnedMessagesCount: 2, hasUnseenPins: true),
      );

      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('Pinned message'), findsOneWidget);
      expect(find.text('Newest important answer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-pinned-message-bar')));
      await tester.pumpAndSettle();
      expect(api.targetMessageIds.last, 3);

      await tester.tap(find.byTooltip('Pinned messages'));
      await tester.pumpAndSettle();
      expect(find.text('Pinned messages'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-pin-91')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-pin-92')), findsOneWidget);
      expect(api.chatPinsRead, [9]);
      expect(
        controller.chat.channel(firstSite, 9)?.membership.hasUnseenPins,
        isFalse,
      );
    });

    testWidgets('the ordinary last-read anchor is never highlighted', (
      tester,
    ) async {
      final api = _ChatApi(
        openPages: {
          firstSite: [_messagesPage(40, 5)],
        },
      );
      final controller = await _controller(api, sites: const [firstSite]);
      addTearDown(controller.dispose);
      controller.chatRecords.put(firstSite, _channel(lastRead: 42));

      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pumpAndSettle();

      expect(api.targetMessageIds, [null]);
      expect(
        find.byKey(const ValueKey('chat-message-highlight')),
        findsNothing,
      );
    });

    testWidgets('a paused dwell resumes without crediting hidden time', (
      tester,
    ) async {
      final api = _ChatApi(
        openPages: {
          firstSite: [_messagesPage(1, 1)],
        },
      );
      final controller = await _controller(api, sites: const [firstSite]);
      addTearDown(controller.dispose);
      addTearDown(() => _resumeLifecycle(tester));
      controller.chatRecords.put(firstSite, _channel(lastRead: 0));

      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.chatReadsMarked, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 2));
      expect(api.chatReadsMarked, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.chatReadsMarked, isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      expect(api.chatReadsMarked, [(channelId: 9, messageId: 1)]);
    });

    testWidgets(
      'read-only channels remove thread creation while existing threads remain openable',
      (tester) async {
        const replyAction = CustomSemanticsAction(label: 'Reply in thread');
        Finder replyActionFor(int messageId) => find.descendant(
          of: find.byKey(ChatMessageTile.actionsKey(messageId)),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.customSemanticsActions?.containsKey(
                      replyAction,
                    ) ??
                    false),
          ),
        );
        final existing = _message(
          2,
          thread: const ChatThreadPreview(
            threadId: 3,
            replyCount: 1,
            lastReplyId: 2,
          ),
        );
        final api = _ChatApi(
          openPages: {
            firstSite: [
              (
                messages: [_message(1), existing],
                canLoadMorePast: false,
                canLoadMoreFuture: false,
                targetMessageId: null,
              ),
            ],
          },
        );
        final controller = await _controller(
          api,
          sites: const [firstSite],
          user: const DiscourseUser(id: 1, username: 'reader'),
        );
        addTearDown(controller.dispose);
        controller.chatRecords.put(firstSite, _channel(lastRead: 0));

        await tester.pumpWidget(_TestView(controller: controller));
        await tester.pumpAndSettle();
        expect(replyActionFor(1), findsOneWidget);
        expect(replyActionFor(2), findsOneWidget);

        controller.chatRecords.put(
          firstSite,
          const ChatChannel(
            id: 9,
            title: 'Chat',
            kind: ChatChannelKind.category,
            status: ChatChannelStatus.readOnly,
            membership: ChatMembership(following: true),
            threadingEnabled: true,
          ),
        );
        await tester.pump();

        expect(replyActionFor(1), findsNothing);
        expect(replyActionFor(2), findsOneWidget);

        final threadPreview = find.byKey(ChatMessageTile.threadPreviewKey(3));
        expect(tester.widget<Semantics>(threadPreview).properties.link, isTrue);
        await tester.tap(
          find.descendant(of: threadPreview, matching: find.byType(InkWell)),
        );
        await tester.pumpAndSettle();

        expect(controller.currentContent?.id, 'chat-c-9-t-3');
      },
    );
  });

  group('live updates and mounted presentation', () {
    testWidgets(
      'scrolling hides message actions until the pointer moves again',
      (tester) async {
        final api = _ChatApi(openPages: const {});
        final controller = await _controller(api, sites: const [firstSite]);
        addTearDown(controller.dispose);
        final messages = [for (var id = 1; id <= 40; id++) _message(id)];
        controller.chatRecords
          ..put(firstSite, _channel(lastRead: 40))
          ..putAll(firstSite, messages);

        await tester.pumpWidget(
          _TestStreamView(
            controller: controller,
            messages: messages,
            stream: ChatStreamState(
              messageIds: [for (final message in messages) message.id],
              fetchedOnce: true,
              fetches: 1,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        final hoveredMessage = find.byType(ChatMessageTile).hitTestable().first;
        final pointerPosition = tester.getCenter(hoveredMessage);
        await mouse.moveTo(pointerPosition);
        await tester.pump();
        expect(find.byTooltip('More message actions'), findsOneWidget);

        final scroll = await tester.startGesture(pointerPosition);
        await scroll.moveBy(const Offset(0, 200));
        await tester.pump();
        expect(find.byTooltip('More message actions'), findsNothing);
        await mouse.moveBy(const Offset(0, 1));
        await tester.pump();
        expect(find.byTooltip('More message actions'), findsNothing);

        await scroll.up();
        await tester.pumpAndSettle();
        expect(find.byTooltip('More message actions'), findsNothing);

        await mouse.moveBy(const Offset(0, 1));
        await tester.pump();
        expect(find.byTooltip('More message actions'), findsOneWidget);
      },
    );

    testWidgets('a failed thread creation is explained', (tester) async {
      final api = _ChatApi(
        openPages: {
          firstSite: [_messagesPage(1, 1)],
        },
      );
      final controller = await _controller(api, sites: const [firstSite]);
      addTearDown(controller.dispose);
      controller.chatRecords.put(firstSite, _channel(lastRead: 0));

      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(ChatMessageTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply in thread'));
      await tester.pumpAndSettle();

      expect(api.chatThreadsCreated.single.originalMessageId, 1);
      expect(
        find.text('Could not start this thread. Try again.'),
        findsOneWidget,
      );
    });

    testWidgets('jump to latest visibly renders its pending message count', (
      tester,
    ) async {
      final api = _ChatApi(openPages: const {});
      final controller = await _controller(api, sites: const [firstSite]);
      addTearDown(controller.dispose);
      final message = _message(1);
      controller.chatRecords
        ..put(firstSite, _channel(lastRead: 0))
        ..put(firstSite, message);

      await tester.pumpWidget(
        _TestStreamView(
          controller: controller,
          messages: [message],
          stream: const ChatStreamState(
            messageIds: [1],
            canLoadMoreFuture: true,
            pendingNewMessages: 3,
            fetchedOnce: true,
            fetches: 1,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('chat-jump-pending-count')),
        findsOneWidget,
      );
      expect(find.text('3'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Jump to latest messages, 3 new'),
        findsOneWidget,
      );
    });

    testWidgets('a live delete collapses the message in a mounted pane', (
      tester,
    ) async {
      const author = DiscourseUser(id: 2, username: 'sam');
      final api = _ChatApi(
        user: author,
        openPages: {
          firstSite: [_messagesPage(1, 3)],
        },
      );
      final controller = await _controller(
        api,
        sites: const [firstSite],
        user: author,
      );
      addTearDown(controller.dispose);
      controller.chatRecords.put(firstSite, _channel(lastRead: 3));

      await controller.chat.openChannel(firstSite, 9);
      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Message 2', findRichText: true),
        findsOneWidget,
      );

      final tracker = FakeSiteTracker.built.singleWhere(
        (tracker) => tracker.siteUrl == firstSite,
      );
      tracker.deliverPluginMessage('/chat/9', {
        'type': 'delete',
        'deleted_id': 2,
        'deleted_at': '2026-05-05T11:00:00.000Z',
      });
      await tester.pump();

      expect(
        find.textContaining('Message 2', findRichText: true),
        findsNothing,
      );
      expect(find.text('1 message deleted'), findsOneWidget);
    });

    testWidgets('a deleted run restores the exact message it retained', (
      tester,
    ) async {
      const reader = DiscourseUser(id: 7, username: 'reader');
      final deleted = _message(
        2,
        authorId: 7,
        deletedAt: DateTime.utc(2026, 8, 25),
        deletedById: 7,
      );
      final api = _ChatApi(
        user: reader,
        openPages: {
          firstSite: [
            (
              messages: [deleted],
              canLoadMorePast: false,
              canLoadMoreFuture: false,
              targetMessageId: null,
            ),
          ],
        },
      );
      final controller = await _controller(
        api,
        sites: const [firstSite],
        user: reader,
      );
      addTearDown(controller.dispose);
      controller.chatRecords.put(
        firstSite,
        _channel(lastRead: 2, canDeleteSelf: true),
      );

      await controller.chat.openChannel(firstSite, 9);
      await tester.pumpWidget(_TestView(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('1 message deleted'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      expect(api.chatMessagesRestored, [(channelId: 9, messageId: 2)]);
      expect(find.text('1 message deleted'), findsNothing);
      expect(
        find.textContaining('Message 2', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a live message does not move a reader scrolled into history', (
      tester,
    ) async {
      final api = _ChatApi(openPages: const {});
      final controller = await _controller(api, sites: const [firstSite]);
      addTearDown(controller.dispose);
      final messages = [for (var id = 1; id <= 40; id++) _message(id)];
      controller.chatRecords
        ..put(firstSite, _channel(lastRead: 40))
        ..putAll(firstSite, messages);

      await tester.pumpWidget(
        _TestStreamView(
          controller: controller,
          messages: messages,
          stream: ChatStreamState(
            messageIds: [for (final message in messages) message.id],
            fetchedOnce: true,
            fetches: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      tester.state<ScrollableState>(_verticalChatScroll()).position.jumpTo(600);
      await tester.pump();
      final held = tester
          .state<ScrollableState>(_verticalChatScroll())
          .position
          .pixels;
      expect(held, greaterThan(0));

      // A live append arrives on a window already at the present: same fetch
      // generation, no future to load, one more newest id. The reversed
      // viewport keeps the reader in place on its own; nothing may reposition.
      final live = _message(41);
      controller.chatRecords.put(firstSite, live);
      await tester.pumpWidget(
        _TestStreamView(
          controller: controller,
          messages: [...messages, live],
          stream: ChatStreamState(
            messageIds: [for (var id = 1; id <= 41; id++) id],
            fetchedOnce: true,
            fetches: 1,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        tester.state<ScrollableState>(_verticalChatScroll()).position.pixels,
        held,
      );
    });

    testWidgets('the day crossing the top of chat stays pinned', (
      tester,
    ) async {
      final api = _ChatApi(openPages: const {});
      final controller = await _controller(api, sites: const [firstSite]);
      addTearDown(controller.dispose);
      final firstDay = DateTime(2020, 1, 2);
      final secondDay = DateTime(2020, 1, 3);
      final messages = [
        for (var id = 1; id <= 48; id++)
          _message(
            id,
            createdAt: (id <= 24 ? firstDay : secondDay).add(
              Duration(minutes: id <= 24 ? id : id - 24),
            ),
          ),
      ];
      controller.chatRecords
        ..put(firstSite, _channel(lastRead: 48))
        ..putAll(firstSite, messages);

      final theme = AppTheme.dark;
      await tester.pumpWidget(
        _TestStreamView(
          controller: controller,
          messages: messages,
          stream: ChatStreamState(
            messageIds: [for (final message in messages) message.id],
            fetchedOnce: true,
            fetches: 1,
          ),
          theme: theme,
        ),
      );
      await tester.pumpAndSettle();

      final floatingSecond = find.byKey(
        ValueKey(('chat-floating-day', secondDay)),
      );
      expect(floatingSecond, findsOneWidget);
      expect(tester.getSize(floatingSecond).height, 44);
      final floatingDecoration = tester
          .widgetList<Container>(
            find.descendant(
              of: floatingSecond,
              matching: find.byType(Container),
            ),
          )
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .single;
      expect(floatingDecoration.color, theme.colorScheme.surfaceContainerLow);
      expect(
        floatingDecoration.border,
        Border.all(color: theme.colorScheme.surfaceContainerHigh),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(floatingSecond));
      await tester.pump();

      final hoveredDecoration = tester
          .widgetList<Container>(
            find.descendant(
              of: floatingSecond,
              matching: find.byType(Container),
            ),
          )
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .single;
      expect(hoveredDecoration.color, theme.shell.hover);

      await mouse.moveTo(Offset.zero);
      await tester.pump();

      final list = tester.widget<SuperListView>(find.byType(SuperListView));
      list.listController!.jumpToItem(
        index: 35,
        scrollController: list.controller!,
        alignment: 0.5,
      );
      await tester.pumpAndSettle();

      expect(floatingSecond, findsNothing);
      expect(
        find.byKey(ValueKey(('chat-floating-day', firstDay))),
        findsOneWidget,
      );
    });

    testWidgets(
      'chat renders the elapsed time before a message after a long gap',
      (tester) async {
        final api = _ChatApi(openPages: const {});
        final controller = await _controller(api, sites: const [firstSite]);
        addTearDown(controller.dispose);
        final messages = [
          _message(1, createdAt: DateTime.utc(2026, 1, 1)),
          _message(2, createdAt: DateTime.utc(2026, 1, 9)),
        ];
        controller.chatRecords
          ..put(firstSite, _channel(lastRead: 2))
          ..putAll(firstSite, messages);

        await tester.pumpWidget(
          _TestStreamView(
            controller: controller,
            messages: messages,
            stream: const ChatStreamState(
              messageIds: [1, 2],
              fetchedOnce: true,
              fetches: 1,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey(('chat-time-gap', 2))),
          findsOneWidget,
        );
        expect(find.text('8 days later'), findsOneWidget);
      },
    );
  });
}

void _resumeLifecycle(WidgetTester tester) {
  var state = tester.binding.lifecycleState;
  if (state == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    state = AppLifecycleState.hidden;
  }
  if (state == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    state = AppLifecycleState.inactive;
  }
  if (state == AppLifecycleState.inactive) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

Finder _verticalChatScroll() => find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.up,
);

Future<void> _startSelectingNewestMessage(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(
    tester.getCenter(find.byKey(const ValueKey('chat-message-2'))),
  );
  await tester.pump();
  await tester.tap(find.byTooltip('More message actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, 'Select'));
  await tester.pumpAndSettle();
  await mouse.removePointer();
}

Future<ShellController> _controller(
  _ChatApi api, {
  List<String> sites = const ['https://one.example', 'https://two.example'],
  Store? store,
  DiscourseUser? user,
}) async {
  final authenticator = _SynchronousAuthenticator();
  for (final siteUrl in sites) {
    authenticator.keys[siteUrl] = 'key';
  }
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      for (final siteUrl in sites)
        DiscourseInstance(
          url: siteUrl,
          title: Uri.parse(siteUrl).host,
          apiVersion: 4,
          user: user,
        ),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    store: store,
    trackers: FakeSiteTracker.reset(),
  );
  await controller.load();
  return controller;
}

final class _TestView extends StatelessWidget {
  const _TestView({required this.controller, this.onScroll});

  final ShellController controller;
  final NotificationListenerCallback<ScrollNotification>? onScroll;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: PluginUiScope.own(
      chatPluginId,
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: NotificationListener<ScrollNotification>(
            onNotification: onScroll ?? (_) => false,
            child: const ChatChannelView(channelId: 9),
          ),
        ),
      ),
    ),
  );
}

final class _TestStreamView extends StatelessWidget {
  const _TestStreamView({
    required this.controller,
    required this.messages,
    required this.stream,
    this.theme,
  });

  final ShellController controller;
  final List<ChatMessage> messages;
  final ChatStreamState stream;
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: PluginUiScope.own(
      chatPluginId,
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Scaffold(
          body: ChatMessageStream(
            siteUrl: 'https://one.example',
            target: const ChatChannelTarget(9),
            items: buildChatStream(messages),
            stream: stream,
          ),
        ),
      ),
    ),
  );
}

final class _SynchronousAuthenticator extends FakeAuthenticator {
  @override
  Future<String?> apiKeyFor(String siteUrl) => SynchronousFuture(keys[siteUrl]);

  @override
  Future<String> clientId() => SynchronousFuture('test-client');
}

typedef _OpenGate = ({String siteUrl, int number, Completer<void> gate});
typedef _FailedOpen = ({String siteUrl, int number});

final class _ChatApi extends FakeDiscourseApi {
  _ChatApi({
    super.user,
    super.chatChannelsBySite,
    super.chatPinsByChannel,
    super.chatQuoteMarkdown,
    super.chatMoveFirstMessageId,
    required this.openPages,
    this.failNewer = false,
    this.gatedOpen,
    this.failedOpen,
    this.gatedOlder,
  });

  final Map<String, List<ChatMessagePage>> openPages;
  final bool failNewer;
  final _OpenGate? gatedOpen;
  final _FailedOpen? failedOpen;
  final Completer<ChatMessagePage>? gatedOlder;
  final Map<String, int> _openCounts = {};
  final List<String> olderSites = [];
  final List<String> newerSites = [];
  final List<int?> targetMessageIds = [];

  @override
  Future<ChatMessagePage> chatMessages({
    required String siteUrl,
    required int channelId,
    int? before,
    int? after,
    int? targetMessageId,
    bool fromLastRead = false,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) {
    if (before != null) {
      olderSites.add(siteUrl);
      final gate = gatedOlder;
      if (gate != null) return gate.future;
      return SynchronousFuture(_messagesPage(before - 1, 1));
    }
    if (after != null) {
      newerSites.add(siteUrl);
      if (failNewer) throw StateError('newer page refused');
      return SynchronousFuture(_messagesPage(after + 1, 1));
    }

    targetMessageIds.add(targetMessageId);

    final count = (_openCounts[siteUrl] ?? 0) + 1;
    _openCounts[siteUrl] = count;
    final failure = failedOpen;
    if (failure != null &&
        failure.siteUrl == siteUrl &&
        failure.number == count) {
      throw StateError('open refused');
    }
    final pages = openPages[siteUrl] ?? const <ChatMessagePage>[];
    if (pages.isEmpty) throw StateError('No open page for $siteUrl');
    final page = pages[(count - 1).clamp(0, pages.length - 1)];
    final gate = gatedOpen;
    if (gate != null && gate.siteUrl == siteUrl && gate.number == count) {
      return gate.gate.future.then((_) => page);
    }
    return SynchronousFuture(page);
  }
}

final class _CountingStore extends Store {
  int messageReads = 0;

  @override
  T? read<T extends Storable<T>>(String siteUrl, Object id) {
    if (T == ChatMessage) messageReads++;
    return super.read<T>(siteUrl, id);
  }
}

ChatChannel _channel({
  required int lastRead,
  bool canDeleteSelf = false,
  int pinnedMessagesCount = 0,
  bool hasUnseenPins = false,
}) => ChatChannel(
  id: 9,
  title: 'Chat',
  kind: ChatChannelKind.category,
  canDeleteSelf: canDeleteSelf,
  pinnedMessagesCount: pinnedMessagesCount,
  membership: ChatMembership(
    following: true,
    lastReadMessageId: lastRead,
    hasUnseenPins: hasUnseenPins,
  ),
  threadingEnabled: true,
);

ChatMessagePage _messagesPage(
  int first,
  int count, {
  bool canLoadMorePast = false,
  bool canLoadMoreFuture = false,
}) => (
  messages: [for (var id = first; id < first + count; id++) _message(id)],
  canLoadMorePast: canLoadMorePast,
  canLoadMoreFuture: canLoadMoreFuture,
  targetMessageId: null,
);

ChatMessage _message(
  int id, {
  String? cooked,
  ChatThreadPreview? thread,
  DateTime? createdAt,
  int authorId = 2,
  DateTime? deletedAt,
  int? deletedById,
  ChatReplyTo? replyTo,
}) => ChatMessage(
  id: id,
  channelId: 9,
  cooked: cooked ?? '<p>Message $id</p>',
  author: ChatMessageAuthor(id: authorId, username: 'sam'),
  createdAt: createdAt ?? DateTime.utc(2026, 1, 1).add(Duration(minutes: id)),
  deletedAt: deletedAt,
  deletedById: deletedById,
  replyTo: replyTo,
  threadId: thread?.threadId,
  thread: thread,
);
