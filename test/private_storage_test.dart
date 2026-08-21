import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/data/private_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late LinuxFileStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'discourse-native-storage-test-',
    );
    storage = LinuxFileStorage(directory: directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('persists values across storage instances', () async {
    await storage.write('api_key::https://one.example', 'first-key');
    await storage.write('draft::42', 'unfinished thought');

    final reopened = LinuxFileStorage(directory: directory);

    expect(await reopened.read('api_key::https://one.example'), 'first-key');
    expect(await reopened.readAll(), {
      'api_key::https://one.example': 'first-key',
      'draft::42': 'unfinished thought',
    });
  });

  test('restricts the directory and file to their owner', () async {
    await storage.write('secret', 'value');

    final file = File('${directory.path}/private-storage.json');
    final directoryMode = (await directory.stat()).mode & 0x1ff;
    final fileMode = (await file.stat()).mode & 0x1ff;

    expect(directoryMode, 0x1c0); // 0700
    expect(fileMode, 0x180); // 0600
  });

  test('serializes overlapping updates without losing values', () async {
    await Future.wait([
      storage.write('first', 'one'),
      storage.write('second', 'two'),
      storage.write('third', 'three'),
    ]);

    expect(await storage.readAll(), {
      'first': 'one',
      'second': 'two',
      'third': 'three',
    });
  });

  test('serializes complete-file updates across storage instances', () async {
    await storage.write('seed', 'kept');
    final first = LinuxFileStorage(directory: directory);
    final second = LinuxFileStorage(directory: directory);

    await Future.wait([
      first.write('first', 'one'),
      second.write('second', 'two'),
    ]);

    expect(await storage.readAll(), {
      'seed': 'kept',
      'first': 'one',
      'second': 'two',
    });
    expect(
      (await File('${directory.path}/private-storage.json.lock').stat()).mode &
          0x1ff,
      0x180,
    ); // 0600
  });

  test('deletes one value without disturbing the rest', () async {
    await storage.write('first', 'one');
    await storage.write('second', 'two');

    await storage.delete('first');

    expect(await storage.readAll(), {'second': 'two'});
  });

  test('does not overwrite a corrupt store', () async {
    final file = File('${directory.path}/private-storage.json');
    await file.writeAsString('not json');

    await expectLater(
      storage.write('secret', 'value'),
      throwsA(isA<FormatException>()),
    );
    expect(await file.readAsString(), 'not json');
  });

  group('Apple Keychain options', () {
    const channel = MethodChannel('test.discourse.native/keychain');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('uses a namespaced Data Protection service by default', () async {
      final storage = AppleKeychainStorage(channel: channel);

      await storage.read('api_key::https://one.example');

      expect(calls, hasLength(1));
      expect(calls.single.method, 'read');
      expect(calls.single.arguments, {
        'key': 'api_key::https://one.example',
        'options': {
          'accountName': 'org.discourse.native.credentials',
          'accessibility': 'unlocked',
          'synchronizable': 'false',
          'useSecureEnclave': 'false',
          'usesDataProtectionKeychain': 'true',
        },
      });
    });

    test('isolates custom-signed macOS development credentials', () async {
      final storage = AppleKeychainStorage(
        channel: channel,
        service: appleDevelopmentCredentialService,
        usesDataProtectionKeychain: false,
      );

      await storage.write('api_key::https://one.example', 'secret');

      expect(calls.map((call) => call.method), ['delete', 'write']);
      final arguments = calls.last.arguments as Map<Object?, Object?>;
      expect(
        arguments['options'],
        containsPair('accountName', appleDevelopmentCredentialService),
      );
      expect(
        arguments['options'],
        containsPair('usesDataProtectionKeychain', 'false'),
      );
    });

    test('can address one exact legacy login-keychain item', () async {
      final storage = AppleKeychainStorage(
        channel: channel,
        service: legacyAppleStorageService,
        usesDataProtectionKeychain: false,
      );

      await storage.read('api_key::https://one.example');

      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['key'], 'api_key::https://one.example');
      expect(
        arguments['options'],
        containsPair('accountName', legacyAppleStorageService),
      );
      expect(
        arguments['options'],
        containsPair('usesDataProtectionKeychain', 'false'),
      );
    });

    test('treats the legacy plugin missing-delete quirk as success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'delete') {
              throw PlatformException(
                code: 'Unexpected security result code',
                details: -34018,
              );
            }
            return null;
          });
      final storage = AppleKeychainStorage(
        channel: channel,
        service: appleDevelopmentCredentialService,
        usesDataProtectionKeychain: false,
      );

      await storage.delete('missing');

      expect(calls.map((call) => call.method), ['delete', 'read']);
    });

    test('does not retry a real legacy delete failure with a read', () async {
      final error = PlatformException(code: 'acl-refused');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'delete') throw error;
            return null;
          });
      final storage = AppleKeychainStorage(
        channel: channel,
        service: appleDevelopmentCredentialService,
        usesDataProtectionKeychain: false,
      );

      await expectLater(
        storage.delete('present'),
        throwsA(
          isA<PlatformException>().having(
            (failure) => failure.code,
            'code',
            error.code,
          ),
        ),
      );
      expect(calls.map((call) => call.method), ['delete']);
    });
  });

  test('a custom-signed macOS test process uses the isolated dev service', () {
    final storage = platformCredentialStorage as AppleKeychainStorage;

    expect(storage.service, appleDevelopmentCredentialService);
    expect(storage.usesDataProtectionKeychain, isFalse);
    expect(platformLegacyAppleStorage, isNull);
  }, skip: !Platform.isMacOS);

  group('exact-item migration', () {
    const key = 'api_key::https://one.example';
    const stateKey = 'discourse_native.migration_state::$key';

    test('a primary hit never asks legacy storage', () async {
      final events = <String>[];
      final primary = _MemoryPrivateStorage('primary', events, {key: 'new'});
      final legacy = _MemoryPrivateStorage('legacy', events, {key: 'old'});
      final storage = MigratingPrivateStorage(primary: primary, legacy: legacy);

      expect(await storage.read(key), 'new');
      expect(primary.values[stateKey], 'active');
      expect(events, [
        'primary.read:$stateKey',
        'primary.read:$key',
        'primary.write:$stateKey',
      ]);
    });

    test(
      'copies a legacy hit only after the primary write is durable',
      () async {
        final events = <String>[];
        final primary = _MemoryPrivateStorage('primary', events);
        final legacy = _MemoryPrivateStorage('legacy', events, {key: 'old'});
        final storage = MigratingPrivateStorage(
          primary: primary,
          legacy: legacy,
        );

        expect(await storage.read(key), 'old');
        expect(primary.values[key], 'old');
        expect(primary.values[stateKey], 'active');
        expect(legacy.values[key], 'old');
        expect(events, [
          'primary.read:$stateKey',
          'primary.read:$key',
          'legacy.read:$key',
          // The legacy read happens with no lock held, so what it found is
          // only a candidate: the modern namespace is asked again before the
          // copy, or a migration or disconnect from another process in that
          // window would be undone here.
          'primary.read:$stateKey',
          'primary.read:$key',
          'primary.write:$key',
          'primary.write:$stateKey',
        ]);
      },
    );

    test('a miss performs exact reads without writes or deletes', () async {
      final events = <String>[];
      final storage = MigratingPrivateStorage(
        primary: _MemoryPrivateStorage('primary', events),
        legacy: _MemoryPrivateStorage('legacy', events),
      );

      expect(await storage.read(key), isNull);
      expect(events, [
        'primary.read:$stateKey',
        'primary.read:$key',
        'legacy.read:$key',
        'primary.read:$stateKey',
        'primary.read:$key',
      ]);
    });

    test(
      'an authoritative state never resurrects a stale legacy key',
      () async {
        final events = <String>[];
        final storage = MigratingPrivateStorage(
          primary: _MemoryPrivateStorage('primary', events, {
            stateKey: 'active',
          }),
          legacy: _MemoryPrivateStorage('legacy', events, {key: 'stale'}),
        );

        expect(await storage.read(key), isNull);
        expect(events, ['primary.read:$stateKey', 'primary.read:$key']);
      },
    );

    test(
      'a failed primary write leaves the legacy credential intact',
      () async {
        final events = <String>[];
        final error = StateError('data protection keychain unavailable');
        final primary = _MemoryPrivateStorage('primary', events)
          ..writeErrors[key] = error;
        final legacy = _MemoryPrivateStorage('legacy', events, {key: 'old'});
        final storage = MigratingPrivateStorage(
          primary: primary,
          legacy: legacy,
        );

        await expectLater(storage.read(key), throwsA(same(error)));
        expect(legacy.values[key], 'old');
        expect(events, [
          'primary.read:$stateKey',
          'primary.read:$key',
          'legacy.read:$key',
          'primary.read:$stateKey',
          'primary.read:$key',
          'primary.write:$key',
        ]);
      },
    );

    test('a disconnect during the legacy read is not undone', () async {
      final events = <String>[];
      final primary = _MemoryPrivateStorage('primary', events);
      final legacy = _MemoryPrivateStorage('legacy', events, {key: 'old'})
        ..gatedReadKey = key
        ..readGate = Completer<void>()
        ..readStarted = Completer<void>();
      final storage = MigratingPrivateStorage(primary: primary, legacy: legacy);

      final pending = storage.read(key);
      await legacy.readStarted!.future;

      // The lock is not held across the legacy read — that read can put an ACL
      // dialog on screen — so another process can tombstone the key in this
      // window. Standing in for one: the migration must see the tombstone on
      // its re-check rather than copying the value it already fetched.
      primary.values[stateKey] = 'deleted';
      legacy.readGate!.complete();

      expect(await pending, isNull);
      expect(primary.values.containsKey(key), isFalse);
    });

    test('delete durably tombstones before best-effort cleanup', () async {
      final events = <String>[];
      final primary = _MemoryPrivateStorage('primary', events, {key: 'new'});
      final legacy = _MemoryPrivateStorage('legacy', events, {key: 'old'});
      final storage = MigratingPrivateStorage(primary: primary, legacy: legacy);

      await storage.delete(key);

      expect(primary.values.containsKey(key), isFalse);
      expect(primary.values[stateKey], 'deleted');
      expect(legacy.values[key], 'old');
      expect(events, ['primary.write:$stateKey', 'primary.delete:$key']);
      events.clear();
      expect(await storage.read(key), isNull);
      expect(events, ['primary.read:$stateKey']);
    });

    test('a primary cleanup refusal still leaves the key inactive', () async {
      final events = <String>[];
      final error = StateError('temporary primary cleanup failure');
      final primary = _MemoryPrivateStorage('primary', events, {key: 'new'});
      primary.deleteErrors[key] = error;
      final legacy = _MemoryPrivateStorage('legacy', events, {key: 'old'});
      final storage = MigratingPrivateStorage(primary: primary, legacy: legacy);

      await storage.delete(key);

      expect(primary.values[key], 'new');
      expect(primary.values[stateKey], 'deleted');
      expect(legacy.values[key], 'old');
      expect(await storage.read(key), isNull);
    });

    test('a failed tombstone cannot report a false deletion', () async {
      final events = <String>[];
      final error = StateError('data protection write failed');
      final primary = _MemoryPrivateStorage('primary', events, {key: 'new'})
        ..writeErrors[stateKey] = error;
      final storage = MigratingPrivateStorage(
        primary: primary,
        legacy: _MemoryPrivateStorage('legacy', events),
      );

      await expectLater(storage.delete(key), throwsA(same(error)));

      expect(primary.values[key], 'new');
      primary.writeErrors.remove(stateKey);
      expect(await storage.read(key), 'new');
    });

    test('a later write replaces a deletion tombstone', () async {
      final events = <String>[];
      final primary = _MemoryPrivateStorage('primary', events, {
        stateKey: 'deleted',
      });
      final legacy = _MemoryPrivateStorage('legacy', events, {key: 'old'});
      final storage = MigratingPrivateStorage(primary: primary, legacy: legacy);

      await storage.write(key, 'new');

      expect(primary.values[key], 'new');
      expect(primary.values[stateKey], 'active');
      expect(await storage.read(key), 'new');
      expect(events.where((event) => event == 'legacy.read:$key'), isEmpty);
    });

    test('a write queued behind migration wins', () async {
      final events = <String>[];
      final gate = Completer<void>();
      final started = Completer<void>();
      final primary = _MemoryPrivateStorage('primary', events);
      final legacy = _MemoryPrivateStorage('legacy', events, {key: 'old'})
        ..gatedReadKey = key
        ..readGate = gate
        ..readStarted = started;
      final storage = MigratingPrivateStorage(primary: primary, legacy: legacy);

      final migration = storage.read(key);
      await started.future;
      final replacement = storage.write(key, 'new');
      gate.complete();
      await Future.wait([migration, replacement]);

      expect(primary.values[key], 'new');
      expect(primary.values[stateKey], 'active');
      expect(legacy.values[key], 'old');
    });

    test('a delete queued behind migration cannot resurrect the key', () async {
      final events = <String>[];
      final gate = Completer<void>();
      final started = Completer<void>();
      final primary = _MemoryPrivateStorage('primary', events);
      final legacy = _MemoryPrivateStorage('legacy', events, {key: 'old'})
        ..gatedReadKey = key
        ..readGate = gate
        ..readStarted = started;
      final storage = MigratingPrivateStorage(primary: primary, legacy: legacy);

      final migration = storage.read(key);
      await started.future;
      final deletion = storage.delete(key);
      gate.complete();
      await migration;
      await deletion;

      expect(primary.values.containsKey(key), isFalse);
      expect(primary.values[stateKey], 'deleted');
      expect(legacy.values[key], 'old');
    });

    test('an advisory lock serializes independent migrators', () async {
      final events = <String>[];
      final gate = Completer<void>();
      final started = Completer<void>();
      final primary = _MemoryPrivateStorage('primary', events);
      final legacy = _MemoryPrivateStorage('legacy', events, {key: 'old'})
        ..gatedReadKey = key
        ..readGate = gate
        ..readStarted = started;
      final lock = File('${directory.path}/credential-migration.lock');
      Future<File> lockFile() async => lock;
      final first = MigratingPrivateStorage(
        primary: primary,
        legacy: legacy,
        lockFile: lockFile,
      );
      final second = MigratingPrivateStorage(
        primary: primary,
        legacy: legacy,
        lockFile: lockFile,
      );

      final migration = first.read(key);
      await started.future;
      final deletion = second.delete(key);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(events, isNot(contains('primary.write:$stateKey')));
      gate.complete();
      await migration;
      await deletion;

      expect(primary.values[stateKey], 'deleted');
      expect(primary.values.containsKey(key), isFalse);
      expect((await lock.stat()).mode & 0x1ff, 0x180); // 0600
    });

    test('a failed operation does not poison a later repair', () async {
      final events = <String>[];
      final primary = _MemoryPrivateStorage('primary', events)
        ..readErrors[key] = StateError('temporary failure');
      final storage = MigratingPrivateStorage(
        primary: primary,
        legacy: _MemoryPrivateStorage('legacy', events),
      );

      await expectLater(storage.read(key), throwsStateError);
      primary.readErrors.remove(key);
      await storage.write(key, 'repaired');

      expect(primary.values[key], 'repaired');
    });
  });
}

final class _MemoryPrivateStorage implements PrivateStorage {
  _MemoryPrivateStorage(this.name, this.events, [Map<String, String>? values])
    : values = {...?values};

  final String name;
  final List<String> events;
  final Map<String, String> values;
  final Map<String, Object> readErrors = {};
  final Map<String, Object> writeErrors = {};
  final Map<String, Object> deleteErrors = {};

  String? gatedReadKey;
  Completer<void>? readGate;
  Completer<void>? readStarted;

  @override
  Future<String?> read(String key) async {
    events.add('$name.read:$key');
    if (key == gatedReadKey) {
      final started = readStarted;
      if (started != null && !started.isCompleted) started.complete();
      await readGate?.future;
    }
    if (readErrors[key] case final error?) throw error;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    events.add('$name.write:$key');
    if (writeErrors[key] case final error?) throw error;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    events.add('$name.delete:$key');
    if (deleteErrors[key] case final error?) throw error;
    values.remove(key);
  }
}
