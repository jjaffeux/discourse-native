import 'dart:async';

import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_avatar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _messageTileKey = ValueKey('message-tile');
const _replyInThreadAction = CustomSemanticsAction(label: 'Reply in thread');

void main() {
  testWidgets(
    'shows the latest reply and the representative participant stack',
    (tester) async {
      final thread = _thread();
      final controller = await _controller(_message(thread));
      final opened = <ChatThreadPreview>[];
      addTearDown(controller.dispose);

      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _TestTile(controller: controller, onOpenThread: opened.add),
        );
        await tester.pumpAndSettle();

        final target = find.byKey(
          ChatMessageTile.threadPreviewKey(thread.threadId),
        );
        expect(target, findsOneWidget);
        expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(target).width, lessThanOrEqualTo(600));
        expect(find.text('Kris'), findsOneWidget);
        expect(find.text('5 replies'), findsOneWidget);
        expect(find.text('It works'), findsOneWidget);
        expect(find.text('+3'), findsOneWidget);
        expect(
          tester.getTopRight(find.text('5 replies')).dx,
          closeTo(tester.getTopRight(target).dx - 8, 0.01),
        );

        final avatars = tester
            .widgetList<ChatUserAvatar>(
              find.descendant(
                of: target,
                matching: find.byType(ChatUserAvatar),
              ),
            )
            .map((avatar) => avatar.userId);
        // The latest-reply avatar comes first. The participant sample keeps
        // its first two users and its most recent (last) user.
        expect(avatars, [10, 1, 2, 5]);

        expect(
          tester.getSemantics(target),
          isSemantics(
            label:
                'Open thread with 5 replies. Latest reply from Kris, now: '
                'It works. 6 participants.',
            isLink: true,
            isButton: false,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );

        // The excerpt is merely one part of the card, but tapping it activates
        // the card's single callback with the complete typed preview.
        await tester.tap(find.text('It works'));
        await tester.pump();
        expect(opened, [same(thread)]);
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final activation in [
    (name: 'Enter', key: LogicalKeyboardKey.enter),
    (name: 'Space', key: LogicalKeyboardKey.space),
  ]) {
    testWidgets('opens the whole thread card with ${activation.name}', (
      tester,
    ) async {
      final thread = _thread();
      final controller = await _controller(_message(thread));
      final opened = <ChatThreadPreview>[];
      addTearDown(controller.dispose);

      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _TestTile(controller: controller, onOpenThread: opened.add),
        );
        await tester.pumpAndSettle();

        final target = find.byKey(
          ChatMessageTile.threadPreviewKey(thread.threadId),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.getSemantics(target),
          isSemantics(isFocusable: true, isFocused: true),
        );

        await tester.sendKeyEvent(activation.key);
        await tester.pump();

        expect(opened, [same(thread)]);
      } finally {
        semantics.dispose();
      }
    });
  }

  for (final variant in [
    (name: 'plain', chained: false, key: LogicalKeyboardKey.f10, shift: true),
    (
      name: 'chained',
      chained: true,
      key: LogicalKeyboardKey.contextMenu,
      shift: false,
    ),
  ]) {
    testWidgets(
      'the ${variant.name} message action surface is keyboard focusable',
      (tester) async {
        final message = _message(null);
        final controller = await _controller(message);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _TestTile(
            controller: controller,
            onOpenThread: (_) {},
            onReplyInThread: (_) {},
            chained: variant.chained,
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final target = find.byKey(ChatMessageTile.actionsKey(message.id));
        expect(
          tester.getSemantics(target),
          isSemantics(isFocusable: true, isFocused: true),
        );

        if (variant.shift) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyEvent(variant.key);
        if (variant.shift) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.pumpAndSettle();

        expect(find.text('Message actions'), findsOneWidget);
        expect(find.text('Reply in thread'), findsOneWidget);
      },
    );
  }

  testWidgets('does not show an unanswered thread', (tester) async {
    final thread = _thread(replyCount: 0);
    final controller = await _controller(_message(thread));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ChatMessageTile.threadPreviewKey(thread.threadId)),
      findsNothing,
    );
    expect(find.text('0 replies'), findsNothing);
  });

  testWidgets('suppresses the original message card in thread context', (
    tester,
  ) async {
    final thread = _thread();
    final controller = await _controller(_message(thread));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(
        controller: controller,
        onOpenThread: (_) {},
        showThreadSummary: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ChatMessageTile.threadPreviewKey(thread.threadId)),
      findsNothing,
    );
    expect(find.text('5 replies'), findsNothing);
  });

  testWidgets('reaction permissions follow live channel changes', (
    tester,
  ) async {
    final controller = await _controller(
      _message(null, reactions: const [ChatReaction(emoji: 'clap', count: 2)]),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Add reaction'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('2 clap reactions')),
      isSemantics(onTapHint: 'add this reaction'),
    );

    controller.store.put(
      _siteUrl,
      const ChatChannel(
        id: 9,
        title: 'Support',
        kind: ChatChannelKind.category,
        status: ChatChannelStatus.readOnly,
        membership: ChatMembership(following: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Add reaction'), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('2 clap reactions')),
      isSemantics(onTapHint: 'show who reacted'),
    );
  });

  testWidgets('hover shows a 44 pixel action for the exact message', (
    tester,
  ) async {
    final message = _message(_thread());
    final controller = await _controller(message);
    final replies = <ChatMessage>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(
        controller: controller,
        onOpenThread: (_) {},
        onReplyInThread: replies.add,
      ),
    );
    await tester.pumpAndSettle();

    await _hoverMessage(tester);

    final action = find.byTooltip('Reply in thread');
    expect(action, findsOneWidget);
    expect(tester.getSize(action), const Size.square(44));
    expect(
      tester.getSemantics(action),
      isSemantics(
        tooltip: 'Reply in thread',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    await tester.tap(action);
    await tester.pump();

    expect(replies, [same(message)]);
  });

  testWidgets('hover actions are not clipped by a short chained message', (
    tester,
  ) async {
    final controller = await _controller(_message(null));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(
        controller: controller,
        onOpenThread: (_) {},
        onReplyInThread: (_) {},
        chained: true,
      ),
    );
    await tester.pumpAndSettle();

    await _hoverMessage(tester);

    final action = find.byTooltip('Reply in thread');
    final actionStack = find.ancestor(
      of: action,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Stack &&
            widget.children.any((child) => child is Positioned),
      ),
    );
    expect(
      tester.getSize(action).height,
      greaterThan(ChatMessageTile.minimumChainedHeight),
    );
    expect(tester.widget<Stack>(actionStack).clipBehavior, Clip.none);
  });

  testWidgets('signed-in hover creates a chat message bookmark once', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: const DiscourseUser(id: 1, username: 'reader'),
      bookmarkList: const [],
    );
    final controller = await _controller(
      _message(null),
      signedIn: true,
      api: api,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();
    await _hoverMessage(tester);

    final action = find.byTooltip('Bookmark');
    expect(action, findsOneWidget);
    expect(tester.getSize(action), const Size.square(44));

    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(api.createdBookmarks, hasLength(1));
    expect(
      api.createdBookmarks.single.targetType,
      BookmarkTargetType.chatMessage,
    );
    expect(api.createdBookmarks.single.targetId, 7);
    expect(find.text('Bookmarked!'), findsOneWidget);
    expect(controller.store.read<ChatMessage>(_siteUrl, 7)?.bookmark?.id, 1000);
  });

  testWidgets('a chat bookmark shows its state and edit action', (
    tester,
  ) async {
    final controller = await _controller(
      _message(
        null,
        bookmark: Bookmark(
          id: 81,
          bookmarkableId: 7,
          bookmarkableType: 'Chat::Message',
          reminderAt: DateTime.now().add(const Duration(days: 1)),
        ),
      ),
      signedIn: true,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Chat message bookmarked with a reminder',
      ),
      findsOneWidget,
    );

    await _hoverMessage(tester);
    final action = find.byTooltip('Edit bookmark');
    expect(action, findsOneWidget);
    expect(tester.getSize(action), const Size.square(44));
  });

  testWidgets('the hover bookmark action disables while its write is active', (
    tester,
  ) async {
    final api = _GatedBookmarkApi();
    final controller = await _controller(
      _message(null),
      signedIn: true,
      api: api,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();

    final write = controller.createBookmark(
      topicId: 0,
      targetType: BookmarkTargetType.chatMessage,
      targetId: 7,
    );
    await api.started.future;
    await tester.pump();
    await _hoverMessage(tester);

    final action = find.byTooltip('Bookmark');
    expect(action, findsOneWidget);
    final button = tester.widget<IconButton>(
      find.ancestor(of: action, matching: find.byType(IconButton)),
    );
    expect(button.onPressed, isNull);
    expect(button.icon, isA<SizedBox>());

    api.response.complete(91);
    expect((await write).saved, isTrue);
  });

  testWidgets('exposes Reply in thread as a custom semantics action', (
    tester,
  ) async {
    final message = _message(_thread());
    final controller = await _controller(message);
    final replies = <ChatMessage>[];
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _TestTile(
          controller: controller,
          onOpenThread: (_) {},
          onReplyInThread: replies.add,
        ),
      );
      await tester.pumpAndSettle();

      final owner = _replySemanticsOwner();
      expect(owner, findsOneWidget);
      final actions = [
        for (final id
            in tester
                    .getSemantics(owner)
                    .getSemanticsData()
                    .customSemanticsActionIds ??
                const <int>[])
          CustomSemanticsAction.getAction(id),
      ];
      expect(actions, contains(_replyInThreadAction));

      tester
          .widget<Semantics>(owner)
          .properties
          .customSemanticsActions![_replyInThreadAction]!();
      await tester.pump();

      expect(replies, [same(message)]);
    } finally {
      semantics.dispose();
    }
  });

  for (final variant
      in <
        ({String name, ChatMessage Function() message, bool provideCallback})
      >[
        (
          name: 'the callback is absent',
          message: () => _message(_thread()),
          provideCallback: false,
        ),
        (
          name: 'the message is deleted',
          message: () =>
              _message(_thread(), deletedAt: DateTime.utc(2026, 8, 12)),
          provideCallback: true,
        ),
        (
          name: 'the message is optimistic',
          message: () => ChatMessage.optimistic(
            id: -1,
            channelId: 9,
            raw: 'Root message',
            stagedId: 'native-1',
            preview: const SourceFallback(
              'Root message',
              ChatPreviewFallbackReason.unsupportedSyntax,
            ),
            author: const ChatMessageAuthor(id: 99, username: 'root'),
            createdAt: DateTime.utc(2026, 8, 12),
          ),
          provideCallback: true,
        ),
        (
          name: 'the message is already a thread reply',
          message: () => _message(null, threadId: 3),
          provideCallback: true,
        ),
      ]) {
    testWidgets('hides the reply action when ${variant.name}', (tester) async {
      final message = variant.message();
      final controller = await _controller(message);
      final replies = <ChatMessage>[];
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _TestTile(
          controller: controller,
          messageId: message.id,
          onOpenThread: (_) {},
          onReplyInThread: variant.provideCallback ? replies.add : null,
        ),
      );
      await tester.pumpAndSettle();

      await _hoverMessage(tester);

      expect(find.byTooltip('Reply in thread'), findsNothing);
      expect(_replySemanticsOwner(), findsNothing);
      expect(replies, isEmpty);
    });
  }

  for (final activation in [
    (name: 'Shift+F10', key: LogicalKeyboardKey.f10, shift: true),
    (
      name: 'the context-menu key',
      key: LogicalKeyboardKey.contextMenu,
      shift: false,
    ),
  ]) {
    testWidgets('${activation.name} opens the message actions sheet', (
      tester,
    ) async {
      final thread = _thread();
      final message = _message(thread);
      final controller = await _controller(message);
      final replies = <ChatMessage>[];
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _TestTile(
          controller: controller,
          onOpenThread: (_) {},
          onReplyInThread: replies.add,
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final actionsTarget = find.byKey(ChatMessageTile.actionsKey(message.id));
      expect(
        tester.getSemantics(actionsTarget),
        isSemantics(isFocusable: true, isFocused: true),
      );

      if (activation.shift) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      }
      await tester.sendKeyEvent(activation.key);
      if (activation.shift) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      await tester.pumpAndSettle();

      expect(find.text('Message actions'), findsOneWidget);
      final action = find.text('Reply in thread');
      expect(action, findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(replies, [same(message)]);
      expect(find.text('Message actions'), findsNothing);
    });
  }

  testWidgets('a touch long press opens the message actions sheet', (
    tester,
  ) async {
    final message = _message(_thread());
    final controller = await _controller(message);
    final replies = <ChatMessage>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(
        controller: controller,
        onOpenThread: (_) {},
        onReplyInThread: replies.add,
        platform: TargetPlatform.android,
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(_messageTileKey));
    await tester.pumpAndSettle();

    expect(find.text('Message actions'), findsOneWidget);
    final action = find.text('Reply in thread');
    expect(action, findsOneWidget);

    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(replies, [same(message)]);
    expect(find.text('Message actions'), findsNothing);
  });

  testWidgets('a signed-in touch long press offers bookmarking', (
    tester,
  ) async {
    final controller = await _controller(_message(null), signedIn: true);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(
        controller: controller,
        onOpenThread: (_) {},
        platform: TargetPlatform.android,
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(_messageTileKey));
    await tester.pumpAndSettle();

    expect(find.text('Message actions'), findsOneWidget);
    expect(find.text('Bookmark'), findsOneWidget);
  });
}

