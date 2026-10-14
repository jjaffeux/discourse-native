import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/user_flair.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_bookmark.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:discourse_native/src/plugins/chat/chat_reactors.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_avatar.dart';
import 'package:discourse_native/src/plugins/discourse_ai/discourse_ai_icons.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/emoji_picker.dart';
import 'package:discourse_native/src/shell/group_flair.dart';
import 'package:discourse_native/src/shell/hover_action_toolbar.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/ui/foundation/material_surface.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kMiddleMouseButton, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/media_pipeline.dart';

const _siteUrl = 'https://meta.example';
const _messageTileKey = ValueKey('message-tile');
const _replyToMessageAction = CustomSemanticsAction(label: 'Reply');
const _copyLinkAction = CustomSemanticsAction(label: 'Copy link');

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final main in [null, 'clap']) {
      testWidgets(
        '$platform double tap adds ${main ?? 'heart'} once with a short haptic',
        (tester) async {
          final config = installedPlugins.models.siteConfig({
            'discourse_reactions_enabled': main != null,
            'discourse_reactions_reaction_for_like': main,
          }, _siteUrl);
          final api = FakeDiscourseApi(siteConfigs: {_siteUrl: config});
          final controller = await _controller(
            _message(null),
            api: api,
            signedIn: true,
          );
          addTearDown(controller.dispose);
          await controller.resolveSiteConfig(_siteUrl);
          final haptics = <Object?>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'HapticFeedback.vibrate') {
                haptics.add(call.arguments);
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await tester.pumpWidget(
            _TestTile(
              controller: controller,
              onOpenThread: (_) {},
              platform: platform,
            ),
          );
          await tester.pumpAndSettle();
          Future<void> doubleTap() async {
            final body = find.text('Root message', findRichText: true);
            await tester.tap(body);
            await tester.pump(const Duration(milliseconds: 50));
            await tester.tap(body);
            await tester.pumpAndSettle();
          }

          await doubleTap();
          expect(api.chatReactionsSet, hasLength(1));
          expect(api.chatReactionsSet.single.emoji, main ?? 'heart');
          expect(api.chatReactionsSet.single.action, ChatReactionAction.add);
          expect(haptics, ['HapticFeedbackType.selectionClick']);
          await doubleTap();
          expect(api.chatReactionsSet, hasLength(1));
          expect(haptics, hasLength(1));
          expect(find.byType(DSheetContent), findsNothing);
        },
      );
    }
  }
  testWidgets('double tap cannot react in a read-only chat channel', (
    tester,
  ) async {
    final api = FakeDiscourseApi();
    final controller = await _controller(
      _message(null),
      api: api,
      signedIn: true,
    );
    addTearDown(controller.dispose);
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
    await tester.pumpWidget(
      _TestTile(
        controller: controller,
        onOpenThread: (_) {},
        platform: TargetPlatform.android,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Root message', findRichText: true));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Root message', findRichText: true));
    await tester.pumpAndSettle();
    expect(api.chatReactionsSet, isEmpty);
  });
  setUpAll(() async {
    final output = Platform.environment['CHAT_REACTION_RENDER_DIR'];
    if (output != null) {
      final fonts =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      for (final entry in fonts.cast<Map<String, dynamic>>()) {
        final loader = FontLoader(entry['family'] as String);
        for (final face
            in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
          loader.addFont(rootBundle.load(face['asset'] as String));
        }
        await loader.load();
      }
    }
  });
  for (final dark in [false, true]) {
    for (final material in DAppearanceMaterial.values) {
      for (final inThread in [false, true]) {
        testWidgets(
          'chat reaction artwork parity ($dark, $material, thread=$inThread)',
          (tester) async {
            final output = Platform.environment['CHAT_REACTION_RENDER_DIR'];
            installTestMediaPipeline(
              client: MockClient((request) async {
                final emojiDir =
                    Platform.environment['CHAT_REACTION_EMOJI_DIR'];
                if (request.url.path.endsWith('/clap.png') ||
                    request.url.path.endsWith('/heart.png')) {
                  return http.Response.bytes(
                    emojiDir == null
                        ? _emojiPng
                        : File(
                            '$emojiDir/${request.url.path.split('/').last}',
                          ).readAsBytesSync(),
                    200,
                    headers: {'content-type': 'image/png'},
                  );
                }
                return http.Response('', 404);
              }),
            );
            final controller = await _controller(
              _message(
                null,
                threadId: inThread ? 3 : null,
                reactions: const [
                  ChatReaction(emoji: 'clap', count: 2),
                  ChatReaction(emoji: 'heart', count: 12, reacted: true),
                ],
              ),
            );
            addTearDown(controller.dispose);
            final captureKey = GlobalKey();
            await tester.pumpWidget(
              _TestTile(
                controller: controller,
                onOpenThread: (_) {},
                contextThreadId: inThread ? 3 : null,
                brightness: dark ? Brightness.dark : Brightness.light,
                material: material,
                captureKey: captureKey,
              ),
            );
            await tester.pumpAndSettle();
            final pills = find.byType(ReactionPill);
            expect(pills, findsNWidgets(2));
            for (var i = 0; i < 2; i++) {
              final toggle = find.descendant(
                of: pills.at(i),
                matching: find.byType(DToggle),
              );
              final artwork = find.descendant(
                of: toggle,
                matching: find.byType(AnimatedContainer),
              );
              final tokens = DTokens.of(tester.element(toggle));
              final decoration =
                  tester.widget<AnimatedContainer>(artwork).decoration!
                      as BoxDecoration;
              expect(tester.getSize(artwork).height, 24);
              expect(
                decoration.color,
                Color.lerp(
                  tokens.colors.surface,
                  tokens.foreground,
                  i == 0 ? .10 : .15,
                ),
              );
              expect(
                find.descendant(
                  of: toggle,
                  matching: find.byType(DMaterialSurface),
                ),
                findsNothing,
              );
            }
            if (output != null) {
              await tester.runAsync(() async {
                for (final element in find.byType(Image).evaluate()) {
                  await precacheImage((element.widget as Image).image, element);
                }
              });
              await tester.pumpAndSettle();
              await tester.runAsync(() async {
                final boundary =
                    captureKey.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await boundary.toImage(pixelRatio: 2);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final dir = Directory(output)..createSync(recursive: true);
                await File(
                  '${dir.path}/${dark ? 'dark' : 'light'}-${material.name}-${inThread ? 'thread' : 'channel'}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  const aiFlair = UserFlair(
    groupId: 12,
    name: 'discourse_ai_users',
    url: 'discourse-ai',
  );

  for (final direction in TextDirection.values) {
    testWidgets('avatar flair follows the trailing edge in $direction', (
      tester,
    ) async {
      final controller = await _controller(_message(null));
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: PluginUiScope.own(
            chatPluginId,
            MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: Directionality(
                  textDirection: direction,
                  child: const Center(
                    child: ChatUserAvatar(
                      siteUrl: _siteUrl,
                      userId: -4000,
                      url: null,
                      size: 40,
                      flair: aiFlair,
                      fallback: SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final avatar = tester.getRect(find.byType(ChatUserAvatar));
      final badge = tester.getRect(find.byType(GroupFlairBadge));
      expect(avatar.size, const Size.square(40));
      expect(badge.size, const Size.square(18));
      expect(badge.bottom, avatar.bottom + 4);
      if (direction == TextDirection.ltr) {
        expect(badge.right, avatar.right + 4);
      } else {
        expect(badge.left, avatar.left - 4);
      }
      expect(find.byTooltip('discourse_ai_users'), findsOneWidget);
    });
  }

  for (final contextThreadId in <int?>[null, 3]) {
    testWidgets(
      'channel/thread $contextThreadId renders and updates author flair',
      (tester) async {
        final message = _message(
          null,
          authorId: -4000,
          authorUsername: 'helper',
          authorFlair: aiFlair,
          threadId: contextThreadId,
        );
        final controller = await _controller(message);
        addTearDown(controller.dispose);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _TestTile(
              controller: controller,
              onOpenThread: (_) {},
              contextThreadId: contextThreadId,
            ),
          );
          await tester.pumpAndSettle();
          final avatar = find.byType(ChatUserAvatar);
          expect(tester.getSize(avatar), const Size.square(28));
          expect(find.byType(GroupFlairBadge), findsOneWidget);
          expect(
            tester
                .widget<DIcon>(
                  find.descendant(
                    of: find.byType(GroupFlairBadge),
                    matching: find.byType(DIcon),
                  ),
                )
                .icon,
            DiscourseAiIcons.ai,
          );
          expect(
            find.bySemanticsLabel(
              'View profile for @helper, discourse_ai_users',
            ),
            findsOneWidget,
          );

          controller.chatRecords.put(
            _siteUrl,
            _message(
              null,
              authorId: -4000,
              authorUsername: 'helper',
              threadId: contextThreadId,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(GroupFlairBadge), findsNothing);
          expect(tester.getSize(avatar), const Size.square(28));
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'thread avatars and reply attribution retain author flair context',
    (tester) async {
      const user = ChatMessageAuthor(
        id: -4000,
        username: 'helper',
        flair: aiFlair,
      );
      const preview = ChatThreadPreview(
        threadId: 3,
        replyCount: 1,
        lastReplyId: 42,
        lastReplyUser: user,
        participantUsers: [user],
      );
      const reply = ChatReplyTo(
        id: 6,
        userId: -4000,
        excerpt: 'Earlier',
        username: 'helper',
        flair: aiFlair,
      );
      final controller = await _controller(_message(preview, replyTo: reply));
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _TestTile(
          controller: controller,
          onOpenThread: (_) {},
          onJumpToMessage: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GroupFlairBadge), findsOneWidget);
      final flairedAvatars = tester
          .widgetList<ChatUserAvatar>(find.byType(ChatUserAvatar))
          .where((avatar) => avatar.userId == -4000);
      expect(flairedAvatars, hasLength(1));
      expect(flairedAvatars.every((avatar) => avatar.flair == aiFlair), isTrue);
    },
  );

  testWidgets(
    'flair leaves the live presence ring and avatar geometry intact',
    (tester) async {
      final controller = await _controller(
        _message(null, authorId: 2, authorFlair: aiFlair),
        api: FakeDiscourseApi(
          chatChannelsBySite: {
            _siteUrl: const ChatChannels(
              public: [],
              direct: [],
              presence: ChatPresence(userIds: {2}, lastMessageId: 47),
            ),
          },
        ),
      );
      addTearDown(controller.dispose);
      await controller.chat.loadChannels(_siteUrl);
      await tester.pumpWidget(
        _TestTile(controller: controller, onOpenThread: (_) {}),
      );
      await tester.pumpAndSettle();
      final ring = find.byKey(ChatUserAvatar.onlineRingKey(2));
      expect(ring, findsOneWidget);
      expect(tester.getSize(ring), const Size.square(28));
      expect(find.byType(GroupFlairBadge), findsOneWidget);
      FakeSiteTracker.built.single.deliverPluginMessage(
        '/presence/chat/online',
        {
          'leaving_user_ids': [2],
        },
        messageId: 48,
      );
      await tester.pumpAndSettle();
      expect(ring, findsNothing);
      expect(find.byType(GroupFlairBadge), findsOneWidget);
      expect(
        tester.getSize(find.byType(ChatUserAvatar)),
        const Size.square(28),
      );
    },
  );

  group('message and thread presentation', () {
    testWidgets('action messages hide the author even without a predecessor', (
      tester,
    ) async {
      final controller = await _controller(_message(null, isAction: true));
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _TestTile(controller: controller, onOpenThread: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChatUserAvatar), findsNothing);
      expect(find.byType(DMessageHeader), findsNothing);
      expect(find.byType(CookedHtml), findsOneWidget);
    });

    for (final scenario in [
      (
        name: 'adjacent reply by another author',
        previous: 6,
        context: null,
        enabled: false,
        force: false,
        thread: false,
        quote: false,
        summary: false,
      ),
      (
        name: 'nonadjacent reply',
        previous: 5,
        context: null,
        enabled: false,
        force: false,
        thread: false,
        quote: true,
        summary: false,
      ),
      (
        name: 'reply in a thread',
        previous: 5,
        context: 3,
        enabled: false,
        force: false,
        thread: false,
        quote: false,
        summary: false,
      ),
      (
        name: 'threaded reply',
        previous: 5,
        context: null,
        enabled: true,
        force: false,
        thread: true,
        quote: false,
        summary: true,
      ),
      (
        name: 'threading disabled',
        previous: 5,
        context: null,
        enabled: false,
        force: false,
        thread: true,
        quote: true,
        summary: false,
      ),
      (
        name: 'forced thread',
        previous: 5,
        context: null,
        enabled: false,
        force: true,
        thread: true,
        quote: false,
        summary: true,
      ),
    ]) {
      testWidgets('web reply rules: ${scenario.name}', (tester) async {
        const reply = ChatReplyTo(
          id: 6,
          userId: 10,
          excerpt: 'Earlier',
          username: 'kris',
        );
        final controller = await _controller(
          _message(
            scenario.thread
                ? ChatThreadPreview(
                    threadId: 3,
                    replyCount: 2,
                    force: scenario.force,
                  )
                : null,
            replyTo: reply,
          ),
          threadingEnabled: scenario.enabled,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _TestTile(
            controller: controller,
            onOpenThread: (_) {},
            previousMessageId: scenario.previous,
            contextThreadId: scenario.context,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(DBubbleQuote),
          scenario.quote ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(ChatMessageTile.threadPreviewKey(3)),
          scenario.summary ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets(
      'inset reply quote attributes and jumps to the referenced message',
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

          final target = find.byKey(
            ChatMessageTile.replyIndicatorKey(reply.id),
          );
          expect(target, findsOneWidget);
          expect(find.byType(DBubbleQuote), findsOneWidget);
          final bubble = tester.getRect(
            find.byKey(const ValueKey('chat-message-bubble-7')),
          );
          final quote = tester.getRect(target);
          expect(bubble.contains(quote.topLeft), isTrue);
          expect(bubble.contains(quote.bottomRight), isTrue);
          expect(find.text('kris'), findsOneWidget);
          expect(
            quote.bottom,
            lessThan(tester.getTopLeft(find.byType(CookedHtml)).dy),
          );
          final excerpt = tester.widget<Text>(find.text(reply.excerpt));
          expect(excerpt.maxLines, 2);
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
      installTestMediaPipeline(
        client: MockClient((_) async => http.Response.bytes(_emojiPng, 200)),
      );
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
      expect(
        find.descendant(of: target, matching: find.byType(Image)),
        findsOne,
      );
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
          expect(tester.getSize(target).height, greaterThanOrEqualTo(28));
          expect(tester.getSize(target).width, lessThanOrEqualTo(654));
          expect(find.text('Kris'), findsNothing);
          expect(find.text('5 replies'), findsOneWidget);
          expect(find.text('It works'), findsOneWidget);
          expect(find.text('+3'), findsOneWidget);
          expect(
            tester.getTopRight(find.text('5 replies')).dx,
            closeTo(tester.getTopRight(target).dx - 13, 0.01),
          );

          final avatars = tester
              .widgetList<ChatUserAvatar>(
                find.descendant(
                  of: target,
                  matching: find.byType(ChatUserAvatar),
                ),
              )
              .map((avatar) => avatar.userId);
          expect(avatars, [1, 2, 5]);

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

          await tester.tap(find.text('It works'));
          await tester.pump();
          expect(opened, [same(thread)]);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('draws emoji in the latest reply excerpt', (tester) async {
      installTestMediaPipeline(
        client: MockClient((_) async => http.Response.bytes(_emojiPng, 200)),
      );
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

    testWidgets('author avatar uses pointer affordances without a hover fill', (
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

      expect(
        WidgetStateProperty.resolveAs<MouseCursor>(ink.mouseCursor!, {}),
        SystemMouseCursors.click,
      );
      expect(
        ink.overlayColor?.resolve({WidgetState.hovered}),
        Colors.transparent,
      );
      expect(
        ink.overlayColor?.resolve({WidgetState.focused}),
        Colors.transparent,
      );
    });

    testWidgets(
      'uses Discourse chat typography for message bodies and authors',
      (tester) async {
        final controller = await _controller(_message(null));
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _TestTile(controller: controller, onOpenThread: (_) {}),
        );
        await tester.pumpAndSettle();

        final cooked = tester.widget<CookedHtml>(find.byType(CookedHtml));
        expect(cooked.compactParagraphs, isTrue);
        expect(cooked.textStyle?.fontSize, 14);
        expect(cooked.textStyle?.height, 1.625);
        final authorStyle = DefaultTextStyle.of(
          tester.element(find.text('Root author')),
        ).style;
        expect(authorStyle.fontSize, 12);
        expect(authorStyle.fontWeight, FontWeight.w500);
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
          for (var step = 0; step < 12; step++) {
            if (tester.getSemantics(target).flagsCollection.isFocused ==
                Tristate.isTrue) {
              break;
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
          }
          expect(
            tester.getSemantics(target),
            isSemantics(isFocusable: true, isFocused: true),
          );
          await tester.sendKeyEvent(activation.key);
          await tester.pump();

          expect(
            opened,
            activation.key == LogicalKeyboardKey.enter
                ? [same(thread)]
                : isEmpty,
          );
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
              onReply: (_) {},
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

          expect(find.byType(DDropdownMenuContent), findsOneWidget);
          expect(find.text('Reply'), findsOneWidget);
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

    testWidgets('thread summary supports modified clicks and open menu', (
      tester,
    ) async {
      final thread = _thread();
      final controller = await _controller(_message(thread), signedIn: true);
      addTearDown(controller.dispose);
      controller.desktopTopicTabs = true;
      var ordinaryOpens = 0;
      await tester.pumpWidget(
        _TestTile(controller: controller, onOpenThread: (_) => ordinaryOpens++),
      );
      await tester.pumpAndSettle();
      final target = find.byKey(
        ChatMessageTile.threadPreviewKey(thread.threadId),
      );
      expect(controller.desktopPanelsEnabled, isTrue);
      final linkPoint =
          tester.getRect(target).bottomLeft + const Offset(24, -8);
      await tester.tapAt(linkPoint, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(ordinaryOpens, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.tapAt(linkPoint, kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(controller.activeTab?.panel, ForumPanel.secondary);
      expect(controller.currentContent?.id, 'chat-c-9-t-3');

      final beforeMiddleClick = controller.tabsForCurrentForum.length;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.tapAt(
        linkPoint,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(controller.tabsForCurrentForum, hasLength(beforeMiddleClick + 1));
      expect(controller.tabsForCurrentForum.last.panel, ForumPanel.secondary);
      expect(
        controller.tabsForCurrentForum.last.currentContent.id,
        'chat-c-9-t-3',
      );

      await tester.tapAt(
        linkPoint,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Open in main panel'), findsOneWidget);
      expect(find.text('Open in new secondary tab'), findsOneWidget);
      final beforeMenuChoice = controller.tabsForCurrentForum.length;
      await tester.tap(find.text('Open in new main tab'));
      await tester.pumpAndSettle();
      expect(controller.tabsForCurrentForum, hasLength(beforeMenuChoice + 1));
      expect(controller.tabsForCurrentForum.last.panel, ForumPanel.main);
      expect(
        controller.tabsForCurrentForum.last.currentContent.id,
        'chat-c-9-t-3',
      );
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

          expect(text.data, '(edited)');
          final style = DefaultTextStyle.of(tester.element(marker)).style;
          expect(style.fontSize, DiscourseTypography.xs);
          expect(
            style.color,
            DTokens.of(tester.element(marker)).mutedForeground,
          );
          expect(
            tester.getTopLeft(marker).dy,
            greaterThanOrEqualTo(
              tester.getBottomLeft(find.byType(CookedHtml)).dy,
            ),
          );
        },
      );
    }

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
  });

  group('selection, reactions, and links', () {
    for (final failFirst in [false, true]) {
      testWidgets(
        'long pressing a reaction shows its users${failFirst ? ' after retry' : ''}',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          const page = ChatMessageReactors(
            channelId: 9,
            messageId: 7,
            filter: 'clap',
            reactors: [
              ChatReactor(
                id: 3,
                username: 'sam',
                name: 'Sam Saffron',
                reaction: 'clap',
              ),
            ],
            total: 1,
          );
          final responses = <String, ChatMessageReactors>{
            if (!failFirst) ChatMessageReactors.key(9, 7, 'clap'): page,
          };
          final gate = Completer<void>();
          final api = FakeDiscourseApi(
            chatReactorsById: responses,
            chatReactorGate: gate,
          );
          final controller = await _controller(
            _message(
              null,
              reactions: const [ChatReaction(emoji: 'clap', count: 1)],
            ),
            api: api,
            signedIn: true,
          );
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            ShellScope(
              controller: controller,
              child: MaterialApp(
                theme: AppTheme.light,
                home: Scaffold(
                  // Plugin contributions live below the navigator in the app.
                  body: PluginUiScope.own(
                    chatPluginId,
                    const ChatMessageTile(
                      siteUrl: _siteUrl,
                      messageId: 7,
                      chained: false,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.longPress(
            find.byKey(const ValueKey('chat-reaction-clap')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          expect(find.text('1 reaction'), findsOneWidget);
          expect(find.byType(DSheetContent), findsOneWidget);
          final sheetBounds = tester.getRect(find.byType(DSheetContent));
          expect(sheetBounds.height, greaterThan(844 * .8));
          expect(sheetBounds.left, greaterThan(0));
          expect(sheetBounds.right, lessThan(390));
          expect(find.byType(DSkeletonRegion), findsOneWidget);
          expect(api.chatReactorsRequested, [
            (channelId: 9, messageId: 7, filter: 'clap'),
          ]);
          expect(api.chatReactionsSet, isEmpty);

          gate.complete();
          await tester.pumpAndSettle();
          if (failFirst) {
            expect(
              find.byKey(const ValueKey('reactor-list-error')),
              findsOneWidget,
            );
            responses[ChatMessageReactors.key(9, 7, 'clap')] = page;
            await tester.tap(find.byKey(const ValueKey('reactor-list-retry')));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          expect(find.text('Sam Saffron'), findsOneWidget);
          expect(find.byType(DSkeletonRegion), findsNothing);
          expect(
            find.byKey(const ValueKey('reactor-list-error')),
            findsNothing,
          );

          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          expect(find.text('Sam Saffron'), findsNothing);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.iOS,
          TargetPlatform.android,
        }),
      );
    }

    testWidgets('selects and copies rendered chat message text', (
      tester,
    ) async {
      final message = _message(null);
      final controller = await _controller(message);
      final copied = _watchClipboard(tester);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _TestTile(controller: controller, onOpenThread: (_) {}),
      );
      await tester.pumpAndSettle();

      final selection = find.byKey(
        ChatMessageTile.bodySelectionKey(message.id),
      );
      expect(selection, findsOneWidget);

      final region = tester
          .state<SelectionAreaState>(selection)
          .selectableRegion;
      region.selectAll(SelectionChangedCause.toolbar);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copied, ['Root message']);
    });

    testWidgets('a touch long press on the body opens message actions', (
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

      expect(find.text('Message actions'), findsOneWidget);
      expect(find.byType(DSheetContent), findsOneWidget);
      expect(find.byType(DDropdownMenuContent), findsNothing);
    });

    testWidgets('reaction permissions follow live channel changes', (
      tester,
    ) async {
      final controller = await _controller(
        _message(
          null,
          reactions: const [ChatReaction(emoji: 'clap', count: 2)],
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _TestTile(controller: controller, onOpenThread: (_) {}),
      );
      await tester.pumpAndSettle();

      final pill = find.byType(ReactionPill);
      expect(
        tester.widget<ReactionPill>(pill).density,
        DToggleDensity.chatReaction,
      );
      final emoji = find.descendant(
        of: pill,
        matching: find.byType(SiteEmojiImage),
      );
      expect(tester.widget<SiteEmojiImage>(emoji).size, 12);
      final toggle = find.descendant(of: pill, matching: find.byType(DToggle));
      final artwork = find.descendant(
        of: toggle,
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(artwork).height, 24);
      final decoration =
          tester.widget<AnimatedContainer>(artwork).decoration!
              as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(999));

      await _hoverMessage(tester);
      expect(find.bySemanticsLabel('Add reaction'), findsOneWidget);
      final reactionAction = tester.widget<DButton>(
        find.byKey(const ValueKey('chat-message-react-7')),
      );
      expect(reactionAction.density, DButtonDensity.chatMessageAction);
      expect(
        tester.getSemantics(find.bySemanticsLabel('2 clap reactions')),
        isSemantics(hint: 'add this reaction'),
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
        isSemantics(hasTapAction: false),
      );
    });

    testWidgets(
      'standalone action adds the first reaction through the emoji picker',
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
        final controller = await _controller(
          _message(null),
          api: api,
          signedIn: true,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _TestTile(controller: controller, onOpenThread: (_) {}),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ReactionPickerButton), findsNothing);
        await _hoverMessage(tester);

        final action = find.byTooltip('Add reaction');
        expect(action, findsOneWidget);
        expect(tester.getSize(action), const Size.square(26));
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

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets(
        '$platform expands messages and reacts from the long-press sheet',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
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
          final controller = await _controller(
            _message(
              null,
              cooked:
                  '<p>${List.filled(30, 'Full width message').join(' ')}</p>',
            ),
            api: api,
            signedIn: true,
          );
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _TestTile(
              controller: controller,
              onOpenThread: (_) {},
              platform: platform,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byTooltip('More message actions'), findsNothing);
          expect(find.byTooltip('Add reaction'), findsNothing);
          final bubble = tester.getRect(
            find.byKey(const ValueKey('chat-message-bubble-7')),
          );
          expect(bubble.right, closeTo(390 - 8, 1));
          await tester.longPress(find.byType(CookedHtml));
          await tester.pumpAndSettle();
          expect(find.byType(DSheetContent), findsOneWidget);
          expect(find.byType(DDropdownMenuContent), findsNothing);
          await tester.tap(find.text('React'));
          await tester.pumpAndSettle();
          // The actions sheet closes; on touch the picker is its own sheet.
          expect(find.text('React'), findsNothing);
          expect(find.byType(DSheetContent), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(DSheetContent),
              matching: find.byType(EmojiPicker),
            ),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip(':wave:'));
          await tester.pumpAndSettle();
          expect(api.chatReactionsSet.single.emoji, 'wave');
          expect(api.chatReactionsSet.single.messageId, 7);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('an upserted DM offers and submits its first reaction', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        directMessageChannelsByUsername: {
          'sam': ChatChannel.fromJson(const {
            'id': 9,
            'title': 'Sam',
            'chatable_type': 'DirectMessage',
          }, _siteUrl),
        },
        emojisBySite: const {
          _siteUrl: [
            SiteEmoji(
              name: 'wave',
              url: 'https://meta.example/images/emoji/wave.png',
            ),
          ],
        },
      );
      final controller = await _controller(
        _message(null),
        api: api,
        channelKind: ChatChannelKind.directMessage,
        signedIn: true,
      );
      addTearDown(controller.dispose);
      await controller.chat.upsertDirectMessageChannel(_siteUrl, 'sam');
      await tester.pumpWidget(
        _TestTile(controller: controller, onOpenThread: (_) {}),
      );
      await tester.pumpAndSettle();
      await _hoverMessage(tester);

      final action = find.byTooltip('Add reaction');
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(':wave:'));
      await tester.pumpAndSettle();

      expect(api.chatReactionsSet, hasLength(1));
      final reaction = api.chatReactionsSet.single;
      expect(reaction.channelId, 9);
      expect(reaction.messageId, 7);
      expect(reaction.emoji, 'wave');
      expect(reaction.action, ChatReactionAction.add);
      expect(find.bySemanticsLabel('1 wave reaction'), findsOneWidget);
    });

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
          onReply: replies.add,
        ),
      );
      await tester.pumpAndSettle();

      await _hoverMessage(tester);

      await tester.tap(find.byTooltip('More message actions').hitTestable());
      await tester.pumpAndSettle();
      final action = find.widgetWithText(DDropdownMenuItem, 'Reply');
      expect(action, findsOneWidget);
      expect(
        tester.getSemantics(action),
        isSemantics(label: 'Reply', hasTapAction: true),
      );
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(replies, [same(message)]);
    });

    for (final outgoing in [false, true]) {
      testWidgets(
        'desktop hover puts Reply beside React (outgoing: $outgoing)',
        (tester) async {
          final message = _message(_thread(), authorId: outgoing ? 1 : 99);
          final controller = await _controller(
            message,
            signedIn: true,
            api: FakeDiscourseApi(
              user: const DiscourseUser(id: 1, username: 'reader'),
            ),
          );
          final replies = <ChatMessage>[];
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            _TestTile(
              controller: controller,
              onOpenThread: (_) {},
              onReply: replies.add,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byTooltip('Reply').hitTestable(), findsNothing);

          await _hoverMessage(tester);
          final reply = find.byTooltip('Reply').hitTestable();
          final react = find.byTooltip('Add reaction').hitTestable();
          expect(reply, findsOneWidget);
          expect(react, findsOneWidget);
          expect(
            tester
                .widget<DButton>(
                  find.byKey(const ValueKey('chat-message-reply-action-7')),
                )
                .density,
            DButtonDensity.chatMessageAction,
          );
          final bubble = tester.getRect(
            find.byKey(const ValueKey('chat-message-bubble-7')),
          );
          final replyBounds = tester.getRect(reply);
          final reactBounds = tester.getRect(react);
          expect(bubble.contains(reactBounds.center), isTrue);
          expect(bubble.contains(replyBounds.center), isTrue);
          expect(reactBounds.right, lessThan(replyBounds.left));

          await tester.tap(reply);
          await tester.pump();
          expect(replies, [same(message)]);
        },
      );
    }

    testWidgets(
      'layout-triggered scrolling hides actions until the pointer moves again',
      (tester) async {
        final controller = await _controller(_message(null));
        addTearDown(controller.dispose);
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final viewportHeight = ValueNotifier<double>(300);
        addTearDown(viewportHeight.dispose);

        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: PluginUiScope.own(
              chatPluginId,
              MaterialApp(
                theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
                home: Scaffold(
                  body: ValueListenableBuilder<double>(
                    valueListenable: viewportHeight,
                    builder: (context, height, _) => SizedBox(
                      height: height,
                      child: ListView(
                        controller: scroll,
                        physics: const BouncingScrollPhysics(),
                        children: const [
                          ChatMessageTile(
                            key: _messageTileKey,
                            siteUrl: _siteUrl,
                            messageId: 7,
                            chained: false,
                          ),
                          SizedBox(height: 600),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.byKey(_messageTileKey)));
        await tester.pump();
        expect(
          find.byTooltip('More message actions').hitTestable(),
          findsOneWidget,
        );
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
        expect(
          tester.getRect(find.byType(DMessageSurface)),
          tester.getRect(find.byKey(_messageTileKey)),
        );

        // An idle overshoot starts its bounce while the viewport lays out its
        // new dimensions, before any scroll pixels are reported to listeners.
        scroll.position.correctPixels(-20);
        viewportHeight.value = 320;
        await tester.pump();

        expect(scroll.position.isScrollingNotifier.value, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pump();
        expect(
          find.byTooltip('More message actions').hitTestable(),
          findsNothing,
        );
        expect(background(), Colors.transparent);

        await tester.pumpAndSettle();
        expect(
          find.byTooltip('More message actions').hitTestable(),
          findsNothing,
        );
        await mouse.moveBy(const Offset(0, 1));
        await tester.pump();
        expect(
          find.byTooltip('More message actions').hitTestable(),
          findsOneWidget,
        );
        expect(background(), hoverTint);
        await mouse.moveTo(const Offset(700, 500));
        await tester.pump();
        expect(background(), Colors.transparent);
      },
    );

    testWidgets('hover matches core primary and secondary message actions', (
      tester,
    ) async {
      final controller = await _controller(_message(null), signedIn: true);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _TestTile(
          controller: controller,
          onOpenThread: (_) {},
          onReply: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(find.byKey(_messageTileKey)));
      await tester.pump();

      expect(find.byType(HoverActionToolbar), findsNothing);
      expect(find.byTooltip('Add reaction').hitTestable(), findsOneWidget);
      final more = find.byTooltip('More message actions').hitTestable();
      expect(
        tester
            .widget<DIcon>(
              find.descendant(of: more, matching: find.byType(DIcon)),
            )
            .icon,
        DIcons.chevronDown,
      );
      await tester.tap(more);
      await tester.pumpAndSettle();

      final copyLink = find.widgetWithText(DDropdownMenuItem, 'Copy link');
      expect(copyLink, findsOneWidget);
      expect(
        find.widgetWithText(DDropdownMenuItem, 'Bookmark'),
        findsOneWidget,
      );
      expect(find.widgetWithText(DDropdownMenuItem, 'Reply'), findsOneWidget);
      expect(find.widgetWithText(DDropdownMenuItem, 'React'), findsOneWidget);

      final pointerTarget = tester.getRect(copyLink);
      await pointer.moveTo(tester.getCenter(copyLink));
      await tester.pumpAndSettle();
      expect(tester.getRect(copyLink), pointerTarget);
      expect(tester.widget<DDropdownMenuItem>(copyLink).onPressed, isNotNull);
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
      await tester.tap(find.byTooltip('More message actions').hitTestable());
      await tester.pumpAndSettle();

      await mouse.moveTo(Offset.zero);
      await tester.pump();

      expect(find.byType(DDropdownMenuContent), findsOneWidget);
      expect(
        find.widgetWithText(DDropdownMenuItem, 'Copy link'),
        findsOneWidget,
      );
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
          onReply: (_) {},
          chained: true,
        ),
      );
      await tester.pumpAndSettle();

      await _hoverMessage(tester);

      final action = find.byTooltip('More message actions').hitTestable();
      final bubble = tester.getRect(
        find.byKey(const ValueKey('chat-message-bubble-7')),
      );
      final control = tester.getRect(action);
      expect(bubble.contains(control.topLeft), isTrue);
      expect(bubble.contains(control.bottomRight), isTrue);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(DDropdownMenuItem, 'Reply'), findsOneWidget);
    });

    testWidgets('copies the canonical channel message link', (tester) async {
      final controller = await _controller(_message(null));
      final copied = _watchClipboard(tester);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _TestTile(
          controller: controller,
          onOpenThread: (_) {},
          withToaster: true,
        ),
      );
      await tester.pumpAndSettle();
      await _hoverMessage(tester);

      expect(find.byTooltip('Copy link'), findsNothing);
      final more = find.byTooltip('More message actions').hitTestable();
      expect(tester.getSize(more), const Size.square(24));
      await tester.tap(more);
      await tester.pumpAndSettle();

      final action = find.widgetWithText(DDropdownMenuItem, 'Copy link');
      expect(action, findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(copied, ['https://meta.example/chat/c/-/9/7']);
      expect(find.text('Link copied!'), findsOneWidget);
    });

    testWidgets('copies a thread-shaped link in thread context', (
      tester,
    ) async {
      final controller = await _controller(_message(null, threadId: 3));
      final copied = _watchClipboard(tester);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _TestTile(
          controller: controller,
          onOpenThread: (_) {},
          contextThreadId: 3,
          platform: TargetPlatform.android,
          withToaster: true,
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
          withToaster: true,
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

    testWidgets('exposes Copy link as a custom semantics action', (
      tester,
    ) async {
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
  });

  group('message mutations and moderation', () {
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

      await tester.tap(find.byTooltip('More message actions').hitTestable());
      await tester.pumpAndSettle();
      final action = find.widgetWithText(DDropdownMenuItem, 'Bookmark');
      expect(action, findsOneWidget);
      expect(tester.widget<DDropdownMenuItem>(action).onPressed, isNotNull);

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
      expect(
        controller.chatRecords.read<ChatMessage>(_siteUrl, 7)?.author.id,
        1,
      );
      expect(
        controller.chat.canEditMessage(
          _siteUrl,
          controller.chatRecords.read<ChatMessage>(_siteUrl, 7)!,
        ),
        isTrue,
      );
      await tester.longPress(find.byKey(_messageTileKey));
      await tester.pumpAndSettle();

      expect(find.byType(DSheetContent), findsOneWidget);
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

      expect(find.byType(DSheetContent), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('an author deletes a message from the touch action sheet', (
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
      await tester.tap(find.byTooltip('More message actions').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DDropdownMenuItem, 'Delete'));
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
      await tester.tap(find.byTooltip('More message actions').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DDropdownMenuItem, 'Pin'));
      await tester.pumpAndSettle();

      expect(api.chatMessagePinsUpdated, [
        (channelId: 9, messageId: 7, pinned: true),
      ]);
      expect(
        controller.chatRecords.read<ChatMessage>(_siteUrl, 7)?.pinned,
        isTrue,
      );
      expect(_pinnedBadge(), findsOneWidget);

      await tester.tap(find.byTooltip('More message actions').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DDropdownMenuItem, 'Unpin'));
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
        _TestTile(
          controller: controller,
          onOpenThread: (_) {},
          withToaster: true,
        ),
      );
      await tester.pumpAndSettle();
      await _hoverMessage(tester);

      expect(find.byTooltip('Rebuild HTML'), findsNothing);
      await tester.tap(find.byTooltip('More message actions').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DDropdownMenuItem, 'Rebuild HTML'));
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
      await tester.tap(find.byTooltip('More message actions').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DDropdownMenuItem, 'Flag'));
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

    testWidgets('a persisted chat bookmark shows its state and edit action', (
      tester,
    ) async {
      final api = FakeDiscourseApi();
      final controller = await _controller(
        _message(
          null,
          bookmark: chatMessageBookmarkFromJson(const {
            'id': 7,
            'bookmark': {
              'id': 81,
              'bookmarkable_id': 7,
              'bookmarkable_type': 'ChatMessage',
              'reminder_at': '2030-01-02T03:04:05.000Z',
            },
          }),
        ),
        signedIn: true,
        api: api,
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
      await tester.tap(find.byTooltip('More message actions').hitTestable());
      await tester.pumpAndSettle();
      final action = find.widgetWithText(DDropdownMenuItem, 'Edit bookmark');
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.text('Chat message bookmark'), findsOneWidget);
      expect(find.text('Bookmark chat message'), findsNothing);
      expect(api.createdBookmarks, isEmpty);

      await tester.tap(find.text('Delete bookmark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(api.deletedBookmarks, [81]);
      expect(
        controller.chatRecords.read<ChatMessage>(_siteUrl, 7)?.bookmark,
        isNull,
      );
    });

    testWidgets(
      'the hover bookmark action disables while its write is active',
      (tester) async {
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

        await tester.tap(find.byTooltip('More message actions').hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final action = find.widgetWithText(DDropdownMenuItem, 'Bookmark');
        expect(action, findsOneWidget);
        final button = tester.widget<DDropdownMenuItem>(action);
        expect(button.onPressed, isNull);
        expect(
          find.descendant(of: action, matching: find.byType(DSpinner)),
          findsOneWidget,
        );

        api.response.complete(91);
        expect((await write).saved, isTrue);
      },
    );
  });

  group('reply and long-press semantics', () {
    testWidgets('exposes Reply as a custom semantics action', (tester) async {
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
            onReply: replies.add,
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
        expect(actions, contains(_replyToMessageAction));

        tester
            .widget<Semantics>(owner)
            .properties
            .customSemanticsActions![_replyToMessageAction]!();
        await tester.pump();

        expect(replies, [same(message)]);
      } finally {
        semantics.dispose();
      }
    });

    for (final variant
        in <
          ({
            String name,
            ChatMessage Function() message,
            bool provideCallback,
            int? contextThreadId,
          })
        >[
          (
            name: 'the callback is absent',
            message: () => _message(_thread()),
            provideCallback: false,
            contextThreadId: null,
          ),
          (
            name: 'the message is deleted',
            message: () =>
                _message(_thread(), deletedAt: DateTime.utc(2026, 8, 12)),
            provideCallback: true,
            contextThreadId: null,
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
            contextThreadId: null,
          ),
          (
            name: 'the message is in a thread pane',
            message: () => _message(_thread()),
            provideCallback: true,
            contextThreadId: 3,
          ),
        ]) {
      testWidgets('hides the reply action when ${variant.name}', (
        tester,
      ) async {
        final message = variant.message();
        final controller = await _controller(message);
        final replies = <ChatMessage>[];
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _TestTile(
            controller: controller,
            messageId: message.id,
            onOpenThread: (_) {},
            onReply: variant.provideCallback ? replies.add : null,
            contextThreadId: variant.contextThreadId,
          ),
        );
        await tester.pumpAndSettle();

        await _hoverMessage(tester);

        expect(find.byTooltip('Reply').hitTestable(), findsNothing);
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
      testWidgets('${activation.name} opens the message actions menu', (
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
            onReply: replies.add,
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final actionsTarget = find.byKey(
          ChatMessageTile.actionsKey(message.id),
        );
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

        expect(find.byType(DDropdownMenuContent), findsOneWidget);
        final action = find.text('Reply');
        expect(action, findsOneWidget);

        await tester.tap(action);
        await tester.pumpAndSettle();

        expect(replies, [same(message)]);
        expect(find.byType(DDropdownMenuContent), findsNothing);
      });
    }

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
        '$platform long press highlights and haptically confirms message actions',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
          tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
          addTearDown(tester.view.reset);
          final message = _message(_thread());
          final controller = await _controller(message);
          final replies = <ChatMessage>[];
          final haptics = <Object?>[];
          addTearDown(controller.dispose);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'HapticFeedback.vibrate') {
                haptics.add(call.arguments);
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );

          await tester.pumpWidget(
            _TestTile(
              controller: controller,
              onOpenThread: (_) {},
              onReply: replies.add,
              platform: platform,
            ),
          );
          await tester.pumpAndSettle();
          final surface = find.byType(DMessageSurface);
          Color background() => tester
              .widget<ColoredBox>(
                find
                    .descendant(of: surface, matching: find.byType(ColoredBox))
                    .first,
              )
              .color;
          final restingBackground = background();

          await tester.longPress(find.byKey(_messageTileKey));
          await tester.pump();
          expect(background(), isNot(restingBackground));
          expect(haptics, ['HapticFeedbackType.lightImpact']);
          await tester.pumpAndSettle();
          expect(background(), isNot(restingBackground));
          expect(find.byType(DSheetContent), findsOneWidget);
          final sheetBounds = tester.getRect(find.byType(DSheetContent));
          expect(sheetBounds.left, greaterThan(0));
          expect(sheetBounds.right, lessThan(390));
          expect(sheetBounds.top, greaterThan(47));
          expect(sheetBounds.bottom, lessThan(844 - 34));
          expect(sheetBounds.height, greaterThan(844 * .8));
          final close = find.byKey(
            const ValueKey('chat-message-actions-close-7'),
          );
          final closeButton = tester.widget<DButton>(close);
          expect(closeButton.shape, DButtonShape.pill);
          expect(closeButton.variant, DButtonVariant.secondary);
          expect(closeButton.tooltip, 'Close');
          final closeBounds = tester.getRect(close);
          expect(closeBounds.width, closeBounds.height);
          expect(sheetBounds.contains(closeBounds.center), isTrue);

          await tester.tap(find.text('Reply'));
          await tester.pumpAndSettle();
          expect(replies, [same(message)]);
          expect(find.byType(DSheetContent), findsNothing);
          expect(background(), restingBackground);

          await tester.longPress(find.byKey(_messageTileKey));
          await tester.pumpAndSettle();
          expect(background(), isNot(restingBackground));
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(find.byType(DSheetContent), findsNothing);
          expect(background(), restingBackground);
          expect(replies, [same(message)]);
          await tester.longPress(find.byKey(_messageTileKey));
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(DSheetContent), findsNothing);
          expect(background(), restingBackground);
          expect(haptics, [
            'HapticFeedbackType.lightImpact',
            'HapticFeedbackType.lightImpact',
            'HapticFeedbackType.lightImpact',
          ]);
        },
      );
    }

    testWidgets(
      'mobile action sheet keeps its circular close visible while actions scroll',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
        addTearDown(tester.view.reset);
        final controller = await _controller(
          _message(null),
          signedIn: true,
          staff: true,
          canDeleteOthers: true,
          canModerate: true,
          canManagePins: true,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _TestTile(
            controller: controller,
            onOpenThread: (_) {},
            onReply: (_) {},
            platform: ThemeData().platform,
            brightness: Brightness.dark,
            textScaler: const TextScaler.linear(2),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.byKey(_messageTileKey));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final close = find.byKey(
          const ValueKey('chat-message-actions-close-7'),
        );
        final closeBounds = tester.getRect(close);
        final body = find.descendant(
          of: find.byType(DSheetBody),
          matching: find.byType(Scrollable),
        );
        final scroll = tester.state<ScrollableState>(body).position;
        expect(scroll.maxScrollExtent, greaterThan(0));
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('chat-message-delete-7')),
          150,
          scrollable: body,
        );
        await tester.pumpAndSettle();
        expect(scroll.pixels, greaterThan(0));
        expect(tester.getRect(close), closeBounds);
        expect(
          find.byKey(const ValueKey('chat-message-delete-7')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsNothing);
        expect(controller.chat.message(_siteUrl, 7)!.isDeleted, isFalse);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );

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
          onReply: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(_messageTileKey));
      await tester.pumpAndSettle();

      expect(find.byType(DDropdownMenuContent), findsNothing);
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

      expect(find.byType(DSheetContent), findsOneWidget);
      expect(find.text('Bookmark'), findsOneWidget);
    });
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
  String cooked = '<p>Root message</p>',
  int authorId = 99,
  String authorUsername = '',
  UserFlair? authorFlair,
  int? threadId,
  DateTime? deletedAt,
  bool edited = false,
  bool pinned = false,
  bool isAction = false,
  List<ChatReaction> reactions = const [],
  Bookmark? bookmark,
  List<String> availableFlags = const [],
  ChatReplyTo? replyTo,
}) => ChatMessage(
  id: 7,
  channelId: 9,
  raw: raw,
  cooked: cooked,
  author: ChatMessageAuthor(
    id: authorId,
    username: authorUsername,
    name: 'Root author',
    flair: authorFlair,
  ),
  deletedAt: deletedAt,
  edited: edited,
  pinned: pinned,
  isAction: isAction,
  reactions: reactions,
  bookmark: bookmark,
  availableFlags: availableFlags,
  replyTo: replyTo,
  threadId: threadId ?? thread?.threadId,
  thread: thread,
);

Future<ShellController> _controller(
  ChatMessage message, {
  ChatChannelKind channelKind = ChatChannelKind.category,
  bool signedIn = false,
  bool staff = false,
  bool canDeleteSelf = false,
  bool canDeleteOthers = false,
  bool canModerate = false,
  bool canManagePins = false,
  bool canFlag = false,
  bool threadingEnabled = true,
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
      kind: channelKind,
      canDeleteSelf: canDeleteSelf,
      canDeleteOthers: canDeleteOthers,
      canModerate: canModerate,
      canManagePins: canManagePins,
      canFlag: canFlag,
      threadingEnabled: threadingEnabled,
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
    this.onReply,
    this.onEdit,
    this.contextThreadId,
    this.showThreadSummary = true,
    this.chained = false,
    this.previousMessageId,
    this.platform = TargetPlatform.macOS,
    this.withToaster = false,
    this.brightness = Brightness.light,
    this.textScaler,
    this.material,
    this.captureKey,
  });

  final ShellController controller;
  final int messageId;
  final ValueChanged<ChatThreadPreview> onOpenThread;
  final ValueChanged<int>? onJumpToMessage;
  final ValueChanged<ChatMessage>? onReply;
  final ValueChanged<ChatMessage>? onEdit;
  final int? contextThreadId;
  final bool showThreadSummary;
  final bool chained;
  final int? previousMessageId;
  final TargetPlatform platform;
  final bool withToaster;
  final Brightness brightness;
  final TextScaler? textScaler;
  final DAppearanceMaterial? material;
  final GlobalKey? captureKey;

  ThemeData get _theme {
    final base = brightness == Brightness.dark ? AppTheme.dark : AppTheme.light;
    final theme = base.copyWith(
      platform: platform,
      textTheme: captureKey == null
          ? base.textTheme
          : base.textTheme.apply(fontFamily: 'Lato'),
    );
    return material == null ? theme : DMaterialTheme.apply(theme, material!);
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: PluginUiScope.own(
      chatPluginId,
      MaterialApp(
        theme: _theme,
        builder: (context, child) {
          if (withToaster) {
            child = DToaster(child: child!);
          }
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          );
        },
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: captureKey == null ? 720 : 380,
              child: RepaintBoundary(
                key: captureKey,
                child: ColoredBox(
                  color: _theme.colorScheme.surface,
                  child: ChatMessageTile(
                    key: _messageTileKey,
                    siteUrl: _siteUrl,
                    messageId: messageId,
                    chained: chained,
                    previousMessageId: previousMessageId,
                    contextThreadId: contextThreadId,
                    onOpenThread: onOpenThread,
                    onJumpToMessage: onJumpToMessage,
                    onReply: onReply,
                    onEdit: onEdit,
                    showThreadSummary: showThreadSummary,
                  ),
                ),
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
            _replyToMessageAction,
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
