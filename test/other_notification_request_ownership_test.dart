import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/shell/account_activity_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');
const _types = [NotificationTypeName('granted_badge')];
const _notification = DiscourseNotification.test(
  id: 11,
  typeId: NotificationTypeId(12),
  title: 'A badge',
);
final _connected = instance('meta.discourse.org').copyWith(user: _user);

enum _Retirement { forget, lifecycleReplacement, dispose }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Other notification request ownership', () {
    for (final retirement in _Retirement.values) {
      test(
        '${retirement.name} during type resolution sends no request',
        () async {
          final api = _NotificationsApi();
          final credentials = FakeApiCredentialReader()
            ..keys[_siteUrl] = 'original-key';
          final lifecycle = SiteLifecycle();
          final controller = _controller(api, credentials, lifecycle);
          var disposed = false;
          addTearDown(() {
            if (!disposed) controller.dispose();
          });
          final resolver = _GatedTypes();

          final first = controller.loadOtherNotifications(
            _connected,
            resolver.call,
          );
          final joined = controller.loadOtherNotifications(
            _connected,
            resolver.call,
          );
          await resolver.started.future;
          expect(resolver.keys, ['original-key']);
          expect(api.requests, isEmpty);

          switch (retirement) {
            case _Retirement.forget:
              // Keep the lease current so this also requires request ownership.
              controller.forget(_siteUrl);
            case _Retirement.lifecycleReplacement:
              lifecycle.invalidate(_siteUrl);
              lifecycle.capture(_siteUrl);
              credentials.keys[_siteUrl] = 'replacement-key';
            case _Retirement.dispose:
              controller.dispose();
              disposed = true;
          }
          final retiredFeed = controller.otherNotificationsFor(_siteUrl);
          resolver.result.complete(_types);
          await Future.wait([first, joined]);

          expect(api.requests, isEmpty);
          expect(controller.otherNotificationsFor(_siteUrl), same(retiredFeed));
          expect(controller.otherNotificationsFor(_siteUrl).loaded, isFalse);
        },
      );
    }

    for (final replacementCompletesFirst in [false, true]) {
      test(
        'late catalog preserves a ${replacementCompletesFirst ? 'loaded' : 'pending'} replacement',
        () async {
          final api = _NotificationsApi();
          final credentials = FakeApiCredentialReader()
            ..keys[_siteUrl] = 'original-key';
          final lifecycle = SiteLifecycle();
          final controller = _controller(api, credentials, lifecycle);
          addTearDown(controller.dispose);
          final abandonedTypes = _GatedTypes();
          final replacementTypes = _GatedTypes();

          final abandoned = controller.loadOtherNotifications(
            _connected,
            abandonedTypes.call,
          );
          final joinedAbandoned = controller.loadOtherNotifications(
            _connected,
            abandonedTypes.call,
          );
          await abandonedTypes.started.future;
          lifecycle.invalidate(_siteUrl);
          controller.forget(_siteUrl);
          credentials.keys[_siteUrl] = 'replacement-key';

          final replacement = controller.loadOtherNotifications(
            _connected,
            replacementTypes.call,
          );
          await replacementTypes.started.future;
          if (replacementCompletesFirst) {
            replacementTypes.result.complete(_types);
            await replacement;
          }
          final replacementFeed = controller.otherNotificationsFor(_siteUrl);

          abandonedTypes.result.complete(_types);
          await Future.wait([abandoned, joinedAbandoned]);
          expect(
            controller.otherNotificationsFor(_siteUrl),
            same(replacementFeed),
          );
          expect(
            api.requests.map((request) => request.apiKey),
            replacementCompletesFirst ? ['replacement-key'] : isEmpty,
          );

          if (!replacementCompletesFirst) {
            final joinedReplacement = controller.loadOtherNotifications(
              _connected,
              replacementTypes.call,
            );
            expect(joinedReplacement, same(replacement));
            replacementTypes.result.complete(_types);
            await Future.wait([replacement, joinedReplacement]);
          }

          expect(replacementTypes.keys, ['replacement-key']);
          expect(api.requests, hasLength(1));
          expect(api.requests.single.siteUrl, _siteUrl);
          expect(api.requests.single.apiKey, 'replacement-key');
          expect(api.requests.single.types, _types);
          expect(controller.otherNotificationsFor(_siteUrl).notifications, [
            _notification,
          ]);
        },
      );
    }

    test(
      'current owner coalesces callers across both request stages',
      () async {
        final response = Completer<List<DiscourseNotification>>();
        final api = _NotificationsApi(response: response);
        final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
        final controller = _controller(api, credentials, SiteLifecycle());
        addTearDown(controller.dispose);
        final resolver = _GatedTypes();

        final first = controller.loadOtherNotifications(
          _connected,
          resolver.call,
        );
        await resolver.started.future;
        final duringCatalog = controller.loadOtherNotifications(
          _connected,
          resolver.call,
        );
        expect(duringCatalog, same(first));
        expect(api.requests, isEmpty);
        expect(controller.otherNotificationsFor(_siteUrl).loading, isTrue);

        resolver.result.complete(_types);
        await api.started.future;
        final duringNotifications = controller.loadOtherNotifications(
          _connected,
          resolver.call,
        );
        expect(duringNotifications, same(first));
        expect(resolver.keys, ['key']);
        expect(api.requests, hasLength(1));
        expect(api.requests.single.siteUrl, _siteUrl);
        expect(api.requests.single.apiKey, 'key');
        expect(api.requests.single.types, _types);
        expect(controller.otherNotificationsFor(_siteUrl).loaded, isFalse);

        response.complete(const [_notification]);
        await Future.wait([first, duringCatalog, duringNotifications]);
        final feed = controller.otherNotificationsFor(_siteUrl);
        expect(feed.notifications, [_notification]);
        expect(feed.loaded, isTrue);
        expect(feed.loading, isFalse);
        expect(feed.error, isNull);
      },
    );

    test(
      'empty catalog completes the feed without a notification request',
      () async {
        final api = _NotificationsApi();
        final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
        final controller = _controller(api, credentials, SiteLifecycle());
        addTearDown(controller.dispose);
        final resolver = _GatedTypes();

        final first = controller.loadOtherNotifications(
          _connected,
          resolver.call,
        );
        await resolver.started.future;
        final joined = controller.loadOtherNotifications(
          _connected,
          resolver.call,
        );
        resolver.result.complete(const []);
        await Future.wait([first, joined]);

        expect(resolver.keys, ['key']);
        expect(api.requests, isEmpty);
        final feed = controller.otherNotificationsFor(_siteUrl);
        expect(feed.isEmpty, isTrue);
        expect(feed.loading, isFalse);
        expect(feed.error, isNull);
      },
    );
  });

  group('shell Other notification catalog ownership', () {
    for (final dispose in [false, true]) {
      test(
        '${dispose ? 'disposal' : 'disconnect'} during the real resolver sends no request',
        () async {
          final api = _CatalogApi();
          final shell = await _shell(api);
          var disposed = false;
          addTearDown(() {
            if (!disposed) shell.dispose();
          });
          final first = shell.loadOtherNotifications(_siteUrl);
          final joined = shell.loadOtherNotifications(_siteUrl);
          await api.catalogStarted.future;
          expect(api.catalogKeys, ['original-key']);

          if (dispose) {
            shell.dispose();
            disposed = true;
          } else {
            expect(await shell.disconnectInstance(_siteUrl), isTrue);
            expect(shell.instances.single.isConnected, isFalse);
          }
          final retiredFeed = shell.otherNotificationsFor(_siteUrl);
          api.catalog.complete(const [CoreNotificationTypes.grantedBadge]);
          await Future.wait([first, joined]);

          expect(api.requests, isEmpty);
          expect(shell.otherNotificationsFor(_siteUrl), same(retiredFeed));
          expect(shell.otherNotificationsFor(_siteUrl).loaded, isFalse);
        },
      );
    }

    test('current shell owner resolves and caches unclaimed types', () async {
      final api = _CatalogApi();
      final shell = await _shell(api);
      addTearDown(shell.dispose);
      final first = shell.loadOtherNotifications(_siteUrl);
      final joined = shell.loadOtherNotifications(_siteUrl);
      await api.catalogStarted.future;
      expect(api.requests, isEmpty);

      api.catalog.complete(const [
        CoreNotificationTypes.replied,
        CoreNotificationTypes.grantedBadge,
      ]);
      await Future.wait([first, joined]);

      expect(api.catalogKeys, ['original-key']);
      expect(api.requests, hasLength(1));
      expect(api.requests.single.siteUrl, _siteUrl);
      expect(api.requests.single.apiKey, 'original-key');
      expect(api.requests.single.types, _types);
      expect(shell.otherNotificationsFor(_siteUrl).notifications, [
        _notification,
      ]);

      await shell.loadOtherNotifications(_siteUrl);
      expect(api.catalogKeys, ['original-key']);
      expect(api.requests, hasLength(2));
    });
  });
}

