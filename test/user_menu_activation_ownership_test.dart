import 'dart:async';

import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _meta = 'https://meta.discourse.org';
const _team = 'https://team.discourse.org';
const _channel = ChatChannel(
  id: 9,
  title: 'Source channel',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
);

enum _Section { bookmarks, notifications, chat }

DiscourseUser _user(String site) => DiscourseUser(
  id: site == _meta ? 1 : 2,
  username: site == _meta ? 'meta-reader' : 'team-reader',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final section in _Section.values) {
    for (final switchSite in [false, true]) {
      testWidgets(
        'held ${section.name} activation ${switchSite ? 'keeps the replacement site menu' : 'dismisses its source menu'}',
        (tester) async {
          final completion = Completer<void>();
          addTearDown(() {
            if (!completion.isCompleted) completion.complete();
          });
          final api = _MenuApi(completion);
          final launched = watchBrowser(tester);
          await pumpShell(
            tester,
            defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
            instances: [
              instance('meta.discourse.org').copyWith(user: _user(_meta)),
              instance('team.discourse.org').copyWith(user: _user(_team)),
            ],
            api: api,
            authenticator: FakeAuthenticator()
              ..keys[_meta] = 'meta-key'
              ..keys[_team] = 'team-key',
          );
          await tester.tap(find.byKey(UserMenuButton.bellKey));
          await tester.pumpAndSettle();
          final menu = find.byType(UserMenuPanel).evaluate().isNotEmpty
              ? find.byType(UserMenuPanel)
              : find.byKey(const ValueKey('user-menu-sheet'));
          final label = switch (section) {
            _Section.bookmarks => 'Bookmarks',
            _Section.notifications => 'Notifications',
            _Section.chat => 'Chat',
          };
          final tab = find
              .descendant(of: menu, matching: find.text(label))
              .last;
          await tester.ensureVisible(tab);
          await tester.pumpAndSettle();
          await tester.tap(tab);
          await tester.pumpAndSettle();

          final stateFinder = switch (section) {
            _Section.bookmarks => find.byWidgetPredicate(
              (widget) =>
                  widget.runtimeType.toString() == '_BookmarkSectionView',
            ),
            _Section.notifications => find.byWidgetPredicate(
              (widget) =>
                  widget.runtimeType.toString() == '_NotificationSectionView',
            ),
            _Section.chat => find.byType(PluginNotificationsSection),
          };
          final sourceState = tester.state(stateFinder);
          final shell = ShellScope.read(tester.element(stateFinder));
          final sourceRoute = shell.currentContent?.id;
          final link = find.descendant(
            of: stateFinder,
            matching: find.textContaining(
              section == _Section.bookmarks
                  ? 'Meta chat bookmark'
                  : 'Meta chat channel',
            ),
          );
          await tester.tap(link);
          await tester.pump();
          await tester.pump();
          expect(api.chatChannelDetailsRequested, [9]);
          expect(stateFinder, findsOneWidget);

          if (switchSite) {
            shell.selectInstance(1);
            await tester.pumpAndSettle();
            expect(stateFinder, findsOneWidget);
            expect(tester.state(stateFinder), same(sourceState));
            expect(shell.currentInstance?.url, _team);
            expect(
              find.descendant(
                of: stateFinder,
                matching: find.textContaining(
                  section == _Section.bookmarks
                      ? 'Team chat bookmark'
                      : 'Team chat channel',
                ),
              ),
              findsOneWidget,
            );
          }

          completion.complete();
          await tester.pumpAndSettle();
          if (switchSite) {
            expect(stateFinder, findsOneWidget);
            expect(shell.currentInstance?.url, _team);
            expect(shell.currentContent?.id, sourceRoute);
            expect(
              shell.pluginSession.require(chatShellService).fullPageChatActive,
              isFalse,
            );
          } else {
            expect(stateFinder, findsNothing);
            expect(
              shell.pluginSession.require(chatShellService).visibleChannelId,
              9,
            );
          }
          expect(launched, isEmpty);
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.iOS,
          TargetPlatform.android,
          TargetPlatform.macOS,
        }),
      );
    }
  }
}

class _MenuApi extends FakeDiscourseApi {
  _MenuApi(this.completion)
    : super(
        totals: chatNotificationTotals(chatNotifications: 1),
        feeds: const {'/latest.json': []},
        chatChannelsBySite: const {
          _meta: ChatChannels(),
          _team: ChatChannels(),
        },
        chatChannelsById: const {9: _channel},
        chatMessagesByKey: {
          FakeDiscourseApi.chatMessagesKey(9, targetMessageId: 31): (
            messages: const <ChatMessage>[],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
        },
      );

  final Completer<void> completion;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => _user(siteUrl);

  @override
  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async => (
    reminders: const <DiscourseNotification>[],
    bookmarks: [
      Bookmark(
        id: 31,
        title: siteUrl == _meta ? 'Meta chat bookmark' : 'Team chat bookmark',
        author: 'reader',
        path: '/chat/c/-/9/31',
      ),
    ],
  );

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    String? clientId,
  }) async => [
    DiscourseNotification.test(
      id: 31,
      typeId: const NotificationTypeId(30),
      data: {
        'display_username': 'reader',
        'chat_channel_title': siteUrl == _meta
            ? 'Meta chat channel'
            : 'Team chat channel',
        'chat_channel_id': 9,
        'chat_message_id': 31,
      },
    ),
  ];

  @override
  Future<ChatChannel> chatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) async {
    final channel = await super.chatChannel(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      clientId: clientId,
    );
    await completion.future;
    return channel;
  }
}
