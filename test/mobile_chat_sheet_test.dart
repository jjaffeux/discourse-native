import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_view.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/chat_shell.dart';

const _site = 'https://meta.discourse.org';
final _handle = find.byKey(const ValueKey('sheet-drag-handle'));
final _sheet = find.byType(DSheetContent);
final _header = find.byKey(const ValueKey('mobile-header'));
final _dock = find.byKey(const ValueKey('mobile-bottom-bar'));
const _platforms = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.android,
});

Future<ShellController> _fixture(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  bool direct = false,
}) async {
  final channel = ChatChannel(
    id: 10,
    title: direct ? 'sam' : 'Support',
    kind: direct ? ChatChannelKind.directMessage : ChatChannelKind.category,
    users: direct ? const [ChatUser(id: 2, username: 'sam')] : const [],
    membership: const ChatMembership(following: true),
    threadingEnabled: true,
  );
  final shell = await pumpMobileShellFixture(
    tester,
    size: size,
    conversations: ChatChannels(
      hasThreads: true,
      public: direct ? const [] : [channel],
      direct: direct ? [channel] : const [],
    ),
    chatThread: const ChatThread(
      id: 3,
      channelId: 10,
      title: 'Support thread',
      status: 'open',
      replyCount: 39,
    ),
    chatMessages: [
      for (var id = 1; id <= 40; id++)
        ChatMessage(
          id: id,
          channelId: 10,
          threadId: 3,
          cooked: '<p>Message $id about the next community release.</p>',
          author: ChatMessageAuthor(
            id: id % 2 + 1,
            username: 'reader${id % 2}',
          ),
          createdAt: DateTime.utc(2026, 10, 1).add(Duration(minutes: id)),
        ),
    ],
  );
  shell.selectMobilePanel('chat');
  if (const bool.fromEnvironment('captureChatSheet')) {
    await shell.forumSettings.setShared(
      shell.forumSettings.shared.copyWith(
        font: ForumFont.lato,
        interfaceFont: ForumFont.lato,
      ),
    );
  }
  await tester.pumpAndSettle();
  return shell;
}

Future<void> _dismiss(WidgetTester tester) async {
  final drag = await tester.startGesture(tester.getCenter(_handle));
  await drag.moveBy(const Offset(0, 20));
  await drag.moveBy(const Offset(0, 180));
  await tester.pump();
  await drag.up();
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('captureChatSheet')) return;
  final size = tester.view.physicalSize;
  await tester.runAsync(() async {
    final builder = ui.SceneBuilder();
    tester.binding.renderViews.first.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(size.width.toInt(), size.height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/private/tmp/chat-page-sheets-audit/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    scene.dispose();
  });
}

