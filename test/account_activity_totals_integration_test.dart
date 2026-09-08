import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final changesAwayFirst in [false, true]) {
    test(
      'accepted ${changesAwayFirst ? 'returning' : 'repeated'} tracker counts survive the active totals response',
      () async {
        final (:shell, :api, :tracker) = await _fixture();
        final loading = shell.accountActivity.refresh(shell.currentInstance!);

        if (changesAwayFirst) {
          tracker.deliverNotification(const {
            'all_unread_notifications_count': 8,
            'new_personal_messages_notifications_count': 4,
            'grouped_unread_notifications': {'2': 4},
          });
          tracker.deliverReviewableCounts(const {'unseen_reviewable_count': 6});
        }
        tracker.deliverNotification(const {
          'all_unread_notifications_count': 3,
          'new_personal_messages_notifications_count': 2,
          'grouped_unread_notifications': {'2': 1},
        });
        tracker.deliverReviewableCounts(const {'unseen_reviewable_count': 3});
        api.response.complete(
          NotificationTotals(
            unreadNotifications: 5,
            unreadPersonalMessages: 5,
            unseenReviewables: 9,
            topicTrackingUnread: 7,
            groupedUnreadNotifications: NotificationTypeCounts.fromWire(const {
              '2': 5,
            }),
          ),
        );
        final result = (await loading)!;

        expect(result.unreadNotifications, 1);
        expect(result.unreadPersonalMessages, 2);
        expect(result.unseenReviewables, 3);
        expect(
          result.groupedUnreadNotifications.count(
            CoreNotificationTypes.replied,
          ),
          1,
        );
        expect(result.topicTrackingUnread, 7);
        expect(shell.instanceFor(_siteUrl)!.notificationTotals, result);
        expect(api.totalsCalls, 1);
      },
    );
  }

  test(
    'retired tracker callbacks and delayed totals cannot repopulate a disconnected account',
    () async {
      final (:shell, :api, :tracker) = await _fixture();
      final loading = shell.accountActivity.refresh(shell.currentInstance!);
      tracker.deliverNotification(const {'all_unread_notifications_count': 3});
      tracker.deliverReviewableCounts(const {'unseen_reviewable_count': 3});

      expect(await shell.disconnectInstance(_siteUrl), isTrue);
      tracker.deliverNotification(const {
        'all_unread_notifications_count': 99,
        'grouped_unread_notifications': {'2': 99},
      });
      tracker.deliverReviewableCounts(const {'unseen_reviewable_count': 99});
      api.response.complete(const NotificationTotals(unreadNotifications: 50));

      expect(await loading, isNull);
      expect(shell.accountActivity.totalsFor(_siteUrl), isNull);
      expect(shell.instanceFor(_siteUrl)!.notificationTotals, isNull);
    },
  );
}

Future<({ShellController shell, _GatedTotalsApi api, FakeSiteTracker tracker})>
_fixture() async {
  final api = _GatedTotalsApi();
  final trackerReady = Completer<FakeSiteTracker>();
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(
        user: _user,
        notificationTotals: NotificationTotals(
          unreadNotifications: 1,
          unreadPersonalMessages: 2,
          unseenReviewables: 3,
          groupedUnreadNotifications: NotificationTypeCounts.fromWire(const {
            '2': 1,
          }),
        ),
      ),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    trackers:
        ({
          required siteUrl,
          required onIncomingTopics,
          required onNotifications,
          required onReviewableCounts,
          userId,
          apiKey,
          clientId,
          shouldLongPoll,
          initialLastIds = const {},
        }) {
          final tracker = FakeSiteTracker(
            siteUrl: siteUrl,
            userId: userId,
            apiKey: apiKey,
            initialLastIds: initialLastIds,
            onIncomingTopics: onIncomingTopics,
            onNotifications: onNotifications,
            onReviewableCounts: onReviewableCounts,
          );
          if (!trackerReady.isCompleted) trackerReady.complete(tracker);
          return tracker;
        },
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await api.started.future;
  return (shell: shell, api: api, tracker: await trackerReady.future);
}

final class _GatedTotalsApi extends FakeDiscourseApi {
  _GatedTotalsApi() : super(user: _user, feeds: const {'/latest.json': []});

  final started = Completer<void>();
  final response = Completer<NotificationTotals>();

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    totalsCalls++;
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}
