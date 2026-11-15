import 'package:discourse_native/src/data/platform_app_badge.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/shell/app_badge_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _user = DiscourseUser(id: 7, username: 'reader');

final class _RecordingBadge implements AppBadge {
  final counts = <int>[];

  @override
  Future<void> setCount(int count) async => counts.add(count);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the badge follows the totals notifier and skips repeats', () {
    final totals = ChangeNotifier();
    addTearDown(totals.dispose);
    final badge = _RecordingBadge();
    var unread = 3;
    final controller = AppBadgeController(
      totals: totals,
      count: () => unread,
      badge: badge,
    );

    totals.notifyListeners();
    unread = 5;
    totals.notifyListeners();
    unread = 0;
    totals.notifyListeners();
    expect(badge.counts, [3, 5, 0]);

    controller.refresh();
    expect(badge.counts, [3, 5, 0, 0]);

    controller.dispose();
    unread = 9;
    totals.notifyListeners();
    controller.refresh();
    expect(badge.counts, [3, 5, 0, 0]);
  });

  test('the badge is the unread total across signed-in forums and clears on '
      'sign-out', () async {
    final sites = [
      instance('meta.discourse.org').copyWith(
        user: _user,
        notificationTotals: const NotificationTotals(
          unreadNotifications: 2,
          unreadPersonalMessages: 1,
        ),
      ),
      instance('try.discourse.org').copyWith(
        user: _user,
        notificationTotals: const NotificationTotals(unseenReviewables: 4),
      ),
    ];
    final api = FakeDiscourseApi(
      user: _user,
      feeds: const {'/latest.json': []},
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore(sites),
      api: api,
      authenticator: FakeAuthenticator.signedIn(sites, site: api),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    final badge = _RecordingBadge();
    final controller = AppBadgeController(
      totals: shell.accountActivity.totalsListenable,
      count: () => shell.appBadgeCount,
      badge: badge,
    );
    addTearDown(controller.dispose);
    expect(badge.counts.last, 7);

    await pumpEventQueue();
    expect(
      FakeSiteTracker.built.map((tracker) => tracker.siteUrl),
      contains(sites[0].url),
    );
    FakeSiteTracker.built
        .firstWhere((tracker) => tracker.siteUrl == sites[0].url)
        .deliverNotification(const {
          'all_unread_notifications_count': 1,
          'new_personal_messages_notifications_count': 0,
        });
    await pumpEventQueue();
    expect(badge.counts.last, 5);

    expect(await shell.disconnectInstance(sites[1].url), isTrue);
    await pumpEventQueue();
    expect(badge.counts.last, 1);

    expect(await shell.disconnectInstance(sites[0].url), isTrue);
    await pumpEventQueue();
    expect(badge.counts.last, 0);
  });

  group('platform channel', () {
    const channel = MethodChannel('test.discourse.native/app_badge');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.android,
    ]) {
      test('${platform.name} receives the count', () async {
        await PlatformAppBadge(
          channel: channel,
          platform: platform,
        ).setCount(4);

        expect(calls.single.method, 'setBadgeCount');
        expect(calls.single.arguments, 4);
      });
    }

    test('Linux has no badge and makes no call', () async {
      await PlatformAppBadge(
        channel: channel,
        platform: TargetPlatform.linux,
      ).setCount(4);

      expect(calls, isEmpty);
    });

    test('a platform without the handler is not an error', () async {
      await PlatformAppBadge(
        channel: const MethodChannel('test.discourse.native/no_badge'),
        platform: TargetPlatform.iOS,
      ).setCount(4);
    });
  });
}
