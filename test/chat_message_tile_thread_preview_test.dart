import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_bookmark.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_avatar.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/emoji_picker.dart';
import 'package:discourse_native/src/shell/hover_action_toolbar.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _messageTileKey = ValueKey('message-tile');
const _replyInThreadAction = CustomSemanticsAction(label: 'Reply in thread');
const _copyLinkAction = CustomSemanticsAction(label: 'Copy link');

void main() {
  testWidgets(
    'direct-reply indicator matches core and jumps to the referenced message',
    (tester) async {
      const reply = ChatReplyTo(
        id: 6,
        userId: 10,
        excerpt: 'The earlier message',
        username: 'kris',
      );
      final controller = await _controller(_message(null, replyTo: reply));
      final jumped = <int>[];
      addTearDown(controller.dispose);

      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _TestTile(
            controller: controller,
            onOpenThread: (_) {},
            onJumpToMessage: jumped.add,
          ),
        );
        await tester.pumpAndSettle();

        final target = find.byKey(ChatMessageTile.replyIndicatorKey(reply.id));
        expect(target, findsOneWidget);
        expect(tester.getSize(target).height, 20);
        expect(
          tester.widget<InkWell>(target).mouseCursor,
          SystemMouseCursors.click,
        );

        final iconFinder = find.descendant(
          of: target,
          matching: find.byType(DIcon),
        );
        final icon = tester.widget<DIcon>(iconFinder);
        expect(icon.icon, DIcons.share);
        expect(icon.size, DiscourseTypography.fontDown1);
        expect(
          icon.color,
          Theme.of(tester.element(target)).discourse.primaryLowMid,
        );

        final avatarFinder = find.descendant(
          of: target,
          matching: find.byType(ChatUserAvatar),
        );
        final avatar = tester.widget<ChatUserAvatar>(avatarFinder);
        expect(avatar.size, 20);
        expect(
          tester.getTopLeft(avatarFinder).dx -
              tester.getTopRight(iconFinder).dx,
          8,
        );

        final excerpt = tester.widget<Text>(find.text(reply.excerpt));
        final theme = Theme.of(tester.element(target));
        expect(excerpt.style?.fontSize, DiscourseTypography.fontDown1);
        expect(excerpt.style?.color, theme.discourse.primaryHigh);
        expect(
          tester.getSemantics(
            find.bySemanticsLabel(
              'Jump to message from @kris: The earlier message',
            ),
          ),
          isSemantics(isLink: true, hasTapAction: true),
        );

        await tester.tap(target);
        await tester.pump();
        expect(jumped, [reply.id]);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('draws emoji in a direct-reply excerpt', (tester) async {
    EmojiCache.instance = EmojiCache(
      client: MockClient((_) async => http.Response.bytes(_emojiPng, 200)),
    );
    addTearDown(EmojiCache.instance.clear);
    const reply = ChatReplyTo(
      id: 6,
      userId: 10,
      excerpt: 'You testing the new app? :rofl:',
      username: 'kris',
    );
    final controller = await _controller(
      _message(null, replyTo: reply),
      api: FakeDiscourseApi(
        emojisBySite: {
          _siteUrl: const [
            SiteEmoji(name: 'rofl', url: '/images/emoji/twitter/rofl.png'),
          ],
        },
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(
        controller: controller,
        onOpenThread: (_) {},
        onJumpToMessage: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    final target = find.byKey(ChatMessageTile.replyIndicatorKey(reply.id));
    final emoji = tester.widget<SiteEmojiImage>(
      find.descendant(of: target, matching: find.byType(SiteEmojiImage)),
    );
    expect(emoji.name, 'rofl');
    expect(
      tester
          .widget<EmojiImage>(
            find.descendant(of: target, matching: find.byType(EmojiImage)),
          )
          .url,
      'https://meta.example/images/emoji/twitter/rofl.png',
    );
    expect(find.descendant(of: target, matching: find.byType(Image)), findsOne);
    expect(
      find.bySemanticsLabel(
        'Jump to message from @kris: You testing the new app? :rofl:',
      ),
      findsOneWidget,
    );
  });

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

  testWidgets('draws emoji in the latest reply excerpt', (tester) async {
    EmojiCache.instance = EmojiCache(
      client: MockClient((_) async => http.Response.bytes(_emojiPng, 200)),
    );
    addTearDown(EmojiCache.instance.clear);
    final thread = _thread(lastReplyExcerpt: 'That works :stuck_out_tongue:');
    final controller = await _controller(
      _message(thread),
      api: FakeDiscourseApi(
        emojisBySite: {
          _siteUrl: const [
            SiteEmoji(
              name: 'stuck_out_tongue',
              url: '/images/emoji/twitter/stuck_out_tongue.png',
            ),
          ],
        },
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();

    final emoji = tester.widget<SiteEmojiImage>(find.byType(SiteEmojiImage));
    expect(emoji.name, 'stuck_out_tongue');
    expect(
      tester.widget<EmojiImage>(find.byType(EmojiImage)).url,
      'https://meta.example/images/emoji/twitter/stuck_out_tongue.png',
    );
    expect(find.byType(Image), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(r'Latest reply from Kris, now: That works :stuck_out_tongue:'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('author avatar only uses the hand cursor under a pointer', (
    tester,
  ) async {
    final controller = await _controller(
      _message(null, authorUsername: 'root'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();

    final avatar = find.byType(ChatUserAvatar);
    final ink = tester.widget<InkWell>(
      find.ancestor(of: avatar, matching: find.byType(InkWell)).first,
    );

    expect(ink.mouseCursor, SystemMouseCursors.click);
    expect(ink.hoverColor, Colors.transparent);
    expect(ink.highlightColor, Colors.transparent);
    expect(ink.splashColor, Colors.transparent);
  });

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
        // Canonical messages now own a keyboard-focusable action surface for
        // Copy link before focus advances into the embedded thread card.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.getSemantics(
            find.byKey(ChatMessageTile.actionsKey(_message(null).id)),
          ),
          isSemantics(isFocusable: true, isFocused: true),
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

  for (final chained in [false, true]) {
    testWidgets(
      'shows the edited marker after the ${chained ? 'chained' : 'regular'} message body',
      (tester) async {
        final message = _message(null, edited: true);
        final controller = await _controller(message);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _TestTile(
            controller: controller,
            onOpenThread: (_) {},
            chained: chained,
          ),
        );
        await tester.pumpAndSettle();

        final marker = find.byKey(
          ChatMessageTile.editedIndicatorKey(message.id),
        );
        final text = tester.widget<Text>(marker);
        final theme = Theme.of(tester.element(marker));

        expect(text.data, '(edited)');
        expect(text.style?.fontSize, DiscourseTypography.fontDown2);
        expect(text.style?.color, theme.discourse.whisper);
        expect(
          tester.getTopLeft(marker).dy,
          greaterThanOrEqualTo(
            tester.getBottomLeft(find.byType(CookedHtml)).dy,
          ),
        );
      },
    );
  }

  testWidgets('selects and copies rendered chat message text', (tester) async {
    final message = _message(null);
    final controller = await _controller(message);
    final copied = _watchClipboard(tester);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();

    final selection = find.byKey(ChatMessageTile.bodySelectionKey(message.id));
    expect(selection, findsOneWidget);

    final region = tester.state<SelectionAreaState>(selection).selectableRegion;
    region.selectAll(SelectionChangedCause.toolbar);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copied, ['Root message']);
  });

  testWidgets('a touch long press selects the rendered message body', (
    tester,
  ) async {
    final message = _message(null);
    final controller = await _controller(message);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(
        controller: controller,
        onOpenThread: (_) {},
        platform: TargetPlatform.android,
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(CookedHtml));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Message actions'), findsNothing);
  });

  testWidgets('does not show an edited marker for an unedited message', (
    tester,
  ) async {
    final message = _message(null);
    final controller = await _controller(message);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ChatMessageTile.editedIndicatorKey(message.id)),
      findsNothing,
    );
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

    controller.chatRecords.put(
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

  testWidgets(
    'hover toolbar adds the first reaction through the emoji picker',
    (tester) async {
      final api = FakeDiscourseApi(
        emojisBySite: const {
          _siteUrl: [
            SiteEmoji(
              name: 'wave',
              url: 'https://meta.example/images/emoji/wave.png',
            ),
          ],
        },
      );
      final controller = await _controller(_message(null), api: api);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _TestTile(controller: controller, onOpenThread: (_) {}),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReactionPickerButton), findsNothing);
      await _hoverMessage(tester);

      final action = find.byTooltip('Add reaction');
      expect(action, findsOneWidget);
      expect(tester.getSize(action), HoverActionButton.size);
      expect(
        tester
            .widget<DIcon>(
              find.descendant(of: action, matching: find.byType(DIcon)),
            )
            .icon,
        DIcons.farFaceSmile,
      );

      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.byType(EmojiPicker), findsOneWidget);
      await tester.tap(find.byTooltip(':wave:'));
      await tester.pumpAndSettle();

      expect(api.chatReactionsSet, hasLength(1));
      expect(api.chatReactionsSet.single.channelId, 9);
      expect(api.chatReactionsSet.single.messageId, 7);
      expect(api.chatReactionsSet.single.emoji, 'wave');
      expect(api.chatReactionsSet.single.action, ChatReactionAction.add);
      expect(find.bySemanticsLabel('1 wave reaction'), findsOneWidget);
    },
  );

  testWidgets('hover shows a compact action for the exact message', (
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
    expect(tester.getSize(action), HoverActionButton.size);
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

  testWidgets('hover matches core primary and secondary message actions', (
    tester,
  ) async {
    final controller = await _controller(_message(null), signedIn: true);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(
        controller: controller,
        onOpenThread: (_) {},
        onReplyInThread: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    await _hoverMessage(tester);

    final toolbar = find.byType(HoverActionToolbar);
    expect(
      tester
          .widgetList<HoverActionButton>(
            find.descendant(
              of: toolbar,
              matching: find.byType(HoverActionButton),
            ),
          )
          .map((button) => button.tooltip),
      ['Add reaction', 'Bookmark', 'Reply in thread', 'More message actions'],
    );
    expect(
      tester.getSize(toolbar),
      const Size(HoverActionButton.width * 4, HoverActionButton.height),
    );
    expect(find.byTooltip('Copy link'), findsNothing);

    final more = find.byTooltip('More message actions');
    expect(
      tester
          .widget<DIcon>(
            find.descendant(of: more, matching: find.byType(DIcon)),
          )
          .icon,
      DIcons.ellipsisVertical,
    );
    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(MenuItemButton, 'Copy link'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'Bookmark'), findsNothing);
    expect(
      find.widgetWithText(MenuItemButton, 'Reply in thread'),
      findsNothing,
    );
  });

  testWidgets('the secondary action menu stays open after mouseleave', (
    tester,
  ) async {
    final controller = await _controller(_message(null));
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(_messageTileKey)));
    await tester.pump();
    await tester.tap(find.byTooltip('More message actions'));
    await tester.pumpAndSettle();

    await mouse.moveTo(Offset.zero);
    await tester.pump();

    expect(find.byType(HoverActionToolbar), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'Copy link'), findsOneWidget);
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

  testWidgets('copies the canonical channel message link', (tester) async {
    final controller = await _controller(_message(null));
    final copied = _watchClipboard(tester);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();
    await _hoverMessage(tester);

    expect(find.byTooltip('Copy link'), findsNothing);
    final more = find.byTooltip('More message actions');
    expect(tester.getSize(more), HoverActionButton.size);
    await tester.tap(more);
    await tester.pumpAndSettle();

    final action = find.widgetWithText(MenuItemButton, 'Copy link');
    expect(action, findsOneWidget);

    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(copied, ['https://meta.example/chat/c/-/9/7']);
    expect(find.text('Link copied!'), findsOneWidget);
  });

  testWidgets('copies a thread-shaped link in thread context', (tester) async {
    final controller = await _controller(_message(null, threadId: 3));
    final copied = _watchClipboard(tester);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(
        controller: controller,
        onOpenThread: (_) {},
        contextThreadId: 3,
        platform: TargetPlatform.android,
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(_messageTileKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();

    expect(copied, ['https://meta.example/chat/c/-/9/t/3/7']);
    expect(find.text('Link copied!'), findsOneWidget);
  });

  testWidgets('copies source message text from the mobile action sheet', (
    tester,
  ) async {
    final controller = await _controller(_message(null, raw: '**source**'));
    final copied = _watchClipboard(tester);
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
    expect(find.text('Copy text'), findsOneWidget);
    await tester.tap(find.text('Copy text'));
    await tester.pumpAndSettle();

    expect(copied, ['**source**']);
    expect(find.text('Message copied!'), findsOneWidget);
  });

  testWidgets('exposes Copy link as a custom semantics action', (tester) async {
    final controller = await _controller(_message(null));
    final copied = _watchClipboard(tester);
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _TestTile(controller: controller, onOpenThread: (_) {}),
      );
      await tester.pumpAndSettle();

      final owner = _copyLinkSemanticsOwner();
      expect(owner, findsOneWidget);
      tester
          .widget<Semantics>(owner)
          .properties
          .customSemanticsActions![_copyLinkAction]!();
      await tester.pumpAndSettle();

      expect(copied, ['https://meta.example/chat/c/-/9/7']);
    } finally {
      semantics.dispose();
    }
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
    expect(tester.getSize(action), HoverActionButton.size);

    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(api.createdBookmarks, hasLength(1));
    expect(api.createdBookmarks.single.targetType, chatMessageBookmarkTarget);
    expect(api.createdBookmarks.single.targetId, 7);
    expect(find.text('Bookmarked!'), findsOneWidget);
    expect(
      controller.chatRecords.read<ChatMessage>(_siteUrl, 7)?.bookmark?.id,
      1000,
    );
  });

  testWidgets('hands an author edit to the owning composer', (tester) async {
    final api = FakeDiscourseApi(
      user: const DiscourseUser(id: 1, username: 'reader'),
    );
    final controller = await _controller(
      _message(null, raw: 'before', authorId: 1),
      signedIn: true,
      api: api,
    );
    addTearDown(controller.dispose);
    expect(controller.currentInstance?.user?.id, 1);
    expect(
      controller.chat.canEditMessage(
        _siteUrl,
        controller.chatRecords.read<ChatMessage>(_siteUrl, 7)!,
      ),
      isTrue,
    );

    final editing = <ChatMessage>[];
    await tester.pumpWidget(
      _TestTile(
        controller: controller,
        onOpenThread: (_) {},
        onEdit: editing.add,
        platform: TargetPlatform.android,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      controller.chatRecords.read<ChatMessage>(_siteUrl, 7)?.raw,
      'before',
    );
    expect(controller.currentInstance?.user?.id, 1);
    expect(controller.chatRecords.read<ChatMessage>(_siteUrl, 7)?.author.id, 1);
    expect(
      controller.chat.canEditMessage(
        _siteUrl,
        controller.chatRecords.read<ChatMessage>(_siteUrl, 7)!,
      ),
      isTrue,
    );
    await tester.longPress(find.byKey(_messageTileKey));
    await tester.pumpAndSettle();

    expect(find.text('Message actions'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(editing.single.id, 7);
    expect(editing.single.raw, 'before');
    expect(find.text('Edit message'), findsNothing);
    expect(api.chatMessagesEdited, isEmpty);
  });

  testWidgets('another author has no edit action', (tester) async {
    final controller = await _controller(
      _message(null, raw: 'before', authorId: 99),
      signedIn: true,
    );
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
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('an author deletes a message from the adaptive actions', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: const DiscourseUser(id: 1, username: 'reader'),
    );
    final controller = await _controller(
      _message(null, raw: 'mine', authorId: 1),
      signedIn: true,
      canDeleteSelf: true,
      api: api,
    );
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

    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(api.chatMessagesDeleted, [(channelId: 9, messageId: 7)]);
    expect(
      controller.chatRecords.read<ChatMessage>(_siteUrl, 7)?.isDeleted,
      isTrue,
    );
  });

  testWidgets('an author deletes from the desktop secondary actions', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: const DiscourseUser(id: 1, username: 'reader'),
    );
    final controller = await _controller(
      _message(null, raw: 'mine', authorId: 1),
      signedIn: true,
      canDeleteSelf: true,
      api: api,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();
    await _hoverMessage(tester);

    expect(find.byTooltip('Delete'), findsNothing);
    await tester.tap(find.byTooltip('More message actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(api.chatMessagesDeleted, [(channelId: 9, messageId: 7)]);
    expect(
      controller.chatRecords.read<ChatMessage>(_siteUrl, 7)?.isDeleted,
      isTrue,
    );
  });

  testWidgets('a channel pin manager pins and unpins from message actions', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: const DiscourseUser(id: 1, username: 'reader'),
    );
    final controller = await _controller(
      _message(null),
      signedIn: true,
      canManagePins: true,
      api: api,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();
    await _hoverMessage(tester);

    expect(find.byTooltip('Pin'), findsNothing);
    await tester.tap(find.byTooltip('More message actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Pin'));
    await tester.pumpAndSettle();

    expect(api.chatMessagePinsUpdated, [
      (channelId: 9, messageId: 7, pinned: true),
    ]);
    expect(
      controller.chatRecords.read<ChatMessage>(_siteUrl, 7)?.pinned,
      isTrue,
    );
    expect(_pinnedBadge(), findsOneWidget);

    await tester.tap(find.byTooltip('More message actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Unpin'));
    await tester.pumpAndSettle();
    expect(api.chatMessagePinsUpdated.last, (
      channelId: 9,
      messageId: 7,
      pinned: false,
    ));
    expect(
      controller.chatRecords.read<ChatMessage>(_siteUrl, 7)?.pinned,
      isFalse,
    );
    expect(_pinnedBadge(), findsNothing);
  });

  testWidgets('a pinned message badge is visible without pin permission', (
    tester,
  ) async {
    final controller = await _controller(_message(null, pinned: true));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(_pinnedBadge(), findsOneWidget);
    await _hoverMessage(tester);
    expect(find.byTooltip('Unpin'), findsNothing);
  });

  testWidgets('staff can queue an HTML rebuild from message actions', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: const DiscourseUser(id: 1, username: 'reader', staff: true),
    );
    final controller = await _controller(
      _message(null),
      signedIn: true,
      staff: true,
      api: api,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();
    await _hoverMessage(tester);

    expect(find.byTooltip('Rebuild HTML'), findsNothing);
    await tester.tap(find.byTooltip('More message actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Rebuild HTML'));
    await tester.pumpAndSettle();

    expect(api.chatMessagesRebaked, [(channelId: 9, messageId: 7)]);
    expect(find.text('HTML rebuild queued.'), findsOneWidget);
  });

  testWidgets('flags another author’s message with an advertised reason', (
    tester,
  ) async {
    const flag = PostFlagType(
      id: 7,
      nameKey: 'spam',
      name: 'Spam',
      description: 'This message is an advertisement.',
      appliesTo: ['Chat::Message'],
    );
    const catalog = SitePostActionCatalog(postFlags: [flag]);
    final api = FakeDiscourseApi(
      user: const DiscourseUser(id: 1, username: 'reader'),
      categoryPostActionCatalog: catalog,
    );
    final controller = await _controller(
      _message(null, authorId: 99, availableFlags: const ['spam']),
      signedIn: true,
      canFlag: true,
      flagCatalog: catalog,
      api: api,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(controller: controller, onOpenThread: (_) {}),
    );
    await tester.pumpAndSettle();
    await _hoverMessage(tester);

    expect(find.byTooltip('Flag'), findsNothing);
    await tester.tap(find.byTooltip('More message actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Flag'));
    await tester.pumpAndSettle();
    expect(find.text('Spam'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-flag-submit')));
    await tester.pumpAndSettle();

    expect(api.chatMessagesFlagged, [
      (channelId: 9, messageId: 7, flagTypeId: 7, message: null),
    ]);
    expect(
      controller.chatRecords.read<ChatMessage>(_siteUrl, 7)?.userFlagStatus,
      0,
    );
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
    expect(tester.getSize(action), HoverActionButton.size);
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

    final write = controller.pluginSession
        .require(chatBookmarkHostService)
        .createBookmark(siteUrl: _siteUrl, targetId: 7);
    await api.started.future;
    await tester.pump();
    await _hoverMessage(tester);

    final action = find.byTooltip('Bookmark');
    expect(action, findsOneWidget);
    final button = tester.widget<DButton>(
      find.ancestor(of: action, matching: find.byType(DButton)),
    );
    expect(button.onPressed, isNull);
    expect(
      find.descendant(
        of: action,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

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

  testWidgets('a desktop long press does not open message actions', (
    tester,
  ) async {
    final message = _message(_thread());
    final controller = await _controller(message);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTile(
        controller: controller,
        onOpenThread: (_) {},
        onReplyInThread: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(_messageTileKey));
    await tester.pumpAndSettle();

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

ChatThreadPreview _thread({
  int replyCount = 5,
  String lastReplyExcerpt = 'It works',
}) => ChatThreadPreview(
  threadId: 3,
  replyCount: replyCount,
  lastReplyId: 42,
  lastReplyAt: DateTime.now().add(const Duration(seconds: 1)),
  lastReplyExcerpt: lastReplyExcerpt,
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
  String raw = '',
  int authorId = 99,
  String authorUsername = '',
  int? threadId,
  DateTime? deletedAt,
  bool edited = false,
  bool pinned = false,
  List<ChatReaction> reactions = const [],
  Bookmark? bookmark,
  List<String> availableFlags = const [],
  ChatReplyTo? replyTo,
}) => ChatMessage(
  id: 7,
  channelId: 9,
  raw: raw,
  cooked: '<p>Root message</p>',
  author: ChatMessageAuthor(
    id: authorId,
    username: authorUsername,
    name: 'Root author',
  ),
  deletedAt: deletedAt,
  edited: edited,
  pinned: pinned,
  reactions: reactions,
  bookmark: bookmark,
  availableFlags: availableFlags,
  replyTo: replyTo,
  threadId: threadId ?? thread?.threadId,
  thread: thread,
);

Future<ShellController> _controller(
  ChatMessage message, {
  bool signedIn = false,
  bool staff = false,
  bool canDeleteSelf = false,
  bool canDeleteOthers = false,
  bool canModerate = false,
  bool canManagePins = false,
  bool canFlag = false,
  SitePostActionCatalog? flagCatalog,
  FakeDiscourseApi? api,
}) async {
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  final resolvedApi =
      api ?? FakeDiscourseApi(categoryPostActionCatalog: flagCatalog);
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      DiscourseInstance(
        url: _siteUrl,
        title: 'Meta',
        apiVersion: 4,
        user: signedIn
            ? DiscourseUser(id: 1, username: 'reader', staff: staff)
            : null,
      ),
    ]),
    api: resolvedApi,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  await controller.load();
  if (flagCatalog != null) await controller.loadCategories(_siteUrl);
  controller.chatRecords.put(
    _siteUrl,
    ChatChannel(
      id: 9,
      title: 'Support',
      kind: ChatChannelKind.category,
      canDeleteSelf: canDeleteSelf,
      canDeleteOthers: canDeleteOthers,
      canModerate: canModerate,
      canManagePins: canManagePins,
      canFlag: canFlag,
      membership: const ChatMembership(following: true),
    ),
  );
  controller.chatRecords.put(_siteUrl, message);
  return controller;
}

class _TestTile extends StatelessWidget {
  const _TestTile({
    required this.controller,
    required this.onOpenThread,
    this.messageId = 7,
    this.onJumpToMessage,
    this.onReplyInThread,
    this.onEdit,
    this.contextThreadId,
    this.showThreadSummary = true,
    this.chained = false,
    this.platform = TargetPlatform.macOS,
  });

  final ShellController controller;
  final int messageId;
  final ValueChanged<ChatThreadPreview> onOpenThread;
  final ValueChanged<int>? onJumpToMessage;
  final ValueChanged<ChatMessage>? onReplyInThread;
  final ValueChanged<ChatMessage>? onEdit;
  final int? contextThreadId;
  final bool showThreadSummary;
  final bool chained;
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: PluginUiScope.own(
      chatPluginId,
      MaterialApp(
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
                contextThreadId: contextThreadId,
                onOpenThread: onOpenThread,
                onJumpToMessage: onJumpToMessage,
                onReplyInThread: onReplyInThread,
                onEdit: onEdit,
                showThreadSummary: showThreadSummary,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final _emojiPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

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

Finder _copyLinkSemanticsOwner() => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.customSemanticsActions?.containsKey(_copyLinkAction) ??
          false),
);

Finder _pinnedBadge() => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics && widget.properties.label == 'Pinned chat message',
);

List<String> _watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return copied;
}

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
