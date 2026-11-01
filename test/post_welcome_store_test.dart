import 'package:discourse_native/src/data/post_welcome_store.dart';
import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('remembers the same welcome in a fresh store', () async {
    final first = PostWelcomeStore();
    addTearDown(first.dispose);
    expect(await first.hasSeen('https://forum.example', 9, 42), isFalse);
    await first.markSeen('https://forum.example', 9, 42);

    final reopened = PostWelcomeStore();
    addTearDown(reopened.dispose);
    expect(await reopened.hasSeen('https://forum.example', 9, 42), isTrue);
    expect(await reopened.hasSeen('https://forum.example', 10, 42), isFalse);
    expect(await reopened.hasSeen('https://forum.example', null, 42), isFalse);
    expect(await reopened.hasSeen('https://forum.example', 9, 43), isFalse);
    expect(await reopened.hasSeen('https://other.example', 9, 42), isFalse);
  });

  test('retiring a forum removes its welcomes without a cached copy', () async {
    final store = PostWelcomeStore();
    addTearDown(store.dispose);
    await store.markSeen('https://forum.example', 9, 42);
    await store.markSeen('https://other.example', 9, 42);
    expect(await store.hasSeen('https://forum.example', 9, 42), isTrue);

    await forgetSitePreferences(
      const [],
      () => ForgottenSites.removed(
        'https://forum.example',
        keeping: const ['https://other.example'],
      ),
    );

    expect(await store.hasSeen('https://forum.example', 9, 42), isFalse);
    expect(await store.hasSeen('https://other.example', 9, 42), isTrue);
  });
}
