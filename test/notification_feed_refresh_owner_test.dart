import 'dart:async';

import 'package:discourse_native/src/data/account_request_session.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/plugin_api/notification_feed_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart'
    show PluginId;
import 'package:discourse_native/src/shell/account_activity_controller.dart';
import 'package:discourse_native/src/shell/notification_feed_refresh_owner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _feed = PluginNotificationFeedSource(
  id: PluginNotificationFeedId(owner: PluginId('test'), name: 'alerts'),
  filterByTypes: [NotificationTypeName('custom_alert')],
  reconnectMessage: 'Reconnect',
  failureMessage: 'Failed',
  emptyMessage: 'Empty',
);
const _serverType = NotificationWireType(901, 'custom_alert');

void main() {
  test(
    'Other and mark-all share one catalog and retain transport scope',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final other = h.owner.loadOtherNotifications(_site);
      final marking = h.owner.markAllNotificationsRead(_site);
      await pumpEventQueue();
      expect(h.api.catalogs, hasLength(1));
      h.api.catalogs.single.complete([
        CoreNotificationTypes.replied,
        _serverType,
      ]);
      await Future.wait([other, marking]);
      expect(h.api.markedTypesRead.single, const [
        NotificationTypeName('replied'),
        NotificationTypeName('custom_alert'),
      ]);
      expect(h.api.catalogSessions, [same(h.lifecycle.capture(_site).session)]);
      expect(h.activity.otherNotificationsFor(_site).loaded, isTrue);
      await h.owner.loadOtherNotifications(_site);
      expect(h.api.catalogs, hasLength(1));
    },
  );

  test('failed catalog keeps Other retryable', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final loading = h.owner.loadOtherNotifications(_site);
    await pumpEventQueue();
    h.api.catalogs.single.completeError(StateError('offline'));
    await loading;
    expect(h.activity.otherNotificationsFor(_site).error, isNotNull);
    final retry = h.owner.loadOtherNotifications(_site);
    await pumpEventQueue();
    expect(h.api.catalogs, hasLength(2));
    h.api.catalogs.last.complete([_serverType]);
    await retry;
    expect(h.activity.otherNotificationsFor(_site).loaded, isTrue);
    expect(h.activity.otherNotificationsFor(_site).error, isNull);
  });

  for (final successorFirst in [false, true]) {
    test(
      'retired catalog cannot clear or cache successor, successorFirst=$successorFirst',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        final old = h.owner.markAllNotificationsRead(_site);
        await pumpEventQueue();
        final oldCatalog = h.api.catalogs.single;
        h.lifecycle.invalidate(_site);
        h.activity.forget(_site);
        h.credentials.keys[_site] = 'successor';
        final next = h.owner.markAllNotificationsRead(_site);
        await pumpEventQueue();
        expect(h.api.catalogs, hasLength(2));
        if (successorFirst) {
          h.api.catalogs.last.complete([_serverType]);
          await next;
        }
        oldCatalog.complete([CoreNotificationTypes.replied]);
        await old;
        if (!successorFirst) {
          final joined = h.owner.loadOtherNotifications(_site);
          await pumpEventQueue();
          expect(h.api.catalogs, hasLength(2));
          h.api.catalogs.last.complete([_serverType]);
          await Future.wait([next, joined]);
        }
        expect(h.api.markedTypesRead, const [
          [NotificationTypeName('custom_alert')],
        ]);
        await h.owner.loadOtherNotifications(_site);
        expect(h.api.catalogs, hasLength(2));
        expect(h.api.catalogKeys, ['original', 'successor']);
      },
    );
  }

  test('forget without lease invalidation fences original catalog', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final old = h.owner.markAllNotificationsRead(_site);
    await pumpEventQueue();
    h.owner.forget(_site);
    final next = h.owner.markAllNotificationsRead(_site);
    await pumpEventQueue();
    h.api.catalogs.first.complete([CoreNotificationTypes.replied]);
    await old;
    expect(h.api.markedTypesRead, isEmpty);
    h.api.catalogs.last.complete([_serverType]);
    await next;
    expect(h.api.markedTypesRead, const [
      [NotificationTypeName('custom_alert')],
    ]);
  });

  testWidgets('live debounce replaces timer and refreshes only tracked feeds', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    final lease = h.lifecycle.capture(_site);
    h.owner.acceptLiveState(_site, const {}, lease);
    await tester.pump(const Duration(seconds: 2));
    expect(h.api.feedKeys, isEmpty);
    await h.activity.loadPluginNotifications(h.current, _feed);
    h.api.feedKeys.clear();
    h.owner.acceptLiveState(_site, const {}, lease);
    await tester.pump(const Duration(milliseconds: 700));
    h.owner.acceptLiveState(_site, const {}, lease);
    await tester.pump(const Duration(milliseconds: 700));
    expect(h.api.feedKeys, isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.api.feedKeys, ['original']);
  });

  test(
    'retirement during credential admission preserves the error outcome',
    () async {
      final credentials = _GatedCredentials();
      final h = _Harness(credentials: credentials);
      addTearDown(h.dispose);
      final marking = h.owner.markAllNotificationsRead(_site);
      final outcome = expectLater(
        marking,
        throwsA(isA<AccountRequestRetiredException>()),
      );
      h.lifecycle.invalidate(_site);
      credentials.pending.complete('original');
      await outcome;
      expect(h.api.catalogs, isEmpty);
      expect(h.api.markedTypesRead, isEmpty);
    },
  );

  test('catalog credential failure stays observable and retryable', () async {
    final credentials = _CatalogFailureCredentials();
    final h = _Harness(credentials: credentials);
    addTearDown(h.dispose);
    await h.owner.loadOtherNotifications(_site);
    expect(h.api.catalogs, isEmpty);
    expect(h.activity.otherNotificationsFor(_site).error, isNotNull);
    final retry = h.owner.loadOtherNotifications(_site);
    await pumpEventQueue();
    h.api.catalogs.single.complete([_serverType]);
    await retry;
    expect(h.activity.otherNotificationsFor(_site).loaded, isTrue);
  });

  for (final retirement in ['lifecycle', 'forget', 'dispose']) {
    testWidgets('$retirement cancels a pending live refresh', (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.activity.loadPluginNotifications(h.current, _feed);
      h.api.feedKeys.clear();
      final lease = h.lifecycle.capture(_site);
      h.owner.acceptLiveState(_site, const {}, lease);
      switch (retirement) {
        case 'lifecycle':
          h.lifecycle.invalidate(_site);
        case 'forget':
          h.owner.forget(_site);
        case 'dispose':
          h.owner.dispose();
      }
      await tester.pump(const Duration(seconds: 2));
      expect(h.api.feedKeys, isEmpty);
    });
  }

  testWidgets('retired live lease cannot replace successor timer', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    final oldLease = h.lifecycle.capture(_site);
    h.lifecycle.invalidate(_site);
    await h.activity.loadPluginNotifications(h.current, _feed);
    h.api.feedKeys.clear();
    h.credentials.keys[_site] = 'successor';
    h.owner.acceptLiveState(_site, const {}, h.lifecycle.capture(_site));
    await tester.pump(const Duration(milliseconds: 500));
    h.owner.acceptLiveState(_site, const {
      'all_unread_notifications_count': 99,
    }, oldLease);
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.api.feedKeys, ['successor']);
    expect(h.activity.totalsFor(_site)?.unreadNotifications, isNot(99));
  });

  testWidgets(
    'grouped authority advances before live publication and can retire it',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.activity.loadPluginNotifications(h.current, _feed);
      h.api.feedKeys.clear();
      h.onAuthority = () {
        expect(h.activity.totalsFor(_site)?.unreadNotifications, isNot(8));
        h.lifecycle.invalidate(_site);
      };
      h.owner.acceptLiveState(_site, const {
        'grouped_unread_notifications': {'901': 8},
        'all_unread_notifications_count': 8,
      }, h.lifecycle.capture(_site));
      await tester.pump(const Duration(seconds: 2));
      expect(h.authorityCalls, 1);
      expect(h.activity.totalsFor(_site)?.unreadNotifications, isNot(8));
      expect(h.api.feedKeys, isEmpty);
    },
  );

  testWidgets('reentrant live publication preserves a successor timer', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.activity.loadPluginNotifications(h.current, _feed);
    h.api.feedKeys.clear();
    var replaced = false;
    h.activity.totalsListenable.addListener(() {
      if (replaced) return;
      replaced = true;
      h.owner.forget(_site);
      h.credentials.keys[_site] = 'successor';
      h.owner.acceptLiveState(_site, const {}, h.lifecycle.capture(_site));
    });
    h.owner.acceptLiveState(_site, const {
      'all_unread_notifications_count': 2,
    }, h.lifecycle.capture(_site));
    expect(replaced, isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(h.api.feedKeys, ['successor']);
  });
}

