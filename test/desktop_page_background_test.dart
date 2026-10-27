import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_info_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_inbox_header.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

void main() {
  const site = 'https://meta.discourse.org';
  const canvas = Color(0xff47395a);
  const capture = ValueKey('page-background-capture');
  const user = DiscourseUser(id: 7, username: 'reader', canCreateTopic: true);
  const channel = ChatChannel(
    id: 9,
    title: 'General',
    kind: ChatChannelKind.category,
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final pageName in [
    'topic header',
    'group header and tabs',
    'user directory',
    'channel info tabs',
    'chat sidebar filters',
    'composer',
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('$pageName inherits its desktop panel in $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final shell = ShellController(
          plugins: installedPlugins,
          instanceStore: FakeInstanceStore([
            instance('meta.discourse.org').copyWith(user: user),
          ]),
          api: FakeDiscourseApi(
            user: user,
            feeds: const {'/latest.json': []},
            creatableFeedPaths: const {'/latest.json'},
            chatChannelsBySite: const {
              site: ChatChannels(public: [channel]),
            },
          ),
          authenticator: FakeAuthenticator()..keys[site] = 'key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);
        await shell.load();
        await shell.chat.loadChannels(site);
        if (pageName == 'composer') await shell.openNewTopicFromSidebar();

        for (final (name, page, anchors) in <(String, Widget, List<Finder>)>[
          if (pageName == 'composer')
            (
              'composer',
              ComposerPanel(composer: shell.visibleComposer!, height: 800),
              [find.byKey(const ValueKey('composer-header'))],
            ),
          (
            'topic header',
            const TopicInboxHeader(
              title: 'A topic',
              siteUrl: site,
              canReturnToSidebar: false,
              keepTopicListOpen: false,
              registry: PluginRegistry.empty,
              loading: true,
            ),
            [
              find.byKey(const ValueKey('topic-content-header')),
              find.byKey(const ValueKey('topic-header-taxonomy-placeholder')),
            ],
          ),
          (
            'group header and tabs',
            GroupPage(
              siteUrl: site,
              route: GroupRoute.detail('support'),
              registry: PluginRegistry.empty,
              data: const GroupPageData(
                detail: GroupDetail(
                  group: Group(
                    id: 9,
                    name: 'support',
                    fullName: 'Support Team',
                    canSeeMembers: true,
                  ),
                ),
              ),
              onOpenMember: (_, _) {},
            ),
            [
              find.text('Support Team'),
              find.byKey(const ValueKey('group-primary-tabs')),
            ],
          ),
          (
            'user directory',
            const UsersPage(siteUrl: site, data: UsersPageData(loaded: true)),
            [find.byKey(const ValueKey('users-search'))],
          ),
          (
            'channel info tabs',
            ChatChannelInfoView(
              siteUrl: site,
              channelId: channel.id,
              tab: ChatChannelInfoTab.members,
              chat: shell.chat,
            ),
            [find.byKey(const ValueKey('chat-channel-info-tabs'))],
          ),
          (
            'chat sidebar filters',
            const Align(
              alignment: Alignment.topLeft,
              child: ChatSidebarInboxHeader(siteUrl: site),
            ),
            [find.byType(ChatInboxFilterBar)],
          ),
        ]) {
          if (name != pageName) continue;
          await tester.pumpWidget(
            ShellScope(
              controller: shell,
              child: PluginUiScope.own(
                chatPluginId,
                MaterialApp(
                  themeAnimationStyle: AnimationStyle.noAnimation,
                  theme: AppTheme.forBrightness(
                    brightness,
                  ).copyWith(platform: TargetPlatform.macOS),
                  home: RepaintBoundary(
                    key: capture,
                    child: DPageSurface(
                      border: false,
                      borderRadius: BorderRadius.zero,
                      backgroundColor: canvas,
                      child: TickerMode(enabled: false, child: page),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: name);
          final origin = tester.getTopLeft(find.byKey(capture));
          final probes = [
            for (final anchor in anchors)
              name == 'chat sidebar filters'
                  ? tester.getTopLeft(anchor) + const Offset(500, 1)
                  : Offset(origin.dx + 2, tester.getCenter(anchor).dy),
          ];
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(find.byKey(capture))
                .toImage();
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              for (final probe in probes) {
                final local = probe - origin;
                final offset =
                    (local.dy.floor() * image.width + local.dx.floor()) * 4;
                expect(
                  List.generate(
                    4,
                    (channel) => bytes.getUint8(offset + channel),
                  ),
                  [71, 57, 90, 255],
                  reason: '$name at $probe',
                );
              }
            } finally {
              image.dispose();
            }
          });
        }
      });
    }
  }
}
