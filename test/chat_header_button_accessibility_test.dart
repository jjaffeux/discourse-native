import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_header_button.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('real macOS header fits two large counts at $width and 200%', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      try {
        await _pump(tester, mentionCount: 128, bellCount: 128, width: width);
        expect(tester.takeException(), isNull);
        expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
        final chat = tester.getRect(find.byKey(ChatHeaderButton.buttonKey));
        final bell = tester.getRect(find.byKey(UserMenuButton.bellKey));
        final avatar = tester.getRect(find.byKey(UserMenuButton.avatarKey));
        expect(chat.overlaps(bell), isFalse);
        expect(bell.overlaps(avatar), isFalse);
        expect(chat.left, greaterThanOrEqualTo(0));
        expect(chat.top, greaterThanOrEqualTo(48));
        expect(avatar.right, lessThanOrEqualTo(width));
        await tester.tap(find.byKey(UserMenuButton.bellKey));
        await tester.pumpAndSettle();
        expect(find.byType(UserMenuPanel), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        debugDefaultTargetPlatformOverride = previous;
      }
    });
  }

  testWidgets('unread chat has one descriptive keyboard button', (
    tester,
  ) async {
    await _pump(tester, unreadCount: 4);
    final semantics = tester.ensureSemantics();
    try {
      final button = find.byKey(ChatHeaderButton.buttonKey);
      expect(button, findsOneWidget);
      final dot = find.byKey(ChatHeaderButton.unreadDotKey);
      expect(tester.widget(dot), isA<DNotificationDot>());
      expect(tester.getSize(dot), const Size.square(12));
      expect(find.byTooltip('Chat, unread messages'), findsOneWidget);
      expect(tester.widget<DButton>(button).variant, DButtonVariant.ghost);
      expect(tester.getSize(button), const Size.square(48));
      expect(
        tester.getSize(
          find.descendant(of: button, matching: find.byType(Material)),
        ),
        const Size.square(28),
      );
      expect(
        tester.getSemantics(button),
        isSemantics(
          label: 'Chat, unread messages',
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

      expect(controller.currentContent?.id, 'latest');
      expect(
        controller.pluginSession
            .require(chatShellService)
            .drawerCurrentContent
            ?.id,
        ChatPlugin.channelsRouteId,
      );
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
      final badge = find.byKey(ChatHeaderButton.urgentBadgeKey);
      expect(find.text('99+'), findsOneWidget);
      expect(find.byTooltip('Chat, 103 urgent messages'), findsOneWidget);

      final theme = Theme.of(tester.element(badge));
      final capsule = tester.widget<DButton>(button);
      expect(
        capsule.backgroundColor,
        theme.discourse.success.withValues(alpha: .14),
      );
      expect(tester.getRect(button).contains(tester.getTopLeft(badge)), isTrue);
      expect(
        tester.getRect(button).contains(tester.getBottomRight(badge)),
        isTrue,
      );

      final node = tester.getSemantics(button);
      expect(node.label, 'Chat, 103 urgent messages');
      expect(node.tooltip, isEmpty);
      expect(
        node,
        isSemantics(
          label: 'Chat, 103 urgent messages',
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
  int bellCount = 0,
  double width = 1440,
}) async {
  tester.view.physicalSize = Size(width, 900);
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
    totals: chatNotificationTotals(unreadNotifications: bellCount),
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
      initialRootMode: ShellRootMode.forum,
      pluginManifest: bundledWidgetTestManifest,
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
