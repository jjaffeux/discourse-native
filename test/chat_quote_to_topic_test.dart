import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ShellController> shell({
    bool openChannel = true,
    Completer<void>? quoteGate,
    WidgetTester? tester,
  }) async {
    const channel = ChatChannel(
      id: 9,
      title: 'Support chat',
      kind: ChatChannelKind.category,
      chatableId: 5,
      membership: ChatMembership(following: true),
    );
    final controller = ShellController(
      plugins: installedPlugins,
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: _user),
      ]),
      api: FakeDiscourseApi(
        totals: chatNotificationTotals(),
        user: _user,
        feeds: const {'/latest.json': <Topic>[]},
        categoryList: const [
          TopicCategory(
            id: 5,
            name: 'Support',
            color: '0088CC',
            permission: 1,
            minimumRequiredTags: 1,
          ),
        ],
        chatChannelsBySite: const {
          _siteUrl: ChatChannels(public: [channel], direct: []),
        },
        chatQuoteGate: quoteGate,
        chatQuoteMarkdown: '[chat channel="Support chat"]\nSelected\n[/chat]',
        chatMessagesByKey: const {
          '9': (
            messages: [
              ChatMessage(
                id: 2,
                channelId: 9,
                cooked: '<p>Selected message</p>',
                author: ChatMessageAuthor(id: 2, username: 'sam'),
              ),
            ],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
        },
      ),
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    await controller.load();
    if (tester == null) {
      await pumpEventQueue();
    } else {
      await tester.pump();
    }
    if (openChannel) expect(controller.openChatChannel(9), isTrue);
    return controller;
  }

  for (final change in ['none', 'tab before frame', 'tab after frame']) {
    testWidgets('held Native Chat Quote stays with its source ($change)', (
      tester,
    ) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final controller = await shell(quoteGate: gate, tester: tester);
      addTearDown(controller.dispose);
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: const Scaffold(body: MainContent(layout: ShellLayout.medium)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('chat-message-2'))),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('chat-message-more-actions-2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await mouse.removePointer();
      final original = tester.element(find.byType(ChatMessageSelectionBar));
      final sourceTab = controller.activeTabId;
      final sourceRoute = controller.currentContent!;
      await tester.tap(find.byKey(const ValueKey('chat-quote-selection')));
      await tester.pump();
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('chat-quote-selection')))
            .onPressed,
        isNull,
      );

      if (change != 'none') {
        expect(
          controller
              .openContentInNewTab(
                sourceRoute,
                source: controller.activeTab,
                select: true,
              )
              .name,
          'opened',
        );
        expect(controller.activeTabId, isNot(sourceTab));
        expect(controller.currentContent, same(sourceRoute));
        if (change == 'tab after frame') {
          await tester.pumpAndSettle();
          expect(original.mounted, isFalse);
        }
      }
      gate.complete();
      await tester.pumpAndSettle();

      if (change == 'none') {
        expect(
          controller.visibleComposer?.raw,
          '[chat channel="Support chat"]\nSelected\n[/chat]',
        );
        expect(controller.visibleComposer?.target.tabId, sourceTab);
      } else {
        expect(controller.visibleComposer, isNull);
        controller.selectTab(sourceTab!);
        await tester.pumpAndSettle();
        expect(controller.visibleComposer, isNull);
      }
      expect(tester.takeException(), isNull);
      controller.closeComposer();
      await tester.pump(const Duration(seconds: 3));
    });
  }

  test(
    'opens a category-aware topic draft over chat and inserts transcript',
    () async {
      final controller = await shell();
      addTearDown(controller.dispose);
      const transcript = '[chat channel="Support chat"]\nHello\n[/chat]';

      expect(await controller.openChatQuote(_siteUrl, 9, transcript), isNull);

      final composer = controller.visibleComposer;
      expect(composer, isNotNull);
      expect(composer!.target.isNewTopic, isTrue);
      expect(composer.categoryId, 5);
      expect(composer.raw, transcript);
    },
  );

  test('reuses an unfinished chat-origin draft for another quote', () async {
    final controller = await shell();
    addTearDown(controller.dispose);

    await controller.openChatQuote(_siteUrl, 9, '[chat]first[/chat]');
    final composer = controller.visibleComposer!;
    composer.insertText('My response');
    await controller.openChatQuote(_siteUrl, 9, '[chat]second[/chat]');

    expect(controller.visibleComposer, same(composer));
    expect(composer.raw, contains('[chat]first[/chat]'));
    expect(composer.raw, contains('My response'));
    expect(composer.raw, contains('[chat]second[/chat]'));
  });

  test('opens a topic draft after navigating with the Chat shortcut', () async {
    final controller = await shell(openChannel: false);
    addTearDown(controller.dispose);
    final chatShell = controller.pluginSession.require(chatShellService);

    await chatShell.openShortcut();
    expect(chatShell.openChannel(9), isTrue);
    expect(chatShell.fullPageChatActive, isTrue);
    expect(chatShell.currentContent?.id, 'chat-c-9');
    expect(controller.currentContent?.id, 'chat-c-9');

    expect(
      await controller.openChatQuote(
        _siteUrl,
        9,
        '[chat channel="Support chat"]\nChat quote\n[/chat]',
      ),
      isNull,
    );
    expect(controller.visibleComposer?.raw, contains('Chat quote'));
  });
}
