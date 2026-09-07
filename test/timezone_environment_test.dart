import 'dart:async';

import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves Discourse aliases and historical IANA names', () {
    final environment = TimezoneEnvironment.forTesting(
      detectDeviceTimezone: () async => null,
    );
    addTearDown(environment.dispose);

    expect(environment.canonicalTimezone('UTC'), 'Etc/UTC');
    expect(environment.canonicalTimezone('IST'), 'Asia/Kolkata');
    expect(environment.canonicalTimezone('KST'), 'Asia/Seoul');
    expect(environment.canonicalTimezone('JST'), 'Asia/Tokyo');
    expect(environment.canonicalTimezone('US/Eastern'), 'US/Eastern');
  });

  test('uses account, device, then UTC reader-zone precedence', () {
    final environment = TimezoneEnvironment.forTesting(
      detectDeviceTimezone: () async => null,
    );
    addTearDown(environment.dispose);

    expect(environment.readerTimezone('Europe/Paris'), 'Europe/Paris');
    expect(environment.readerTimezone('not/a-zone'), 'Etc/UTC');
    environment.setDeviceTimezone('Asia/Tokyo');
    expect(environment.readerTimezone('Europe/Paris'), 'Europe/Paris');
    expect(environment.readerTimezone('not/a-zone'), 'Asia/Tokyo');
  });

  test('a stale timezone detection cannot replace a newer result', () async {
    final first = Completer<String?>();
    final second = Completer<String?>();
    var reads = 0;
    final environment = TimezoneEnvironment.forTesting(
      detectDeviceTimezone: () => reads++ == 0 ? first.future : second.future,
    );
    addTearDown(environment.dispose);

    final olderRefresh = environment.refreshDeviceTimezone();
    final newerRefresh = environment.refreshDeviceTimezone();
    second.complete('Asia/Tokyo');
    await newerRefresh;
    expect(environment.deviceTimezone, 'Asia/Tokyo');

    first.complete('Europe/Paris');
    await olderRefresh;
    expect(environment.deviceTimezone, 'Asia/Tokyo');
  });

  for (final result in <({String name, Future<String?> Function() read})>[
    (
      name: 'a platform failure',
      read: () async => throw StateError('unavailable'),
    ),
    (name: 'an empty reply', read: () async => null),
    (name: 'an unknown identifier', read: () async => 'Unknown/Zone'),
  ]) {
    test('retains the last device timezone after ${result.name}', () async {
      final environment = TimezoneEnvironment.forTesting(
        detectDeviceTimezone: result.read,
      )..setDeviceTimezone('Europe/Paris');
      addTearDown(environment.dispose);
      var changes = 0;
      environment.addListener(() => changes++);

      await environment.refreshDeviceTimezone();

      expect(environment.readerTimezone(), 'Europe/Paris');
      expect(changes, 0);
      await environment.refreshDeviceTimezone(forceNotify: true);
      expect(environment.readerTimezone(), 'Europe/Paris');
      expect(
        changes,
        1,
        reason: 'resume refreshes relative dates even when detection fails',
      );
    });
  }

  test('failed initial detection falls back to UTC and can recover', () async {
    var reads = 0;
    final environment = TimezoneEnvironment.forTesting(
      detectDeviceTimezone: () async {
        if (reads++ == 0) throw StateError('unavailable');
        return 'Europe/Paris';
      },
    );
    addTearDown(environment.dispose);

    await environment.initialize();
    expect(environment.deviceTimezone, isNull);
    expect(environment.readerTimezone(), 'Etc/UTC');
    await environment.refreshDeviceTimezone();
    expect(environment.readerTimezone(), 'Europe/Paris');
  });

  test(
    'disposal cancels detection results and prevents further platform reads',
    () async {
      final detected = Completer<String?>();
      var reads = 0;
      final environment = TimezoneEnvironment.forTesting(
        detectDeviceTimezone: () {
          reads++;
          return detected.future;
        },
      );
      final refresh = environment.refreshDeviceTimezone();
      environment.dispose();
      detected.complete('Asia/Tokyo');

      await refresh;
      await environment.refreshDeviceTimezone(forceNotify: true);
      expect(environment.deviceTimezone, isNull);
      expect(reads, 1);
    },
  );
}
