import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_menu.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://forum.example';
const _topic = Topic(
  id: 7,
  slug: 'notification-topic',
  title: 'Notification topic',
);
final _user = _reader(7, 'reader');
final _replacement = _reader(8, 'replacement');

DiscourseUser _reader(int id, String username) => DiscourseUser(
  id: id,
  username: username,
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);

DiscourseNotification _notification(int type) => DiscourseNotification.test(
  id: 31,
  typeId: NotificationTypeId(type),
  topicId: 7,
  postNumber: 1,
  data: const {
    'display_username': 'sam',
    'topic_title': 'Notification topic',
    'topic_slug': 'notification-topic',
  },
);

final class _Authenticator extends FakeAuthenticator {
  _Authenticator(this.transition)
    : super(
        credentials: const UserApiCredentials(
          key: 'replacement-key',
          apiVersion: 4,
          push: false,
        ),
        failure: transition == 'cancelled reconnect'
            ? UserApiAuthFailure.cancelled
            : null,
      );
  final String transition;

  @override
  Future<void> persistCredentials(
    String siteUrl,
    UserApiCredentials credentials,
  ) async {
    if (transition == 'connect rollback') {
      throw StateError('Keychain refused replacement');
    }
    await super.persistCredentials(siteUrl, credentials);
  }
}

final class _Instances extends FakeInstanceStore {
  _Instances() : super([instance('forum.example').copyWith(user: _user)]);
  bool rejectSignedOut = false;

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    if (rejectSignedOut && instances.any((site) => site.user == null)) {
      throw StateError('Preferences refused signed-out snapshot');
    }
    await super.save(instances);
  }
}

final class _Api extends FakeDiscourseApi {
  _Api(this.writer)
    : super(
        user: _user,
        totals: chatNotificationTotals(chatNotifications: 1),
        notificationList: [_notification(2)],
        chatNotificationList: [_notification(33)],
        reminderList: [_notification(24)],
        bookmarkList: const [],
        feeds: const {
          '/latest.json': [_topic],
        },
        topics: {7: topicPayload(id: 7, title: _topic.title)},
      ) {
    accounts['replacement-key'] = _replacement;
  }
  final DiscourseApi writer;

  @override
  Future<void> markNotificationRead({
    required String siteUrl,
    required String apiKey,
    required int id,
    String? clientId,
  }) => writer.markNotificationRead(
    siteUrl: siteUrl,
    apiKey: apiKey,
    id: id,
    clientId: clientId,
  );
}

Future<void> _load(ShellController shell, String section) => switch (section) {
  'Chat' => shell.loadPluginNotificationFeed(_site, chatNotificationFeed),
  'Bookmarks' => shell.loadBookmarks(_site),
  _ => shell.loadNotifications(_site),
};