void main() {
  if (const bool.fromEnvironment('captureChatSheet')) {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('org.discourse.native/notification_opens');
    setUpAll(() async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      for (final entry in manifest.cast<Map<String, dynamic>>()) {
        final loader = FontLoader(entry['family'] as String);
        for (final face
            in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
          loader.addFont(rootBundle.load(face['asset'] as String));
        }
        await loader.load();
      }
    });
    tearDownAll(() => messenger.setMockMethodCallHandler(channel, null));
  }

  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    for (final material in DAppearanceMaterial.values) {
      testWidgets('chat page sheet geometry ${mode.name} ${material.name}', (
        tester,
      ) async {
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
        final shell = await _fixture(tester);
        shell.openChatChannel(10);
        await shell.forumSettings.setThemeMode(_site, mode);
        await shell.forumSettings.setThemes(
          _site,
          ForumThemePreferences.preset('dracula'),
        );
        await shell.forumSettings.setShared(
          shell.forumSettings.shared.copyWith(
            material: material,
            font: ForumFont.lato,
            interfaceFont: ForumFont.lato,
          ),
        );
        await tester.pumpAndSettle();
        final bounds = tester.getRect(_sheet);
        expect(bounds.left, 0);
        expect(bounds.right, 390);
        expect(bounds.bottom, 810);
        expect(bounds.top, tester.getRect(_header).bottom + 6);
        expect(tester.getSize(_handle), const Size(36, 5));
        expect(tester.getRect(_handle).top, bounds.top + 7);
        final surface = find
            .descendant(of: _sheet, matching: find.byType(DPageSurface))
            .first;
        expect(
          tester.widget<DPageSurface>(surface).borderRadius,
          BorderRadius.circular(22),
        );
        expect(find.byType(ChatChannelView), findsOneWidget);
        final semantics = tester.ensureSemantics();
        expect(find.bySemanticsLabel('Support'), findsWidgets);
        expect(
          find.byKey(const ValueKey('chat-inbox-channel-10')).hitTestable(),
          findsNothing,
        );
        semantics.dispose();
        final dock = tester.getRect(_dock);
        final header = tester.getRect(_header);
        final name =
            '${Theme.of(tester.element(_sheet)).platform.name}-${mode.name}-${material.name}';
        await _capture(tester, '$name-open');
        final drag = await tester.startGesture(tester.getCenter(_handle));
        await drag.moveBy(const Offset(0, 20));
        await drag.moveBy(const Offset(0, 70));
        await tester.pump();
        expect(tester.getRect(_sheet).top, greaterThan(bounds.top));
        expect(tester.getRect(_dock), dock);
        expect(tester.getRect(_header), header);
        await _capture(tester, '$name-pull');
        await drag.cancel();
        await tester.pumpAndSettle();
        expect(tester.getRect(_sheet), bounds);
        expect(tester.takeException(), isNull);
      }, variant: _platforms);
    }
  }

  for (final direct in [false, true]) {
    testWidgets(
      '${direct ? 'direct' : 'channel'} dismissal restores its originating list',
      (tester) async {
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
        final shell = await _fixture(tester, direct: direct);
        final origin = shell.mobileNavigation.entryId;
        shell.openChatChannel(10);
        await tester.pumpAndSettle();
        expect(_handle, findsOneWidget);
        await _capture(
          tester,
          '${Theme.of(tester.element(_sheet)).platform.name}-${direct ? "direct" : "channel"}-open',
        );
        await _dismiss(tester);
        expect(shell.mobileNavigation.entryId, same(origin));
        expect(shell.mobileNavigation.atRoot, isTrue);
        expect(_sheet, findsNothing);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('mobile-content-panel')))
              .bottom,
          844,
        );
        expect(
          find.byKey(const ValueKey('chat-inbox-channel-10')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      variant: _platforms,
    );
  }

  testWidgets('conversation dismissal restores an explicit channel directory', (
    tester,
  ) async {
    final shell = await _fixture(tester);
    shell.pluginSession.require(chatShellService).openChannels();
    await tester.pumpAndSettle();
    final entry = shell.mobileNavigation.entryId;
    expect(shell.currentContent?.id, ChatPlugin.channelsRouteId);
    expect(_sheet, findsNothing);
    shell.openChatChannel(10);
    await tester.pumpAndSettle();
    await _dismiss(tester);
    expect(shell.mobileNavigation.entryId, same(entry));
    expect(shell.currentContent?.id, ChatPlugin.channelsRouteId);
    expect(_sheet, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  for (final origin in [
    'channel',
    'direct',
    'my-threads',
    'channel-threads',
    'channel-info',
  ]) {
    testWidgets(
      'thread opened from $origin dismisses through its parent channel',
      (tester) async {
        final shell = await _fixture(tester, direct: origin == 'direct');
        final chat = shell.pluginSession.require(chatShellService);
        if (origin == 'my-threads') chat.openMyThreads();
        if (origin == 'channel-info') {
          chat.openChannelInfo(siteUrl: _site, channelId: 10);
        }
        if (origin == 'channel-threads') {
          chat.openChannelThreads(siteUrl: _site, channelId: 10);
        }
        await tester.pumpAndSettle();
        expect(_sheet, findsNothing);
        final entry = shell.mobileNavigation.entryId;
        final atRoot = shell.mobileNavigation.atRoot;
        final route = shell.currentContent?.id;
        if (origin == 'channel' || origin == 'direct') {
          shell.openChatChannel(10);
        }
        shell.openChatThread(siteUrl: _site, channelId: 10, threadId: 3);
        await tester.pumpAndSettle();
        expect(find.byType(ChatThreadView), findsOneWidget);
        if (origin == 'channel' || origin == 'direct') {
          await _capture(
            tester,
            '${Theme.of(tester.element(_sheet)).platform.name}-$origin-thread-open',
          );
        }
        if (origin == 'channel') {
          await tester.drag(
            find
                .descendant(
                  of: find.byType(ChatThreadView),
                  matching: find.byType(DSheetDragRegion),
                )
                .hitTestable()
                .first,
            const Offset(0, 180),
          );
          await tester.pumpAndSettle();
        } else {
          await _dismiss(tester);
        }
        expect(shell.currentContent?.id, ChatRoute.channel(10).routeId);
        expect(find.byType(ChatChannelView), findsOneWidget);
        await _dismiss(tester);
        expect(shell.mobileNavigation.entryId, same(entry));
        expect(shell.mobileNavigation.atRoot, atRoot);
        if (!atRoot) expect(shell.currentContent?.id, route);
        expect(_sheet, findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: _platforms,
    );
  }

  for (final thread in [false, true]) {
    testWidgets(
      '${thread ? 'thread' : 'conversation'} short and cancelled pulls retain scroll, editor, draft and focus',
      (tester) async {
        final shell = await _fixture(tester, direct: true);
        if (thread) {
          shell.openChatThread(siteUrl: _site, channelId: 10, threadId: 3);
        } else {
          shell.openChatChannel(10);
        }
        await tester.pumpAndSettle();
        final editor = find.byType(ComposerEditor);
        final textField = find.descendant(
          of: editor,
          matching: find.byType(TextField),
        );
        await tester.enterText(textField, 'Keep this draft while pulling');
        await tester.pumpAndSettle();
        final element = tester.element(editor);
        final composer = tester.widget<ComposerEditor>(editor).composer;
        final stream = find.byType(DMessageScrollerViewport);
        final streamElement = tester.element(stream);
        final scroll = tester
            .widget<DMessageScrollerViewport>(stream)
            .scrollController!;
        scroll.jumpTo(100);
        await tester.pumpAndSettle();
        final offset = scroll.offset;
        final entry = shell.mobileNavigation.entryId;
        final bounds = tester.getRect(_sheet);
        final drag = await tester.startGesture(tester.getCenter(_handle));
        await drag.moveBy(const Offset(0, 20));
        await drag.moveBy(const Offset(0, 60));
        await tester.pump();
        expect(tester.getRect(_sheet).top, greaterThan(bounds.top));
        await drag.cancel();
        await tester.pumpAndSettle();
        final shortPull = await tester.startGesture(tester.getCenter(_handle));
        await shortPull.moveBy(
          const Offset(0, 20),
          timeStamp: const Duration(milliseconds: 100),
        );
        await shortPull.moveBy(
          const Offset(0, 50),
          timeStamp: const Duration(milliseconds: 300),
        );
        await tester.pump(const Duration(milliseconds: 200));
        await shortPull.up();
        await tester.pumpAndSettle();
        expect(shell.mobileNavigation.entryId, same(entry));
        expect(tester.element(editor), same(element));
        expect(tester.widget<ComposerEditor>(editor).composer, same(composer));
        expect(composer.text.text, 'Keep this draft while pulling');
        expect(composer.focus.hasFocus, isTrue);
        expect(tester.element(stream), same(streamElement));
        expect(scroll.offset, offset);
        expect(tester.getRect(_sheet), bounds);
        await _dismiss(tester);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(tester.takeException(), isNull);
      },
      variant: _platforms,
    );
  }

  testWidgets(
    'downward conversation header drag dismisses and stale callbacks preserve newer visits',
    (tester) async {
      final shell = await _fixture(tester);
      shell.openChatChannel(10);
      await tester.pumpAndSettle();
      final oldDismiss = tester
          .widget<DSheetViewport>(find.byType(DSheetViewport))
          .onDismiss!;
      final region = find
          .descendant(
            of: find.byType(ChatChannelView),
            matching: find.byType(DSheetDragRegion),
          )
          .hitTestable()
          .first;
      await tester.drag(region, const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.atRoot, isTrue);
      shell.pushContent(
        const ContentRoute(id: 'users', title: 'Users', icon: DIcons.user),
      );
      await tester.pumpAndSettle();
      final entry = shell.mobileNavigation.entryId;
      oldDismiss();
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.entryId, same(entry));
      expect(shell.currentContent?.id, 'users');
      expect(tester.takeException(), isNull);
    },
    variant: _platforms,
  );

  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets('chat sheet keyboard, safe areas and reduced motion at $width', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
      final shell = await _fixture(tester, size: Size(width, 844));
      shell.openChatChannel(10);
      await shell.appSettings.setTextScale(AppTextScale.percent200);
      await shell.appSettings.setReduceMotion(true);
      await tester.pumpAndSettle();
      expect(tester.getRect(_sheet).width, width);
      expect(tester.getRect(_sheet).bottom, 810);
      expect(tester.getRect(_dock).bottom, lessThanOrEqualTo(810));
      await tester.showKeyboard(
        find.descendant(
          of: find.byType(ComposerEditor),
          matching: find.byType(TextField),
        ),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final send = find.byKey(const ValueKey('chat-composer-send'));
      expect(send.hitTestable(), findsOneWidget);
      expect(tester.getRect(send).bottom, lessThanOrEqualTo(544));
      expect(_dock.hitTestable(), findsNothing);
      await _capture(
        tester,
        '${Theme.of(tester.element(_sheet)).platform.name}-keyboard-${width.toInt()}',
      );
      await _dismiss(tester);
      expect(shell.mobileNavigation.atRoot, isTrue);
      expect(tester.takeException(), isNull);
    }, variant: _platforms);
  }
}
