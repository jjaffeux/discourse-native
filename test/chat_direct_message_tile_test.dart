import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_avatar.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/hover_action_toolbar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

const _site = 'https://dm.example';
const _otherSite = 'https://other.example';
const _bodyKey = ValueKey('chat-message-7');
const _upload = ChatUpload(
  id: 1,
  url: '/uploads/notes.pdf',
  originalFilename: 'notes.pdf',
  kind: ChatUploadKind.attachment,
);

ChatMessage _message({
  int author = 1,
  String cooked = '<p>Hello from chat</p>',
  bool edited = false,
  List<ChatUpload> uploads = const [],
  List<ChatReaction> reactions = const [],
  ChatReplyTo? replyTo,
  ChatThreadPreview? thread,
}) => ChatMessage(
  id: 7,
  channelId: 9,
  author: ChatMessageAuthor(id: author, username: 'user$author'),
  raw: 'Hello from chat',
  cooked: cooked,
  createdAt: DateTime.utc(2026, 9, 11),
  edited: edited,
  uploads: uploads,
  reactions: reactions,
  replyTo: replyTo,
  thread: thread,
);

ChatChannel _channel({
  ChatChannelKind kind = ChatChannelKind.directMessage,
  bool group = false,
  ChatChannelStatus status = ChatChannelStatus.open,
  bool canDeleteSelf = false,
  bool canManagePins = false,
}) => ChatChannel(
  id: 9,
  title: 'Chat',
  kind: kind,
  isGroup: group,
  status: status,
  canDeleteSelf: canDeleteSelf,
  canManagePins: canManagePins,
  membership: const ChatMembership(following: true),
);

class _SiteIdentityApi extends FakeDiscourseApi {
  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => siteUrl == _site
      ? const DiscourseUser(id: 1, username: 'user1')
      : const DiscourseUser(id: 2, username: 'user2');
}

Future<ShellController> _controller(
  ChatMessage message, {
  ChatChannel? channel,
  bool putChannel = true,
}) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore(const [
      DiscourseInstance(
        url: _site,
        title: 'DMs',
        apiVersion: 4,
        user: DiscourseUser(id: 1, username: 'user1'),
      ),
      DiscourseInstance(
        url: _otherSite,
        title: 'Other',
        apiVersion: 4,
        user: DiscourseUser(id: 2, username: 'user2'),
      ),
    ]),
    api: _SiteIdentityApi(),
    authenticator: FakeAuthenticator()
      ..keys[_site] = 'local-key'
      ..keys[_otherSite] = 'other-local-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  await controller.load();
  for (final site in [_site, _otherSite]) {
    if (putChannel) controller.chatRecords.put(site, channel ?? _channel());
    controller.chatRecords.put(site, message);
  }
  addTearDown(controller.dispose);
  return controller;
}

