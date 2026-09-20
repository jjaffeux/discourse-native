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
import 'package:discourse_native/src/plugins/local_dates/local_date_widget.dart';
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
      theme: theme ?? AppTheme.light.copyWith(platform: TargetPlatform.macOS),
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
  for (final kind in ChatChannelKind.values) {
    testWidgets('provisional HTML uses canonical rendering in $kind', (
      tester,
    ) async {
      const html =
          '<p><strong>Local</strong> '
          '<span class="discourse-local-date" data-date="2026-09-19" '
          'data-time="12:00:00" data-timezone="Etc/UTC" '
          'data-format="YYYY-MM-DD">Date fallback</span></p>';
      final pending = _message()
          .withPendingEdit(
            'Raw fallback',
            const SourceFallback(
              'Raw fallback',
              ChatPreviewFallbackReason.unsupportedSyntax,
            ),
          )
          .withProvisionalCooked(html);
      final controller = await _controller(
        pending,
        channel: _channel(kind: kind),
      );
      await tester.pumpWidget(_tile(controller));
      await tester.pumpAndSettle();

      final provisional = tester.widget<CookedHtml>(find.byType(CookedHtml));
      expect(provisional.html, html);
      expect(provisional.siteUrl, _site);
      expect(provisional.compactParagraphs, isTrue);
      expect(provisional.contentSized, isTrue);
      expect(find.text('Raw fallback'), findsNothing);
      expect(find.byType(LocalDateInline), findsOneWidget);
      expect(
        tester.widget<LocalDateInline>(find.byType(LocalDateInline)).siteUrl,
        _site,
      );
      final body = tester.element(
        find.byKey(ChatMessageTile.bodySelectionKey(7)),
      );

      controller.chatRecords.put(
        _site,
        pending.withCanonical(_message(cooked: html)),
      );
      await tester.pumpAndSettle();
      final canonical = tester.widget<CookedHtml>(find.byType(CookedHtml));
      expect(canonical.textStyle, provisional.textStyle);
      expect(canonical.linkStyle, provisional.linkStyle);
      expect(canonical.contentSized, provisional.contentSized);
      expect(
        tester.element(find.byKey(ChatMessageTile.bodySelectionKey(7))),
        same(body),
      );
      expect(find.byType(LocalDateInline), findsOneWidget);

      controller.chatRecords.put(
        _site,
        pending.withCanonical(_message(cooked: '')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CookedHtml), findsNothing);
      expect(find.byType(LocalDateInline), findsNothing);
      expect(find.text('Raw fallback'), findsNothing);
      expect(find.byType(DBubble), findsNothing);
    });

    for (final projected in [false, true]) {
      testWidgets(
        'empty provisional suppresses ${projected ? 'preview' : 'raw'} in $kind',
        (tester) async {
          final pending = _message()
              .withPendingEdit(
                'Raw fallback',
                projected
                    ? ProjectedPreview(
                        PreviewDocument('Legacy preview', [
                          ChatPreviewText(
                            range: const SourceRange(0, 14),
                            text: 'Legacy preview',
                          ),
                        ]),
                      )
                    : const SourceFallback(
                        'Raw fallback',
                        ChatPreviewFallbackReason.unsupportedSyntax,
                      ),
                uploads: const [_upload],
              )
              .withProvisionalCooked('');
          final controller = await _controller(
            pending,
            channel: _channel(kind: kind),
          );
          await tester.pumpWidget(_tile(controller));
          await tester.pumpAndSettle();
          expect(find.byType(CookedHtml), findsNothing);
          expect(find.text('Raw fallback'), findsNothing);
          expect(find.text('Legacy preview'), findsNothing);
          expect(find.byType(DBubble), findsOneWidget);
          expect(find.text('notes.pdf'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

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
          final avatar = tester.getRect(find.byType(ChatUserAvatar));
          expect(
            right ? avatar.left > bubble.right : avatar.right < bubble.left,
            isTrue,
          );
          expect(avatar.size, const Size.square(28));
          expect(avatar.bottom, closeTo(bubble.bottom, .01));
          expect(find.byType(DMessageHeader), findsOneWidget);
          expect(find.text(outgoing ? 'you' : 'user2'), findsOneWidget);
          expect(
            tester.widget<DBubble>(find.byType(DBubble)).variant,
            outgoing ? DBubbleVariant.accent : DBubbleVariant.neutral,
          );
          expect(bubble.width, lessThanOrEqualTo(content.width * .88));
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
              expect(find.byType(DButton), findsNWidgets(2));
              expect(tester.getRect(find.byType(DBubbleContent)), bubble);
              expect(
                tester.element(find.byKey(ChatMessageTile.bodySelectionKey(7))),
                same(body),
              );
              final reaction = find.byKey(
                const ValueKey('chat-message-react-7'),
              );
              final reactionRect = tester.getRect(reaction);
              final onRight = outgoing == (direction == TextDirection.ltr);
              expect(
                onRight
                    ? reactionRect.right <= bubble.left
                    : reactionRect.left >= bubble.right,
                isTrue,
              );
              await mouse.moveTo(reactionRect.center);
              await tester.pump();
              expect(reaction.hitTestable(), findsOneWidget);
              final control = tester.getRect(trigger);
              expect(bubble.contains(control.topLeft), isTrue);
              expect(bubble.contains(control.bottomRight), isTrue);
              expect(control.top, closeTo(bubble.top + 9, .01));
              expect(
                direction == TextDirection.ltr ? control.right : control.left,
                closeTo(
                  direction == TextDirection.ltr
                      ? bubble.right - 13
                      : bubble.left + 13,
                  .01,
                ),
              );
              expect(reactionRect.center.dy, closeTo(bubble.center.dy, .01));
              await tester.tap(trigger);
              await tester.pumpAndSettle();
              expect(find.byType(DDropdownMenuContent), findsOneWidget);
              expect(find.text('Reply'), findsOneWidget);
              expect(
                find.widgetWithText(DDropdownMenuItem, 'React'),
                findsOneWidget,
              );
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
        expect(find.byKey(ChatMessageTile.timestampKey(7)), findsOneWidget);
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
        expect(find.byType(DBubble), findsOneWidget);
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
        expect(find.byType(DDropdownMenuSeparator), findsOneWidget);
        final edit = tester.getRect(
          find.widgetWithText(DDropdownMenuItem, 'Edit'),
        );
        final delete = tester.getRect(
          find.widgetWithText(DDropdownMenuItem, 'Delete'),
        );
        final select = tester.getRect(
          find.widgetWithText(DDropdownMenuItem, 'Select'),
        );
        expect(delete.top, edit.bottom);
        expect(select.top, delete.bottom);
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
          'React',
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
        await Scrollable.ensureVisible(tester.element(trigger), alignment: .5);
        await tester.pumpAndSettle();
        await mouse.moveTo(tester.getCenter(trigger));
        await tester.pump();
        Color background() => tester
            .widget<ColoredBox>(
              find
                  .descendant(
                    of: find.byType(DMessageSurface),
                    matching: find.byType(ColoredBox),
                  )
                  .first,
            )
            .color;
        final hoverTint = DTokens.of(
          tester.element(find.byType(DMessageSurface)),
        ).foreground.withValues(alpha: .03);
        expect(background(), hoverTint);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        scroll.jumpTo(scroll.pixels + 20);
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(triggerOpacity(tester), 0);
        expect(background(), Colors.transparent);
        await mouse.moveBy(const Offset(1, 0));
        await tester.pumpAndSettle();
        expect(triggerOpacity(tester), 1);
        expect(background(), hoverTint);
      },
    );
  });

  for (final kind in ChatChannelKind.values) {
    testWidgets('$kind uses the shared conversation presentation', (
      tester,
    ) async {
      final controller = await _controller(
        _message(),
        channel: _channel(kind: kind),
      );
      await tester.pumpWidget(_tile(controller));
      await tester.pumpAndSettle();
      expect(find.byType(DBubble), findsOneWidget);
      expect(
        tester.getSize(find.byType(ChatUserAvatar)),
        const Size.square(28),
      );
      expect(
        tester.widget<DMessage>(find.byType(DMessage)).align,
        DMessageAlign.end,
      );
      expect(find.text('you'), findsOneWidget);
    });
  }

  testWidgets(
    'channel metadata changes preserve bubble and selection identity',
    (tester) async {
      final controller = await _controller(
        _message(author: 2),
        putChannel: false,
      );
      await tester.pumpWidget(_tile(controller));
      await tester.pumpAndSettle();
      final body = tester.element(
        find.byKey(ChatMessageTile.bodySelectionKey(7)),
      );
      for (final channel in [
        _channel(),
        _channel(group: true),
        _channel(kind: ChatChannelKind.category),
      ]) {
        controller.chatRecords.put(_site, channel);
        await tester.pumpAndSettle();
        expect(find.byType(DBubble), findsOneWidget);
        expect(find.byType(ChatUserAvatar), findsOneWidget);
        expect(find.text('user2'), findsOneWidget);
        expect(
          tester.element(find.byKey(ChatMessageTile.bodySelectionKey(7))),
          same(body),
        );
      }
    },
  );

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
      expect(find.byType(ChatUserAvatar), findsOneWidget);
      expect(find.text('(edited)'), findsOneWidget);
      expect(find.text('Failed to send: Offline'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-reaction-pill-7-heart')),
        findsOneWidget,
      );
      await tester.pumpWidget(_tile(controller, chained: true));
      await tester.pumpAndSettle();
      expect(find.byKey(ChatMessageTile.timestampKey(7)), findsNothing);
      expect(find.byType(ChatUserAvatar), findsNothing);
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

  for (final width in [240.0, 720.0]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'pending DM keeps its bubble size after confirmation at $width in $direction',
        (tester) async {
          final controller = await _controller(
            const ChatMessage(
              id: 7,
              channelId: 9,
              stagedId: 'pending-7',
              cooked: '',
              author: ChatMessageAuthor(id: 1, username: 'user1'),
              optimisticRaw: 'azdz adzaldzlkjzalk',
              canonicalReceived: false,
              delivery: ChatMessageDelivery.sending,
            ),
          );
          await tester.pumpWidget(
            _tile(
              controller,
              width: width,
              direction: direction,
              theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
            ),
          );
          await tester.pumpAndSettle();
          final pending = tester.getRect(find.byType(DBubbleContent));
          controller.chatRecords.put(
            _site,
            _message(cooked: '<p>azdz adzaldzlkjzalk</p>'),
          );
          await tester.pumpAndSettle();
          final confirmed = tester.getRect(find.byType(DBubbleContent));
          expect(confirmed.width, closeTo(pending.width, .01));
          expect(confirmed.height, closeTo(pending.height, .01));
          expect(confirmed.right, closeTo(pending.right, .01));
        },
      );
    }
  }

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
        expect(find.text('Sending'), findsNothing);
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
    'failed attachment messages announce errors and retain a single surface',
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
      expect(find.byType(DBubble), findsOneWidget);
      final file = tester.getRect(find.byType(DAttachment));
      final bubble = tester.getRect(find.byType(DBubbleContent));
      expect(bubble.contains(file.topLeft), isTrue);
      expect(bubble.contains(file.bottomRight), isTrue);
    },
  );

  testWidgets('pending attachment-only previews retain one message surface', (
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
    expect(find.byType(DBubble), findsOneWidget);
    expect(find.text('notes.pdf'), findsOneWidget);
    expect(find.text('Sending'), findsNothing);
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
        expect(html.textStyle!.color, tokens.buttonTheme.primary.foreground);
        expect(html.textStyle!.fontSize, 13.5);
        expect(html.linkStyle!.color, tokens.buttonTheme.primary.foreground);
        expect(html.linkStyle!.decoration, TextDecoration.underline);
        expect(html.linkStyle!.fontWeight, FontWeight.w500);
        expect(
          html.linkStyle!.decorationColor,
          tokens.buttonTheme.primary.foreground,
        );
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

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final kind in ChatChannelKind.values) {
      testWidgets('reaction row launcher for $kind on $platform', (
        tester,
      ) async {
        final controller = await _controller(
          _message(reactions: const [ChatReaction(emoji: 'heart', count: 2)]),
          channel: _channel(kind: kind),
        );
        await tester.pumpWidget(
          _tile(controller, theme: AppTheme.light.copyWith(platform: platform)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('chat-reaction-pill-7-heart')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('chat-reaction-picker-7')),
          findsNothing,
        );
      });
    }
  }

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
    expect(find.text('React'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-message-react-7')), findsNothing);
    expect(find.byType(DSheetContent), findsOneWidget);
  });
}
