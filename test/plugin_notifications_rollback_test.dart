import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_menu.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
final _user = DiscourseUser(
  id: 7,
  username: 'reader',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);

enum _Operation { cancelledReconnect, failedReconnect, failedDisconnect }

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final operation in _Operation.values) {
    testWidgets(
      'the Chat menu restores notifications after ${operation.name}',
      (tester) async {
        final site = instance('meta.discourse.org').copyWith(user: _user);
        final store = _FailingStore([site]);
        final api = FakeDiscourseApi(
          user: _user,
          totals: chatNotificationTotals(chatNotifications: 1),
          feeds: const {'/latest.json': []},
          chatNotificationList: const [
            DiscourseNotification.test(
              id: 31,
              typeId: NotificationTypeId(30),
              data: {
                'display_username': 'reader',
                'chat_channel_title': 'Restored channel notification',
                'chat_channel_id': 9,
                'chat_message_id': 31,
              },
            ),
          ],
        );
        final auth = FakeAuthenticator(
          failure: operation == _Operation.cancelledReconnect
              ? UserApiAuthFailure.cancelled
              : null,
        )..keys[_site] = 'old-key';
        await pumpShell(
          tester,
          defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
          instances: [site],
          store: store,
          api: api,
          authenticator: auth,
        );
        await tester.tap(find.byKey(UserMenuButton.bellKey));
        await tester.pumpAndSettle();
        final menu = find.byType(UserMenuPanel).evaluate().isNotEmpty
            ? find.byType(UserMenuPanel)
            : find.byKey(const ValueKey('user-menu-sheet'));
        final tab = find.descendant(of: menu, matching: find.text('Chat')).last;
        await tester.ensureVisible(tab);
        await tester.pumpAndSettle();
        await tester.tap(tab);
        await tester.pumpAndSettle();

        final section = find.byType(PluginNotificationsSection);
        final state = tester.state(section);
        final shell = ShellScope.read(tester.element(section));
        final lease = shell.lifecycle.capture(_site);
        final route = shell.currentContent?.id;
        final rows = find.descendant(
          of: section,
          matching: find.textContaining('Restored channel notification'),
        );
        bool loaded() => shell.accountActivity
            .pluginNotificationsFor(chatNotificationFeed.id, _site)
            .loaded;
        expect(rows, findsOneWidget);
        expect(api.chatNotificationCalls, 1);
        expect(loaded(), isTrue);

        // The account coordinator restores the account and visible menu before
        // the next frame when persisting the signed-out snapshot fails.
        store.failSignedOut = operation != _Operation.cancelledReconnect;
        if (operation == _Operation.failedDisconnect) {
          expect(
            await tester.runAsync(() => shell.disconnectInstance(_site)),
            isFalse,
          );
        } else {
          await tester.runAsync(shell.connectCurrentInstance);
        }
        expect(shell.currentInstance?.user?.id, _user.id);
        expect(shell.currentContent?.id, route);
        expect(lease.isCurrent, operation == _Operation.cancelledReconnect);
        expect(loaded(), operation == _Operation.cancelledReconnect);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.state(section), same(state));
        expect(
          api.chatNotificationCalls,
          operation == _Operation.cancelledReconnect ? 1 : 2,
        );
        expect(rows, findsOneWidget);
        expect(loaded(), isTrue);
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

class _FailingStore extends FakeInstanceStore {
  _FailingStore(super.instances);
  bool failSignedOut = false;

  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut &&
        instances.any((site) => site.url == _site && site.user == null)) {
      return Future.error(StateError('Account snapshot storage unavailable'));
    }
    return super.save(instances);
  }
}
