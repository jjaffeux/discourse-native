import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_drawer.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/groups_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_indicators.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:flutter/material.dart';

import '../../test/support/bundled_plugins.dart';
import '../../test/support/fakes.dart';

const badgeFixtureSite = 'https://badge-review.invalid';

/// Real app widgets backed only by in-memory test adapters. No account writes.
Future<ShellController> createBadgeFixtureController() async {
  const user = DiscourseUser(id: 7, username: 'reader');
  final totals = chatNotificationTotals();
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      DiscourseInstance(
        url: badgeFixtureSite,
        title: 'Badge review',
        user: user,
        notificationTotals: totals,
      ),
    ]),
    api: FakeDiscourseApi(
      totals: totals,
      user: user,
      cards: const {
        'reviewer': UserCard(
          username: 'reviewer',
          name: 'Review account',
          isStaff: true,
          badgeCount: 123,
        ),
      },
      chatChannelsBySite: const {
        badgeFixtureSite: ChatChannels(
          public: [
            ChatChannel(
              id: 9,
              title: 'Review channel',
              kind: ChatChannelKind.category,
              membership: ChatMembership(following: true),
              tracking: ChatTracking(mentionCount: 123),
            ),
          ],
        ),
      },
    ),
    authenticator: FakeAuthenticator()
      ..keys[badgeFixtureSite] = 'local-fixture-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  await controller.pluginSession
      .require(chatControllerService)
      .loadChannels(badgeFixtureSite);
  return controller;
}

class BadgeMigrationFixtures extends StatelessWidget {
  const BadgeMigrationFixtures({super.key, required this.controller});
  final ShellController controller;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TopicUnreadBadge(count: 1),
            TopicUnreadBadge(count: 123),
            UserCardTarget(
              username: 'reviewer',
              siteUrl: badgeFixtureSite,
              child: Text('Open staff profile'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 350,
          child: GroupsPage(
            siteUrl: badgeFixtureSite,
            data: const GroupsPageData(
              loaded: true,
              groups: [
                Group(
                  id: 1,
                  name: 'review-members',
                  fullName: 'Community members',
                  userCount: 123,
                  isGroupUser: true,
                ),
                Group(
                  id: 2,
                  name: 'review-owners',
                  fullName: 'Community owners',
                  userCount: 4,
                  isGroupOwner: true,
                ),
              ],
            ),
            onOpenGroup: (_) {},
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 280,
          child: PluginUiScope.own(
            chatPluginId,
            const ChatDrawerChannelsView(
              siteUrl: badgeFixtureSite,
              kind: ChatDrawerChannelListKind.channels,
            ),
          ),
        ),
      ],
    ),
  );
}
