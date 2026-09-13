import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_drawer.dart';
import 'package:discourse_native/src/plugins/chat/chat_drawer_preferences_store.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

void main() {
  testWidgets('unread channel rows and navigation announce their state once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final fixture = await _pumpDrawer(
      tester,
      api: FakeDiscourseApi(
        totals: chatNotificationTotals(),
        user: _user,
        chatChannelsBySite: const {
          _siteUrl: ChatChannels(
            public: [
              ChatChannel(
                id: 9,
                title: 'Community discussion',
                kind: ChatChannelKind.category,
                membership: ChatMembership(following: true),
                tracking: ChatTracking(unreadCount: 4),
              ),
            ],
            direct: [
              ChatChannel(
                id: 10,
                title: 'Sam',
                kind: ChatChannelKind.directMessage,
                membership: ChatMembership(following: true),
              ),
            ],
          ),
        },
      ),
      contentBuilder: (_, _) => const Column(
        children: [
          ChatDrawerNavigation(),
          Expanded(
            child: ChatDrawerChannelsView(
              siteUrl: _siteUrl,
              kind: ChatDrawerChannelListKind.channels,
            ),
          ),
        ],
      ),
    );
    await fixture.shell.chat.loadChannels(_siteUrl);
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('chat-drawer-channel-9'));
    expect(row, findsOneWidget);
    final rowSemantics = tester.getSemantics(row);
    expect(
      rowSemantics.label,
      'Unread conversation\nCommunity discussion\nNo messages yet',
    );
    final childLabels = <String>[];
    rowSemantics.visitChildren((child) {
      childLabels.add(child.label);
      return true;
    });
    expect(childLabels, ['Open Community discussion menu']);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('chat-drawer-navigation-chat-channels')),
          )
          .label,
      'Channels\nUnread messages',
    );
  });

  testWidgets(
    'collapse pauses retained body ticks while the header stays active',
    (tester) async {
      var bodyTicks = 0;
      var headerTicks = 0;
      await _pumpDrawer(
        tester,
        contentBuilder: (_, _) =>
            _TickProbe(onTick: () => bodyTicks++, child: const TextField()),
        headerLeading: _TickProbe(
          onTick: () => headerTicks++,
          child: const SizedBox.expand(),
        ),
        settle: false,
      );
      await tester.enterText(find.byType(TextField), 'Retained draft');
      await tester.pump(const Duration(milliseconds: 100));
      expect(bodyTicks, greaterThan(0));
      expect(headerTicks, greaterThan(0));

      await tester.tap(find.byKey(ChatDrawerOverlay.collapseButtonKey));
      await tester.pump();
      final pausedBodyTicks = bodyTicks;
      final activeHeaderTicks = headerTicks;
      await tester.pump(const Duration(seconds: 2));
      expect(bodyTicks, pausedBodyTicks);
      expect(headerTicks, greaterThan(activeHeaderTicks));

      await tester.tap(find.byKey(ChatDrawerOverlay.headerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(bodyTicks, greaterThan(pausedBodyTicks));
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Retained draft',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'retained body ticks follow closing, layout and parent visibility',
    (tester) async {
      var ticks = 0;
      final fixture = await _pumpDrawer(
        tester,
        api: _chatApi(),
        channelId: 9,
        contentBuilder: (_, _) => _TickProbe(
          onTick: () => ticks++,
          child: const ChatChannelView(channelId: 9),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(ticks, greaterThan(0));
      final tracker = FakeSiteTracker.built.singleWhere(
        (tracker) => tracker.siteUrl == _siteUrl,
      );
      expect(tracker.pluginChannelCallbacks['/chat/9'], isNotEmpty);

      fixture.shell.closeDrawer();
      await tester.pump();
      var pausedTicks = ticks;
      await tester.pump(const Duration(seconds: 2));
      expect(ticks, pausedTicks);
      expect(tracker.pluginChannelCallbacks['/chat/9'], isEmpty);
      await fixture.shell.openShortcut(drawerAvailable: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(ticks, greaterThan(pausedTicks));
      expect(tracker.pluginChannelCallbacks['/chat/9'], isNotEmpty);

      tester.view.physicalSize = const Size(600, 900);
      await tester.pump();
      pausedTicks = ticks;
      await tester.pump(const Duration(seconds: 2));
      expect(ticks, pausedTicks);
      expect(tracker.pluginChannelCallbacks['/chat/9'], isEmpty);
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(ticks, greaterThan(pausedTicks));
      expect(tracker.pluginChannelCallbacks['/chat/9'], isNotEmpty);

      fixture.tickersEnabled.value = false;
      await tester.pump();
      pausedTicks = ticks;
      await tester.tap(find.byKey(ChatDrawerOverlay.collapseButtonKey));
      await tester.pump();
      await tester.tap(find.byKey(ChatDrawerOverlay.headerKey));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(ticks, pausedTicks);
      expect(tracker.pluginChannelCallbacks['/chat/9'], isEmpty);
      fixture.tickersEnabled.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(ticks, greaterThan(pausedTicks));
      expect(tracker.pluginChannelCallbacks['/chat/9'], isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('expanding resumes only the remaining visible read dwell', (
    tester,
  ) async {
    final api = _chatApi();
    await _pumpDrawer(
      tester,
      api: api,
      channelId: 9,
      contentBuilder: (context, _) {
        final chat = PluginUiScope.require(context, chatControllerService);
        return ChatMessageStream(
          siteUrl: _siteUrl,
          target: const ChatChannelTarget(9),
          items: buildChatStream([_message()]),
          stream: chat.streamFor(_siteUrl, const ChatChannelTarget(9)),
          clock: tester.binding.clock.now,
        );
      },
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(api.chatReadsMarked, isEmpty);
    await tester.tap(find.byKey(ChatDrawerOverlay.collapseButtonKey));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(api.chatReadsMarked, isEmpty);

    await tester.tap(find.byKey(ChatDrawerOverlay.headerKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));
    expect(api.chatReadsMarked, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(api.chatReadsMarked, [(channelId: 9, messageId: 41)]);
  });

  testWidgets('closing the drawer tolerates a deactivated primary focus', (
    tester,
  ) async {
    final fixture = await _pumpDrawer(tester);
    fixture.forumFocus.requestFocus();
    await tester.pump();
    expect(fixture.forumFocus.hasPrimaryFocus, isTrue);

    fixture.showForumFocus.value = false;
    fixture.shell.closeDrawer();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
    expect(fixture.forumFocus.hasFocus, isFalse);
  });

  testWidgets('closing the drawer releases focus from its retained content', (
    tester,
  ) async {
    final fixture = await _pumpDrawer(tester);
    fixture.drawerFocus.requestFocus();
    await tester.pump();
    expect(fixture.drawerFocus.hasPrimaryFocus, isTrue);

    fixture.shell.closeDrawer();
    await tester.pumpAndSettle();

    expect(fixture.drawerFocus.hasFocus, isFalse);
    expect(
      find.byKey(ChatDrawerOverlay.drawerKey, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('closing the drawer preserves focus in the forum', (
    tester,
  ) async {
    final fixture = await _pumpDrawer(tester);
    fixture.forumFocus.requestFocus();
    await tester.pump();
    expect(fixture.forumFocus.hasPrimaryFocus, isTrue);

    fixture.shell.closeDrawer();
    await tester.pumpAndSettle();

    expect(fixture.forumFocus.hasPrimaryFocus, isTrue);
    expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
  });
}

Future<
  ({
    ChatShellService shell,
    FocusNode drawerFocus,
    FocusNode forumFocus,
    ValueNotifier<bool> showForumFocus,
    ValueNotifier<bool> tickersEnabled,
  })
>
_pumpDrawer(
  WidgetTester tester, {
  ChatDrawerContentBuilder? contentBuilder,
  Widget? headerLeading,
  FakeDiscourseApi? api,
  int? channelId,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await const ChatDrawerPreferencesStore().writePreferredDisplayMode(
    ChatPreferredDisplayMode.drawer,
  );
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      DiscourseInstance(
        url: _siteUrl,
        title: 'Meta',
        user: _user,
        notificationTotals: chatNotificationTotals(),
      ),
    ]),
    api: api ?? FakeDiscourseApi(totals: chatNotificationTotals(), user: _user),
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  final shell = controller.pluginSession.require(chatShellService);
  await shell.openShortcut(drawerAvailable: true);
  if (channelId != null) {
    expect(shell.openChannel(channelId), isTrue);
    await shell.chat.openChannel(_siteUrl, channelId);
  }
  final drawerFocus = FocusNode();
  final forumFocus = FocusNode();
  final showForumFocus = ValueNotifier(true);
  final tickersEnabled = ValueNotifier(true);
  addTearDown(drawerFocus.dispose);
  addTearDown(forumFocus.dispose);
  addTearDown(showForumFocus.dispose);
  addTearDown(tickersEnabled.dispose);
  final drawer = ChatDrawerOverlay(
    contentBuilder:
        contentBuilder ??
        (_, _) =>
            Focus(focusNode: drawerFocus, child: const Text('Chat content')),
    headerActionsBuilder: (_, _) => const [],
    headerLeadingBuilder: (_, _) => headerLeading,
    headerTitleTrailingBuilder: (_, _) => null,
    headerTitleActionBuilder: (_, _) => null,
    showNavigationForRoute: (_) => false,
  );
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: PluginUiScope.own(
        chatPluginId,
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: showForumFocus,
              builder: (_, showFocus, _) => Stack(
                fit: StackFit.expand,
                children: [
                  if (showFocus)
                    Focus(
                      focusNode: forumFocus,
                      child: const Text('Forum content'),
                    )
                  else
                    const SizedBox.shrink(),
                  ValueListenableBuilder(
                    valueListenable: tickersEnabled,
                    builder: (_, enabled, child) =>
                        TickerMode(enabled: enabled, child: child!),
                    child: drawer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  expect(find.byKey(ChatDrawerOverlay.drawerKey), findsOneWidget);
  return (
    shell: shell,
    drawerFocus: drawerFocus,
    forumFocus: forumFocus,
    showForumFocus: showForumFocus,
    tickersEnabled: tickersEnabled,
  );
}

class _TickProbe extends StatefulWidget {
  const _TickProbe({required this.onTick, required this.child});

  final VoidCallback onTick;
  final Widget child;

  @override
  State<_TickProbe> createState() => _TickProbeState();
}

class _TickProbeState extends State<_TickProbe>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => widget.onTick())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

ChatMessage _message() => ChatMessage(
  id: 41,
  channelId: 9,
  cooked: '<p>Unread message</p>',
  author: const ChatMessageAuthor(id: 2, username: 'sam'),
  createdAt: DateTime.utc(2026, 9, 8),
);

FakeDiscourseApi _chatApi() => FakeDiscourseApi(
  totals: chatNotificationTotals(),
  user: _user,
  chatChannelsBySite: const {
    _siteUrl: ChatChannels(
      public: [
        ChatChannel(
          id: 9,
          title: 'Chat',
          kind: ChatChannelKind.category,
          membership: ChatMembership(following: true, lastReadMessageId: 0),
        ),
      ],
    ),
  },
  chatMessagesByKey: {
    FakeDiscourseApi.chatMessagesKey(9): (
      messages: [_message()],
      canLoadMorePast: false,
      canLoadMoreFuture: false,
      targetMessageId: null,
    ),
  },
);
