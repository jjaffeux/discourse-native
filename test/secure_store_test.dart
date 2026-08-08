import 'dart:async';

import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('key pair', () {
    test('reads a complete pair', () async {
      final storage = _FakeStorage({
        'rsa_key_pair_v2': '{"public":"public","private":"private"}',
      });

      final pair = await SecureStore(storage: storage).readKeyPair();

      expect(pair, isNotNull);
      expect(pair!.publicPem, 'public');
      expect(pair.privatePem, 'private');
      expect(storage.events, [
        'read:rsa_key_pair_v2',
        'read:rsa_public_key',
        'read:rsa_private_key',
      ]);
    });

    test('migrates legacy entries into the atomic record', () async {
      final storage = _FakeStorage({
        'rsa_public_key': 'legacy-public',
        'rsa_private_key': 'legacy-private',
      });

      final pair = await SecureStore(storage: storage).readKeyPair();

      expect(pair, isNotNull);
      expect(pair!.publicPem, 'legacy-public');
      expect(pair.privatePem, 'legacy-private');
      expect(storage.values.keys, ['rsa_key_pair_v2']);
      expect(storage.events, [
        'read:rsa_key_pair_v2',
        'read:rsa_public_key',
        'read:rsa_private_key',
        'write:rsa_key_pair_v2',
        'delete:rsa_public_key',
        'delete:rsa_private_key',
      ]);
    });

    test('keeps a complete legacy pair when migration fails', () async {
      final storage = _FakeStorage({
        'rsa_public_key': 'legacy-public',
        'rsa_private_key': 'legacy-private',
      })..writeErrors['rsa_key_pair_v2'] = StateError('keychain unavailable');

      final pair = await SecureStore(storage: storage).readKeyPair();

      expect(pair?.publicPem, 'legacy-public');
      expect(pair?.privatePem, 'legacy-private');
      expect(
        storage.values.keys,
        containsAll(['rsa_public_key', 'rsa_private_key']),
      );
    });

    test('independently retries legacy cleanup after migration', () async {
      final storage = _FakeStorage({
        'rsa_public_key': 'legacy-public',
        'rsa_private_key': 'legacy-private',
      })..deleteErrors['rsa_public_key'] = StateError('keychain unavailable');
      final store = SecureStore(storage: storage);

      final migrated = await store.readKeyPair();

      expect(migrated?.publicPem, 'legacy-public');
      expect(storage.values.keys, {'rsa_public_key', 'rsa_key_pair_v2'});
      expect(storage.events, contains('delete:rsa_private_key'));

      storage.deleteErrors.clear();
      final restored = await store.readKeyPair();

      expect(restored?.privatePem, 'legacy-private');
      expect(storage.values.keys, ['rsa_key_pair_v2']);
    });

    test('treats a partial legacy pair as missing', () async {
      final storage = _FakeStorage({'rsa_public_key': 'orphaned-public'});

      expect(await SecureStore(storage: storage).readKeyPair(), isNull);
    });

    test('writes both halves as one atomic keychain value', () async {
      final storage = _FakeStorage();
      final store = SecureStore(storage: storage);

      await store.writeKeyPair(
        const AuthKeyPair(publicPem: 'public', privatePem: 'private'),
      );

      expect(storage.values['rsa_key_pair_v2'], contains('"public":"public"'));
      expect(
        storage.values['rsa_key_pair_v2'],
        contains('"private":"private"'),
      );
      expect(storage.events, ['write:rsa_key_pair_v2']);
    });

    test('propagates an atomic write failure', () async {
      final error = StateError('keychain unavailable');
      final storage = _FakeStorage()..writeErrors['rsa_key_pair_v2'] = error;
      final store = SecureStore(storage: storage);

      await expectLater(
        store.writeKeyPair(
          const AuthKeyPair(publicPem: 'public', privatePem: 'private'),
        ),
        throwsA(same(error)),
      );
      expect(storage.values, isEmpty);
      expect(storage.events, ['write:rsa_key_pair_v2']);
    });
  });

  group('client id', () {
    test('reuses the persisted id without generating a replacement', () async {
      var generations = 0;
      final storage = _FakeStorage({'client_id': 'persisted'});
      final store = SecureStore(
        storage: storage,
        tokenGenerator: () {
          generations += 1;
          return 'replacement';
        },
      );

      expect(await store.readOrCreateClientId(), 'persisted');
      expect(await store.readOrCreateClientId(), 'persisted');
      expect(generations, 0);
      expect(storage.events, ['read:client_id']);
    });

    test('replaces an empty id and persists it before returning', () async {
      final storage = _FakeStorage({'client_id': ''});
      final store = SecureStore(
        storage: storage,
        tokenGenerator: () => 'generated-id',
      );

      expect(await store.readOrCreateClientId(), 'generated-id');
      expect(storage.values['client_id'], 'generated-id');
      expect(storage.events, ['read:client_id', 'write:client_id']);
    });

    test('coalesces simultaneous creation requests', () async {
      final readGate = Completer<void>();
      final readStarted = Completer<void>();
      final storage = _FakeStorage()
        ..gatedReadKey = 'client_id'
        ..readGate = readGate
        ..readStarted = readStarted;
      var generations = 0;
      final store = SecureStore(
        storage: storage,
        tokenGenerator: () {
          generations += 1;
          return 'generated-id';
        },
      );

      final first = store.readOrCreateClientId();
      await readStarted.future;
      final second = store.readOrCreateClientId();
      readGate.complete();

      expect(await Future.wait([first, second]), [
        'generated-id',
        'generated-id',
      ]);
      expect(generations, 1);
      expect(
        storage.events.where((event) => event == 'read:client_id'),
        hasLength(1),
      );
      expect(
        storage.events.where((event) => event == 'write:client_id'),
        hasLength(1),
      );
    });

    test('retries after a failed creation', () async {
      final error = StateError('keychain unavailable');
      final storage = _FakeStorage()..writeErrors['client_id'] = error;
      final store = SecureStore(
        storage: storage,
        tokenGenerator: () => 'generated-id',
      );

      await expectLater(store.readOrCreateClientId(), throwsA(same(error)));
      storage.writeErrors.clear();

      expect(await store.readOrCreateClientId(), 'generated-id');
      expect(
        storage.events.where((event) => event == 'read:client_id'),
        hasLength(2),
      );
    });
  });

  group('API keys', () {
    test('keeps credentials isolated by site', () async {
      final storage = _FakeStorage();
      final store = SecureStore(storage: storage);

      await store.writeApiKey('https://one.example', 'one-key');
      await store.writeApiKey('https://two.example', 'two-key');

      expect(await store.readApiKey('https://one.example'), 'one-key');
      expect(await store.readApiKey('https://two.example'), 'two-key');
    });

    test('reuses a persisted key without repeated platform reads', () async {
      final storage = _FakeStorage({
        'api_key::https://meta.discourse.org': 'api-key',
      });
      final store = SecureStore(storage: storage);

      expect(await store.readApiKey('https://meta.discourse.org'), 'api-key');
      expect(await store.readApiKey('https://meta.discourse.org'), 'api-key');

      expect(storage.events, ['read:api_key::https://meta.discourse.org']);
    });

    test('coalesces simultaneous platform reads for one site', () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final storage =
          _FakeStorage({'api_key::https://meta.discourse.org': 'api-key'})
            ..gatedReadKey = 'api_key::https://meta.discourse.org'
            ..readGate = gate
            ..readStarted = started;
      final store = SecureStore(storage: storage);

      final first = store.readApiKey('https://meta.discourse.org');
      await started.future;
      final second = store.readApiKey('https://meta.discourse.org');
      gate.complete();

      expect(await Future.wait([first, second]), ['api-key', 'api-key']);
      expect(storage.events, ['read:api_key::https://meta.discourse.org']);
    });

    test('a successful write replaces the cached key', () async {
      final storage = _FakeStorage({
        'api_key::https://meta.discourse.org': 'old-key',
      });
      final store = SecureStore(storage: storage);
      expect(await store.readApiKey('https://meta.discourse.org'), 'old-key');

      await store.writeApiKey('https://meta.discourse.org', 'new-key');

      expect(await store.readApiKey('https://meta.discourse.org'), 'new-key');
      expect(storage.events, [
        'read:api_key::https://meta.discourse.org',
        'write:api_key::https://meta.discourse.org',
      ]);
    });

    test(
      'an invalidated platform read returns the newly written key',
      () async {
        const siteUrl = 'https://meta.discourse.org';
        final gate = Completer<void>();
        final started = Completer<void>();
        final storage = _FakeStorage({'api_key::$siteUrl': 'old-key'})
          ..gatedReadKey = 'api_key::$siteUrl'
          ..snapshotGatedRead = true
          ..readGate = gate
          ..readStarted = started;
        final store = SecureStore(storage: storage);

        final staleRead = store.readApiKey(siteUrl);
        await started.future;
        final coalescedStaleRead = store.readApiKey(siteUrl);
        await store.writeApiKey(siteUrl, 'new-key');
        gate.complete();

        expect(await staleRead, 'new-key');
        expect(await coalescedStaleRead, 'new-key');
        expect(await store.readApiKey(siteUrl), 'new-key');
      },
    );

    test('an obsolete read failure returns the newly written key', () async {
      const siteUrl = 'https://meta.discourse.org';
      final gate = Completer<void>();
      final started = Completer<void>();
      final storage = _FakeStorage()
        ..gatedReadKey = 'api_key::$siteUrl'
        ..readGate = gate
        ..readStarted = started
        ..readErrors['api_key::$siteUrl'] = StateError('obsolete read');
      final store = SecureStore(storage: storage);

      final staleRead = store.readApiKey(siteUrl);
      await started.future;
      final coalescedStaleRead = store.readApiKey(siteUrl);
      await store.writeApiKey(siteUrl, 'new-key');
      gate.complete();

      expect(await staleRead, 'new-key');
      expect(await coalescedStaleRead, 'new-key');
      expect(await store.readApiKey(siteUrl), 'new-key');
    });

    test('serializes writes so the last requested key wins', () async {
      const siteUrl = 'https://meta.discourse.org';
      final gate = Completer<void>();
      final started = Completer<void>();
      final storage = _FakeStorage()
        ..gatedWriteKey = 'api_key::$siteUrl'
        ..writeGate = gate
        ..writeStarted = started;
      final store = SecureStore(storage: storage);

      final first = store.writeApiKey(siteUrl, 'first-key');
      await started.future;
      final second = store.writeApiKey(siteUrl, 'second-key');
      await Future<void>.delayed(Duration.zero);

      expect(storage.events, ['write:api_key::$siteUrl']);
      gate.complete();
      await Future.wait([first, second]);

      expect(storage.values['api_key::$siteUrl'], 'second-key');
      expect(await store.readApiKey(siteUrl), 'second-key');
    });

    test('does not ask the platform to delete a missing key', () async {
      final storage = _FakeStorage();
      final store = SecureStore(storage: storage);

      await store.deleteApiKey('https://missing.example');

      expect(storage.events, ['read:api_key::https://missing.example']);
    });

    test('deletes an existing key after confirming it exists', () async {
      final storage = _FakeStorage({
        'api_key::https://meta.discourse.org': 'api-key',
      });
      final store = SecureStore(storage: storage);

      await store.deleteApiKey('https://meta.discourse.org');

      expect(storage.values, isEmpty);
      expect(storage.events, [
        'read:api_key::https://meta.discourse.org',
        'delete:api_key::https://meta.discourse.org',
      ]);
      expect(await store.readApiKey('https://meta.discourse.org'), isNull);
      expect(storage.events, [
        'read:api_key::https://meta.discourse.org',
        'delete:api_key::https://meta.discourse.org',
      ]);
    });

    test('propagates read failures without attempting deletion', () async {
      final error = StateError('keychain unavailable');
      final storage = _FakeStorage()
        ..readErrors['api_key::https://meta.discourse.org'] = error;
      final store = SecureStore(storage: storage);

      await expectLater(
        store.deleteApiKey('https://meta.discourse.org'),
        throwsA(same(error)),
      );
      expect(storage.events, ['read:api_key::https://meta.discourse.org']);
    });
  });
}

