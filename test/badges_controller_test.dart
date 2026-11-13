import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/badges_api.dart';
import 'package:discourse_native/src/data/discourse_badges_api.dart';
import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/badge.dart';
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
      api: DiscourseBadgesApi(transport),
      credentials: const _Credentials(),
      lifecycle: lifecycle,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'badge presentation consumes a domain API without HTTP or wire fixtures',
    () async {
      final catalog = BadgeCatalog([
        BadgeGroup(
          id: 1,
          name: 'Community',
          badges: const [DiscourseBadge(id: 1, name: 'Welcome')],
        ),
      ]);
      final fake = _DomainBadgesApi(catalog);
      final presentation = BadgesController(
        api: fake,
        credentials: const _Credentials(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(presentation.dispose);
      await presentation.load(site, directory);
      final state = presentation.stateFor(site.url, directory);
      expect(state.loaded, isTrue);
      expect(state.catalog, same(catalog));
      expect(state.catalog!.groups.single.badges.single.name, 'Welcome');
      expect(fake.sites, [site.url]);
    },
  );

  test(
    'keeps paging older recipients after a mass award shifts a full page',
    () async {
      final initial = badgeGrantsWire(count: 200);
      final initialInfo = initial['user_badge_info'] as Map<String, dynamic>;
      var serverRows = (initialInfo['user_badges'] as List).reversed.toList();
      transport.respond = (path) async {
        if (path == '/badges/1.json') return {'badge': badgeWire};
        final offset = int.parse(Uri.parse(path).queryParameters['offset']!);
        return {
          ...initial,
          'user_badge_info': {
            'user_badges': serverRows.skip(offset).take(96).toList(),
          },
        };
      };
      await controller.load(site, detail);
      expect(controller.stateFor(site.url, detail).grants, hasLength(96));

      // A scheduled award adds a page ahead of the already displayed grants.
      final awarded = badgeGrantsWire(offset: 200, count: 96);
      final awardedInfo = awarded['user_badge_info'] as Map<String, dynamic>;
      serverRows = [
        ...(awardedInfo['user_badges'] as List).reversed,
        ...serverRows,
      ];
      await controller.load(site, detail, more: true);
      final duplicatePage = controller.stateFor(site.url, detail);
      expect(duplicatePage.grants, hasLength(96));
      expect(duplicatePage.nextOffset, 192);
      expect(duplicatePage.hasMore, isTrue);

      await controller.load(site, detail, more: true);
      expect(controller.stateFor(site.url, detail).grants, hasLength(192));
      await controller.load(site, detail, more: true);
      final finished = controller.stateFor(site.url, detail);
      expect(finished.grants.map((grant) => grant.id), [
        for (var id = 200; id > 0; id--) id,
      ]);
      expect(finished.nextOffset, 296);
      expect(finished.hasMore, isFalse);
      final requests = transport.requests.length;
      await controller.load(site, detail, more: true);
      expect(transport.requests, hasLength(requests));
    },
  );

  for (final (boundary, count, total) in [
    ('an empty page', 0, null),
    ('a partial duplicate page', 2, null),
    ('the reported total on a full duplicate page', 96, 192),
  ]) {
    test('recipient pagination stops at $boundary', () async {
      transport.respond = (path) async {
        if (path == '/badges/1.json') return {'badge': badgeWire};
        final offset = int.parse(Uri.parse(path).queryParameters['offset']!);
        return badgeGrantsWire(count: offset == 0 ? 96 : count, total: total);
      };
      await controller.load(site, detail);
      expect(controller.stateFor(site.url, detail).hasMore, isTrue);
      await controller.load(site, detail, more: true);
      final finished = controller.stateFor(site.url, detail);
      expect(finished.grants, hasLength(96));
      expect(finished.nextOffset, 96 + count);
      expect(finished.hasMore, isFalse);
      final requests = transport.requests.length;
      await controller.load(site, detail, more: true);
      expect(transport.requests, hasLength(requests));
    });
  }

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

  test('late failure cannot release a pending successor catalog', () async {
    final oldStarted = Completer<void>();
    final oldReply = Completer<Map<String, dynamic>>();
    transport.respond = (_) {
      oldStarted.complete();
      return oldReply.future;
    };
    final former = controller.load(site, directory);
    await oldStarted.future;
    lifecycle.invalidate(site.url);
    final newStarted = Completer<void>();
    final newReply = Completer<Map<String, dynamic>>();
    transport.respond = (_) {
      newStarted.complete();
      return newReply.future;
    };
    final replacement = controller.load(site, directory);
    await newStarted.future;
    oldReply.completeError(StateError('old catalog'));
    await former;
    expect(controller.stateFor(site.url, directory).loading, isTrue);
    expect(controller.stateFor(site.url, directory).error, isNull);
    await controller.load(site, directory);
    expect(transport.requests, hasLength(2));
    newReply.complete(badgeCatalogWire);
    await replacement;
    expect(controller.stateFor(site.url, directory).catalog!.total, 3);
  });

  test(
    'bounds routes and fences an evicted request for the same route',
    () async {
      final oldStarted = Completer<void>();
      final oldReply = Completer<Map<String, dynamic>>();
      transport.respond = (path) async {
        if (path == '/badges.json?only_listable=true') {
          oldStarted.complete();
          return oldReply.future;
        }
        if (path.startsWith('/badges/')) return {'badge': badgeWire};
        return badgeGrantsWire();
      };
      final former = controller.load(site, directory);
      await oldStarted.future;
      for (var id = 1; id <= 16; id++) {
        await controller.load(site, BadgeRoute.detail(id));
      }
      expect(controller.stateFor(site.url, directory).loading, isFalse);
      final newStarted = Completer<void>();
      final newReply = Completer<Map<String, dynamic>>();
      transport.respond = (_) {
        newStarted.complete();
        return newReply.future;
      };
      final replacement = controller.load(site, directory);
      await newStarted.future;
      oldReply.complete(badgeCatalogWire);
      await former;
      expect(controller.stateFor(site.url, directory).loading, isTrue);
      final count = transport.requests.length;
      await controller.load(site, directory);
      expect(transport.requests.length, count);
      newReply.complete(badgeCatalogWire);
      await replacement;
      expect(controller.stateFor(site.url, directory).catalog!.total, 3);
      expect(
        controller.stateFor(site.url, BadgeRoute.detail(1)).loaded,
        isFalse,
      );
    },
  );

  test(
    'forgetting during detail publication prevents recipient publication',
    () async {
      transport.respond = (path) async =>
          path == '/badges/1.json' ? {'badge': badgeWire} : badgeGrantsWire();
      var forgotten = false;
      controller.addListener(() {
        if (!forgotten && controller.stateFor(site.url, detail).badge != null) {
          forgotten = true;
          controller.forget(site.url);
        }
      });
      await controller.load(site, detail);
      expect(forgotten, isTrue);
      expect(controller.stateFor(site.url, detail).badge, isNull);
      expect(transport.requests.map((request) => request.path), [
        '/badges/1.json',
        '/user_badges.json?badge_id=1&offset=0',
      ]);
    },
  );

  test(
    'forgetting a forum suppresses late detail and recipient responses',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      final grants = Completer<Map<String, dynamic>>();
      transport.respond = (path) {
        if (path == '/badges/1.json') {
          started.complete();
          return pending.future;
        }
        return grants.future;
      };
      final old = controller.load(site, detail);
      await started.future;
      controller.forget(site.url);
      grants.complete(badgeGrantsWire());
      pending.complete({'badge': badgeWire});
      await old;
      expect(controller.stateFor(site.url, detail).badge, isNull);
      expect(controller.stateFor(site.url, detail).grants, isEmpty);
      expect(transport.requests.length, 2);
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

final class _DomainBadgesApi implements BadgesApi {
  _DomainBadgesApi(this.value);
  final BadgeCatalog value;
  final List<String> sites = [];

  @override
  Future<BadgeCatalog> catalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    sites.add(siteUrl);
    return value;
  }

  @override
  Future<DiscourseBadge> badge({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  }) async => value.groups.single.badges.single;

  @override
  Future<BadgeGrantPage> grants({
    required String siteUrl,
    required BadgeRoute route,
    int offset = 0,
    String? apiKey,
    String? clientId,
  }) => throw UnimplementedError();
}
