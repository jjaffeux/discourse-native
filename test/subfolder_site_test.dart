import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/group_pages_shell_port.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/global_search_fixtures.dart';
import 'support/shell_test_harness.dart';

const _siteUrl = 'https://example.com/forum';
const _rootSiteUrl = 'https://example.com';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ShellController> loadShell(FakeDiscourseApi api) async {
    final credentials = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('example.com/forum', title: 'Subfolder'),
      ]),
      api: api,
      authenticator: credentials,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      plugins: installedPlugins,
    );
    await shell.load();
    await pumpEventQueue();
    return shell;
  }

  group('a forum served from a subfolder', () {
    test('is stored and addressed under its subfolder', () async {
      final shell = await loadShell(FakeDiscourseApi());
      addTearDown(shell.dispose);

      expect(shell.currentInstance?.url, _siteUrl);
      expect(shell.currentInstance?.host, 'example.com');
      expect(shell.absoluteUrl('/forum/t/a-topic/7'), '$_siteUrl/t/a-topic/7');
    });

    test(
      'opens its own topic links and leaves the rest of the host alone',
      () async {
        final api = FakeDiscourseApi(
          feeds: const {
            '/latest.json': [Topic(id: 7, title: 'A topic', slug: 'a-topic')],
          },
          topics: {
            7: topicPayload(
              id: 7,
              title: 'A topic',
              posts: const [
                Post(
                  id: 1,
                  postNumber: 1,
                  username: 'author',
                  cooked: '<p>x</p>',
                ),
              ],
            ),
          },
        );
        final shell = await loadShell(api);
        addTearDown(shell.dispose);

        expect(shell.openTopicUrl('https://example.com/t/a-topic/7'), isFalse);
        expect(
          shell.openTopicUrl('https://example.com/other/t/a-topic/7'),
          isFalse,
        );
        expect(shell.openTopicUrl('$_siteUrl/t/a-topic/7'), isTrue);
        expect(shell.currentContent?.topicId, 7);
      },
    );

    test('opens the pages the app links to under its subfolder', () async {
      final shell = await loadShell(FakeDiscourseApi());
      addTearDown(shell.dispose);

      expect(shell.siteLink('/latest'), '$_siteUrl/latest');
      expect(shell.siteLink('/u/alice'), '$_siteUrl/u/alice');
      expect(shell.openCorePageUrl(shell.siteLink('/latest')), isTrue);
      expect(shell.currentContent?.id, 'latest');
    });

    test('opens its topic list links in the app', () async {
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': [], '/top.json?period=weekly': []},
      );
      final shell = await loadShell(api);
      addTearDown(shell.dispose);

      expect(
        shell.openCorePageUrl('https://example.com/top?period=weekly'),
        isFalse,
      );
      expect(shell.openCorePageUrl('$_siteUrl/top?period=weekly'), isTrue);
      expect(shell.currentContent?.id, 'top-weekly');
      await pumpEventQueue();
      expect(api.feedPaths, contains('/top.json?period=weekly'));
      expect(shell.currentFeed?.loaded, isTrue);

      expect(shell.openCorePageUrl('$_siteUrl/tags'), isTrue);
      expect(shell.currentContent?.id, 'all-tags');
      expect(shell.openLinkInNewTab('$_siteUrl/hot'), TabOpenResult.opened);
      // Signed out, as on the web, Unread is not this reader's to see.
      expect(shell.openCorePageUrl('$_siteUrl/unread'), isFalse);
      expect(
        shell.openLinkInNewTab('$_siteUrl/unread'),
        TabOpenResult.unsupported,
      );
    });

    test('opens its category, tag and group links in the app', () async {
      final shell = await loadShell(FakeDiscourseApi());
      addTearDown(shell.dispose);

      expect(shell.openListUrl('$_siteUrl/c/general/4'), isTrue);
      expect(shell.currentContent?.feedPath, '/c/general/4.json');
      expect(shell.openListUrl('$_siteUrl/tag/news/3'), isTrue);
      expect(shell.currentContent?.feedPath, '/tag/news/3.json');
      expect(shell.openListUrl('https://example.com/c/general/4'), isFalse);

      expect(shell.openGroupUrl('$_siteUrl/g/staff'), isTrue);
      expect(shell.currentContent?.groupRoute, GroupRoute.detail('staff'));
      expect(shell.openGroupUrl('https://example.com/g/staff'), isFalse);

      expect(
        shell.openLinkInNewTab('$_siteUrl/c/general/4'),
        TabOpenResult.opened,
      );
      expect(shell.openLinkInNewTab('$_siteUrl/g/staff'), TabOpenResult.opened);
    });

    test('opens a group chosen from its directory', () async {
      final shell = await loadShell(FakeDiscourseApi());
      addTearDown(shell.dispose);

      ShellGroupPagesPort(shell).openGroup((
        siteUrl: _siteUrl,
        accountIdentity: shell.currentAccountIdentity!,
        tabId: shell.activeTabId,
      ), 'staff');

      expect(shell.currentContent?.groupRoute, GroupRoute.detail('staff'));
    });

    test('opens the message a membership request produced', () async {
      final api = FakeDiscourseApi(
        topics: {
          42: topicPayload(
            id: 42,
            title: 'Membership request',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'alice',
                cooked: '<p>I run the help desk.</p>',
              ),
            ],
          ),
        },
      );
      final shell = await loadShell(api);
      addTearDown(shell.dispose);

      // Discourse writes the path with the forum's subfolder already on it.
      ShellGroupPagesPort(shell).openMembershipRequest((
        siteUrl: _siteUrl,
        accountIdentity: shell.currentAccountIdentity!,
        tabId: shell.activeTabId,
      ), '/forum/t/membership-request/42');

      expect(shell.currentContent?.topicId, 42);
    });

    testWidgets('shows the card of a user found by search in the app', (
      tester,
    ) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launched = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final api = GlobalSearchFixtureApi();
      await pumpShell(
        tester,
        desktop,
        instances: [
          DiscourseInstance(
            url: _siteUrl,
            title: 'Subfolder',
            user: globalSearchFixtureUser,
          ),
        ],
        api: api,
        authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      );

      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(ForumSearch.inputKey), 'design');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('global-search-result-users:101')),
      );
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      expect(api.cardsRequested, ['mira']);
      expect(find.byKey(const ValueKey('user-card-surface')), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });

  for (final site in const [_rootSiteUrl, _siteUrl]) {
    final prefix = Uri.parse(site).path;
    group('a notification on a forum served from '
        '${site == _siteUrl ? 'a subfolder' : 'the root'}', () {
      testWidgets('opens a reply in the app', (tester) async {
        final menu = await _pumpNotificationMenu(
          tester,
          site,
          notifications: [
            _notification(
              1,
              CoreNotificationTypes.replied,
              topicId: 7,
              postNumber: 3,
            ),
          ],
        );

        await menu.tap('notification-row-1');

        expect(menu.launched, isEmpty);
        expect(menu.shell.currentInstance?.url, site);
        expect(menu.shell.currentContent?.topicId, 7);
        expect(menu.shell.currentContent?.postNumber, 3);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

      testWidgets('opens a mention in the app', (tester) async {
        final menu = await _pumpNotificationMenu(
          tester,
          site,
          notifications: [
            _notification(
              1,
              CoreNotificationTypes.mentioned,
              topicId: 7,
              postNumber: 2,
            ),
          ],
        );

        await menu.tap('notification-row-1');

        expect(menu.launched, isEmpty);
        expect(menu.shell.currentContent?.topicId, 7);
        expect(menu.shell.currentContent?.postNumber, 2);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

      testWidgets(
        "opens the post a bookmark reminder's server link names in the app",
        (tester) async {
          final menu = await _pumpNotificationMenu(
            tester,
            site,
            notifications: [
              _notification(
                1,
                CoreNotificationTypes.bookmarkReminder,
                data: {'bookmarkable_url': '$prefix/t/a-topic/7/3'},
              ),
            ],
          );

          await menu.tap('notification-row-1');

          expect(menu.launched, isEmpty);
          expect(menu.shell.currentContent?.topicId, 7);
          expect(menu.shell.currentContent?.postNumber, 3);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );

      testWidgets(
        'opens a bookmark reminder from the Bookmarks tab in the app',
        (tester) async {
          final menu = await _pumpNotificationMenu(
            tester,
            site,
            reminders: [
              _notification(
                1,
                CoreNotificationTypes.bookmarkReminder,
                topicId: 7,
                postNumber: 3,
              ),
            ],
          );
          await menu.tap('user-menu-tab-${UserMenuSection.bookmarksId}');

          await menu.tap('notification-row-1');

          expect(menu.launched, isEmpty);
          expect(menu.shell.currentContent?.topicId, 7);
          expect(menu.shell.currentContent?.postNumber, 3);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );

      testWidgets(
        'opens a group message summary at the group inbox on the forum',
        (tester) async {
          final menu = await _pumpNotificationMenu(
            tester,
            site,
            notifications: [
              _notification(
                1,
                CoreNotificationTypes.groupMessageSummary,
                data: {
                  'username': 'reader',
                  'group_name': 'staff',
                  'inbox_count': 2,
                },
              ),
            ],
          );

          await menu.tap('notification-row-1');

          // A group inbox has no page in the app on any forum, so it opens
          // in the browser; it must be this forum's inbox that opens.
          expect(menu.launched, ['$site/u/reader/messages/group/staff']);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );

      testWidgets('opens an accepted group membership in the app', (
        tester,
      ) async {
        final menu = await _pumpNotificationMenu(
          tester,
          site,
          notifications: [
            _notification(
              1,
              CoreNotificationTypes.membershipRequestAccepted,
              data: {'group_name': 'staff'},
            ),
          ],
        );

        await menu.tap('notification-row-1');

        expect(menu.launched, isEmpty);
        expect(
          menu.shell.currentContent?.groupRoute,
          GroupRoute.detail('staff'),
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

      testWidgets('opens a reply in another panel from its context menu', (
        tester,
      ) async {
        final menu = await _pumpNotificationMenu(
          tester,
          site,
          notifications: [
            _notification(
              1,
              CoreNotificationTypes.replied,
              topicId: 7,
              postNumber: 3,
            ),
          ],
        );
        menu.shell.desktopTopicTabs = true;
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('notification-row-1')),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open in secondary panel'));
        await tester.pumpAndSettle();

        expect(menu.launched, isEmpty);
        expect(menu.shell.currentContent?.topicId, 7);
        expect(menu.shell.currentContent?.postNumber, 3);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

      testWidgets('opens a chat mention in the app', (tester) async {
        final menu = await _pumpNotificationMenu(
          tester,
          site,
          chatNotifications: [
            _notification(
              51,
              const NotificationWireType(29, 'chat_mention'),
              data: {
                'chat_message_id': 44,
                'chat_channel_id': 9,
                'chat_channel_title': 'Support',
                'mentioned_by_username': 'sam',
              },
            ),
          ],
        );
        await menu.tap('user-menu-tab-chat/notifications');

        await menu.tap('notification-row-51');

        expect(menu.launched, isEmpty);
        expect(menu.shell.currentInstance?.url, site);
        expect(menu.shell.currentContent?.id, 'chat-c-9');
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

      test('resolves plugin notification links under the forum', () async {
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            DiscourseInstance(url: site, title: 'Forum', apiVersion: 4),
          ]),
          api: FakeDiscourseApi(),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          plugins: installedPlugins,
        );
        addTearDown(shell.dispose);
        await shell.load();

        expect(
          shell.pluginAbsoluteUrl(
            '/my/preferences/notifications',
            siteUrl: site,
          ),
          '$site/my/preferences/notifications',
        );
      });
    });
  }
}

final DiscourseUser _reader = DiscourseUser(
  id: 1,
  username: 'reader',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);

DiscourseNotification _notification(
  int id,
  NotificationWireType type, {
  int? topicId,
  int? postNumber,
  Map<String, Object?> data = const {},
}) => DiscourseNotification.test(
  id: id,
  typeId: NotificationTypeId(type.wireId),
  topicId: topicId,
  postNumber: postNumber,
  slug: topicId == null ? '' : 'a-topic',
  title: topicId == null ? '' : 'A topic',
  data: {'display_username': 'sam', ...data},
);

typedef _NotificationMenu = ({
  ShellController shell,
  List<String> launched,
  Future<void> Function(String key) tap,
});

Future<_NotificationMenu> _pumpNotificationMenu(
  WidgetTester tester,
  String site, {
  List<DiscourseNotification> notifications = const [],
  List<DiscourseNotification> reminders = const [],
  List<DiscourseNotification> chatNotifications = const [],
}) async {
  final launched = watchBrowser(tester);
  final api = FakeDiscourseApi(
    user: _reader,
    totals: chatNotificationTotals(chatNotifications: chatNotifications.length),
    notificationList: notifications,
    chatNotificationList: chatNotifications,
    reminderList: reminders,
    bookmarkList: const [],
    feeds: const {'/latest.json': []},
    topics: {
      7: topicPayload(
        id: 7,
        title: 'A topic',
        posts: const [
          Post(id: 1, postNumber: 1, username: 'author', cooked: '<p>x</p>'),
        ],
      ),
    },
    chatChannelsBySite: {
      site: const ChatChannels(
        public: [
          ChatChannel(
            id: 9,
            title: 'Support',
            kind: ChatChannelKind.category,
            membership: ChatMembership(following: true),
            tracking: ChatTracking(),
          ),
        ],
      ),
    },
  );
  await pumpShell(
    tester,
    desktop,
    instances: [
      DiscourseInstance(
        url: site,
        title: 'Forum',
        apiVersion: 4,
        user: _reader,
      ),
    ],
    api: api,
    authenticator: FakeAuthenticator()..keys[site] = 'api-key',
  );
  await tester.tap(find.byKey(UserMenuButton.bellKey));
  await tester.pumpAndSettle();
  final shell = ShellScope.read(tester.element(find.byType(UserMenuPanel)));
  Future<void> tap(String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  return (shell: shell, launched: launched, tap: tap);
}
