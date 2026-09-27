import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
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
  List<SidebarSection>? customSections,
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
      customSidebarSectionsBySite: {site: ?customSections},
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

void _desktopTest(String name, WidgetTesterCallback callback) => testWidgets(
  name,
  callback,
  variant: TargetPlatformVariant.only(TargetPlatform.macOS),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  _desktopTest('Shortcuts owns custom sections and configured links', (
    tester,
  ) async {
    final shell = await pumpTabs(
      tester,
      installed: false,
      customSections: const [
        SidebarSection(
          id: 'community',
          title: 'Community',
          destinations: [],
          moreDestinations: [
            SidebarDestination(
              id: 'community-1-1',
              label: 'About this forum',
              icon: DIcons.link,
              url: '/about',
            ),
          ],
        ),
        SidebarSection(
          id: 'custom-2',
          title: 'Projects',
          destinations: [
            SidebarDestination(
              id: 'custom-2-20',
              label: 'Roadmap',
              icon: DIcons.link,
              url: '/c/roadmap/4',
            ),
          ],
        ),
      ],
    );
    final route = shell.currentContent;
    expect(tabs, findsOneWidget);
    expect(tab('chat'), findsNothing);
    expect(tab('shortcuts'), findsOneWidget);
    expect(sidebarDestination('Topics'), findsOneWidget);
    expect(sidebarDestination('Roadmap'), findsNothing);
    expect(sidebarDestination('About this forum'), findsNothing);

    await tester.tap(tab('shortcuts'));
    await tester.pumpAndSettle();
    expect(tester.widget<DTabs<String>>(tabs).value, 'shortcuts');
    expect(sidebarDestination('Topics'), findsNothing);
    expect(sidebarDestination('Roadmap'), findsOneWidget);
    expect(sidebarDestination('About this forum'), findsOneWidget);
    expect(shell.currentContent, route);

    await tester.tap(tab('main'));
    await tester.pumpAndSettle();
    expect(sidebarDestination('Topics'), findsOneWidget);
    expect(sidebarDestination('Roadmap'), findsNothing);
  });

  _desktopTest(
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

  _desktopTest('the Chat tab total replaces per-section totals and updates', (
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

    final total = find.byKey(const ValueKey('chat-sidebar-unread-badge'));
    Finder inTotal(String text) =>
        find.descendant(of: total, matching: find.text(text));
    expect(inTotal('${chat.unreadMessageCount(site)}'), findsOneWidget);
    for (final title in ['Starred channels', 'Chat', 'Direct messages']) {
      expect(find.widgetWithText(DSidebarMenuButton, title), findsNothing);
    }
    expect(find.byKey(const ValueKey('chat-inbox-channel-11')), findsOneWidget);

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
    expect(chat.unreadMessageCount(site), 2);
    expect(inTotal('2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _desktopTest(
    'Chat contains text and voice destinations without navigating or joining',
    (tester) async {
      final shell = await pumpTabs(tester);
      final route = shell.currentContent;
      final count = shell.tabsForCurrentForum.length;
      expect(tabs, findsOneWidget);
      expect(tab('voice'), findsNothing);
      expect(sidebarDestination('Topics'), findsOneWidget);
      expect(sidebarDestination('General'), findsNothing);
      expect(sidebarDestination('Watercooler'), findsNothing);
      for (final (owner, destination) in [
        ('chat', 'General'),
        ('chat', 'Watercooler'),
        ('main', 'Topics'),
      ]) {
        await tester.ensureVisible(tab(owner));
        await tester.pumpAndSettle();
        // The touch resize handle overlays the sidebar's trailing edge.
        await tester.tapAt(
          tester.getRect(tab(owner)).centerLeft + const Offset(8, 0),
        );
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
    _desktopTest(scenario.name, (tester) async {
      await pumpTabs(
        tester,
        chat: scenario.chat,
        voice: scenario.voice,
        voiceAccess: scenario.access,
        connected: scenario.connected,
        installed: scenario.installed,
      );
      expect(tabs, findsOneWidget);
      expect(tab('shortcuts'), findsOneWidget);
      expect(tab('voice'), findsNothing);
      expect(tab('chat'), scenario.hasVoice ? findsOneWidget : findsNothing);
      expect(sidebarDestination('Topics'), findsOneWidget);
    });
  }

  _desktopTest('empty accessible Voice directory has no creation button', (
    tester,
  ) async {
    await pumpTabs(tester, rooms: false);
    await tester.ensureVisible(tab('chat'));
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getRect(tab('chat')).centerLeft + const Offset(8, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Create voice room'), findsNothing);
    expect(find.text('Voice rooms'), findsNothing);
    expect(sidebarDestination('Topics'), findsNothing);
  });

  _desktopTest(
    'voice room navigation selects Chat and revoked voice access falls back to Forum',
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
      expect(tester.widget<DTabs<String>>(tabs).value, 'chat');
      shell.pluginSession.require(voiceControllerService).forget(site);
      await tester.pumpAndSettle();
      expect(tab('voice'), findsNothing);
      expect(tester.widget<DTabs<String>>(tabs).value, 'forum');
      expect(sidebarDestination('Topics'), findsOneWidget);
    },
  );

  _desktopTest('revoking text Chat access keeps voice rooms inside Chat', (
    tester,
  ) async {
    final shell = await pumpTabs(tester);
    await tester.tap(tab('chat'));
    await tester.pumpAndSettle();
    shell.accountActivity.applyCounts(
      site,
      (_) => chatNotificationTotals(available: false),
    );
    await tester.pumpAndSettle();
    expect(tab('chat'), findsOneWidget);
    expect(tab('voice'), findsNothing);
    expect(tester.widget<DTabs<String>>(tabs).value, 'chat');
    expect(sidebarDestination('General'), findsNothing);
    expect(sidebarDestination('Watercooler'), findsOneWidget);
    expect(find.byTooltip('Create voice room'), findsNothing);
    expect(find.bySemanticsLabel('Collapse Voice rooms'), findsNothing);
    expect(find.bySemanticsLabel('Expand Voice rooms'), findsNothing);
    expect(find.text('Empty'), findsNothing);
    expect(sidebarDestination('Topics'), findsNothing);
  });

  _desktopTest('keyboard moves between sidebar tabs', (tester) async {
    await pumpTabs(tester);
    await tester.tap(tab('main'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<DTabs<String>>(tabs).value, 'chat');
    expect(sidebarDestination('General'), findsOneWidget);
  });
}
