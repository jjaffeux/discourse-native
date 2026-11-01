import 'package:discourse_native/src/data/post_welcome_store.dart';
import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('remembers the same welcome in a fresh store', () async {
    const createStore = PostWelcomeStore.new;
    final first = createStore();
    expect(await first.claim('https://forum.example', 9, 42), isTrue);

    final reopened = createStore();
    expect(await reopened.claim('https://forum.example', 9, 42), isFalse);
    expect(await reopened.claim('https://forum.example', 10, 42), isTrue);
    expect(await reopened.claim('https://forum.example', null, 42), isTrue);
    expect(await reopened.claim('https://forum.example', 9, 43), isTrue);
    expect(await reopened.claim('https://other.example', 9, 42), isTrue);
  });

  test('retiring a forum removes its welcomes without a cached copy', () async {
    const store = PostWelcomeStore();
    expect(await store.claim('https://forum.example', 9, 42), isTrue);
    expect(await store.claim('https://other.example', 9, 42), isTrue);
    expect(await store.claim('https://forum.example', 9, 42), isFalse);

    await forgetSitePreferences(
      const [],
      () => ForgottenSites.removed(
        'https://forum.example',
        keeping: const ['https://other.example'],
      ),
    );

    expect(await store.claim('https://forum.example', 9, 42), isTrue);
    expect(await store.claim('https://other.example', 9, 42), isFalse);
  });

  test('concurrent stores grant one claim for the same welcome', () async {
    const createStore = PostWelcomeStore.new;
    final results = await Future.wait([
      createStore().claim('https://forum.example', 9, 42),
      createStore().claim('https://forum.example', 9, 42),
    ]);
    expect(results, [true, false]);
    expect(await createStore().claim('https://forum.example', 9, 42), isFalse);
  });
}
