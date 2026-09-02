import 'dart:async';

import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_menu.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/finders.dart';

import 'support/shell_test_harness.dart';

void main() {
  _registerConnectionSessionTests();
}

void _registerConnectionSessionTests() {
  group('connecting', () {
    testWidgets('signed-out sites show sign-up and sign-in actions', (
      tester,
    ) async {
      await pumpShell(tester, desktop);

      expect(find.byKey(UserMenuButton.signUpKey), findsOneWidget);
      expect(find.byKey(UserMenuButton.signInKey), findsOneWidget);
      expect(find.byKey(UserMenuButton.avatarKey), findsNothing);

      final signUp = tester.getRect(find.byKey(UserMenuButton.signUpKey));
      final signUpLabel = tester.getRect(find.text('Sign up'));
      expect(signUpLabel.left - signUp.left, moreOrLessEquals(11.4));
      expect(signUp.right - signUpLabel.right, moreOrLessEquals(11.4));

      final signIn = tester.getRect(find.byKey(UserMenuButton.signInKey));
      final signInIcon = tester.getRect(find.dIcon(DIcons.user));
      final signInLabel = tester.getRect(find.text('Sign in'));
      expect(signInIcon.left - signIn.left, moreOrLessEquals(11.4));
      expect(signIn.right - signInLabel.right, moreOrLessEquals(11.4));
    });

    testWidgets('aggregate hides forum account actions', (tester) async {
      await pumpShell(tester, desktop);

      expect(find.byKey(UserMenuButton.signUpKey), findsOneWidget);
      expect(find.byKey(UserMenuButton.signInKey), findsOneWidget);

      final controller = ShellScope.read(
        tester.element(find.byType(ShellTitleBar)),
      );
      controller.selectAggregate();
      await tester.pump();

      expect(find.byKey(UserMenuButton.signUpKey), findsNothing);
      expect(find.byKey(UserMenuButton.signInKey), findsNothing);
      expect(find.byKey(UserMenuButton.avatarKey), findsNothing);

      controller.selectInstance(0);
      await tester.pump();

      expect(find.byKey(UserMenuButton.signUpKey), findsOneWidget);
      expect(find.byKey(UserMenuButton.signInKey), findsOneWidget);
    });

    testWidgets('sign-up opens the selected forum registration page', (
      tester,
    ) async {
      final launched = watchBrowser(tester);
      await pumpShell(tester, desktop);

      await tester.tap(find.byKey(UserMenuButton.signUpKey));
      await tester.pumpAndSettle();

      expect(launched, ['https://meta.discourse.org/signup']);
    });

    testWidgets('records the account against the site', (tester) async {
      final store = FakeInstanceStore(twoSites);
      final auth = FakeAuthenticator();

      await pumpShell(tester, desktop, store: store, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(auth.connected, ['https://meta.discourse.org']);
      expect(find.byTooltip('Joffrey'), findsOneWidget);
      expect(find.text('meta.discourse.org'), findsNothing);
      expect(store.saveCount, 2);
    });

    testWidgets('backing out of the browser is not an error', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.cancelled);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(find.byKey(UserMenuButton.signInKey), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('an unverifiable reply is surfaced', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.badReply);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('could not be verified'), findsOneWidget);
    });

    testWidgets('a browser that never opened is surfaced', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.launchFailed);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Could not open'), findsOneWidget);
    });

    testWidgets('a private-site sign-in failure stays actionable in the gate', (
      tester,
    ) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.launchFailed);
      final api = FakeDiscourseApi();
      final privateSite = instance(
        'meetup.discourse.org',
        title: 'Discourse Meetup',
      ).copyWith(loginRequired: true);
      final publicSite = instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      );

      await pumpShell(
        tester,
        desktop,
        instances: [privateSite, publicSite],
        api: api,
        authenticator: auth,
      );

      expect(api.feedPaths, isEmpty);
      expect(api.appearancesRequested, isEmpty);
      expect(api.siteConfigsRequested, isEmpty);
      expect(api.customEmojisRequired, isEmpty);
      expect(api.categoryRequests, isEmpty);

      expect(find.byType(MainContent), findsNothing);
      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      expect(find.byType(ForumTabsBar), findsNothing);
      expect(find.byType(ShellTitleBar), findsOneWidget);
      expect(find.byKey(ForumSearch.inputKey), findsNothing);
      expect(userMenu, findsNothing);
      expect(find.byKey(ValueKey(privateSite.url)), findsOneWidget);
      expect(find.byKey(ValueKey(publicSite.url)), findsOneWidget);

      await tester.tap(find.byKey(ValueKey(publicSite.url)));
      await tester.pumpAndSettle();
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);

      await tester.tap(find.byKey(ValueKey(privateSite.url)));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to continue'), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);

      await tester.tap(find.byKey(const ValueKey('private-forum-sign-in')));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to continue'), findsOneWidget);
      expect(find.textContaining('Could not open'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('private-forum-sign-in')),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('counters appear once connected', (tester) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        name: 'Joffrey',
        draftCount: 4,
      );
      final api = FakeDiscourseApi(
        user: user,
        totals: const NotificationTotals(
          unreadNotifications: 3,
          unreadPersonalMessages: 2,
          topicTrackingNew: 19,
        ),
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      Finder countFor(String destinationId, String count) => find.descendant(
        of: find.byKey(ValueKey(destinationId)),
        matching: find.text(count),
      );

      expect(countFor('latest', '19'), findsOneWidget);
      expect(countFor('messages', '2'), findsOneWidget);
      expect(countFor('drafts', '4'), findsOneWidget);
      expect(find.text('5'), findsNWidgets(2));
      expect(api.totalsCalls, 1);
    });

    testWidgets('a site whose counters fail still renders', (tester) async {
      final api = FakeDiscourseApi();

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Joffrey'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching to a connected site refreshes its counters', (
      tester,
    ) async {
      final connected = [
        instance('meta.discourse.org', title: 'Discourse Meta'),
        instance('team.discourse.org', title: 'Discourse Team'),
      ];
      final api = FakeDiscourseApi(totals: const NotificationTotals());
      final auth = FakeAuthenticator();

      await pumpShell(
        tester,
        desktop,
        instances: connected,
        api: api,
        authenticator: auth,
      );

      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      final afterConnect = api.totalsCalls;

      await tester.tap(find.text('DT'));
      await tester.pumpAndSettle();
      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(api.totalsCalls, greaterThan(afterConnect));
      expect(auth.connected, [
        'https://meta.discourse.org',
        'https://team.discourse.org',
      ]);
    });

    testWidgets('disconnecting revokes the key with the site', (tester) async {
      final api = FakeDiscourseApi(totals: const NotificationTotals());
      final auth = FakeAuthenticator();

      await pumpShell(tester, desktop, api: api, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      await _openProfileSection(tester);
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(api.revoked, ['https://meta.discourse.org']);
      expect(auth.disconnected, ['https://meta.discourse.org']);
    });

    testWidgets('disconnecting forgets the key and the account', (
      tester,
    ) async {
      final auth = FakeAuthenticator();
      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Joffrey'), findsOneWidget);

      await _openProfileSection(tester);
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(auth.disconnected, ['https://meta.discourse.org']);
      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.byKey(UserMenuButton.signUpKey), findsOneWidget);
      expect(find.byKey(UserMenuButton.signInKey), findsOneWidget);
    });
  });

  group('the user menu', () {
    const me = DiscourseUser(
      username: 'joffreyj',
      name: 'Joffrey',
      hidePresence: false,
    );
    final connected = [
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: me),
    ];

    FakeAuthenticator signedIn() =>
        FakeAuthenticator()..keys['https://meta.discourse.org'] = 'api-key';

    const notifications = [
      DiscourseNotification.test(
        id: 1,
        typeId: NotificationTypeId(2),
        title: 'Better image handling',
        topicId: 7,
        slug: 'better-image-handling',
        data: {'display_username': 'sam'},
      ),
      DiscourseNotification.test(
        id: 2,
        typeId: NotificationTypeId(5),
        read: true,
        title: 'Merge CVSS',
        topicId: 8,
        slug: 'merge-cvss',
        data: {'display_username': 'david'},
      ),
      DiscourseNotification.test(
        id: 3,
        typeId: NotificationTypeId(12),
        data: {
          'badge_id': 24,
          'badge_name': 'Nice Reply',
          'badge_slug': 'nice-reply',
        },
      ),
      DiscourseNotification.test(
        id: 4,
        typeId: NotificationTypeId(4242),
        title: 'Something from a plugin',
      ),
    ];

    final chatEnabledTotals = chatNotificationTotals(chatNotifications: 1);
    const emptyChatChannels = ChatChannels(
      public: <ChatChannel>[],
      direct: <ChatChannel>[],
    );
    final chatMention = DiscourseNotification.fromJson(const {
      'id': 51,
      'notification_type': 29,
      'read': false,
      'created_at': '2026-08-09T08:00:00.000Z',
      'data': {
        'chat_message_id': 44,
        'chat_channel_id': 9,
        'chat_channel_title': '#dev',
        'mentioned_by_username': 'sam',
      },
    });

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
    }

    Future<void> openNotifications(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
    }

    Future<void> openReplies(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Replies'));
      await tester.pumpAndSettle();
    }

    Future<void> openChat(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
    }

    testWidgets('notification rows render site emoji shortcodes', (
      tester,
    ) async {
      const notification = DiscourseNotification.test(
        id: 52,
        typeId: NotificationTypeId(2),
        title: ':telephone: Engineering call',
        data: {'display_username': 'sam'},
      );
      final api = FakeDiscourseApi(
        notificationList: const [notification],
        emojisBySite: const {
          'https://meta.discourse.org': [
            SiteEmoji(name: 'telephone', url: '/images/emoji/telephone.png'),
          ],
        },
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);

      final row = find.byType(NotificationRow);
      expect(
        find.descendant(of: row, matching: find.byType(SiteEmojiImage)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SiteEmojiImage>(
              find.descendant(of: row, matching: find.byType(SiteEmojiImage)),
            )
            .name,
        'telephone',
      );
      expect(api.emojisRequested, ['https://meta.discourse.org']);
    });

    testWidgets('a thumb gets a sheet, and one sheet per section inside it', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        replyNotificationList: [notifications.first],
      );
      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openMenu(tester);

      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.text('Joffrey'), findsOneWidget);
      expect(find.text('@joffreyj · meta.discourse.org'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Replies')).style?.color,
        isNot(Theme.of(tester.element(find.text('Replies'))).shell.placeholder),
      );

      await tester.tap(find.text('Replies'));
      await tester.pumpAndSettle();

      expect(api.replyNotificationCalls, 1);
      expect(api.notificationFilters.single, userMenuReplyNotificationTypes);
      expect(
        find.textContaining('sam replied to Better image handling'),
        findsOneWidget,
      );
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.dIcon(DIcons.arrowLeft), findsOneWidget);

      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.textContaining('sam replied to'), findsNothing);
    });

    testWidgets('a title bar takes the avatar off the columns', (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpShell(
          tester,
          desktop,
          instances: connected,
          key: const ValueKey('macos'),
        );

        expect(userMenu, findsOneWidget);
        final avatar = tester.getRect(userMenu);

        expect(
          tester.getRect(find.byType(ShellTitleBar)).contains(avatar.center),
          isTrue,
        );
        expect(
          avatar.bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(MainContent)).top),
        );
        expect(desktop.width - avatar.right, lessThan(16));
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('a reply opens its topic and is marked read', (tester) async {
      final api = FakeDiscourseApi(
        replyNotificationList: [notifications.first],
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Better image handling',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>First post body</p>',
              ),
            ],
            stream: const [1],
          ),
        },
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openReplies(tester);
      await tester.tap(
        find.textContaining('sam replied to Better image handling'),
      );
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(api.markedRead, [1]);
      expect(find.byType(RepliesSection), findsNothing);
      expect(renderedText('First post body'), findsOneWidget);
    });

    testWidgets('a reaction notification refreshes a post already open', (
      tester,
    ) async {
      const notification = DiscourseNotification.test(
        id: 5,
        typeId: NotificationTypeId(25),
        title: 'Better image handling',
        topicId: 7,
        postNumber: 1,
        slug: 'better-image-handling',
        data: {'display_username': 'david'},
      );
      Post reactionPost(List<Reaction> reactions) => Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked: '<p>First post body</p>',
        plugins: PluginData.none.withValue(
          reactionsDataKey,
          Reactions(entries: reactions, userCount: reactions.length),
        ),
      );
      final topics = <int, TopicPayload>{
        7: topicPayload(
          id: 7,
          title: 'Better image handling',
          posts: [reactionPost(const [])],
        ),
      };
      final api = FakeDiscourseApi(
        notificationList: const [notification],
        feeds: const {
          '/latest.json': [
            Topic(
              id: 7,
              title: 'Better image handling',
              slug: 'better-image-handling',
            ),
          ],
        },
        topics: topics,
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      final controller = tester
          .widget<ShellScope>(find.byType(ShellScope))
          .notifier!;
      controller.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'better-image-handling',
          title: 'Better image handling',
        ),
      );
      await controller.loadTopic(7, 'better-image-handling');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post-reaction-1-clap')), findsNothing);

      topics[7] = topicPayload(
        id: 7,
        title: 'Better image handling',
        posts: [
          reactionPost(const [Reaction(id: 'clap', count: 1)]),
        ],
      );
      await tester.tap(find.byTooltip('Show topic sidebar'));
      await tester.pumpAndSettle();
      await openNotifications(tester);
      await tester.tap(find.textContaining('david reacted to your post in'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7, 7]);
      expect(api.markedRead, [5]);
      expect(
        find.byKey(const ValueKey('post-reaction-1-clap')),
        findsOneWidget,
      );
    });

    testWidgets('Replies can retry a failed filtered request', (tester) async {
      final api = FakeDiscourseApi();

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openReplies(tester);

      expect(find.textContaining("Couldn't reach"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.replyNotificationCalls, 2);
      expect(api.notificationCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty Replies tab stops waiting', (tester) async {
      final api = FakeDiscourseApi(replyNotificationList: const []);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openReplies(tester);

      expect(find.text('Nothing new.'), findsOneWidget);
    });

    testWidgets('the pointer Chat tab requests and renders its own feed', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final api = FakeDiscourseApi(
          totals: chatEnabledTotals,
          notificationList: const [],
          chatNotificationList: [chatMention],
          chatChannelsBySite: const {
            'https://meta.discourse.org': emptyChatChannels,
          },
        );
        await pumpShell(
          tester,
          desktop,
          instances: connected,
          api: api,
          authenticator: signedIn(),
          key: const ValueKey('pointer-chat-menu'),
        );
        await openMenu(tester);

        final chatTab = find.descendant(
          of: find.byType(UserMenuPanel),
          matching: find.byTooltip('Chat'),
        );
        expect(chatTab, findsOneWidget);
        await tester.tap(chatTab);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('sam mentioned you in #dev'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(NotificationRow),
            matching: find.dIcon(DIcons.comment),
          ),
          findsOneWidget,
        );
        expect(api.chatNotificationCalls, 1);
        expect(api.notificationCalls, 1);
        expect(api.replyNotificationCalls, 0);
        expect(api.notificationFilters, [
          const <NotificationTypeName>[],
          chatNotificationFeed.filterByTypes,
        ]);

        final title = find.text('Chat');
        final placeholder = Theme.of(tester.element(title)).shell.placeholder;
        expect(tester.widget<Text>(title).style?.color, isNot(placeholder));
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('a Chat row marks read, opens its link, and dismisses', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        totals: chatEnabledTotals,
        chatNotificationList: [chatMention],
        chatChannelsBySite: const {
          'https://meta.discourse.org': emptyChatChannels,
        },
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openChat(tester);
      await tester.tap(find.textContaining('sam mentioned you in #dev'));
      await tester.pumpAndSettle();

      expect(api.markedRead, [51]);
      expect(launched, ['https://meta.discourse.org/chat/c/-/9/44']);
      expect(find.byType(ChatUserMenuNotifications), findsNothing);
      expect(find.text('@joffreyj · meta.discourse.org'), findsNothing);
      expect(api.notificationFilters, [chatNotificationFeed.filterByTypes]);
    });

    testWidgets('an empty Chat tab explains that there is no activity', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        totals: chatEnabledTotals,
        chatNotificationList: const [],
        chatChannelsBySite: const {
          'https://meta.discourse.org': emptyChatChannels,
        },
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openChat(tester);

      expect(
        find.text('You don’t have any chat notifications yet.'),
        findsOneWidget,
      );
      expect(api.chatNotificationCalls, 1);
    });

    testWidgets('Chat can retry a failed filtered request', (tester) async {
      final api = FakeDiscourseApi(
        totals: chatEnabledTotals,
        chatChannelsBySite: const {
          'https://meta.discourse.org': emptyChatChannels,
        },
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openChat(tester);

      expect(find.textContaining("Couldn't reach"), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.chatNotificationCalls, 2);
      expect(api.notificationCalls, 0);
      expect(api.notificationFilters, [
        chatNotificationFeed.filterByTypes,
        chatNotificationFeed.filterByTypes,
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Chat is hidden when the site does not make it available', (
      tester,
    ) async {
      final api = FakeDiscourseApi(totals: const NotificationTotals());

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openMenu(tester);

      expect(find.text('Chat'), findsNothing);
      expect(api.chatNotificationCalls, 0);
    });

    testWidgets('Chat is hidden when the current user disabled it', (
      tester,
    ) async {
      final userWithoutChat = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        plugins: PluginData.none.withValue(
          chatCurrentUserDataKey,
          const ChatCurrentUser(hasChatEnabled: false),
        ),
      );
      final api = FakeDiscourseApi(
        user: userWithoutChat,
        totals: chatEnabledTotals,
        chatNotificationList: [chatMention],
        chatChannelsBySite: const {
          'https://meta.discourse.org': emptyChatChannels,
        },
      );

      await pumpShell(
        tester,
        phone,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: userWithoutChat),
        ],
        api: api,
        authenticator: signedIn(),
      );
      await openMenu(tester);

      expect(find.text('Chat'), findsNothing);
      expect(api.chatNotificationCalls, 0);
    });

    testWidgets('a pointer gets a popover with a tab per section', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpShell(
          tester,
          desktop,
          instances: connected,
          api: FakeDiscourseApi(notificationList: notifications),
          authenticator: signedIn(),
          key: const ValueKey('macos'),
        );
        await openMenu(tester);

        expect(find.byType(UserMenuPanel), findsOneWidget);
        expect(
          find.textContaining('sam replied to Better image handling'),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Likes'));
        await tester.pumpAndSettle();

        expect(find.text('Likes'), findsOneWidget);
        expect(find.textContaining('sam replied to'), findsNothing);
        expect(find.textContaining('liked your post'), findsNWidgets(2));
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('the pointer messages tab opens the full inbox', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final api = FakeDiscourseApi(
          feeds: {
            '/latest.json': const [],
            '/topics/private-messages/joffreyj.json': const [
              Topic(id: 9, title: 'A private message', slug: 'a-pm'),
            ],
          },
        );
        await pumpShell(
          tester,
          desktop,
          instances: connected,
          api: api,
          authenticator: signedIn(),
          key: const ValueKey('pointer-messages'),
        );
        await openMenu(tester);

        await tester.tap(find.byTooltip('Messages'));
        await tester.pumpAndSettle();

        expect(find.byType(UserMenuPanel), findsNothing);
        expect(find.text('A private message'), findsOneWidget);
        expect(
          api.feedPaths,
          contains('/topics/private-messages/joffreyj.json'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('the touch messages row opens the full inbox', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': const [],
          '/topics/private-messages/joffreyj.json': const [
            Topic(id: 9, title: 'A private message', slug: 'a-pm'),
          ],
        },
      );
      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openMenu(tester);

      await tester.tap(find.text('Messages').last);
      await tester.pumpAndSettle();

      expect(find.text('Joffrey'), findsNothing);
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.text('A private message'), findsOneWidget);
    });

    testWidgets('the account section is last and holds the disconnect', (
      tester,
    ) async {
      await pumpShell(tester, phone, instances: connected);
      await openMenu(tester);

      expect(find.text('Disconnect'), findsNothing);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Preferences'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets('Preferences hides topic creation and its drafts menu', (
      tester,
    ) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        name: 'Joffrey',
        draftCount: 1,
      );
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
        user: user,
      );
      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: user),
        ],
        api: api,
        authenticator: signedIn(),
      );

      expect(find.byKey(TopicCreateButton.buttonKey), findsOneWidget);
      expect(find.byTooltip('Open the latest drafts menu'), findsOneWidget);

      await _openProfileSection(tester);
      await tester.tap(find.byKey(const ValueKey('user-menu-row-preferences')));
      await tester.pumpAndSettle();

      expect(find.byKey(TopicCreateButton.buttonKey), findsNothing);
      expect(find.byTooltip('Open the latest drafts menu'), findsNothing);
      expect(
        ShellScope.read(
          tester.element(find.byType(MainContent)),
        ).canCreateTopicHere,
        isFalse,
      );
    });

    testWidgets('only unfinished profile rows are orange', (tester) async {
      await pumpShell(
        tester,
        phone,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: me.withHidePresence(false)),
        ],
      );
      await openMenu(tester);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      final placeholder = Theme.of(
        tester.element(find.text('Preferences')),
      ).shell.placeholder;

      expect(
        tester.widget<Text>(find.text('Preferences')).style?.color,
        isNot(placeholder),
      );
      expect(
        tester.widget<Text>(find.text('Summary')).style?.color,
        isNot(placeholder),
      );
      expect(
        tester.widget<Text>(find.text('Activity')).style?.color,
        isNot(placeholder),
      );
      expect(
        tester.widget<Text>(find.text('Online')).style?.color,
        isNot(placeholder),
      );
      expect(
        tester.widget<Text>(find.text('Disconnect')).style?.color,
        isNot(placeholder),
      );
    });

    testWidgets(
      'profile Activity opens an accessible native stream and preserves Back',
      (tester) async {
        const activity = UserActivityItem(
          actionType: UserActivityItem.replyActionType,
          topicId: 7,
          postNumber: 4,
          postId: 74,
          title: 'A useful discussion',
          slug: 'a-useful-discussion',
          username: 'joffreyj',
          excerpt: '<p>A useful reply &amp; follow-up</p>',
          categoryId: 5,
        );
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          creatableFeedPaths: const {'/latest.json'},
          userActivityItems: const [activity],
          userActivityCategories: const [
            TopicCategory(id: 5, name: 'Support', color: '0088CC'),
          ],
          topics: {
            7: topicPayload(
              id: 7,
              title: 'A useful discussion',
              posts: const [
                Post(
                  id: 74,
                  postNumber: 4,
                  username: 'joffreyj',
                  cooked: '<p>A useful reply &amp; follow-up</p>',
                ),
              ],
              stream: const [74],
            ),
          },
        );
        await pumpShell(
          tester,
          phone,
          instances: connected,
          api: api,
          authenticator: signedIn(),
        );

        await _openProfileSection(tester);
        final activityAction = find.byKey(
          const ValueKey('user-menu-row-activity'),
        );
        expect(activityAction, findsOneWidget);
        final menuSemantics = tester.ensureSemantics();
        try {
          expect(
            tester.getSemantics(activityAction),
            isSemantics(label: 'Activity', isButton: true, hasTapAction: true),
          );
          expect(
            tester.getSize(activityAction).height,
            greaterThanOrEqualTo(44),
          );
        } finally {
          menuSemantics.dispose();
        }
        expect(
          tester.widget<Text>(find.text('Activity').last).style?.color,
          isNot(
            Theme.of(
              tester.element(find.text('Preferences')),
            ).shell.placeholder,
          ),
        );

        await tester.tap(activityAction);
        await tester.pumpAndSettle();

        expect(find.byType(UserMenuPanel), findsNothing);
        expect(find.byType(UserActivityView), findsOneWidget);
        expect(find.byType(TopicCreateButton), findsNothing);
        expect(api.userActivityRequests, [
          (
            siteUrl: 'https://meta.discourse.org',
            username: 'joffreyj',
            offset: 0,
            limit: 30,
          ),
        ]);
        final shell = ShellScope.read(
          tester.element(find.byType(UserActivityView)),
        );
        expect(shell.currentContent?.id, 'activity');
        expect(shell.contentStack.last.title, 'Activity');

        final row = find.byKey(const ValueKey('user-activity-row-7/4'));
        final target = find.byKey(
          const ValueKey('user-activity-row-target-7/4'),
        );
        expect(row, findsOneWidget);
        expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
        final semantics = tester.ensureSemantics();
        try {
          final node = tester.getSemantics(row);
          expect(node.label, contains('A useful discussion'));
          expect(node.label, contains('Reply by joffreyj'));
          expect(node.label, contains('Support'));
          expect(node.label, contains('A useful reply & follow-up'));
          final data = node.getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);

          final inkWell = find.descendant(
            of: row,
            matching: find.byType(InkWell),
          );
          final focusChild = find
              .descendant(of: inkWell, matching: find.byType(MouseRegion))
              .first;
          final focus = Focus.of(tester.element(focusChild));
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(focus.hasPrimaryFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
        } finally {
          semantics.dispose();
        }

        expect(api.topicsOpened, [7]);
        expect(api.topicPostNumbersOpened, [4]);
        expect(shell.currentContent?.topicId, 7);

        expect(shell.handleBack(canReturnToSidebar: false), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(UserActivityView), findsOneWidget);
        expect(shell.handleBack(canReturnToSidebar: false), isTrue);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, isNot('activity'));
      },
    );

    testWidgets('Activity exposes loading, refresh, and empty states', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(userActivityGate: gate);
      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );

      await _openProfileSection(tester);
      await tester.tap(find.byKey(const ValueKey('user-menu-row-activity')));
      // Let both sheets dismiss and the loader cross its asynchronous shell
      // and credential boundaries. Do not settle: the skeleton intentionally
      // animates until the gated request returns.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final semantics = tester.ensureSemantics();
      try {
        expect(find.bySemanticsLabel('Loading activity'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('No activity yet'), findsOneWidget);
      expect(
        find.textContaining('Topics you create and replies you post'),
        findsOneWidget,
      );

      await tester.drag(find.byType(ListView).last, const Offset(0, 320));
      await tester.pumpAndSettle();
      expect(api.userActivityRequests, hasLength(2));
    });

    testWidgets('Activity failure remains a retryable native page', (
      tester,
    ) async {
      final api = _FailingUserActivityApi();
      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );

      await _openProfileSection(tester);
      await tester.tap(find.byKey(const ValueKey('user-menu-row-activity')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Couldn't load activity from"),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(api.calls, 2);
      expect(find.byType(UserActivityView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a persisted Activity route restores in the wide shell', (
      tester,
    ) async {
      final forumTabs = FakeForumTabStore([
        ForumWorkspace(
          siteUrl: 'https://meta.discourse.org',
          accountIdentity: 'user:joffreyj',
          activeTabId: 'restored-tab',
          tabs: [
            ForumTab(
              id: 'restored-tab',
              rootDestinationId: 'latest',
              contentStack: [
                const ContentRoute(
                  id: 'latest',
                  title: 'Latest',
                  icon: DIcons.layerGroup,
                ),
                ContentRoute.userActivity(),
              ],
            ),
          ],
        ),
      ]);
      final api = FakeDiscourseApi(userActivityItems: const []);

      await pumpShell(
        tester,
        desktop,
        instances: connected,
        api: api,
        authenticator: signedIn(),
        forumTabs: forumTabs,
      );

      expect(find.byType(UserActivityView), findsOneWidget);
      expect(find.text('No activity yet'), findsOneWidget);
      final shell = ShellScope.read(
        tester.element(find.byType(UserActivityView)),
      );
      expect(shell.currentContent?.id, 'activity');
      expect(shell.canPopContent, isTrue);
      expect(api.userActivityRequests, hasLength(1));
    });

    testWidgets('the notifications tab reads what the site sent', (
      tester,
    ) async {
      final api = FakeDiscourseApi(notificationList: notifications);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);

      expect(api.notificationCalls, 1);
      expect(
        find.textContaining('sam replied to Better image handling'),
        findsOneWidget,
      );
      expect(
        find.textContaining('david liked your post in Merge CVSS'),
        findsOneWidget,
      );
      expect(
        find.textContaining('You earned the Nice Reply badge'),
        findsOneWidget,
      );
      final tab = tester.widget<Text>(find.text('Notifications').first);
      expect(
        tab.style?.color,
        isNot(Theme.of(tester.element(find.text('Profile'))).shell.placeholder),
      );
    });

    testWidgets('tapping one opens its topic and marks it read', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        notificationList: notifications,
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Better image handling',
            posts: [
              const Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>First post body</p>',
              ),
            ],
            stream: [1],
          ),
        },
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);
      await tester.tap(
        find.textContaining('sam replied to Better image handling'),
      );
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(api.markedRead, [1]);
      expect(find.byType(NotificationRow), findsNothing);
      expect(renderedText('First post body'), findsOneWidget);
    });

    testWidgets('one the app has no page for opens the browser', (
      tester,
    ) async {
      final api = FakeDiscourseApi(notificationList: notifications);
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);
      await tester.tap(find.textContaining('You earned the Nice Reply badge'));
      await tester.pumpAndSettle();

      // Resolved against the site it came from, since Discourse writes its own
      // links site-relative.
      expect(launched, ['https://meta.discourse.org/badges/24/nice-reply']);
      expect(api.markedRead, [3]);
      expect(find.byType(NotificationRow), findsNothing);
    });

    testWidgets('one with nowhere to go is read where it stands', (
      tester,
    ) async {
      final api = FakeDiscourseApi(notificationList: notifications);
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);
      await tester.tap(find.textContaining('Something from a plugin'));
      await tester.pumpAndSettle();

      expect(api.markedRead, [4]);
      expect(launched, isEmpty);
      expect(find.byType(NotificationRow), findsNWidgets(4));
    });

    testWidgets('notifications that will not load can be asked for again', (
      tester,
    ) async {
      final api = FakeDiscourseApi();

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);

      expect(find.textContaining("Couldn't reach"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.notificationCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty inbox says so rather than spinning', (tester) async {
      final api = FakeDiscourseApi(notificationList: const []);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);

      expect(find.text('Nothing new.'), findsOneWidget);
    });

    testWidgets('reopening the tab asks the site again', (tester) async {
      final api = FakeDiscourseApi(notificationList: notifications);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      expect(api.notificationCalls, 2);
      expect(
        find.textContaining('sam replied to Better image handling'),
        findsOneWidget,
      );
    });

    const bookmarks = [
      // Site-relative, which is what the parse leaves a topic link as — see
      // `Bookmark._path`.
      Bookmark(
        id: 8,
        title: 'Thinking about the next project',
        name: 'read this properly',
        author: 'sam',
        path: '/t/next-project/7/3',
      ),
      Bookmark(
        id: 9,
        title: 'A message in #dev',
        author: 'david',
        path: 'https://meta.discourse.org/chat/c/-/9/44',
      ),
    ];

    const reminder = DiscourseNotification.test(
      id: 41,
      typeId: NotificationTypeId(24),
      title: 'Better image handling',
      topicId: 7,
      slug: 'better-image-handling',
    );

    Future<void> openBookmarks(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();
    }

    testWidgets('the bookmarks tab reads what the site sent', (tester) async {
      final api = FakeDiscourseApi(
        bookmarkList: bookmarks,
        reminderList: const [reminder],
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      expect(api.bookmarksRequested, ['joffreyj']);
      expect(
        find.textContaining('Reminder: Better image handling'),
        findsOneWidget,
      );
      expect(
        find.textContaining('sam Thinking about the next project'),
        findsOneWidget,
      );
      final tab = tester.widget<Text>(find.text('Bookmarks').first);
      expect(
        tab.style?.color,
        isNot(Theme.of(tester.element(find.text('Profile'))).shell.placeholder),
      );
    });

    testWidgets('tapping one opens the topic it was kept from', (tester) async {
      final api = FakeDiscourseApi(
        bookmarkList: bookmarks,
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Thinking about the next project',
            posts: [
              const Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>First post body</p>',
              ),
            ],
            stream: [1],
          ),
        },
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      await tester.tap(
        find.textContaining('sam Thinking about the next project'),
      );
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(find.byType(BookmarkRow), findsNothing);
      expect(renderedText('First post body'), findsOneWidget);
    });

    testWidgets('a topic opens here even when the site named another host', (
      tester,
    ) async {
      // Straight off the wire, because it is the parse that has to take the
      // host off: `Discourse.base_url` is the site's own idea of where it
      // lives, and a development site's is not the origin the app connected
      // through. Left alone, its own topics look like somebody else's and go
      // to the browser.
      final api = FakeDiscourseApi(
        bookmarkList: [
          Bookmark.fromJson(const {
            'id': 8,
            'title': 'Thinking about the next project',
            'bookmarkable_url': 'http://localhost:4200/t/next-project/7/3',
            'user': {'username': 'sam'},
          }),
        ],
        topics: {
          7: topicPayload(id: 7, title: 'Thinking about the next project'),
        },
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: [instance('localhost:3000').copyWith(user: me)],
        api: api,
        authenticator: FakeAuthenticator()
          ..keys['https://localhost:3000'] = 'api-key',
      );
      await openBookmarks(tester);
      await tester.tap(
        find.textContaining('sam Thinking about the next project'),
      );
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(launched, isEmpty);
    });

    testWidgets('a channel-message bookmark opens its exact target natively', (
      tester,
    ) async {
      const emptyPage = (
        messages: <ChatMessage>[],
        canLoadMorePast: false,
        canLoadMoreFuture: false,
        targetMessageId: 44,
      );
      final api = FakeDiscourseApi(
        bookmarkList: [bookmarks[1]],
        chatChannelsBySite: const {
          'https://meta.discourse.org': ChatChannels(
            public: [
              ChatChannel(
                id: 9,
                title: 'Dev',
                kind: ChatChannelKind.category,
                membership: ChatMembership(following: true),
                threadingEnabled: true,
              ),
            ],
          ),
        },
        chatMessagesByKey: const {'9~target~44': emptyPage},
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      final shell = ShellScope.read(
        tester.element(find.byType(BookmarkSection)),
      );

      await tester.tap(find.textContaining('david A message in #dev'));
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      expect(shell.currentContent?.id, 'chat-c-9');
      expect(
        api.chatMessagesRequested.map((request) => request.targetMessageId),
        contains(44),
      );
      expect(find.byType(BookmarkRow), findsNothing);
    });

    testWidgets('a thread bookmark opens its exact reply natively', (
      tester,
    ) async {
      const threadBookmark = Bookmark(
        id: 10,
        title: 'A reply in the support thread',
        author: 'kris',
        path: '/chat/c/-/9/t/3/45',
      );
      const emptyPage = (
        messages: <ChatMessage>[],
        canLoadMorePast: false,
        canLoadMoreFuture: false,
        targetMessageId: 45,
      );
      final api = FakeDiscourseApi(
        bookmarkList: const [threadBookmark],
        chatChannelsBySite: const {
          'https://meta.discourse.org': ChatChannels(
            public: [
              ChatChannel(
                id: 9,
                title: 'Support',
                kind: ChatChannelKind.category,
                membership: ChatMembership(following: true),
                threadingEnabled: true,
              ),
            ],
          ),
        },
        chatThreadsByKey: const {
          '9~3': ChatThread(
            id: 3,
            channelId: 9,
            status: 'open',
            replyCount: 2,
            membership: ChatThreadMembership(threadId: 3),
          ),
        },
        chatMessagesByKey: const {'thread-9-3~target~45': emptyPage},
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      final shell = ShellScope.read(
        tester.element(find.byType(BookmarkSection)),
      );

      await tester.tap(
        find.textContaining('kris A reply in the support thread'),
      );
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      expect(shell.currentContent?.id, 'chat-c-9-t-3');
      expect(
        api.chatThreadMessagesRequested.map(
          (request) => request.targetMessageId,
        ),
        contains(45),
      );
      expect(find.byType(BookmarkRow), findsNothing);
    });

    testWidgets('an unclaimable Chat bookmark keeps browser fallback', (
      tester,
    ) async {
      final api = FakeDiscourseApi(bookmarkList: bookmarks);
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      await tester.tap(find.textContaining('david A message in #dev'));
      await tester.pumpAndSettle();

      expect(launched, ['https://meta.discourse.org/chat/c/-/9/44']);
      expect(find.byType(BookmarkRow), findsNothing);
    });

    testWidgets('an inaccessible thread bookmark keeps browser fallback', (
      tester,
    ) async {
      const path = 'https://meta.discourse.org/chat/c/-/9/t/99/45';
      final api = FakeDiscourseApi(
        bookmarkList: const [
          Bookmark(
            id: 12,
            title: 'Inaccessible support thread',
            author: 'kris',
            path: path,
          ),
        ],
        chatChannelsBySite: const {
          'https://meta.discourse.org': ChatChannels(
            public: [
              ChatChannel(
                id: 9,
                title: 'Support',
                kind: ChatChannelKind.category,
                membership: ChatMembership(following: true),
                threadingEnabled: true,
              ),
            ],
          ),
        },
        chatThreadsByKey: const {},
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      await tester.tap(find.textContaining('kris Inaccessible support thread'));
      await tester.pumpAndSettle();

      expect(launched, [path]);
      expect(find.byType(BookmarkRow), findsNothing);
    });

    testWidgets('a Chat bookmark on a disconnected site opens the browser', (
      tester,
    ) async {
      const path = 'https://team.discourse.org/chat/c/-/9/t/3/45';
      final api = FakeDiscourseApi(
        bookmarkList: const [
          Bookmark(
            id: 11,
            title: 'Disconnected support thread',
            author: 'kris',
            path: path,
          ),
        ],
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: [
          ...connected,
          instance('team.discourse.org', title: 'Discourse Team'),
        ],
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      await tester.tap(find.textContaining('kris Disconnected support thread'));
      await tester.pumpAndSettle();

      expect(launched, [path]);
      expect(find.byType(BookmarkRow), findsNothing);
    });

    testWidgets('a reminder in here is read like any other notification', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        bookmarkList: bookmarks,
        reminderList: const [reminder],
        topics: {7: topicPayload(id: 7, title: 'Better image handling')},
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      await tester.tap(find.textContaining('Reminder: Better image handling'));
      await tester.pumpAndSettle();

      expect(api.markedRead, [41]);
      expect(api.topicsOpened, [7]);
    });

    testWidgets('nothing kept says so rather than spinning', (tester) async {
      final api = FakeDiscourseApi(bookmarkList: const []);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      expect(find.text('Nothing bookmarked yet.'), findsOneWidget);
    });

    testWidgets('bookmarks that will not load can be asked for again', (
      tester,
    ) async {
      final api = FakeDiscourseApi();

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      expect(find.textContaining("Couldn't reach"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.bookmarksRequested.length, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('user cards', () {
    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    final detail = topicPayload(
      id: 7,
      title: 'A real topic',
      posts: const [
        Post(
          id: 1,
          postNumber: 1,
          username: 'joffreyj',
          name: 'Joffrey',
          cooked: '<p>First post body</p>',
        ),
      ],
      stream: const [1],
    );

    final card = UserCard(
      username: 'joffreyj',
      name: 'Joffrey',
      title: 'Team member',
      bioExcerpt: '<p>Builds the thing.</p>',
      location: 'Paris',
      website: 'https://discourse.org',
      websiteName: 'discourse.org',
      createdAt: DateTime.utc(2015, 3, 4),
      timeRead: 7200,
      badgeCount: 12,
    );

    Future<void> openTopic(WidgetTester tester, FakeDiscourseApi api) async {
      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping an avatar opens the card', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail},
        cards: {'joffreyj': card},
      );

      await openTopic(tester, api);
      final semantics = tester.ensureSemantics();
      final profileTargets = find.bySemanticsLabel(
        'View profile for @joffreyj',
      );
      final profileSemantics = find.semantics.byLabel(
        'View profile for @joffreyj',
      );
      expect(profileTargets, findsNWidgets(2));
      expect(
        tester
            .getSemantics(profileTargets.first)
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isTrue,
      );
      tester.semantics.tap(profileSemantics.first);
      await tester.pumpAndSettle();

      expect(api.cardsRequested, ['joffreyj']);
      expect(find.text('@joffreyj'), findsOneWidget);
      expect(find.text('Team member'), findsOneWidget);
      expect(renderedText('Builds the thing.'), findsOneWidget);
      expect(find.text('Paris'), findsOneWidget);
      expect(find.text('discourse.org'), findsOneWidget);
      expect(find.textContaining('Mar 2015'), findsOneWidget);
      expect(find.textContaining('2h'), findsOneWidget);
      expect(find.text('12 badges'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('user-card-surface'))).width,
        624,
      );
      semantics.dispose();
    });

    testWidgets('Chat contributes a card action and opens a direct message', (
      tester,
    ) async {
      final reader = DiscourseUser(
        id: 7,
        username: 'reader',
        plugins: PluginData.none.withValue(
          chatCurrentUserDataKey,
          const ChatCurrentUser(hasChatEnabled: true),
        ),
      );
      final chatCard = UserCard.fromJson(
        const {
          'username': 'joffreyj',
          'name': 'Joffrey',
          'can_chat_user': true,
        },
        'https://meta.discourse.org',
        extensions: pluginRegistry,
      );
      const directMessage = ChatChannel(
        id: 55,
        title: 'Joffrey',
        kind: ChatChannelKind.directMessage,
      );
      final api = FakeDiscourseApi(
        user: reader,
        feeds: {'/latest.json': listed},
        topics: {7: detail},
        cards: {'joffreyj': chatCard},
        directMessageChannelsByUsername: const {'joffreyj': directMessage},
        chatMessagesByKey: const {
          '55': (
            messages: <ChatMessage>[],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
        },
      );
      final auth = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'api-key';

      await pumpShell(
        tester,
        phone,
        api: api,
        authenticator: auth,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: reader),
        ],
      );
      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Chat'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('user-card-surface'))).width,
        366,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Chat'));
      await tester.pumpAndSettle();

      expect(api.directMessageChannelsRequested, ['joffreyj']);
      expect(find.byType(ChatChannelView), findsOneWidget);
      expect(find.byKey(const ValueKey('user-card-surface')), findsNothing);
    });

    testWidgets('tapping the name opens the same card, already held', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail},
        cards: {'joffreyj': card},
      );

      await openTopic(tester, api);
      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();
      expect(find.text('@joffreyj'), findsOneWidget);

      await tester.tapAt(const Offset(20, 500));
      await tester.pumpAndSettle();
      expect(find.text('@joffreyj'), findsNothing);

      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();

      expect(find.text('@joffreyj'), findsOneWidget);
      expect(api.cardsRequested, ['joffreyj']);
    });

    testWidgets('a card that fails to load offers a retry', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail},
      );

      await openTopic(tester, api);
      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't reach"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.cardsRequested, ['joffreyj', 'joffreyj']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an open card keeps the site that it was loaded from', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = _GatedUserCardApi(
        cardGate: gate,
        feeds: {'/latest.json': listed},
        topics: {7: detail},
      );

      await openTopic(tester, api);
      final shell = ShellScope.read(tester.element(find.byType(TopicView)));

      await tester.tap(find.text('Joffrey'));
      await tester.pump();
      await api.started.future;
      await tester.pump(const Duration(milliseconds: 200));

      shell.selectInstance(1);
      await tester.pump();

      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(api.cardSites, ['https://meta.discourse.org']);
      expect(shell.currentInstance?.url, 'https://team.discourse.org');
      expect(find.text('First-site profile'), findsOneWidget);
      expect(find.text('From Meta'), findsOneWidget);
    });
  });
}

final class _GatedUserCardApi extends FakeDiscourseApi {
  _GatedUserCardApi({
    required this.cardGate,
    required super.feeds,
    required super.topics,
  });

  final Completer<void> cardGate;
  final started = Completer<void>();
  final List<String> cardSites = [];

  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) async {
    cardsRequested.add(username);
    cardSites.add(siteUrl);
    started.complete();
    await cardGate.future;
    return UserCard(
      username: username,
      name: 'First-site profile',
      title: 'From Meta',
    );
  }
}

final class _FailingUserActivityApi extends FakeDiscourseApi {
  int calls = 0;

  @override
  Future<UserActivityPage> userActivity({
    required String siteUrl,
    required String apiKey,
    required String username,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    calls++;
    throw StateError('offline');
  }
}

Future<void> _openProfileSection(WidgetTester tester) async {
  await tester.tap(userMenu);
  await tester.pumpAndSettle();

  final tab = find.byTooltip('Profile');
  await tester.tap(tab.evaluate().isEmpty ? find.text('Profile') : tab);
  await tester.pumpAndSettle();
}