ChatThreadPreview _thread({int replyCount = 5}) => ChatThreadPreview(
  threadId: 3,
  replyCount: replyCount,
  lastReplyId: 42,
  lastReplyAt: DateTime.now().add(const Duration(seconds: 1)),
  lastReplyExcerpt: 'It works',
  lastReplyUser: const ChatMessageAuthor(
    id: 10,
    username: 'kris',
    name: 'Kris',
  ),
  participantCount: 6,
  participantUsers: const [
    ChatMessageAuthor(id: 1, username: 'one'),
    ChatMessageAuthor(id: 2, username: 'two'),
    ChatMessageAuthor(id: 3, username: 'three'),
    ChatMessageAuthor(id: 4, username: 'four'),
    ChatMessageAuthor(id: 5, username: 'five'),
  ],
);

ChatMessage _message(
  ChatThreadPreview? thread, {
  int? threadId,
  DateTime? deletedAt,
  List<ChatReaction> reactions = const [],
  Bookmark? bookmark,
}) => ChatMessage(
  id: 7,
  channelId: 9,
  cooked: '<p>Root message</p>',
  author: const ChatMessageAuthor(id: 99, username: '', name: 'Root author'),
  deletedAt: deletedAt,
  reactions: reactions,
  bookmark: bookmark,
  threadId: threadId ?? thread?.threadId,
  thread: thread,
);