Widget _tile(
  ShellController controller, {
  String site = _site,
  ThemeData? theme,
  TextDirection direction = TextDirection.ltr,
  double width = 720,
  double scale = 1,
  bool chained = false,
  bool endsGroup = true,
  bool selecting = false,
  bool selected = false,
  ValueChanged<bool>? onSelectedChanged,
  ValueChanged<ChatMessage>? onReply,
  ValueChanged<ChatMessage>? onEdit,
  VoidCallback? onSelect,
  ValueChanged<int>? onJump,
  ValueChanged<ChatThreadPreview>? onThread,
}) => ShellScope(
  controller: controller,
  child: PluginUiScope.own(
    chatPluginId,
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: Directionality(
                    textDirection: direction,
                    child: ChatMessageTile(
                      siteUrl: site,
                      messageId: 7,
                      chained: chained,
                      endsGroup: endsGroup,
                      selecting: selecting,
                      selected: selected,
                      onSelectedChanged: onSelectedChanged,
                      onJumpToMessage: onJump,
                      onOpenThread: onThread,
                      onReply: onReply ?? (_) {},
                      onEdit: onEdit,
                      onSelect: onSelect,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final group in [false, true]) {
    for (final outgoing in [false, true]) {
      for (final direction in TextDirection.values) {
        testWidgets('group=$group outgoing=$outgoing aligns in $direction', (
          tester,
        ) async {
          final controller = await _controller(
            _message(author: outgoing ? 1 : 2),
            channel: _channel(group: group),
          );
          await tester.pumpWidget(_tile(controller, direction: direction));
          await tester.pumpAndSettle();
          final bubble = tester.getRect(find.byType(DBubbleContent));
          final content = tester.getRect(find.byType(DMessageContent));
          final right = outgoing == (direction == TextDirection.ltr);
          expect(
            right ? bubble.right : bubble.left,
            closeTo(right ? content.right : content.left, .01),
          );
          if (group) {
            final avatar = tester.getRect(find.byType(ChatUserAvatar));
            expect(
              right ? avatar.left > bubble.right : avatar.right < bubble.left,
              isTrue,
            );
            expect(avatar.size, const Size.square(32));
          } else {
            expect(find.byType(ChatUserAvatar), findsNothing);
            expect(find.byType(DMessageAvatar), findsNothing);
            expect(find.text('user1'), findsNothing);
            expect(find.text('user2'), findsNothing);
            expect(content.width, tester.getSize(find.byType(DMessage)).width);
          }
          expect(
            find.byType(DMessageHeader),
            group && !outgoing ? findsOneWidget : findsNothing,
          );
          expect(
            tester.widget<DBubble>(find.byType(DBubble)).variant,
            outgoing ? DBubbleVariant.primary : DBubbleVariant.muted,
          );
          expect(bubble.width, lessThanOrEqualTo(content.width * .8));
        });
      }
    }
  }

  group('desktop DM dropdown', () {
    final trigger = find.byKey(const ValueKey('chat-message-more-actions-7'));
    double triggerOpacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find.ancestor(of: trigger, matching: find.byType(Opacity)).first,
        )
        .opacity;

    Future<TestGesture> hover(WidgetTester tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(_bodyKey)));
      await tester.pump();
      return mouse;
    }

    for (final group in [false, true]) {
      for (final outgoing in [false, true]) {
        for (final direction in TextDirection.values) {
          testWidgets(
            'group=$group outgoing=$outgoing trailing trigger in $direction',
            (tester) async {
              final controller = await _controller(
                _message(author: outgoing ? 1 : 2),
                channel: _channel(group: group),
              );
              int? replied;
              await tester.pumpWidget(
                _tile(
                  controller,
                  theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
                  direction: direction,
                  onReply: (message) => replied = message.id,
                ),
              );
              await tester.pumpAndSettle();
              expect(triggerOpacity(tester), 0);
              final bubble = tester.getRect(find.byType(DBubbleContent));
              final body = tester.element(
                find.byKey(ChatMessageTile.bodySelectionKey(7)),
              );
              final mouse = await hover(tester);
              expect(triggerOpacity(tester), 1);
              expect(find.byType(HoverActionToolbar), findsNothing);
              expect(find.byType(DButton), findsOneWidget);
              expect(tester.getRect(find.byType(DBubbleContent)), bubble);
              expect(
                tester.element(find.byKey(ChatMessageTile.bodySelectionKey(7))),
                same(body),
              );
              final control = tester.getRect(trigger);
              expect(bubble.contains(control.center), isTrue);
              expect(
                direction == TextDirection.ltr
                    ? control.center.dx > bubble.center.dx
                    : control.center.dx < bubble.center.dx,
                isTrue,
              );
              await tester.tap(trigger);
              await tester.pumpAndSettle();
              expect(find.byType(DDropdownMenuContent), findsOneWidget);
              expect(find.text('Reply'), findsOneWidget);
              expect(find.text('Add reaction'), findsOneWidget);
              expect(find.text('Bookmark'), findsOneWidget);
              await mouse.moveTo(const Offset(790, 590));
              await tester.pumpAndSettle();
              expect(find.text('Copy link'), findsOneWidget);
              await tester.tap(find.text('Reply'));
              await tester.pumpAndSettle();
              expect(replied, 7);
              expect(find.byType(DDropdownMenuContent), findsNothing);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    testWidgets(
      'keyboard opens the menu, Escape restores focus, and outside click closes it',
      (tester) async {
        final controller = await _controller(_message());
        await tester.pumpWidget(
          _tile(
            controller,
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.f10);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.widget<DButton>(trigger).focusNode!.hasFocus, isTrue);
        expect(triggerOpacity(tester), 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('Copy link'), findsOneWidget);
        await tester.tapAt(const Offset(790, 590));
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsNothing);
      },
    );

    testWidgets(
      'attachment-only messages have one accessible dropdown at narrow 200% RTL',
      (tester) async {
        final controller = await _controller(
          _message(cooked: '', uploads: [_upload]),
        );
        await tester.pumpWidget(
          _tile(
            controller,
            theme: StyleguideTheme.plum
                .resolve(AppTheme.dark)
                .copyWith(platform: TargetPlatform.macOS),
            width: 360,
            scale: 2,
            direction: TextDirection.rtl,
          ),
        );
        await tester.pumpAndSettle();
        await hover(tester);
        expect(find.byType(DBubble), findsNothing);
        expect(find.byType(DDropdownMenu), findsOneWidget);
        final semantics = tester.ensureSemantics();
        expect(find.bySemanticsLabel('More message actions'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('Open attachment: notes.pdf')),
          findsOneWidget,
        );
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsOneWidget);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );

    testWidgets(
      'permissions and editing callbacks stay live while the dropdown is open',
      (tester) async {
        final controller = await _controller(
          _message(),
          channel: _channel(canDeleteSelf: true, canManagePins: true),
        );
        int? edited;
        await tester.pumpWidget(
          _tile(
            controller,
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            onEdit: (message) => edited = message.id,
            onSelect: () {},
          ),
        );
        await tester.pumpAndSettle();
        await hover(tester);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        expect(find.text('Pin'), findsOneWidget);
        expect(find.text('Select'), findsOneWidget);
        expect(
          tester
              .widget<DDropdownMenuItem>(
                find.widgetWithText(DDropdownMenuItem, 'Delete'),
              )
              .variant,
          DDropdownMenuItemVariant.destructive,
        );
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        expect(edited, 7);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        controller.chatRecords.put(
          _site,
          _channel(status: ChatChannelStatus.readOnly),
        );
        await tester.pumpAndSettle();
        for (final label in [
          'Reply',
          'Add reaction',
          'Bookmark',
          'Pin',
          'Edit',
          'Delete',
        ]) {
          expect(find.text(label), findsNothing);
        }
        expect(find.text('Copy link'), findsOneWidget);
        expect(find.text('Select'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'scrolling closes the dropdown and hides its trigger until pointer movement',
      (tester) async {
        final controller = await _controller(
          _message(
            cooked: '<p>${List.filled(150, 'Long message').join(' ')}</p>',
          ),
        );
        await tester.pumpWidget(
          _tile(
            controller,
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            width: 360,
          ),
        );
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(40, 40));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(trigger));
        await tester.pump();
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        scroll.jumpTo(20);
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(triggerOpacity(tester), 0);
        await mouse.moveBy(const Offset(1, 0));
        await tester.pumpAndSettle();
        expect(triggerOpacity(tester), 1);
      },
    );
  });

  testWidgets('category channels retain the compact unboxed presentation', (
    tester,
  ) async {
    final controller = await _controller(
      _message(),
      channel: _channel(kind: ChatChannelKind.category),
    );
    await tester.pumpWidget(_tile(controller));
    await tester.pumpAndSettle();
    expect(find.byType(DBubble), findsNothing);
    expect(tester.getSize(find.byType(ChatUserAvatar)), const Size.square(28));
    expect(
      tester.widget<DMessage>(find.byType(DMessage)).avatarAlignment,
      DMessageAvatarAlignment.top,
    );
  });

  testWidgets('unknown channel updates to DM styling when its record arrives', (
    tester,
  ) async {
    final controller = await _controller(
      _message(author: 2),
      putChannel: false,
    );
    await tester.pumpWidget(_tile(controller));
    await tester.pumpAndSettle();
    expect(find.byType(DBubble), findsNothing);
    controller.chatRecords.put(_site, _channel());
    await tester.pumpAndSettle();
    expect(find.byType(DBubble), findsOneWidget);
    expect(find.byType(DMessageAvatar), findsNothing);
    expect(find.byType(DMessageHeader), findsNothing);
    controller.chatRecords.put(_site, _channel(group: true));
    await tester.pumpAndSettle();
    expect(find.byType(ChatUserAvatar), findsOneWidget);
    expect(find.text('user2'), findsOneWidget);
    controller.chatRecords.put(_site, _channel(kind: ChatChannelKind.category));
    await tester.pumpAndSettle();
    expect(find.byType(DBubble), findsNothing);
  });

  testWidgets('ownership comes from the message site', (tester) async {
    final controller = await _controller(_message(author: 2));
    await tester.pumpWidget(_tile(controller, site: _otherSite));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DMessage>(find.byType(DMessage)).align,
      DMessageAlign.end,
    );
    await tester.pumpWidget(_tile(controller));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DMessage>(find.byType(DMessage)).align,
      DMessageAlign.start,
    );
  });

  testWidgets(
    'intermediate messages retain edited, reaction and failed-send metadata',
    (tester) async {
      final controller = await _controller(
        _message(
          edited: true,
          reactions: const [ChatReaction(emoji: 'heart', count: 2)],
        ).withSendState(delivery: ChatMessageDelivery.failed, error: 'Offline'),
        channel: _channel(group: true),
      );
      await tester.pumpWidget(_tile(controller, endsGroup: false));
      await tester.pumpAndSettle();
      expect(find.byKey(ChatMessageTile.timestampKey(7)), findsNothing);
      expect(find.byType(ChatUserAvatar), findsNothing);
      expect(find.text('(edited)'), findsOneWidget);
      expect(find.text('Failed to send: Offline'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-reaction-pill-7-heart')),
        findsOneWidget,
      );
      await tester.pumpWidget(_tile(controller, chained: true));
      await tester.pumpAndSettle();
      expect(find.byKey(ChatMessageTile.timestampKey(7)), findsOneWidget);
      expect(find.byType(ChatUserAvatar), findsOneWidget);
    },
  );

  testWidgets('chaining keeps the bubble edge and body selection identity', (
    tester,
  ) async {
    final controller = await _controller(
      _message(author: 2, edited: true),
      channel: _channel(group: true),
    );
    await tester.pumpWidget(_tile(controller));
    await tester.pumpAndSettle();
    final left = tester.getTopLeft(find.byType(DBubbleContent)).dx;
    final selection = tester.element(
      find.byKey(ChatMessageTile.bodySelectionKey(7)),
    );
    await tester.pumpWidget(_tile(controller, chained: true, endsGroup: false));
    await tester.pumpAndSettle();
    expect(find.byType(ChatUserAvatar), findsNothing);
    expect(find.byType(DMessageHeader), findsNothing);
    expect(tester.getTopLeft(find.byType(DBubbleContent)).dx, left);
    expect(
      tester.element(find.byKey(ChatMessageTile.bodySelectionKey(7))),
      same(selection),
    );
    expect(find.text('(edited)'), findsOneWidget);
  });

  for (final projected in [false, true]) {
    testWidgets(
      'pending ${projected ? 'preview' : 'fallback'} becomes canonical without changing sides',
      (tester) async {
        final message = ChatMessage(
          id: 7,
          channelId: 9,
          cooked: '',
          author: const ChatMessageAuthor(id: 1, username: 'user1'),
          optimisticRaw: 'Draft',
          canonicalReceived: false,
          delivery: ChatMessageDelivery.sending,
          preview: projected
              ? ProjectedPreview(
                  PreviewDocument('Draft', [
                    ChatPreviewText(
                      range: const SourceRange(0, 5),
                      text: 'Draft',
                    ),
                  ]),
                )
              : null,
        );
        final controller = await _controller(message);
        await tester.pumpWidget(_tile(controller));
        await tester.pumpAndSettle();
        expect(find.text('Draft'), findsOneWidget);
        expect(find.text('Sending'), findsOneWidget);
        final body = tester.element(
          find.byKey(ChatMessageTile.bodySelectionKey(7)),
        );
        controller.chatRecords.put(_site, _message(cooked: '<p>Canonical</p>'));
        await tester.pumpAndSettle();
        expect(find.text('Sending'), findsNothing);
        expect(
          tester.widget<CookedHtml>(find.byType(CookedHtml)).html,
          '<p>Canonical</p>',
        );
        expect(
          tester.widget<DMessage>(find.byType(DMessage)).align,
          DMessageAlign.end,
        );
        expect(
          tester.element(find.byKey(ChatMessageTile.bodySelectionKey(7))),
          same(body),
        );
        expect(find.text('Delivered'), findsNothing);
      },
    );
  }

  testWidgets(
    'failed sends announce the error and attachment-only messages have no empty bubble',
    (tester) async {
      final controller = await _controller(
        _message(
          cooked: '',
          uploads: [_upload],
        ).withSendState(delivery: ChatMessageDelivery.failed, error: 'Offline'),
      );
      await tester.pumpWidget(_tile(controller));
      await tester.pumpAndSettle();
      expect(find.text('Failed to send: Offline'), findsOneWidget);
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(find.byType(DBubble), findsNothing);
      final file = tester.getRect(find.byType(DAttachment));
      final content = tester.getRect(find.byType(DMessageContent));
      expect(file.right, closeTo(content.right, .01));
    },
  );

  testWidgets('pending attachment-only previews omit the empty bubble', (
    tester,
  ) async {
    final controller = await _controller(
      ChatMessage(
        id: 7,
        channelId: 9,
        cooked: '',
        optimisticRaw: '',
        author: const ChatMessageAuthor(id: 1, username: 'user1'),
        canonicalReceived: false,
        delivery: ChatMessageDelivery.sending,
        preview: ProjectedPreview(PreviewDocument('', const [])),
        uploads: const [_upload],
      ),
    );
    await tester.pumpWidget(_tile(controller));
    await tester.pumpAndSettle();
    expect(find.byType(DBubble), findsNothing);
    expect(find.text('notes.pdf'), findsOneWidget);
    expect(find.text('Sending'), findsOneWidget);
  });

  for (final palette in [
    AppTheme.light,
    AppTheme.dark,
    StyleguideTheme.plum.resolve(AppTheme.light),
  ]) {
    testWidgets(
      'rich content inherits bubble colors for palette ${palette.colorScheme.primary}',
      (tester) async {
        final controller = await _controller(
          _message(
            cooked:
                '<p>Hello <strong>friend</strong> <a href="/t/7">link</a></p>',
          ),
        );
        await tester.pumpWidget(_tile(controller, theme: palette));
        await tester.pumpAndSettle();
        final tokens = DTokens.of(tester.element(find.byType(DBubbleContent)));
        final html = tester.widget<CookedHtml>(find.byType(CookedHtml));
        expect(html.textStyle!.color, tokens.primaryForeground);
        expect(html.textStyle!.fontSize, 14);
        expect(html.linkStyle!.color, tokens.primaryForeground);
        expect(html.linkStyle!.decoration, TextDecoration.underline);
        expect(html.textStyle!.color, isNot(tokens.primary));
      },
    );
  }

  testWidgets(
    'narrow scaled RTL messages retain wrapping controls and callbacks',
    (tester) async {
      final message = _message(
        author: 2,
        edited: true,
        uploads: [_upload],
        cooked:
            '<p>A long message with <strong>formatting</strong> and several words to wrap.</p><pre><code>print(42);</code></pre>',
        reactions: const [
          ChatReaction(emoji: 'thumbsup', count: 12),
          ChatReaction(emoji: 'heart', count: 3),
        ],
        replyTo: const ChatReplyTo(
          id: 3,
          userId: 1,
          username: 'user1',
          excerpt: 'Earlier message',
        ),
        thread: const ChatThreadPreview(
          threadId: 4,
          replyCount: 3,
          participantCount: 2,
          lastReplyExcerpt: 'A reply',
        ),
      );
      final controller = await _controller(message);
      int? jumped;
      int? opened;
      await tester.pumpWidget(
        _tile(
          controller,
          width: 360,
          scale: 2,
          direction: TextDirection.rtl,
          onJump: (id) => jumped = id,
          onThread: (thread) => opened = thread.threadId,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(ChatMessageTile.replyIndicatorKey(3)),
      );
      await tester.tap(find.byKey(ChatMessageTile.replyIndicatorKey(3)));
      await tester.pumpAndSettle();
      expect(jumped, 3);
      await tester.ensureVisible(
        find.byKey(ChatMessageTile.threadPreviewKey(4)),
      );
      await tester.tap(find.byKey(ChatMessageTile.threadPreviewKey(4)));
      await tester.pumpAndSettle();
      expect(opened, 4);
      expect(
        find.byKey(const ValueKey('chat-reaction-pill-7-thumbsup')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selection and keyboard message actions remain usable in DMs', (
    tester,
  ) async {
    final controller = await _controller(_message());
    bool? selected;
    await tester.pumpWidget(
      _tile(
        controller,
        selecting: true,
        onSelectedChanged: (value) => selected = value,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DCheckbox));
    expect(selected, isTrue);
    await tester.pumpWidget(_tile(controller));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Copy link'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Copy link'), findsNothing);
  });

  testWidgets('touch long press still opens DM actions', (tester) async {
    final controller = await _controller(_message());
    await tester.pumpWidget(
      _tile(
        controller,
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPressAt(
      tester.getTopLeft(find.byKey(_bodyKey)) + const Offset(4, 4),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy link'), findsOneWidget);
  });
}