final class _FakeStorage extends FlutterSecureStorage {
  _FakeStorage([Map<String, String>? values]) : values = {...?values};

  final Map<String, String> values;
  final List<String> events = [];
  final Map<String, Object> readErrors = {};
  final Map<String, Object> writeErrors = {};
  final Map<String, Object> deleteErrors = {};

  String? gatedReadKey;
  bool snapshotGatedRead = false;
  Completer<void>? readGate;
  Completer<void>? readStarted;
  String? gatedWriteKey;
  Completer<void>? writeGate;
  Completer<void>? writeStarted;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    events.add('read:$key');
    final snapshot = snapshotGatedRead && key == gatedReadKey
        ? (present: values.containsKey(key), value: values[key])
        : null;
    if (key == gatedReadKey) {
      if (readStarted case final started? when !started.isCompleted) {
        started.complete();
      }
      await readGate?.future;
    }
    if (readErrors[key] case final error?) throw error;
    if (snapshot case (:final present, :final value)) {
      return present ? value : null;
    }
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    events.add('write:$key');
    if (key == gatedWriteKey) {
      if (writeStarted case final started? when !started.isCompleted) {
        started.complete();
      }
      await writeGate?.future;
    }
    if (writeErrors[key] case final error?) throw error;
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    events.add('delete:$key');
    if (deleteErrors[key] case final error?) throw error;
    values.remove(key);
  }
}
