import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The keychain behaves differently per platform and only fails on a real
/// device, so it gets its own integration test.
///
/// macOS in particular refuses the data protection keychain without the
/// `keychain-access-groups` entitlement, which needs a signing certificate —
/// see [SecureStore]. That failure surfaces as `errSecMissingEntitlement`
/// (-34018) and is invisible to unit tests.
///
///   `flutter test integration_test/keychain_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('api keys round-trip through the keychain', () async {
    final store = SecureStore();
    const site = 'https://keychain-test.invalid';

    await store.writeApiKey(site, 'secret-key');
    expect(await store.readApiKey(site), 'secret-key');

    await store.deleteApiKey(site);
    expect(await store.readApiKey(site), isNull);
  });

  test('deleting a key that was never written is not an error', () async {
    final store = SecureStore();

    // Removing a site that was never connected asks for exactly this, and on
    // macOS it is the delete that finds nothing which reports -34018 — see
    // [SecureStore.deleteApiKey]. The round-trip above never reaches it,
    // because there the entry is always there to delete.
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

  test('the RSA key pair survives a round-trip', () async {
    final store = SecureStore();
    final generated = AuthKeyPair.generate();

    await store.writeKeyPair(generated);
    final read = await store.readKeyPair();

    expect(read, isNotNull);
    expect(read!.publicPem, generated.publicPem);
    // Parsing proves the PEM came back intact, not just string-equal.
    expect(read.privateKey.modulus, generated.privateKey.modulus);
  });
}