AccountActivityController _controller(
  _NotificationsApi api,
  FakeApiCredentialReader credentials,
  SiteLifecycle lifecycle,
) => AccountActivityController(
  api: api,
  credentials: credentials,
  lifecycle: lifecycle,
);

Future<ShellController> _shell(_CatalogApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([_connected]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'original-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await pumpEventQueue();
  return shell;
}

final class _GatedTypes {
  final started = Completer<void>();
  final result = Completer<List<NotificationTypeName>>();
  final List<String> keys = [];

  Future<List<NotificationTypeName>> call(String apiKey) {
    keys.add(apiKey);
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

class _NotificationsApi extends FakeDiscourseApi {
  _NotificationsApi({this.response})
    : super(user: _user, totals: const NotificationTotals());

  final Completer<List<DiscourseNotification>>? response;
  final started = Completer<void>();
  final List<
    ({String siteUrl, String apiKey, List<NotificationTypeName> types})
  >
  requests = [];

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    String? clientId,
  }) {
    requests.add((
      siteUrl: siteUrl,
      apiKey: apiKey,
      types: List.unmodifiable(filterByTypes),
    ));
    if (!started.isCompleted) started.complete();
    return response?.future ?? Future.value(const [_notification]);
  }
}

final class _CatalogApi extends _NotificationsApi {
  final catalogStarted = Completer<void>();
  final catalog = Completer<List<NotificationWireType>>();
  final List<String?> catalogKeys = [];

  @override
  Future<List<NotificationWireType>> siteNotificationTypes({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    catalogKeys.add(apiKey);
    if (!catalogStarted.isCompleted) catalogStarted.complete();
    return catalog.future;
  }
}