bool _read(ShellController shell, String section) => switch (section) {
  'Chat' =>
    shell.accountActivity
        .pluginNotificationsFor(chatNotificationFeed.id, _site)
        .notifications
        .single
        .read,
  'Bookmarks' => shell.bookmarksFor(_site).reminders.single.read,
  _ => shell.notificationsFor(_site).notifications.single.read,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final section in ['Notifications', 'Chat', 'Bookmarks']) {
    for (final transition in [
      'unchanged',
      'reconnect',
      'connect rollback',
      'disconnect rollback',
      'cancelled reconnect',
    ]) {
      for (final activation in [
        'click',
        'middle-click',
        'held-click',
        'held-middle-click',
      ]) {
        final middle = activation.contains('middle');
        final held = activation.startsWith('held');
        testWidgets(
          'Native $section $activation row keeps its rendered account after $transition',
          (tester) async {
            final sent = <http.Request>[];
            final client = MockClient((request) async {
              sent.add(request);
              return http.Response(jsonEncode({}), 200);
            });
            addTearDown(client.close);
            final api = _Api(DiscourseApi(client: client));
            final instances = _Instances();
            final auth = _Authenticator(transition)..keys[_site] = 'old-key';
            await pumpShell(
              tester,
              desktop,
              store: instances,
              api: api,
              authenticator: auth,
            );
            await tester.tap(find.byKey(UserMenuButton.bellKey));
            await tester.pumpAndSettle();
            final menu = find.byType(UserMenuPanel);
            expect(menu, findsOneWidget);
            final tab = find
                .descendant(of: menu, matching: find.text(section))
                .last;
            await tester.ensureVisible(tab);
            await tester.pumpAndSettle();
            await tester.tap(tab);
            await tester.pumpAndSettle();
            final row = find.byKey(const ValueKey('notification-row-31'));
            expect(tester.widget(row), isA<DItem>());
            final source = tester.element(row);
            final sourceState = tester.state(row);
            final shell = ShellScope.read(tester.element(menu));
            final lease = shell.lifecycle.capture(_site);
            TestGesture? gesture;
            if (held) {
              gesture = await tester.startGesture(
                tester.getCenter(row),
                kind: PointerDeviceKind.mouse,
                buttons: middle ? kMiddleMouseButton : kPrimaryMouseButton,
              );
              await tester.pump();
            }
            if (transition == 'disconnect rollback') {
              instances.rejectSignedOut = true;
              expect(await shell.disconnectInstance(_site), isFalse);
            } else if (transition != 'unchanged') {
              await shell.connectCurrentInstance();
            }
            await _load(shell, section);
            final retired =
                transition != 'unchanged' &&
                transition != 'cancelled reconnect';
            expect(lease.isCurrent, !retired);
            expect(
              auth.keys[_site],
              transition == 'reconnect' ? 'replacement-key' : 'old-key',
            );
            expect(
              shell.currentInstance?.user,
              transition == 'reconnect' ? _replacement : _user,
            );
            expect(tester.element(row), same(source));
            expect(_read(shell, section), isFalse);
            if (held) {
              await tester.pumpAndSettle();
              if (retired) {
                expect(sourceState.mounted, isFalse);
                expect(tester.state(row), isNot(same(sourceState)));
              } else {
                expect(tester.state(row), same(sourceState));
              }
            }
            final destination = shell.currentContent;
            final tabId = shell.activeTabId;
            final tabCount = shell.tabsForCurrentForum.length;
            Future<void> activate() async {
              if (gesture case final heldGesture?) {
                gesture = null;
                await heldGesture.up();
              } else {
                await tester.tap(
                  row,
                  kind: PointerDeviceKind.mouse,
                  buttons: middle ? kMiddleMouseButton : kPrimaryMouseButton,
                );
              }
            }

            await activate();
            await tester.pumpAndSettle();
            if (retired) {
              expect(sent, isEmpty);
              expect(_read(shell, section), isFalse);
              expect(shell.currentContent, same(destination));
              expect(shell.tabsForCurrentForum, hasLength(tabCount));
              expect(find.byType(UserMenuPanel), findsOneWidget);
              await activate();
              await tester.pumpAndSettle();
            }
            expect(sent.single.method, 'PUT');
            expect(sent.single.url.path, '/notifications/mark-read.json');
            expect(jsonDecode(sent.single.body), {'id': 31});
            expect(sent.single.headers['user-api-key'], auth.keys[_site]);
            expect(_read(shell, section), isTrue);
            if (middle) {
              expect(shell.activeTabId, tabId);
              expect(shell.tabsForCurrentForum, hasLength(tabCount + 1));
              expect(shell.tabsForCurrentForum.last.currentContent.topicId, 7);
              expect(find.byType(UserMenuPanel), findsOneWidget);
            } else {
              expect(shell.currentContent?.topicId, 7);
              expect(find.byType(UserMenuPanel), findsNothing);
            }
            expect(tester.takeException(), isNull);
          },
          variant: TargetPlatformVariant.only(TargetPlatform.macOS),
        );
      }
    }
  }
}
