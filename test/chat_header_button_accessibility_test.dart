import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_header_button.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  for (final width in [1000.0, 1440.0]) {
    for (final chatEnabled in [false, true]) {
      for (final count in [0, 128]) {
        testWidgets(
          'header uses standard gaps at $width, chat=$chatEnabled, count=$count',
          (tester) async {
            await _pump(
              tester,
              width: width,
              chatEnabled: chatEnabled,
              mentionCount: count,
              bellCount: count,
            );
            final chatVisible = chatEnabled;
            expect(
              find.byKey(ChatHeaderButton.buttonKey),
              chatVisible ? findsOneWidget : findsNothing,
            );
            final controls = [
              find.byType(DInputGroup),
              if (chatVisible) find.byKey(ChatHeaderButton.buttonKey),
              find.byKey(UserMenuButton.bellKey),
              find.byKey(UserMenuButton.avatarKey),
            ];
            for (var index = 1; index < controls.length; index++) {
              final previous = tester.getRect(controls[index - 1]);
              final current = tester.getRect(controls[index]);
              expect(
                current.left - previous.right,
                closeTo(DSpacing.controlGap, .01),
                reason: 'Gap before control $index',
              );
            }
            expect(tester.takeException(), isNull);
          },
          variant: const TargetPlatformVariant({
            TargetPlatform.macOS,
            TargetPlatform.fuchsia,
          }),
        );
      }
    }
  }

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'real macOS header fits large notification counts at $width and 200%',
      (tester) async {
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
          expect(chat.top, greaterThanOrEqualTo(53));
          expect(avatar.right, lessThanOrEqualTo(width));
          await tester.tap(find.byKey(UserMenuButton.bellKey));
          await tester.pumpAndSettle();
          expect(find.byType(UserMenuPanel), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          debugDefaultTargetPlatformOverride = previous;
        }
      },
    );
  }

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'mobile header fits large counts at $width and 200%',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(tester, mentionCount: 128, bellCount: 128, width: width);
        expect(tester.takeException(), isNull);
        final chat = tester.getRect(find.byKey(ChatHeaderButton.buttonKey));
        final bell = tester.getRect(find.byKey(UserMenuButton.bellKey));
        final avatar = tester.getRect(find.byKey(UserMenuButton.avatarKey));
        expect(chat.overlaps(bell), isFalse);
        expect(bell.overlaps(avatar), isFalse);
        for (final rect in [chat, bell, avatar]) {
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
        }
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
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
      expect(
        tester.widget<DButton>(button).variant,
        DButtonVariant.transparentBackground,
      );
      expect(tester.getSize(button), const Size.square(34));
      expect(
        tester.getSize(
          find.descendant(of: button, matching: find.byType(Material)),
        ),
        const Size.square(34),
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
      expect(controller.currentContent?.id, 'chat-c-9');
    } finally {
      semantics.dispose();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

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
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final mode in [
    ChatSeparateSidebarMode.never,
    ChatSeparateSidebarMode.always,
    ChatSeparateSidebarMode.fullscreen,
  ]) {
    testWidgets('desktop full-page chat with ${mode.wireName} sidebar mode', (
      tester,
    ) async {
      final shell = await _pump(tester, mentionCount: 3, sidebarMode: mode);
      final previous = shell.currentContent;
      final button = find.byKey(ChatHeaderButton.buttonKey);
      expect(find.byKey(ChatHeaderButton.urgentBadgeKey), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, 'chat-c-9');
      expect(button, findsOneWidget);
      expect(find.byKey(ChatHeaderButton.urgentBadgeKey), findsNothing);
      expect(find.byKey(ChatHeaderButton.unreadDotKey), findsNothing);
      expect(
        tester.widget<DButton>(button).tooltip,
        mode == ChatSeparateSidebarMode.never ? 'Chat' : 'Exit chat',
      );

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        shell.currentContent?.id,
        mode == ChatSeparateSidebarMode.never ? 'chat-c-9' : previous?.id,
      );
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets(
      'mobile hides active chat with ${mode.wireName} sidebar mode',
      (tester) async {
        final shell = await _pump(
          tester,
          mentionCount: 3,
          sidebarMode: mode,
          width: 390,
        );
        final button = find.byKey(ChatHeaderButton.buttonKey);
        expect(button, findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, 'chat-channels');
        expect(button, findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }

  for (final scenario in [
    (siteEnabled: false, userEnabled: true),
    (siteEnabled: true, userEnabled: false),
  ]) {
    testWidgets(
      'chat header respects site and account availability $scenario',
      (tester) async {
        await _pump(
          tester,
          siteEnabled: scenario.siteEnabled,
          userEnabled: scenario.userEnabled,
        );
        expect(find.byKey(ChatHeaderButton.buttonKey), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}

Future<ShellController> _pump(
  WidgetTester tester, {
  int unreadCount = 0,
  int mentionCount = 0,
  int bellCount = 0,
  bool chatEnabled = true,
  double width = 1440,
  bool siteEnabled = true,
  bool userEnabled = true,
  ChatSeparateSidebarMode sidebarMode = ChatSeparateSidebarMode.never,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final user = DiscourseUser(
    id: 7,
    username: 'reader',
    name: 'Reader',
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      ChatCurrentUser(hasChatEnabled: userEnabled, lastChannelId: 9),
    ),
  );
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      ChatSettings(chatEnabled: siteEnabled, separateSidebarMode: sidebarMode),
    ),
  );
  final site = instance(
    'meta.discourse.org',
  ).copyWith(user: user, config: config);
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
    siteConfigs: {_siteUrl: config},
    totals: chatNotificationTotals(
      unreadNotifications: bellCount,
      available: chatEnabled,
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
      initialRootMode: ShellRootMode.forum,
      pluginManifest: bundledWidgetTestManifest,
    ),
  );
  await tester.pumpAndSettle();
  final menu = find.byKey(const ValueKey('mobile-menu-button'));
  if (menu.evaluate().isNotEmpty) {
    await tester.tap(menu);
    await tester.pumpAndSettle();
  }
  return tester.widget<ShellScope>(find.byType(ShellScope).first).notifier!;
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
