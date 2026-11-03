import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'cakeday_fixture.dart';

void main() {
  testWidgets('minute timer ignores newly observed forums on the same day', (
    tester,
  ) async {
    final f = CakedayFixture();
    addTearDown(f.dispose);
    f.controller.observeDecorations(cakedaySite);
    var changes = 0;
    f.controller.addListener(() => changes++);
    f.controller.observeDecorations('https://second.example');

    await tester.pump(const Duration(minutes: 1));
    f.controller.setForeground(false);

    expect(changes, 0);
  });

  testWidgets('minute timer ignores forgotten forums on the same day', (
    tester,
  ) async {
    final f = CakedayFixture();
    addTearDown(f.dispose);
    f.controller.observeDecorations(cakedaySite);
    f.controller.observeDecorations('https://second.example');
    f.controller.setForeground(true);
    f.controller.forget('https://second.example');
    var changes = 0;
    f.controller.addListener(() => changes++);

    await tester.pump(const Duration(minutes: 1));
    f.controller.setForeground(false);

    expect(changes, 0);
  });

  testWidgets('minute timer does not repeat an announced timezone change', (
    tester,
  ) async {
    tzdata.initializeTimeZones();
    final f = CakedayFixture();
    addTearDown(f.dispose);
    f.clock = DateTime.utc(2026, 11, 1, 23, 30);
    f.controller.observeDecorations(cakedaySite);
    var changes = 0;
    f.controller.addListener(() => changes++);
    f.user = const DiscourseUser(
      id: 7,
      username: 'reader',
      timezone: 'Pacific/Kiritimati',
    );
    f.timezoneChanges.notifyListeners();
    expect(changes, 1);

    await tester.pump(const Duration(minutes: 1));
    f.controller.setForeground(false);

    expect(changes, 1);
  });

  for (final viewerMidnight in [false, true]) {
    testWidgets(
      'minute timer preserves ${viewerMidnight ? 'viewer' : 'device'} midnight when another forum is observed',
      (tester) async {
        tzdata.initializeTimeZones();
        final f = CakedayFixture();
        addTearDown(f.dispose);
        if (viewerMidnight) {
          f.user = const DiscourseUser(
            id: 7,
            username: 'reader',
            timezone: 'Pacific/Kiritimati',
          );
        }
        f.clock = DateTime.utc(2026, 11, 1, viewerMidnight ? 9 : 23, 59);
        f.controller.observeDecorations(cakedaySite);
        var changes = 0;
        f.controller.addListener(() => changes++);
        f.clock = f.clock.add(const Duration(minutes: 1));
        f.controller.observeDecorations('https://second.example');

        await tester.pump(const Duration(minutes: 1));
        final afterMidnight = changes;
        await tester.pump(const Duration(minutes: 1));
        f.controller.setForeground(false);
        expect(afterMidnight, 1);
        expect(changes, 1);
      },
    );
  }

  test(
    'effective birthday gate requires master plus login and makes no request',
    () async {
      for (final flags in [
        (false, true, true),
        (true, false, true),
        (true, true, false),
      ]) {
        final f = CakedayFixture(
          connected: flags.$1,
          enabled: flags.$2,
          birthdays: flags.$3,
        );
        addTearDown(f.dispose);
        await f.controller.load(cakedaySite, birthdayQuery);
        expect(f.transport.requests, isEmpty);
        expect(
          f.controller.enabled(cakedaySite, CakedayKind.birthdays),
          isFalse,
        );
      }
    },
  );
  test(
    'loading coalesces and account rotation revokes late publication',
    () async {
      final f = CakedayFixture();
      addTearDown(f.dispose);
      final pending = Completer<Map<String, dynamic>>();
      f
              .transport
              .responders['GET /cakeday/birthdays.json?page=0&filter=today'] =
          (_) => pending.future;
      final read = f.controller.load(cakedaySite, birthdayQuery);
      await Future<void>.delayed(Duration.zero);
      await f.controller.load(cakedaySite, birthdayQuery);
      expect(f.transport.reads, hasLength(1));
      f.requests.forget(cakedaySite);
      f.controller.forget(cakedaySite);
      f.user = const DiscourseUser(id: 9, username: 'another');
      pending.complete(page([celebration(2)]));
      await read;
      expect(f.controller.state(cakedaySite, birthdayQuery).members, isEmpty);
    },
  );
  test(
    'append preserves server order, deduplicates and retries a failed page',
    () async {
      final f = CakedayFixture();
      addTearDown(f.dispose);
      f
              .transport
              .responders['GET /cakeday/birthdays.json?page=0&filter=today'] =
          (_) => page(
            [celebration(2), celebration(1)],
            total: 60,
            next: '/community/cakeday/birthdays?page=1&filter=today',
          );
      await f.controller.load(cakedaySite, birthdayQuery);
      f.transport.failures['GET /cakeday/birthdays.json?page=1&filter=today'] =
          const WriteException(WriteFailure.unreachable);
      await f.controller.load(cakedaySite, birthdayQuery, more: true);
      expect(
        f.controller.state(cakedaySite, birthdayQuery).members.map((m) => m.id),
        [2, 1],
      );
      expect(f.controller.state(cakedaySite, birthdayQuery).failure, isNotNull);
      f
              .transport
              .responders['GET /cakeday/birthdays.json?page=1&filter=today'] =
          (_) => page(
            [celebration(1), celebration(3)],
            total: 60,
            next: '/community/cakeday/birthdays?page=2&filter=today',
          );
      await f.controller.load(cakedaySite, birthdayQuery, more: true);
      expect(
        f.controller.state(cakedaySite, birthdayQuery).members.map((m) => m.id),
        [2, 1, 3],
      );
      expect(f.controller.state(cakedaySite, birthdayQuery).nextPage, 2);
      expect(
        f.transport.reads.skip(1).map((request) => request.path),
        List.filled(2, '/cakeday/birthdays.json?page=1&filter=today'),
      );
    },
  );
  test('birthdays404 does not suppress available anniversaries', () async {
    final f = CakedayFixture();
    addTearDown(f.dispose);
    f.transport.failures['GET /cakeday/birthdays.json?page=0&filter=today'] =
        const WriteException(WriteFailure.validation, statusCode: 404);
    await f.controller.load(cakedaySite, birthdayQuery);
    expect(f.controller.enabled(cakedaySite, CakedayKind.birthdays), isFalse);
    expect(
      f.controller.enabled(cakedaySite, CakedayKind.anniversaries),
      isTrue,
    );
  });
  test(
    'forbidden result clears all private data and disables both directories',
    () async {
      final f = CakedayFixture();
      addTearDown(f.dispose);
      f
              .transport
              .responders['GET /cakeday/birthdays.json?page=0&filter=today'] =
          (_) => page([celebration(2)]);
      await f.controller.load(cakedaySite, birthdayQuery);
      f.transport.failures['GET /cakeday/birthdays.json?page=0&filter=today'] =
          const WriteException(WriteFailure.forbidden);
      await f.controller.load(cakedaySite, birthdayQuery, refresh: true);
      expect(f.controller.state(cakedaySite, birthdayQuery).members, isEmpty);
      expect(
        f.controller.enabled(cakedaySite, CakedayKind.anniversaries),
        isFalse,
      );
    },
  );
  test('same IDs on separate forums never share directory state', () async {
    final f = CakedayFixture();
    addTearDown(f.dispose);
    f.transport.responders['GET /cakeday/birthdays.json?page=0&filter=today'] =
        (r) => page([celebration(r.siteUrl == cakedaySite ? 2 : 3)]);
    await f.controller.load(cakedaySite, birthdayQuery);
    await f.controller.load('https://second.example', birthdayQuery);
    expect(f.controller.state(cakedaySite, birthdayQuery).members.single.id, 2);
    expect(
      f.controller
          .state('https://second.example', birthdayQuery)
          .members
          .single
          .id,
      3,
    );
  });
  test(
    'settings disabling clears data, then enabling permits a fresh read',
    () async {
      final f = CakedayFixture();
      addTearDown(f.dispose);
      f
              .transport
              .responders['GET /cakeday/birthdays.json?page=0&filter=today'] =
          (_) => page([celebration(2)]);
      await f.controller.load(cakedaySite, birthdayQuery);
      f.config.value = SiteConfig(
        plugins: PluginData.none.withValue(
          cakedaySettingsKey,
          const CakedaySettings(),
        ),
      );
      expect(f.controller.state(cakedaySite, birthdayQuery).members, isEmpty);
      f.config.value = SiteConfig(
        plugins: PluginData.none.withValue(
          cakedaySettingsKey,
          const CakedaySettings(enabled: true, birthdays: true),
        ),
      );
      await f.controller.load(cakedaySite, birthdayQuery);
      expect(f.transport.reads, hasLength(2));
    },
  );
  test(
    'canonical subfolder links retain month and reject foreign forums',
    () async {
      final f = CakedayFixture();
      addTearDown(f.dispose);
      expect(
        await f.navigation.openPluginUrl(
          '$cakedaySite/cakeday/birthdays/all?month=12',
        ),
        isTrue,
      );
      expect(f.routes.currentContent!.id, 'cakeday/birthdays/all/12');
      expect(
        await f.navigation.openPluginUrl(
          'https://other.example/cakeday/birthdays',
        ),
        isFalse,
      );
      expect(
        await f.navigation.openPluginUrl(
          '$cakedaySite/cakeday/birthdays/all?month=99',
        ),
        isFalse,
      );
    },
  );
  test(
    'visible directory hydrates again after an authorized current-user refresh',
    () async {
      final f = CakedayFixture();
      addTearDown(f.dispose);
      var id = 2;
      f
              .transport
              .responders['GET /cakeday/birthdays.json?page=0&filter=today'] =
          (_) => page([celebration(id)]);
      f.controller.retain(cakedaySite, birthdayQuery);
      await Future<void>.delayed(Duration.zero);
      expect(
        f.controller.state(cakedaySite, birthdayQuery).members.single.id,
        2,
      );
      id = 3;
      f.controller.pluginCurrentUserRefreshed(cakedaySite);
      await Future<void>.delayed(Duration.zero);
      expect(
        f.controller.state(cakedaySite, birthdayQuery).members.single.id,
        3,
      );
      f.controller.release(cakedaySite, birthdayQuery);
    },
  );
  test(
    'disposing during a read rejects its result and removes settings listeners',
    () async {
      final f = CakedayFixture();
      final pending = Completer<Map<String, dynamic>>();
      f
              .transport
              .responders['GET /cakeday/birthdays.json?page=0&filter=today'] =
          (_) => pending.future;
      final read = f.controller.load(cakedaySite, birthdayQuery);
      await Future<void>.delayed(Duration.zero);
      f.controller.dispose();
      pending.complete(page([celebration(2)]));
      await read;
      expect(f.config.listenerCount, 0);
      expect(f.timezoneChanges.listenerCount, 0);
      f.config.dispose();
      f.timezoneChanges.dispose();
    },
  );
  test(
    'directory today uses viewer timezone while inline decoration keeps device civil day',
    () {
      tzdata.initializeTimeZones();
      final f = CakedayFixture();
      addTearDown(f.dispose);
      f.user = const DiscourseUser(
        id: 7,
        username: 'reader',
        timezone: 'Pacific/Kiritimati',
      );
      f.clock = DateTime.utc(2026, 11, 1, 23, 30);
      expect(f.controller.viewerToday(cakedaySite), DateTime.utc(2026, 11, 2));
      final dates = CakedayDates.read({'birthdate': '1992-11-01'})!;
      expect(dates.celebratesBirthday(f.controller.now), isTrue);
      expect(
        dates.celebratesBirthday(f.controller.viewerToday(cakedaySite)),
        isFalse,
      );
    },
  );
  test(
    'foreground after midnight reloads visible query and revokes yesterday response',
    () async {
      final f = CakedayFixture();
      addTearDown(f.dispose);
      final yesterday = Completer<Map<String, dynamic>>();
      var reads = 0;
      f
              .transport
              .responders['GET /cakeday/birthdays.json?page=0&filter=today'] =
          (_) => ++reads == 1 ? yesterday.future : page([celebration(3)]);
      f.controller.retain(cakedaySite, birthdayQuery);
      await Future<void>.delayed(Duration.zero);
      f.controller.setForeground(false);
      f.clock = DateTime(2026, 11, 2, 1);
      f.controller.setForeground(true);
      await Future<void>.delayed(Duration.zero);
      expect(
        f.controller.state(cakedaySite, birthdayQuery).members.single.id,
        3,
      );
      yesterday.complete(page([celebration(2)]));
      await Future<void>.delayed(Duration.zero);
      expect(
        f.controller.state(cakedaySite, birthdayQuery).members.single.id,
        3,
      );
      f.controller.release(cakedaySite, birthdayQuery);
    },
  );
  for (final status in [401, 403, 404]) {
    test(
      'real HTTP adapter status $status clears held birthday rows with correct scope',
      () async {
        var responseStatus = 200;
        final requests = <http.Request>[];
        final api = DiscourseApi(
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode(
                responseStatus == 200
                    ? page([celebration(1)])
                    : <String, Object?>{
                        'errors': ['Not available'],
                      },
              ),
              responseStatus,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(api.close);
        final f = CakedayFixture(actualTransport: api);
        addTearDown(f.dispose);
        await f.controller.load(cakedaySite, birthdayQuery);
        expect(
          f.controller.state(cakedaySite, birthdayQuery).members.single.id,
          1,
        );
        responseStatus = status;
        await f.controller.load(cakedaySite, birthdayQuery, refresh: true);
        expect(requests.last.url.path, '/community/cakeday/birthdays.json');
        expect(requests.last.headers['user-api-key'], 'key');
        expect(f.controller.state(cakedaySite, birthdayQuery).members, isEmpty);
        expect(
          f.controller.enabled(cakedaySite, CakedayKind.birthdays),
          isFalse,
        );
        expect(
          f.controller.enabled(cakedaySite, CakedayKind.anniversaries),
          status == 404,
        );
      },
    );
  }
}
