import 'dart:async';

import 'package:discourse_native/src/data/private_storage.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Fault injection at shared_preferences' platform boundary is test-only.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  group('client ID preferences', () {
    const key = 'discourse_native.client_id';
    const apiKeyEntry = 'api_key::https://meta.discourse.org';

    for (final (type, malformed) in <(String, Object)>[
      ('bool', true),
      ('int', 42),
      ('double', 1.5),
      ('list', <String>['malformed-id']),
    ]) {
      test('repairs $type preferences with the legacy ID', () async {
        SharedPreferences.setMockInitialValues({
          key: malformed,
          'unrelated': 'kept',
        });
        final preferences = await SharedPreferences.getInstance();
        final storage = _FakeStorage({
          'client_id': 'legacy-id',
          apiKeyEntry: 'api-key',
        });
        final store = SecureStore(
          storage: storage,
          tokenGenerator: () => throw StateError('must not generate'),
        );

        expect(preferences.get(key), malformed);
        expect(await store.readOrCreateClientId(), 'legacy-id');
        expect(await store.readOrCreateClientId(), 'legacy-id');
        await preferences.reload();

        expect(preferences.getString(key), 'legacy-id');
        expect(preferences.getString('unrelated'), 'kept');
        expect(storage.values, {
          'client_id': 'legacy-id',
          apiKeyEntry: 'api-key',
        });
        expect(storage.events, ['read:client_id']);
      });

      test('repairs $type preferences with one generated ID', () async {
        SharedPreferences.setMockInitialValues({key: malformed});
        final preferences = await SharedPreferences.getInstance();
        final storage = _FakeStorage({apiKeyEntry: 'api-key'});
        var generations = 0;
        String generate() => 'generated-${++generations}';
        final store = SecureStore(storage: storage, tokenGenerator: generate);
        final replacement = SecureStore(
          storage: storage,
          tokenGenerator: generate,
        );

        expect(preferences.get(key), malformed);
        expect(
          await Future.wait([
            store.readOrCreateClientId(),
            store.readOrCreateClientId(),
            replacement.readOrCreateClientId(),
          ]),
          ['generated-1', 'generated-1', 'generated-1'],
        );
        await preferences.reload();

        expect(preferences.getString(key), 'generated-1');
        final reopened = SecureStore(
          storage: storage,
          tokenGenerator: () => throw StateError('must not regenerate'),
        );
        expect(await reopened.readOrCreateClientId(), 'generated-1');
        expect(generations, 1);
        expect(storage.values, {apiKeyEntry: 'api-key'});
        expect(storage.events, ['read:client_id']);
      });
    }

    test('reuses a valid preference before reading legacy storage', () async {
      SharedPreferences.setMockInitialValues({key: 'persisted-id'});
      final storage = _FakeStorage({'client_id': 'legacy-id'});
      final store = SecureStore(
        storage: storage,
        tokenGenerator: () => throw StateError('must not generate'),
      );

      expect(await store.readOrCreateClientId(), 'persisted-id');
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      expect(preferences.getString(key), 'persisted-id');
      expect(storage.values, {'client_id': 'legacy-id'});
      expect(storage.events, isEmpty);
    });

    test('replaces an empty preference with the legacy ID', () async {
      SharedPreferences.setMockInitialValues({key: ''});
      final store = SecureStore(
        storage: _FakeStorage({'client_id': 'legacy-id'}),
        tokenGenerator: () => throw StateError('must not generate'),
      );

      expect(await store.readOrCreateClientId(), 'legacy-id');
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      expect(preferences.getString(key), 'legacy-id');
    });

    test('propagates preference read failures and retries', () async {
      final error = StateError('preferences unavailable');
      final preferences = _ControlledPreferences({'flutter.$key': 'persisted'})
        ..readError = error;
      SharedPreferencesStorePlatform.instance = preferences;
      final storage = _FakeStorage({'client_id': 'legacy-id'});
      var generations = 0;
      final store = SecureStore(
        storage: storage,
        tokenGenerator: () => 'generated-${++generations}',
      );

      await expectLater(store.readOrCreateClientId(), throwsA(same(error)));
      await expectLater(store.readOrCreateClientId(), throwsA(same(error)));

      expect(storage.events, isEmpty);
      expect(generations, 0);
      expect(preferences.writes, 0);
      preferences.readError = null;

      expect(await store.readOrCreateClientId(), 'persisted');
      expect(storage.events, isEmpty);
      expect(generations, 0);
      expect(preferences.writes, 0);
    });

    test(
      'preserves a malformed preference when the legacy read fails',
      () async {
        SharedPreferences.setMockInitialValues({key: true});
        final error = StateError('legacy storage unavailable');
        final storage = _FakeStorage({'client_id': 'legacy-id'})
          ..readErrors['client_id'] = error;
        final store = SecureStore(
          storage: storage,
          tokenGenerator: () => throw StateError('must not generate'),
        );

        await expectLater(store.readOrCreateClientId(), throwsA(same(error)));
        final preferences = await SharedPreferences.getInstance();
        await preferences.reload();
        expect(preferences.get(key), true);
        storage.readErrors.clear();

        expect(await store.readOrCreateClientId(), 'legacy-id');
        await preferences.reload();
        expect(preferences.getString(key), 'legacy-id');
      },
    );

    for (final throwsError in [false, true]) {
      test('propagates repair write failures (throws: $throwsError)', () async {
        final error = StateError('preferences unavailable');
        final preferences = _ControlledPreferences({'flutter.$key': true})
          ..writeError = throwsError ? error : null
          ..acceptWrites = false;
        SharedPreferencesStorePlatform.instance = preferences;
        final store = SecureStore(
          storage: _FakeStorage({'client_id': 'legacy-id'}),
          tokenGenerator: () => throw StateError('must not generate'),
        );

        await expectLater(
          store.readOrCreateClientId(),
          throwsError ? throwsA(same(error)) : throwsStateError,
        );
        expect((await preferences.getAll())['flutter.$key'], true);

        // Reload the platform value after SharedPreferences' optimistic write.
        await (await SharedPreferences.getInstance()).reload();
        preferences
          ..writeError = null
          ..acceptWrites = true;

        expect(await store.readOrCreateClientId(), 'legacy-id');
        expect((await preferences.getAll())['flutter.$key'], 'legacy-id');
        expect(preferences.writes, 2);
      });
    }

    test(
      'waits for the repair write before returning or caching the ID',
      () async {
        final writeGate = Completer<void>();
        final writeStarted = Completer<void>();
        addTearDown(() {
          if (!writeGate.isCompleted) writeGate.complete();
        });
        final preferences = _ControlledPreferences({'flutter.$key': true})
          ..writeGate = writeGate
          ..writeStarted = writeStarted;
        SharedPreferencesStorePlatform.instance = preferences;
        var generations = 0;
        String generate() => 'generated-${++generations}';
        final storage = _FakeStorage();
        final store = SecureStore(storage: storage, tokenGenerator: generate);
        final replacement = SecureStore(
          storage: storage,
          tokenGenerator: generate,
        );
        final returned = <String>[];

        Future<void> read(SecureStore target) async {
          returned.add(await target.readOrCreateClientId());
        }

        final first = read(store);
        await writeStarted.future;
        final repeated = read(store);
        final replaced = read(replacement);
        await Future<void>.delayed(Duration.zero);

        expect(returned, isEmpty);
        expect((await preferences.getAll())['flutter.$key'], true);
        expect(generations, 1);
        writeGate.complete();
        await Future.wait([first, repeated, replaced]);

        expect(returned, ['generated-1', 'generated-1', 'generated-1']);
        expect((await preferences.getAll())['flutter.$key'], 'generated-1');
        expect(generations, 1);
        expect(preferences.writes, 1);
      },
    );
  });

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

    test('a read joining a failed write answers from storage', () async {
      const siteUrl = 'https://meta.discourse.org';
      final gate = Completer<void>();
      final started = Completer<void>();
      final storage = _FakeStorage()
        ..values['api_key::$siteUrl'] = 'stored-key'
        ..gatedWriteKey = 'api_key::$siteUrl'
        ..writeGate = gate
        ..writeStarted = started
        ..writeErrors['api_key::$siteUrl'] = StateError('keychain refused');
      final store = SecureStore(storage: storage);

      final write = store.writeApiKey(siteUrl, 'new-key');
      await started.future;
      final read = store.readApiKey(siteUrl);
      gate.complete();

      await expectLater(write, throwsStateError);
      expect(await read, 'stored-key');
      expect(await store.readApiKey(siteUrl), 'stored-key');
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

final class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences(super.data) : super.withData();

  Object? readError;
  Object? writeError;
  bool acceptWrites = true;
  Completer<void>? writeGate;
  Completer<void>? writeStarted;
  int writes = 0;

  @override
  Future<Map<String, Object>> getAll() async {
    if (readError case final error?) throw error;
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes += 1;
    if (writeStarted case final started? when !started.isCompleted) {
      started.complete();
    }
    await writeGate?.future;
    if (writeError case final error?) throw error;
    if (!acceptWrites) return false;
    return super.setValue(valueType, key, value);
  }
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
