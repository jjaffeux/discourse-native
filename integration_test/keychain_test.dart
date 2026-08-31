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
/// ```sh
/// flutter test integration_test/keychain_test.dart \
///   --test-randomize-ordering-seed=random -d macos
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('API key lifecycle persists across reopened stores', () async {
    final store = SecureStore();
    const site = 'https://keychain-test.invalid';
    addTearDown(() => SecureStore().deleteApiKey(site));

    await store.writeApiKey(site, 'first-key');
    final afterWrite = SecureStore();
    expect(await afterWrite.readApiKey(site), 'first-key');

    await afterWrite.writeApiKey(site, 'replacement-key');
    final afterReplacement = SecureStore();
    expect(await afterReplacement.readApiKey(site), 'replacement-key');

    await afterReplacement.deleteApiKey(site);
    expect(await SecureStore().readApiKey(site), isNull);
  });

  test('deleting an already-absent API key is idempotent', () async {
    final store = SecureStore();
    const site = 'https://never-connected.invalid';

    // Removing a site that was never connected asks for exactly this. It must
    // remain idempotent and must never enumerate unrelated legacy items.
    await store.deleteApiKey(site);
    await expectLater(store.deleteApiKey(site), completes);
  });

  test('the client ID remains stable across reopened stores', () async {
    final store = SecureStore();

    final first = await store.readOrCreateClientId();
    expect(first, isNotEmpty);
    expect(await SecureStore().readOrCreateClientId(), first);
  });
}
