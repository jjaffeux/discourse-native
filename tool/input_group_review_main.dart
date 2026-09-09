// Offline native review of the actual Input Group styleguide and Chat adopters.
// All reads and writes use in-memory fakes; no account or network is used.
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_direct_message_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/widgets.dart';

import '../test/support/bundled_plugins.dart';
import '../test/support/fakes.dart';

const _site = 'https://input-group-review.invalid';

const _channel = ChatChannel(
  id: 9,
  title: 'Input Group review',
  kind: ChatChannelKind.category,
  description: 'Offline production search fixture',
  membership: ChatMembership(following: true),
  tracking: ChatTracking(),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(searchEnabled: true),
    ),
  );
  final chatUser = DiscourseUser(
    id: 7,
    username: 'reviewer',
    name: 'Input Group Reviewer',
    staff: true,
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(
        hasChatEnabled: true,
        canChat: true,
        canDirectMessage: true,
      ),
    ),
  );
  final reviewInstance = instance(
    'input-group-review.invalid',
    title: 'Input Group Review',
  ).copyWith(user: chatUser, config: config);
  final authenticator = FakeAuthenticator()..keys[_site] = 'offline-key';
  final api = FakeDiscourseApi(
    totals: chatNotificationTotals(),
    user: chatUser,
    siteConfigs: {_site: config},
    chatChannelsBySite: {
      _site: const ChatChannels(public: [_channel]),
    },
    chatChannelsById: const {9: _channel},
    chatDirectMessageSearches: {
      'sam': ChatDirectMessageSearchResults(const [
        ChatDirectMessageUser(
          identifier: 'u-2',
          matchQuality: 1,
          enabled: true,
          username: 'sam',
          name: 'Sam Example',
        ),
      ]),
    },
    chatSearchPagesByKey: {
      FakeDiscourseApi.chatSearchKey('needle'): const ChatSearchPage(hits: []),
    },
  );
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    DiscourseApp(
      store: FakeInstanceStore([reviewInstance]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
      pluginManifest: bundledWidgetTestManifest,
    ),
  );
}
