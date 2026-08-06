import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'user_api_key.dart';

/// Keychain-backed storage for anything that must not sit in plain
/// preferences: the RSA key pair and the per-site API keys.
///
/// Note DiscourseMobile keeps these in AsyncStorage, which is not encrypted.
/// There is no reason to copy that.
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(mOptions: _macOptions);

  /// macOS only. The data protection keychain — the plugin's default — requires
  /// the `keychain-access-groups` entitlement, which in turn requires signing
  /// with a real development certificate; without one every read fails with
  /// `errSecMissingEntitlement` (-34018).
  ///
  /// The file-based keychain is still the system keychain, just the older API,
  /// and needs no entitlement. Switch this back once the macOS target is signed
  /// with a team, and add the entitlement at the same time.
  static const AppleOptions _macOptions = MacOsOptions(
    usesDataProtectionKeychain: false,
  );

  static const String _publicKeyEntry = 'rsa_public_key';
  static const String _privateKeyEntry = 'rsa_private_key';
  static const String _clientIdEntry = 'client_id';

  final FlutterSecureStorage _storage;

  static String _apiKeyEntry(String siteUrl) => 'api_key::$siteUrl';

  Future<AuthKeyPair?> readKeyPair() async {
    final public = await _storage.read(key: _publicKeyEntry);
    final private = await _storage.read(key: _privateKeyEntry);
    if (public == null || private == null) return null;
    return AuthKeyPair(publicPem: public, privatePem: private);
  }

  Future<void> writeKeyPair(AuthKeyPair pair) async {
    await _storage.write(key: _publicKeyEntry, value: pair.publicPem);
    await _storage.write(key: _privateKeyEntry, value: pair.privatePem);
  }

  /// Stable per-install id, sent as `client_id` so a site can tell our
  /// installs apart and revoke one.
  Future<String> readOrCreateClientId() async {
    final existing = await _storage.read(key: _clientIdEntry);
    if (existing != null && existing.isNotEmpty) return existing;

    final created = randomToken();
    await _storage.write(key: _clientIdEntry, value: created);
    return created;
  }

  Future<String?> readApiKey(String siteUrl) =>
      _storage.read(key: _apiKeyEntry(siteUrl));

  Future<void> writeApiKey(String siteUrl, String key) =>
      _storage.write(key: _apiKeyEntry(siteUrl), value: key);

  /// Looks before deleting, because on macOS deleting nothing is not free.
  ///
  /// The plugin deletes twice, once for each synchronizable variant, and the
  /// synchronizable query needs the data protection keychain we deliberately
  /// do not use (see [_macOptions]) — so it answers `errSecMissingEntitlement`
  /// (-34018). That is harmless while the other delete succeeds, since either
  /// one succeeding is reported as success. When there is no entry to delete
  /// the other one only finds nothing, and -34018 becomes the answer.
  ///
  /// Which makes removing a site that was never connected — the one case where
  /// there is certainly no key — the case that fails. A read is exact where a
  /// delete is not, so ask first.
  Future<void> deleteApiKey(String siteUrl) async {
    if (await readApiKey(siteUrl) == null) return;
    await _storage.delete(key: _apiKeyEntry(siteUrl));
  }

  /// URL-safe random token, used for both the client id and the nonce.
  static String randomToken([int bytes = 16]) {
    final random = Random.secure();
    final values = List<int>.generate(bytes, (_) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }
}
