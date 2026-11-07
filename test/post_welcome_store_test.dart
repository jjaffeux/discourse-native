import 'dart:async';

import 'package:discourse_native/src/data/post_welcome_store.dart';
import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime.utc(2026, 11, 2, 12);
  final recent = DateTime.utc(2026, 11, 1, 12);
  PostWelcomeStore createStore() => PostWelcomeStore(clock: () => now);

  test('remembers the same welcome in a fresh store', () async {
    final first = createStore();
    expect(
      await first.claim('https://forum.example', 9, 42, createdAt: recent),
      isTrue,
    );

    final reopened = createStore();
    expect(
      await reopened.claim('https://forum.example', 9, 42, createdAt: recent),
      isFalse,
    );
    expect(
      await reopened.claim('https://forum.example', 10, 42, createdAt: recent),
      isTrue,
    );
    expect(
      await reopened.claim(
        'https://forum.example',
        null,
        42,
        createdAt: recent,
      ),
      isTrue,
    );
    expect(
      await reopened.claim('https://forum.example', 9, 43, createdAt: recent),
      isTrue,
    );
    expect(
      await reopened.claim('https://other.example', 9, 42, createdAt: recent),
      isTrue,
    );
  });

  test('retiring a forum removes its welcomes without a cached copy', () async {
    final store = createStore();
    expect(
      await store.claim('https://forum.example', 9, 42, createdAt: recent),
      isTrue,
    );
    expect(
      await store.claim('https://other.example', 9, 42, createdAt: recent),
      isTrue,
    );
    expect(
      await store.claim('https://forum.example', 9, 42, createdAt: recent),
      isFalse,
    );

    await forgetSitePreferences(
      const [],
      () => ForgottenSites.removed(
        'https://forum.example',
        keeping: const ['https://other.example'],
      ),
    );

    expect(
      await store.claim('https://forum.example', 9, 42, createdAt: recent),
      isTrue,
    );
    expect(
      await store.claim('https://other.example', 9, 42, createdAt: recent),
      isFalse,
    );
  });

  test(
    'a pending welcome claim cannot cross permanent forum retirement',
    () async {
      await SharedPreferences.getInstance();
      final claiming = createStore().claim(
        'https://forum.example',
        9,
        42,
        createdAt: recent,
      );
      await Future<void>.value();
      await forgetSitePreferences(
        const [],
        () =>
            ForgottenSites.removed('https://forum.example', keeping: const []),
      );
      expect(await claiming, isFalse);
      expect(
        await createStore().claim(
          'https://forum.example',
          9,
          42,
          createdAt: recent,
        ),
        isTrue,
      );
    },
  );

  test(
    'retirement orders an active claim before deletion and a fresh claim',
    () async {
      final backend = _WelcomePreferences()..hold = true;
      SharedPreferencesStorePlatform.instance = backend;
      final claiming = createStore().claim(
        'https://forum.example',
        9,
        42,
        createdAt: recent,
      );
      await backend.started.future;
      final retiring = Completer<void>();
      final forgetting = forgetSitePreferences(const [], () {
        retiring.complete();
        return ForgottenSites.removed(
          'https://forum.example',
          keeping: const [],
        );
      });
      await retiring.future;
      final successor = createStore().claim(
        'https://forum.example',
        9,
        42,
        createdAt: recent,
      );
      backend.hold = false;
      backend.release.complete();
      expect(await claiming, isFalse);
      await forgetting;
      expect(await successor, isTrue);
      expect(
        await createStore().claim(
          'https://forum.example',
          9,
          42,
          createdAt: recent,
        ),
        isFalse,
      );
    },
  );

  test(
    'a queued claim rechecks its welcome age at storage admission',
    () async {
      var current = DateTime.utc(2026, 11, 2, 12);
      final createdAt = DateTime.utc(2026, 10, 2, 12);
      final store = PostWelcomeStore(clock: () => current);
      final backend = _WelcomePreferences()
        ..hold = true
        ..rejectOnce = true;
      SharedPreferencesStorePlatform.instance = backend;
      final first = store.claim(
        'https://forum.example',
        9,
        42,
        createdAt: createdAt,
      );
      await backend.started.future;
      final queued = store.claim(
        'https://forum.example',
        9,
        42,
        createdAt: createdAt,
      );
      current = current.add(const Duration(microseconds: 1));
      backend.hold = false;
      backend.release.complete();
      expect(await first, isFalse);
      expect(await queued, isFalse);
    },
  );

  for (final throwsError in [false, true]) {
    test(
      'a failed claim remains available after ${throwsError ? 'exception' : 'rejection'}',
      () async {
        final backend = _WelcomePreferences()
          ..reject = !throwsError
          ..fail = throwsError;
        SharedPreferencesStorePlatform.instance = backend;
        expect(
          await createStore().claim(
            'https://forum.example',
            9,
            42,
            createdAt: recent,
          ),
          isFalse,
        );
        backend.reject = false;
        backend.fail = false;
        expect(
          await createStore().claim(
            'https://forum.example',
            9,
            42,
            createdAt: recent,
          ),
          isTrue,
        );
      },
    );
  }

  test('concurrent stores grant one claim for the same welcome', () async {
    final results = await Future.wait([
      createStore().claim('https://forum.example', 9, 42, createdAt: recent),
      createStore().claim('https://forum.example', 9, 42, createdAt: recent),
    ]);
    expect(results, [true, false]);
    expect(
      await createStore().claim(
        'https://forum.example',
        9,
        42,
        createdAt: recent,
      ),
      isFalse,
    );
  });

  for (final (name, createdAt, current, allowed) in [
    (
      'just before one month',
      DateTime.utc(2026, 10, 2, 12),
      DateTime.utc(2026, 11, 2, 11, 59, 59, 999, 999),
      true,
    ),
    (
      'exactly one month',
      DateTime.utc(2026, 10, 2, 12),
      DateTime.utc(2026, 11, 2, 12),
      true,
    ),
    (
      'just beyond one month',
      DateTime.utc(2026, 10, 2, 12),
      DateTime.utc(2026, 11, 2, 12, 0, 0, 0, 1),
      false,
    ),
    (
      'month end clamps to February',
      DateTime.utc(2026, 1, 31, 12),
      DateTime.utc(2026, 2, 28, 12),
      true,
    ),
    (
      'after the February month-end anniversary',
      DateTime.utc(2026, 1, 31, 12),
      DateTime.utc(2026, 2, 28, 12, 0, 0, 0, 1),
      false,
    ),
    (
      'leap-year month end',
      DateTime.utc(2024, 1, 31, 12),
      DateTime.utc(2024, 2, 29, 12),
      true,
    ),
    (
      'February to March uses the creation-day anniversary',
      DateTime.utc(2026, 2, 28, 12),
      DateTime.utc(2026, 3, 29, 12),
      false,
    ),
    (
      'year boundary',
      DateTime.utc(2025, 12, 31, 12),
      DateTime.utc(2026, 1, 31, 12),
      true,
    ),
    (
      'timestamp offsets represent the same instant',
      DateTime.parse('2026-10-02T14:00:00+02:00'),
      DateTime.utc(2026, 11, 2, 12),
      true,
    ),
    ('missing creation date', null, DateTime.utc(2026, 11, 2, 12), false),
  ]) {
    test('welcome age eligibility at $name', () async {
      final store = PostWelcomeStore(clock: () => current);
      expect(
        await store.claim('https://forum.example', 9, 42, createdAt: createdAt),
        allowed,
      );
      if (!allowed) {
        expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      }
    });
  }

  test(
    'checks age when claiming rather than when creating the store',
    () async {
      var current = DateTime.utc(2026, 2, 28, 12);
      final store = PostWelcomeStore(clock: () => current);
      current = DateTime.utc(2026, 3, 1, 12);
      expect(
        await store.claim(
          'https://forum.example',
          9,
          42,
          createdAt: DateTime.utc(2026, 1, 31, 12),
        ),
        isFalse,
      );
    },
  );
}

final class _WelcomePreferences extends InMemorySharedPreferencesStore {
  _WelcomePreferences() : super.withData({});
  bool hold = false, reject = false, fail = false, rejectOnce = false;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (hold) {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    if (fail) throw StateError('unavailable');
    if (rejectOnce) {
      rejectOnce = false;
      return false;
    }
    return reject ? false : super.setValue(valueType, key, value);
  }
}