Future<ShellController> _controller(
  ChatMessage message, {
  bool signedIn = false,
  FakeDiscourseApi? api,
}) async {
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      DiscourseInstance(
        url: _siteUrl,
        title: 'Meta',
        apiVersion: 4,
        user: signedIn ? const DiscourseUser(id: 1, username: 'reader') : null,
      ),
    ]),
    api: api ?? FakeDiscourseApi(),
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await controller.load();
  controller.store.put(
    _siteUrl,
    const ChatChannel(
      id: 9,
      title: 'Support',
      kind: ChatChannelKind.category,
      membership: ChatMembership(following: true),
    ),
  );
  controller.store.put(_siteUrl, message);
  return controller;
}

class _TestTile extends StatelessWidget {
  const _TestTile({
    required this.controller,
    required this.onOpenThread,
    this.messageId = 7,
    this.onReplyInThread,
    this.showThreadSummary = true,
    this.chained = false,
    this.platform = TargetPlatform.macOS,
  });

  final ShellController controller;
  final int messageId;
  final ValueChanged<ChatThreadPreview> onOpenThread;
  final ValueChanged<ChatMessage>? onReplyInThread;
  final bool showThreadSummary;
  final bool chained;
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light.copyWith(platform: platform),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 720,
            child: ChatMessageTile(
              key: _messageTileKey,
              siteUrl: _siteUrl,
              messageId: messageId,
              chained: chained,
              onOpenThread: onOpenThread,
              onReplyInThread: onReplyInThread,
              showThreadSummary: showThreadSummary,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _hoverMessage(WidgetTester tester) async {
  final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await pointer.addPointer(location: Offset.zero);
  addTearDown(pointer.removePointer);
  await pointer.moveTo(tester.getCenter(find.byKey(_messageTileKey)));
  await tester.pump();
}

Finder _replySemanticsOwner() => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.customSemanticsActions?.containsKey(
            _replyInThreadAction,
          ) ??
          false),
);

final class _GatedBookmarkApi extends FakeDiscourseApi {
  _GatedBookmarkApi()
    : super(
        user: const DiscourseUser(id: 1, username: 'reader'),
        bookmarkList: const [],
      );

  final Completer<void> started = Completer<void>();
  final Completer<int> response = Completer<int>();

  @override
  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  }) {
    started.complete();
    return response.future;
  }
}
