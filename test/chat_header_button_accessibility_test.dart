import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_header_button.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  testWidgets('unread chat has one descriptive keyboard button', (
    tester,
  ) async {
    await _pump(tester, unreadCount: 4);
    final semantics = tester.ensureSemantics();
    try {
      final button = find.byKey(ChatHeaderButton.buttonKey);
      expect(button, findsOneWidget);
      expect(find.byTooltip('Chat, unread messages'), findsOneWidget);
      expect(
        tester.getSemantics(button),
        isSemantics(
          tooltip: 'Chat, unread messages',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      final controller = ShellScope.read(tester.element(button));
      final focus = _focusButton(tester, button);
      await tester.pumpAndSettle();

      expect(focus.hasPrimaryFocus, isTrue);
      expect(
        tester.getSemantics(button),
        isSemantics(isFocusable: true, isFocused: true),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, ChatChannel.routeId(9));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('urgent chat announces the uncapped count only once', (
    tester,
  ) async {
    await _pump(tester, mentionCount: 103);
    final semantics = tester.ensureSemantics();
    try {
      final button = find.byKey(ChatHeaderButton.buttonKey);
      expect(find.text('99+'), findsOneWidget);
      expect(find.byTooltip('Chat, 103 urgent messages'), findsOneWidget);

      final node = tester.getSemantics(button);
      expect(node.tooltip, 'Chat, 103 urgent messages');
      expect(node.label, isEmpty);
      expect(
        node,
        isSemantics(
          tooltip: 'Chat, 103 urgent messages',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _pump(
  WidgetTester tester, {
  int unreadCount = 0,
  int mentionCount = 0,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  const user = DiscourseUser(id: 7, username: 'reader', name: 'Reader');
  final site = instance('meta.discourse.org').copyWith(user: user);
  final channel = ChatChannel(
    id: 9,
    title: 'Bugs',
    kind: ChatChannelKind.category,
    slug: 'bugs',
    membership: const ChatMembership(following: true),
    tracking: ChatTracking(
      unreadCount: unreadCount,
      mentionCount: mentionCount,
    ),
  );
  final api = FakeDiscourseApi(
    user: user,
    totals: const NotificationTotals(
      chatNotifications: 0,
      hasChatEnabled: true,
    ),
    feeds: const {'/latest.json': []},
    chatChannelsBySite: {
      _siteUrl: ChatChannels(
        public: [channel],
        direct: const [],
        presence: const ChatPresence(),
      ),
    },
    chatMessagesByKey: {
      FakeDiscourseApi.chatMessagesKey(9): (
        messages: const <ChatMessage>[],
        canLoadMorePast: false,
        canLoadMoreFuture: false,
        targetMessageId: null,
      ),
    },
  );

  await tester.pumpWidget(
    DiscourseApp(
      store: FakeInstanceStore([site]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      pluginManifest: bundledPluginManifestWithoutDiagnostics,
    ),
  );
  await tester.pumpAndSettle();
}

FocusNode _focusButton(WidgetTester tester, Finder button) {
  final inkWell = find.descendant(of: button, matching: find.byType(InkWell));
  expect(inkWell, findsOneWidget);
  final focusChild = find
      .descendant(of: inkWell, matching: find.byType(MouseRegion))
      .first;
  final focus = Focus.of(tester.element(focusChild));
  focus.requestFocus();
  return focus;
}
