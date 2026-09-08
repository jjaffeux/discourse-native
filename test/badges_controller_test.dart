import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/badges_api.dart';
import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/badge_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/badges_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/badge_fixtures.dart';

void main() {
  const site = DiscourseInstance(
    url: 'https://example.com/forum',
    title: 'Forum',
  );
  const directory = BadgeRoute.directory();
  final detail = BadgeRoute.detail(1);
  late _Transport transport;
  late SiteLifecycle lifecycle;
  late BadgesController controller;
  setUp(() {
    transport = _Transport();
    lifecycle = SiteLifecycle();
    controller = BadgesController(
      api: BadgesApi(transport),
      credentials: const _Credentials(),
      lifecycle: lifecycle,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'public catalog uses only_listable and caches until refreshed',
    () async {
      await controller.load(site, directory);
      expect(transport.requests.single.path, '/badges.json?only_listable=true');
      expect(transport.requests.single.apiKey, isNull);
      expect(controller.stateFor(site.url, directory).catalog!.total, 3);
      await controller.load(site, directory);
      expect(transport.requests.length, 1);
      await controller.load(site, directory, refresh: true);
      expect(transport.requests.length, 2);
    },
  );

  test('disabled forums do not load badges', () async {
    await controller.load(
      site.copyWith(config: const SiteConfig(badgesEnabled: false)),
      directory,
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'preserves a loaded catalog on refresh failure and supports retry',
    () async {
      await controller.load(site, directory);
      transport.fail = true;
      await controller.load(site, directory, refresh: true);
      final state = controller.stateFor(site.url, directory);
      expect(state.catalog!.total, 3);
      expect(state.loading, isFalse);
      expect(state.error, isNotNull);
      transport.fail = false;
      await controller.load(site, directory, refresh: true);
      expect(controller.stateFor(site.url, directory).error, isNull);
    },
  );

  test(
    'details keep repeat awards, deduplicate grants, and retry the same offset',
    () async {
      transport.respond = (path) async {
        if (path == '/badges/1.json') return {'badge': badgeWire};
        final offset = int.parse(Uri.parse(path).queryParameters['offset']!);
        return offset == 0
            ? badgeGrantsWire(count: 96)
            : badgeGrantsWire(offset: 95, count: 2);
      };
      await controller.load(site, detail);
      expect(controller.stateFor(site.url, detail).hasMore, isTrue);
      transport.fail = true;
      await controller.load(site, detail, more: true);
      expect(controller.stateFor(site.url, detail).grants.length, 96);
      expect(controller.stateFor(site.url, detail).nextOffset, 96);
      expect(controller.stateFor(site.url, detail).recipientsError, isNotNull);
      transport.fail = false;
      await controller.load(site, detail, more: true);
      final state = controller.stateFor(site.url, detail);
      expect(state.grants.length, 97);
      expect(state.grants.map((grant) => grant.username).toSet(), {'sam'});
      expect(state.hasMore, isFalse);
      expect(state.recipientsError, isNull);
      expect(
        transport.requests.last.path,
        '/user_badges.json?badge_id=1&offset=96',
      );
    },
  );

  test(
    'recipient failure leaves badge details visible and can retry page zero',
    () async {
      transport.respond = (path) async {
        if (path == '/badges/1.json') return {'badge': badgeWire};
        throw StateError('unavailable');
      };
      final route = BadgeRoute.detail(1, username: 'sam');
      await controller.load(
        site.copyWith(user: const DiscourseUser(username: 'sam')),
        route,
      );
      expect(
        controller.stateFor(site.url, route).badge!.name,
        'Autobiographer',
      );
      expect(controller.stateFor(site.url, route).error, isNull);
      expect(controller.stateFor(site.url, route).recipientsError, isNotNull);
      expect(transport.requests.last.apiKey, 'secret');
      expect(transport.requests.last.clientId, 'client');
      transport.respond = (_) async => badgeGrantsWire();
      await controller.load(site, route, more: true);
      expect(
        transport.requests.last.path,
        '/user_badges.json?badge_id=1&offset=0&username=sam',
      );
      expect(controller.stateFor(site.url, route).grants.length, 1);
    },
  );

  test(
    'an old account response cannot overwrite or block its replacement',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      transport.respond = (_) {
        started.complete();
        return pending.future;
      };
      final old = controller.load(site, directory);
      await started.future;
      lifecycle.invalidate(site.url);
      expect(controller.stateFor(site.url, directory).catalog, isNull);
      transport.respond = (_) async => {
        ...badgeCatalogWire,
        'badges': <Map<String, dynamic>>[],
      };
      await controller.load(site, directory);
      pending.complete(badgeCatalogWire);
      await old;
      expect(controller.stateFor(site.url, directory).catalog!.total, 0);
      expect(controller.stateFor(site.url, directory).loading, isFalse);
    },
  );

  test(
    'forgetting a forum suppresses late details and recipient requests',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      transport.respond = (_) {
        started.complete();
        return pending.future;
      };
      final old = controller.load(site, detail);
      await started.future;
      controller.forget(site.url);
      pending.complete({'badge': badgeWire});
      await old;
      expect(controller.stateFor(site.url, detail).badge, isNull);
      expect(transport.requests.length, 1);
    },
  );
}

final class _Transport implements PluginApiTransport {
  final requests = <({String path, String? apiKey, String? clientId})>[];
  bool fail = false;
  Future<Map<String, dynamic>> Function(String) respond = (_) async =>
      badgeCatalogWire;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    requests.add((path: path, apiKey: apiKey, clientId: clientId));
    if (fail) throw StateError('unavailable');
    return respond(path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Credentials implements ApiCredentialReader {
  const _Credentials();
  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'secret';
  @override
  Future<String> clientId() async => 'client';
}
