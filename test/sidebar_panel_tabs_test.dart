import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const site = 'https://meta.discourse.org';
const user = DiscourseUser(id: 7, username: 'reader');
final tabs = find.byKey(const ValueKey('sidebar-panel-tabs'));
Finder tab(String owner) => find.byKey(ValueKey('sidebar-panel-switch-$owner'));

Future<ShellController> pumpTabs(
  WidgetTester tester, {
  bool chat = true,
  bool voice = true,
  bool voiceAccess = true,
  bool connected = true,
  bool installed = true,
  bool rooms = true,
  Map<String, ChatChannels>? channels,
}) async {
  final config = SiteConfig(
    plugins: PluginData.none
        .withValue(
          chatSettingsDataKey,
          ChatSettings(chatEnabled: chat, publicChannelsEnabled: chat),
        )
        .withValue(voiceSettingsDataKey, VoiceClientConfig(enabled: voice)),
  );
  await pumpShell(
    tester,
    desktop,
    pluginManifest: PluginManifest([
      if (installed) ...[
        ChatModule(apiFactory: (transport) => transport as ChatApi),
        const VoiceModule.withoutDiagnostics(),
      ],
    ]),
    instances: [
      instance(
        'meta.discourse.org',
        title: 'Meta',
      ).copyWith(user: connected ? user : null, config: config),
    ],
    authenticator: FakeAuthenticator()
      ..keys.addAll({if (connected) site: 'key'}),
    api: FakeDiscourseApi(
      user: connected ? user : null,
      totals: chatNotificationTotals(available: chat),
      feeds: const {'/latest.json': []},
      siteConfigs: {site: config},
      chatChannelsBySite:
          channels ??
          {
            site: const ChatChannels(
              public: [
                ChatChannel(
                  id: 9,
                  title: 'General',
                  kind: ChatChannelKind.category,
                  membership: ChatMembership(following: true),
                ),
              ],
            ),
          },
      pluginResponses: {
        if (voiceAccess)
          'GET /voice/rooms.json': {
            'rooms': [
              if (rooms)
                {
                  'id': 7,
                  'name': 'Watercooler',
                  'slug': 'watercooler',
                  'room_type': 'conference',
                  'active_participants': <Object>[],
                },
            ],
            'can_create_room': true,
          },
      },
    ),
  );
  final shell = ShellScope.read(tester.element(find.byType(InstanceSidebar)));
  if (installed && connected) {
    await shell.pluginSession
        .require(voiceControllerService)
        .ensureLoaded(site);
    await tester.pumpAndSettle();
  }
  return shell;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'chat tab counts unread messages and updates without navigation',
    (tester) async {
      final channels = {
        site: const ChatChannels(
          public: [
            ChatChannel(
              id: 9,
              title: 'General',
              kind: ChatChannelKind.category,
              membership: ChatMembership(following: true),
              tracking: ChatTracking(
                unreadCount: 20,
                mentionCount: 3,
                watchedThreadsUnreadCount: 5,
              ),
            ),
          ],
          direct: [
            ChatChannel(
              id: 10,
              title: 'Direct',
              kind: ChatChannelKind.directMessage,
              membership: ChatMembership(following: true),
              tracking: ChatTracking(unreadCount: 7, mentionCount: 2),
            ),
          ],
        ),
      };
      final shell = await pumpTabs(tester, channels: channels);
      final chat = shell.pluginSession.require(chatControllerService);
      await chat.loadChannels(site);
      await tester.pumpAndSettle();
      final badge = find.descendant(
        of: tab('chat'),
        matching: find.byType(DBadge),
      );
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('32')),
        findsOneWidget,
      );
      expect(tester.widget<DBadge>(badge).semanticLabel, '32 unread messages');
      final route = shell.currentContent;

      channels[site] = ChatChannels(
        public: [
          channels[site]!.public.single.withTrackingState(
            tracking: const ChatTracking(unreadCount: 1),
          ),
        ],
      );
      await chat.loadChannels(site, force: true);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: badge, matching: find.text('1')),
        findsOneWidget,
      );
      expect(tester.widget<DBadge>(badge).semanticLabel, '1 unread message');
      expect(shell.currentContent, route);

      channels[site] = const ChatChannels();
      await chat.loadChannels(site, force: true);
      await tester.pumpAndSettle();
      expect(badge, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('section unread totals stay visible when collapsed and update', (
    tester,
  ) async {
    final channels = {
      site: const ChatChannels(
        public: [
          ChatChannel(
            id: 9,
            title: 'General',
            kind: ChatChannelKind.category,
            membership: ChatMembership(following: true),
            tracking: ChatTracking(
              unreadCount: 20,
              mentionCount: 3,
              watchedThreadsUnreadCount: 5,
            ),
          ),
          ChatChannel(
            id: 11,
            title: 'Starred public',
            kind: ChatChannelKind.category,
            membership: ChatMembership(following: true, starred: true),
            tracking: ChatTracking(unreadCount: 2),
          ),
        ],
        direct: [
          ChatChannel(
            id: 10,
            title: 'Direct',
            kind: ChatChannelKind.directMessage,
            membership: ChatMembership(following: true),
            tracking: ChatTracking(unreadCount: 7),
          ),
          ChatChannel(
            id: 12,
            title: 'Starred direct',
            kind: ChatChannelKind.directMessage,
            membership: ChatMembership(following: true, starred: true),
            tracking: ChatTracking(unreadCount: 4),
          ),
        ],
      ),
    };
    final shell = await pumpTabs(tester, channels: channels);
    final chat = shell.pluginSession.require(chatControllerService);
    await chat.loadChannels(site);
    await tester.pumpAndSettle();
    await tester.tap(tab('chat'));
    await tester.pumpAndSettle();

    Finder badge(String id) =>
        find.byKey(ValueKey('sidebar-section-unread-$id'));
    for (final (id, title, count) in [
      ('chat-starred-channels', 'Starred channels', '6'),
      ('chat', 'Chat', '25'),
      ('direct-messages', 'Direct messages', '7'),
    ]) {
      await tester.ensureVisible(badge(id));
      expect(
        find.descendant(of: badge(id), matching: find.text(count)),
        findsOneWidget,
      );
      await tester.tap(
        find.ancestor(of: badge(id), matching: find.byType(DSidebarMenuButton)),
      );
      await tester.pumpAndSettle();
      expect(badge(id), findsOneWidget);
      final button = tester.widget<DSidebarMenuButton>(
        find.ancestor(of: badge(id), matching: find.byType(DSidebarMenuButton)),
      );
      expect(button.expanded, isFalse);
      expect(button.semanticLabel, 'Expand $title, $count unread messages');
    }

    channels[site] = ChatChannels(
      public: [
        for (final channel in channels[site]!.public)
          channel.withTrackingState(tracking: const ChatTracking()),
      ],
      direct: [
        for (final channel in channels[site]!.direct)
          channel.withTrackingState(
            tracking: const ChatTracking(unreadCount: 1),
          ),
      ],
    );
    await chat.loadChannels(site, force: true);
    await tester.pumpAndSettle();
    expect(badge('chat'), findsNothing);
    for (final id in ['chat-starred-channels', 'direct-messages']) {
      expect(
        find.descendant(of: badge(id), matching: find.text('1')),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'three tabs partition destinations without navigating or joining',
    (tester) async {
      final shell = await pumpTabs(tester);
      final route = shell.currentContent;
      final count = shell.tabsForCurrentForum.length;
      expect(tabs, findsOneWidget);
      expect(sidebarDestination('Topics'), findsOneWidget);
      expect(sidebarDestination('General'), findsNothing);
      expect(sidebarDestination('Watercooler'), findsNothing);
      for (final (owner, destination) in [
        ('chat', 'General'),
        ('voice', 'Watercooler'),
        ('main', 'Topics'),
      ]) {
        await tester.ensureVisible(tab(owner));
        await tester.tap(tab(owner));
        await tester.pumpAndSettle();
        expect(sidebarDestination(destination), findsOneWidget);
        expect(shell.currentContent, route);
        expect(shell.tabsForCurrentForum.length, count);
        expect(
          shell.pluginSession.require(voiceControllerService).call,
          isNull,
        );
      }
      expect(
        tester.getRect(tabs).bottom,
        lessThanOrEqualTo(tester.getRect(sidebarDestination('Topics')).top),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in [
    (
      name: 'disabled plugins',
      chat: false,
      voice: false,
      access: true,
      connected: true,
      installed: true,
      hasVoice: false,
    ),
    (
      name: 'missing plugins',
      chat: true,
      voice: true,
      access: true,
      connected: true,
      installed: false,
      hasVoice: false,
    ),
    (
      name: 'Voice denied by server',
      chat: false,
      voice: true,
      access: false,
      connected: true,
      installed: true,
      hasVoice: false,
    ),
    (
      name: 'signed out of private plugins',
      chat: false,
      voice: true,
      access: true,
      connected: false,
      installed: true,
      hasVoice: false,
    ),
    (
      name: 'Voice without Chat access',
      chat: false,
      voice: true,
      access: true,
      connected: true,
      installed: true,
      hasVoice: true,
    ),
  ]) {
    testWidgets(scenario.name, (tester) async {
      await pumpTabs(
        tester,
        chat: scenario.chat,
        voice: scenario.voice,
        voiceAccess: scenario.access,
        connected: scenario.connected,
        installed: scenario.installed,
      );
      expect(tabs, scenario.hasVoice ? findsOneWidget : findsNothing);
      expect(tab('voice'), scenario.hasVoice ? findsOneWidget : findsNothing);
      expect(tab('chat'), findsNothing);
      expect(sidebarDestination('Topics'), findsOneWidget);
    });
  }

  testWidgets('empty accessible Voice directory retains room creation', (
    tester,
  ) async {
    await pumpTabs(tester, rooms: false);
    await tester.ensureVisible(tab('voice'));
    await tester.tap(tab('voice'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Create voice room'), findsOneWidget);
    expect(sidebarDestination('Topics'), findsNothing);
  });

  testWidgets(
    'route navigation selects Voice and revoked access falls back to Forum',
    (tester) async {
      final shell = await pumpTabs(tester);
      shell.pushContent(
        const ContentRoute(
          id: 'voice-room-7',
          title: 'Watercooler',
          icon: DIcons.microphoneLines,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<DTabs<String>>(tabs).value, 'voice');
      shell.pluginSession.require(voiceControllerService).forget(site);
      await tester.pumpAndSettle();
      expect(tab('voice'), findsNothing);
      expect(tester.widget<DTabs<String>>(tabs).value, 'forum');
      expect(sidebarDestination('Topics'), findsOneWidget);
    },
  );

  testWidgets('revoking Chat access removes its selected tab', (tester) async {
    final shell = await pumpTabs(tester);
    await tester.tap(tab('chat'));
    await tester.pumpAndSettle();
    shell.accountActivity.applyCounts(
      site,
      (_) => chatNotificationTotals(available: false),
    );
    await tester.pumpAndSettle();
    expect(tab('chat'), findsNothing);
    expect(tab('voice'), findsOneWidget);
    expect(tester.widget<DTabs<String>>(tabs).value, 'forum');
    expect(sidebarDestination('General'), findsNothing);
    expect(sidebarDestination('Topics'), findsOneWidget);
  });

  testWidgets('keyboard moves between sidebar tabs', (tester) async {
    await pumpTabs(tester);
    await tester.tap(tab('main'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<DTabs<String>>(tabs).value, 'chat');
    expect(sidebarDestination('General'), findsOneWidget);
  });
}
