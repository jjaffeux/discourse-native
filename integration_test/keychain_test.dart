import 'package:discourse_native/src/data/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Private storage behaves differently per platform and only reaches Keychain
/// or the Linux filesystem on a real device, so it gets an integration test.
///
/// A normal macOS test run exercises the isolated custom-signed development
/// service. The distributed release uses the Data Protection Keychain instead;
/// its application identifier is supplied by TestFlight/App Store signing and
/// must also be checked in a distribution-signed smoke test.
///
///   `flutter test integration_test/keychain_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('api keys round-trip through private storage', () async {
    final store = SecureStore();
    const site = 'https://keychain-test.invalid';

    await store.writeApiKey(site, 'first-key');
    await store.writeApiKey(site, 'secret-key');
    final reopened = SecureStore();
    expect(await reopened.readApiKey(site), 'secret-key');

    await reopened.deleteApiKey(site);
    expect(await SecureStore().readApiKey(site), isNull);
  });

  test('deleting a key that was never written is not an error', () async {
    final store = SecureStore();

    // Removing a site that was never connected asks for exactly this. It must
    // remain idempotent and must never enumerate unrelated legacy items.
    await expectLater(
      store.deleteApiKey('https://never-connected.invalid'),
      completes,
    );
  });

  test('the client id is created once and then reused', () async {
    final store = SecureStore();

    final first = await store.readOrCreateClientId();
    expect(first, isNotEmpty);
    expect(await store.readOrCreateClientId(), first);
  });
}
