import 'dart:async';

import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/chat_shell.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _platforms = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.android,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('state notifications preserve parked visits and Forward', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    shell.selectMobilePanel('chat');
    shell.openChatChannel(10);
    await tester.pumpAndSettle();
    final channelVisit = shell.mobileNavigation.entryId;
    expect(shell.handleBack(), isTrue);
    await tester.pumpAndSettle();
    final rootVisit = shell.mobileNavigation.entryId;
    final before = shell.mobileNavigation.state;
    final parked = shell.activeTab!.location;
    expect(shell.currentContent, isNull);
    shell.notifyPluginStateChanged();
    shell.toggleMobileSidebar();
    shell.notifyPluginStateChanged();
    shell.closeMobileSidebar();
    expect(shell.openAppSettingsModal(), isTrue);
    shell.notifyPluginStateChanged();
    shell.closeAppSettingsModal();
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.state, before);
    expect(shell.mobileNavigation.entryId, same(rootVisit));
    expect(shell.mobileNavigation.nextEntryId, same(channelVisit));
    expect(shell.activeTab!.location, parked);
    expect(shell.currentContent, isNull);
    expect(shell.handleForward(), isTrue);
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.entryId, same(channelVisit));
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  for (final origin in [
    'latest',
    'inbox',
    'topic',
    'private message',
    'users',
    'chat root',
    'channel',
    'thread',
  ]) {
    testWidgets('PM notification returns to the visited $origin', (
      tester,
    ) async {
      final shell = await pumpMobileShellFixture(
        tester,
        topic: topicPayload(
          id: 7,
          title: 'Original discussion',
          privateMessage: origin == 'private message',
        ),
        chatThread: const ChatThread(
          id: 3,
          channelId: 10,
          title: 'Original thread',
          status: 'open',
          replyCount: 0,
        ),
        onApi: (api) {
          api.topics[8] = topicPayload(
            id: 8,
            title: 'Notification message',
            privateMessage: true,
          );
        },
      );
      switch (origin) {
        case 'inbox' || 'users':
          shell.selectMobileDestination(
            origin == 'inbox' ? MobileTab.messages : MobileTab.users,
            SidebarDestination(
              id: origin == 'inbox' ? 'messages' : 'users',
              label: origin,
              icon: DIcons.list,
            ),
          );
        case 'topic' || 'private message':
          shell.openTopic(
            const Topic(id: 7, title: 'Original discussion', slug: 'original'),
          );
        case 'chat root' || 'channel' || 'thread':
          shell.selectMobilePanel('chat');
          if (origin != 'chat root') shell.openChatChannel(10);
          if (origin == 'thread') {
            shell.openChatThread(siteUrl: _site, channelId: 10, threadId: 3);
          }
      }
      await tester.pumpAndSettle();
      final previous = shell.mobileNavigation.entryId;
      final location = shell.mobileNavigation.location;
      final originalTab = shell.mobileNavigation.tab;
      expect(
        await shell.openNotificationUrl('$_site/t/notification/8/1'),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(shell.currentTopic?.privateMessage, isTrue);
      expect(shell.mobileNavigation.previousEntryId, same(previous));
      expect(shell.mobileNavigation.tab, originalTab);
      expect(
        shell.activeTab!.contentStack.where((route) => route.isMessages),
        origin == 'inbox' ? hasLength(1) : isEmpty,
        reason: 'Only an explicitly visited Inbox belongs in the route stack.',
      );
      final message = shell.mobileNavigation.entryId;
      expect(shell.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.entryId, same(previous));
      expect(shell.mobileNavigation.location, location);
      expect(shell.handleForward(), isTrue);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 8);
      expect(shell.mobileNavigation.entryId, same(message));
      expect(shell.mobileNavigation.previousEntryId, same(previous));
      expect(tester.takeException(), isNull);
    }, variant: _platforms);
  }

  testWidgets('PM hydration preserves its visit and the forward branch', (
    tester,
  ) async {
    final gate = Completer<void>();
    final shell = await pumpMobileShellFixture(
      tester,
      topicGate: gate,
      onApi: (api) {
        api.topics[8] = topicPayload(
          id: 8,
          title: 'Delayed private message',
          privateMessage: true,
        );
      },
    );
    final source = shell.mobileNavigation.entryId;
    expect(await shell.openNotificationUrl('$_site/t/delayed/8/1'), isTrue);
    await tester.pump();
    final message = shell.mobileNavigation.entryId;
    expect(shell.currentContent?.topicId, 8);
    shell.openTopic(const Topic(id: 7, title: 'Next reader', slug: 'next'));
    await tester.pump();
    final next = shell.mobileNavigation.entryId;
    expect(shell.handleBack(), isTrue);
    await tester.pump();
    expect(shell.mobileNavigation.entryId, same(message));
    expect(shell.mobileNavigation.canGoForward, isTrue);
    gate.complete();
    await tester.pumpAndSettle();
    expect(shell.currentTopic?.privateMessage, isTrue);
    expect(shell.mobileNavigation.entryId, same(message));
    expect(shell.mobileNavigation.previousEntryId, same(source));
    expect(shell.mobileNavigation.canGoForward, isTrue);
    expect(shell.handleForward(), isTrue);
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.entryId, same(next));
    expect(shell.currentContent?.topicId, 7);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('PM notification retains the search input and selection', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(
      tester,
      onApi: (api) {
        api.topics[8] = topicPayload(
          id: 8,
          title: 'Private search interruption',
          privateMessage: true,
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byKey(ForumSearch.inputKey),
      matching: find.byType(EditableText),
    );
    await tester.enterText(
      find.byKey(ForumSearch.inputKey),
      'remember my query',
    );
    await tester.pump(const Duration(milliseconds: 400));
    final editor = tester.widget<EditableText>(input).controller;
    const selection = TextSelection(baseOffset: 3, extentOffset: 11);
    editor.selection = selection;
    final search = shell.mobileNavigation.entryId;
    expect(await shell.openNotificationUrl('$_site/t/private/8/1'), isTrue);
    await tester.pumpAndSettle();
    expect(shell.currentTopic?.privateMessage, isTrue);
    expect(shell.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.entryId, same(search));
    expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
    expect(
      tester.widget<EditableText>(input).controller.text,
      'remember my query',
    );
    expect(tester.widget<EditableText>(input).controller.selection, selection);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);
}
