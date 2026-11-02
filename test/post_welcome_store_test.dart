import 'package:discourse_native/src/data/post_welcome_store.dart';
import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
