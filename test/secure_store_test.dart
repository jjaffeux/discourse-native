import 'dart:async';

import 'package:discourse_native/src/data/private_storage.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('client ID', () {
    test('reuses the persisted ID without generating a replacement', () async {
      var generations = 0;
      final storage = _FakeStorage();
      final clientIds = _FakeClientIds('persisted');
      final store = SecureStore(
        storage: storage,
        clientIds: clientIds,
        tokenGenerator: () {
          generations += 1;
          return 'replacement';
        },
      );

      expect(await store.readOrCreateClientId(), 'persisted');
      expect(await store.readOrCreateClientId(), 'persisted');
      expect(generations, 0);
      expect(clientIds.events, ['read']);
      expect(storage.events, isEmpty);
    });

    test('copies the old private-storage ID to preferences once', () async {
      final storage = _FakeStorage({'client_id': 'legacy-id'});
      final clientIds = _FakeClientIds();
      final store = SecureStore(
        storage: storage,
        clientIds: clientIds,
        tokenGenerator: () => throw StateError('must not generate'),
      );

      expect(await store.readOrCreateClientId(), 'legacy-id');
      expect(clientIds.value, 'legacy-id');
      expect(storage.values['client_id'], 'legacy-id');
      expect(storage.events, ['read:client_id']);
    });

    test('creates a missing ID in preferences', () async {
      final storage = _FakeStorage();
      final clientIds = _FakeClientIds();
      final store = SecureStore(
        storage: storage,
        clientIds: clientIds,
        tokenGenerator: () => 'generated-id',
      );

      expect(await store.readOrCreateClientId(), 'generated-id');
      expect(clientIds.value, 'generated-id');
      expect(storage.events, ['read:client_id']);
      expect(clientIds.events, ['read', 'write']);
    });

    test('coalesces simultaneous creation requests', () async {
      final readGate = Completer<void>();
      final readStarted = Completer<void>();
      final storage = _FakeStorage();
      final clientIds = _FakeClientIds()
        ..readGate = readGate
        ..readStarted = readStarted;
      var generations = 0;
      final store = SecureStore(
        storage: storage,
        clientIds: clientIds,
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
      expect(clientIds.events, ['read', 'write']);
    });

    test('replacement stores share one client ID creation cycle', () async {
      final readGate = Completer<void>();
      final readStarted = Completer<void>();
      final clientIds = _FakeClientIds()
        ..snapshotGatedRead = true
        ..readGate = readGate
        ..readStarted = readStarted;
      final generations = <String>[];
      final firstStore = SecureStore(
        storage: _FakeStorage(),
        clientIds: clientIds,
        tokenGenerator: () {
          generations.add('first-generated');
          return 'first-generated';
        },
      );
      final replacementStore = SecureStore(
        storage: _FakeStorage(),
        clientIds: clientIds,
        tokenGenerator: () {
          generations.add('replacement-generated');
          return 'replacement-generated';
        },
      );

      final first = firstStore.readOrCreateClientId();
      await readStarted.future;
      final replacement = replacementStore.readOrCreateClientId();
      await Future<void>.delayed(Duration.zero);

      expect(clientIds.events, ['read']);
      readGate.complete();

      expect(await Future.wait([first, replacement]), [
        'first-generated',
        'first-generated',
      ]);
      expect(generations, ['first-generated']);
      expect(clientIds.events, ['read', 'write', 'read']);

      final reopened = SecureStore(
        storage: _FakeStorage(),
        clientIds: clientIds,
        tokenGenerator: () => throw StateError('must not regenerate'),
      );
      expect(await reopened.readOrCreateClientId(), 'first-generated');
      expect(clientIds.events, ['read', 'write', 'read', 'read']);
    });

    test('different client ID persistence owners remain independent', () async {
      final firstReadGate = Completer<void>();
      final firstReadStarted = Completer<void>();
      final firstClientIds = _FakeClientIds()
        ..readGate = firstReadGate
        ..readStarted = firstReadStarted;
      final secondClientIds = _FakeClientIds('second-persisted');
      final firstStore = SecureStore(
        storage: _FakeStorage(),
        clientIds: firstClientIds,
        tokenGenerator: () => 'first-generated',
      );
      final secondStore = SecureStore(
        storage: _FakeStorage(),
        clientIds: secondClientIds,
        tokenGenerator: () => throw StateError('must not regenerate'),
      );

      final first = firstStore.readOrCreateClientId();
      await firstReadStarted.future;

      expect(await secondStore.readOrCreateClientId(), 'second-persisted');
      expect(secondClientIds.events, ['read']);

      firstReadGate.complete();
      expect(await first, 'first-generated');
    });

    test('retries after a failed creation', () async {
      final error = StateError('preferences unavailable');
      final storage = _FakeStorage();
      final clientIds = _FakeClientIds()..writeError = error;
      final store = SecureStore(
        storage: storage,
        clientIds: clientIds,
        tokenGenerator: () => 'generated-id',
      );

      await expectLater(store.readOrCreateClientId(), throwsA(same(error)));
      clientIds.writeError = null;

      expect(await store.readOrCreateClientId(), 'generated-id');
      expect(clientIds.events, ['read', 'write', 'read', 'write']);
    });
  });

  group('API key storage', () {
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

    test('a replacement store invalidates another store cached key', () async {
      const siteUrl = 'https://meta.discourse.org';
      final storage = _FakeStorage({'api_key::$siteUrl': 'old-key'});
      final firstStore = SecureStore(storage: storage);
      final replacementStore = SecureStore(storage: storage);

      expect(await firstStore.readApiKey(siteUrl), 'old-key');
      await replacementStore.deleteApiKey(siteUrl);

      expect(await firstStore.readApiKey(siteUrl), isNull);
      expect(storage.events, [
        'read:api_key::$siteUrl',
        'delete:api_key::$siteUrl',
      ]);
    });

    test('a replacement store replaces another store cached miss', () async {
      const siteUrl = 'https://meta.discourse.org';
      final storage = _FakeStorage();
      final firstStore = SecureStore(storage: storage);
      final replacementStore = SecureStore(storage: storage);

      expect(await firstStore.readApiKey(siteUrl), isNull);
      await replacementStore.writeApiKey(siteUrl, 'new-key');

      expect(await firstStore.readApiKey(siteUrl), 'new-key');
      expect(storage.events, [
        'read:api_key::$siteUrl',
        'write:api_key::$siteUrl',
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

    test('an in-flight stale read resolves to a completed deletion', () async {
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
      final coalescedRead = store.readApiKey(siteUrl);
      await store.deleteApiKey(siteUrl);
      gate.complete();

      expect(await staleRead, isNull);
      expect(await coalescedRead, isNull);
      expect(await store.readApiKey(siteUrl), isNull);
    });

    test('a delete queued behind a write wins', () async {
      const siteUrl = 'https://meta.discourse.org';
      final gate = Completer<void>();
      final started = Completer<void>();
      final storage = _FakeStorage()
        ..gatedWriteKey = 'api_key::$siteUrl'
        ..writeGate = gate
        ..writeStarted = started;
      final store = SecureStore(storage: storage);

      final write = store.writeApiKey(siteUrl, 'new-key');
      await started.future;
      final deletion = store.deleteApiKey(siteUrl);
      gate.complete();
      await Future.wait([write, deletion]);

      expect(storage.values.containsKey('api_key::$siteUrl'), isFalse);
      expect(await store.readApiKey(siteUrl), isNull);
    });

    test('a write queued behind a delete wins', () async {
      const siteUrl = 'https://meta.discourse.org';
      final gate = Completer<void>();
      final started = Completer<void>();
      final storage = _FakeStorage({'api_key::$siteUrl': 'old-key'})
        ..gatedDeleteKey = 'api_key::$siteUrl'
        ..deleteGate = gate
        ..deleteStarted = started;
      final store = SecureStore(storage: storage);

      final deletion = store.deleteApiKey(siteUrl);
      await started.future;
      final write = store.writeApiKey(siteUrl, 'new-key');
      gate.complete();
      await Future.wait([deletion, write]);

      expect(storage.values['api_key::$siteUrl'], 'new-key');
      expect(await store.readApiKey(siteUrl), 'new-key');
    });

    test('asks storage for an idempotent deletion of a missing key', () async {
      final storage = _FakeStorage();
      final store = SecureStore(storage: storage);

      await store.deleteApiKey('https://missing.example');

      expect(storage.events, ['delete:api_key::https://missing.example']);
    });

    test('deletes an existing key without a stale preflight read', () async {
      final storage = _FakeStorage({
        'api_key::https://meta.discourse.org': 'api-key',
      });
      final store = SecureStore(storage: storage);

      await store.deleteApiKey('https://meta.discourse.org');

      expect(storage.values, isEmpty);
      expect(await store.readApiKey('https://meta.discourse.org'), isNull);
      expect(storage.events, ['delete:api_key::https://meta.discourse.org']);
    });

    test('propagates deletion failures', () async {
      final error = StateError('keychain unavailable');
      final storage = _FakeStorage()
        ..deleteErrors['api_key::https://meta.discourse.org'] = error;
      final store = SecureStore(storage: storage);

      await expectLater(
        store.deleteApiKey('https://meta.discourse.org'),
        throwsA(same(error)),
      );
      expect(storage.events, ['delete:api_key::https://meta.discourse.org']);
    });
  });
}

final class _FakeStorage implements PrivateStorage {
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
  String? gatedDeleteKey;
  Completer<void>? deleteGate;
  Completer<void>? deleteStarted;

  @override
  Future<String?> read(String key) async {
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
  Future<void> write(String key, String value) async {
    events.add('write:$key');
    if (key == gatedWriteKey) {
      if (writeStarted case final started? when !started.isCompleted) {
        started.complete();
      }
      await writeGate?.future;
    }
    if (writeErrors[key] case final error?) throw error;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    events.add('delete:$key');
    if (key == gatedDeleteKey) {
      if (deleteStarted case final started? when !started.isCompleted) {
        started.complete();
      }
      await deleteGate?.future;
    }
    if (deleteErrors[key] case final error?) throw error;
    values.remove(key);
  }
}

final class _FakeClientIds implements ClientIdPersistence {
  _FakeClientIds([this.value]);

  String? value;
  Object? writeError;
  bool snapshotGatedRead = false;
  Completer<void>? readGate;
  Completer<void>? readStarted;
  final List<String> events = [];

  @override
  Future<String?> read() async {
    events.add('read');
    final snapshot = snapshotGatedRead ? value : null;
    if (readStarted case final started? when !started.isCompleted) {
      started.complete();
    }
    await readGate?.future;
    return snapshotGatedRead ? snapshot : value;
  }

  @override
  Future<void> write(String value) async {
    events.add('write');
    if (writeError case final error?) throw error;
    this.value = value;
  }
}