final class _Harness {
  _Harness({FakeApiCredentialReader? credentials})
    : credentials =
          credentials ?? (FakeApiCredentialReader()..keys[_site] = 'original') {
    activity = AccountActivityController(
      api: api,
      credentials: this.credentials,
      lifecycle: lifecycle,
    );
    owner = NotificationFeedRefreshOwner(
      api: api,
      credentials: this.credentials,
      lifecycle: lifecycle,
      activity: activity,
      instanceFor: (_) => current,
      claimedTypes: (_) => {const NotificationTypeName('replied')},
      groupedAuthorityAdvanced: (_) {
        authorityCalls++;
        onAuthority?.call();
      },
      refreshDebounce: const Duration(seconds: 1),
    );
  }
  final api = _Api();
  final FakeApiCredentialReader credentials;
  final lifecycle = SiteLifecycle();
  DiscourseInstance current = instance(
    'meta.discourse.org',
  ).copyWith(user: const DiscourseUser(id: 7, username: 'reader'));
  late final AccountActivityController activity;
  late final NotificationFeedRefreshOwner owner;
  int authorityCalls = 0;
  void Function()? onAuthority;
  void dispose() {
    owner.dispose();
    activity.dispose();
  }
}

final class _Api extends FakeDiscourseApi {
  _Api() : super(totals: const NotificationTotals());
  final catalogs = <Completer<List<NotificationWireType>>>[];
  final catalogKeys = <String?>[];
  final catalogSessions = <Object?>[];
  final feedKeys = <String>[];

  @override
  Future<List<NotificationWireType>> siteNotificationTypes({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final scope = AccountRequestScope.current!;
    scope.validate(siteUrl, apiKey, clientId);
    catalogSessions.add(scope.session);
    catalogKeys.add(apiKey);
    final result = Completer<List<NotificationWireType>>();
    catalogs.add(result);
    return result.future;
  }

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    String? clientId,
  }) async {
    feedKeys.add(apiKey);
    return const [];
  }
}

final class _GatedCredentials extends FakeApiCredentialReader {
  final pending = Completer<String?>();

  @override
  Future<String?> apiKeyFor(String siteUrl) => pending.future;
}

final class _CatalogFailureCredentials extends FakeApiCredentialReader {
  int reads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    if (++reads == 2) throw StateError('private storage unavailable');
    return 'original';
  }
}
