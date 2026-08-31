import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/private_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const sitePrefix = 'discourse_native.draft::https://one.example::';
  const key = '${sitePrefix}topic_42';
  const otherKey = 'discourse_native.draft::https://two.example::topic_42';

  late Directory directory;
  late File file;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp(
      'discourse-native-drafts-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    file = File('${directory.path}/drafts/drafts-v1.json');
  });

  group('file persistence and schema', () {
    test('retains drafts across reopened instances', () async {
      final storage = AppleFileDraftPersistence(file: file);
      await storage.write(key, 'unfinished thought');

      final reopened = AppleFileDraftPersistence(file: file);
      expect(await reopened.read(key), (
        value: 'unfinished thought',
        allowPreferenceFallback: false,
      ));
    });

    test('writes the stable v1 schema with sorted legacy blockers', () async {
      final storage = AppleFileDraftPersistence(
        file: file,
        legacyStorage: null,
      );
      const later = '${sitePrefix}topic_z';
      const earlier = '${sitePrefix}topic_a';

      await storage.write(later, 'later');
      await storage.write(earlier, 'earlier');

      expect(jsonDecode(await file.readAsString()), {
        'version': 1,
        'values': {later: 'later', earlier: 'earlier'},
        'blockedLegacyKeys': [earlier, later],
        'blockedLegacyPrefixes': <Object?>[],
      });
    });
  });

  group('legacy lookup and migration', () {
    test('writes a current draft without consulting the Keychain', () async {
      final legacy = _LegacyDraftStorage({key: 'old'});
      final storage = AppleFileDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );

      await storage.write(key, 'new');

      expect(legacy.values, {key: 'old'});
      expect(legacy.events, isEmpty);
    });

    test('uses a primary file hit without consulting the Keychain', () async {
      final legacy = _LegacyDraftStorage({key: 'old'});
      final storage = AppleFileDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );
      await storage.write(key, 'new');
      legacy.events.clear();

      expect(await storage.read(key), (
        value: 'new',
        allowPreferenceFallback: false,
      ));
      expect(legacy.events, isEmpty);
    });

    test('allows preference fallback when both stores miss', () async {
      final legacy = _LegacyDraftStorage();
      final storage = AppleFileDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );

      expect(await storage.read(key), (
        value: null,
        allowPreferenceFallback: true,
      ));
      expect(legacy.events, ['read:$key']);
    });

    test(
      'migrates one exact Keychain draft without enumerating storage',
      () async {
        final legacy = _LegacyDraftStorage({key: 'old'});
        final storage = AppleFileDraftPersistence(
          file: file,
          legacyStorage: legacy,
        );

        expect(await storage.read(key), (
          value: 'old',
          allowPreferenceFallback: false,
        ));
        expect(legacy.events, ['read:$key']);
        expect(legacy.values, {key: 'old'});

        legacy.events.clear();
        final reopened = AppleFileDraftPersistence(
          file: file,
          legacyStorage: legacy,
        );
        expect(await reopened.read(key), (
          value: 'old',
          allowPreferenceFallback: false,
        ));
        expect(legacy.events, isEmpty);
      },
    );

    test('retries a denied Keychain read', () async {
      final failure = StateError('legacy ACL refused');
      final legacy = _LegacyDraftStorage({key: 'old'})..readError = failure;
      final storage = AppleFileDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );

      await expectLater(storage.read(key), throwsA(same(failure)));
      legacy.readError = null;

      expect(await storage.read(key), (
        value: 'old',
        allowPreferenceFallback: false,
      ));
      expect(legacy.events, ['read:$key', 'read:$key']);
    });

    test('retries after its file write fails', () async {
      final parentBlocker = File('${directory.path}/not-a-directory');
      await parentBlocker.writeAsString('block directory creation');
      final impossibleFile = File('${parentBlocker.path}/drafts-v1.json');
      final legacy = _LegacyDraftStorage({key: 'old'});
      final storage = AppleFileDraftPersistence(
        file: impossibleFile,
        legacyStorage: legacy,
      );

      await expectLater(storage.read(key), throwsA(isA<FileSystemException>()));
      expect(legacy.values, {key: 'old'});
      expect(legacy.events, isEmpty);

      await parentBlocker.delete();
      expect(await storage.read(key), (
        value: 'old',
        allowPreferenceFallback: false,
      ));
      expect(legacy.events, ['read:$key']);
    });
  });

  group('legacy resurrection blockers', () {
    test('deletes an existing draft and blocks all legacy fallback', () async {
      final legacy = _LegacyDraftStorage({key: 'stale'});
      final storage = AppleFileDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );
      await storage.write(key, 'current');
      expect(legacy.events, isEmpty);

      await storage.delete(key);

      expect(legacy.events, isEmpty);
      expect(await storage.read(key), (
        value: null,
        allowPreferenceFallback: false,
      ));
      expect(legacy.events, isEmpty);
    });

    test('clearing a site blocks its unknown Keychain drafts only', () async {
      final legacy = _LegacyDraftStorage({key: 'stale', otherKey: 'other-old'});
      final storage = AppleFileDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );
      await storage.write(key, 'current');
      await storage.write(otherKey, 'other-current');
      legacy.events.clear();

      await storage.deletePrefix(sitePrefix);

      expect(await storage.read(key), (
        value: null,
        allowPreferenceFallback: false,
      ));
      expect(await storage.read(otherKey), (
        value: 'other-current',
        allowPreferenceFallback: false,
      ));
      expect(legacy.events, isEmpty);
    });

    test('persist a site blocker across reopened instances', () async {
      final legacy = _LegacyDraftStorage({key: 'stale'});
      await AppleFileDraftPersistence(
        file: file,
        legacyStorage: legacy,
      ).deletePrefix(sitePrefix);

      final reopened = AppleFileDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );

      expect(await reopened.read(key), (
        value: null,
        allowPreferenceFallback: false,
      ));
      expect(legacy.events, isEmpty);
    });
  });

  group('corrupt file handling', () {
    test('preserves the corrupt file when a write fails', () async {
      await file.parent.create(recursive: true);
      await file.writeAsString('not json');
      final storage = AppleFileDraftPersistence(file: file);

      await expectLater(
        storage.write(key, 'new'),
        throwsA(isA<FormatException>()),
      );

      expect(await file.readAsString(), 'not json');
    });

    test('fails closed instead of exposing a stale preference draft', () async {
      await file.parent.create(recursive: true);
      await file.writeAsString('not json');
      SharedPreferences.setMockInitialValues({key: 'previous account text'});
      final store = DraftStore(
        persistence: AppleFileDraftPersistence(file: file),
      );

      expect(await store.read('https://one.example', 'topic_42'), isNull);
      expect(
        (await SharedPreferences.getInstance()).getString(key),
        'previous account text',
      );
    });
  });

  group('concurrent mutations', () {
    test('lets a deletion win over a delayed Keychain read', () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final started = Completer<void>();
      final legacy = _LegacyDraftStorage({key: 'old'})
        ..readGate = gate
        ..readStarted = started;
      final storage = AppleFileDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );

      final migration = storage.read(key);
      await started.future;
      await storage.delete(key);
      gate.complete();

      expect(await migration, (value: null, allowPreferenceFallback: false));
      expect(await storage.read(key), (
        value: null,
        allowPreferenceFallback: false,
      ));
      expect(legacy.events, ['read:$key']);
    });
  });
}

final class _LegacyDraftStorage implements PrivateStorage {
  _LegacyDraftStorage([Map<String, String>? values]) : values = {...?values};

  final Map<String, String> values;
  final List<String> events = [];
  Object? readError;
  Completer<void>? readGate;
  Completer<void>? readStarted;

  @override
  Future<String?> read(String key) async {
    events.add('read:$key');
    final started = readStarted;
    if (started != null && !started.isCompleted) started.complete();
    await readGate?.future;
    if (readError case final error?) throw error;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    events.add('write:$key');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    events.add('delete:$key');
    values.remove(key);
  }
}
