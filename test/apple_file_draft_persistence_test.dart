import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/private_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
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
    test('edits one large draft and restores every untouched draft', () async {
      final original = {
        for (var index = 0; index < 50; index++)
          '${sitePrefix}topic_$index': 'é⛵' * 25000,
      };
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'values': original,
          'blockedLegacyKeys': original.keys.toList()..sort(),
          'blockedLegacyPrefixes': <String>[],
        }),
      );
      final legacy = _LegacyDraftStorage();
      final unsendable = ReceivePort();
      addTearDown(unsendable.close);
      legacy.readError = unsendable;
      final storage = ApplicationSupportDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );
      final edited = '${original[key]}a';

      final write = storage.write(key, edited);
      final read = storage.read(key);
      await write;
      expect(await read, (value: edited, allowPreferenceFallback: false));

      final persisted =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      expect(persisted['values'], {...original, key: edited});
      expect(legacy.events, isEmpty);
      final oldStamp = DateTime(2001);
      await file.setLastModified(oldStamp);
      final before = (await file.stat()).modified;
      await storage.write(key, edited);
      expect((await file.stat()).modified, before);
    });

    test(
      'preserves normalized no-op bytes and the serialized draft order',
      () async {
        const later = '${sitePrefix}topic_z';
        const earlier = '${sitePrefix}topic_a';
        const covered = '${sitePrefix}topic_missing';
        final seeded = jsonEncode({
          'version': 1,
          'values': {later: 'later', earlier: 'earlier'},
          'blockedLegacyKeys': [covered, earlier, earlier, later],
          'blockedLegacyPrefixes': [sitePrefix, sitePrefix],
        });
        await file.parent.create(recursive: true);
        await file.writeAsString(seeded);
        final storage = ApplicationSupportDraftPersistence(file: file);

        await storage.write(earlier, 'earlier');
        await storage.delete(covered);
        expect(await file.readAsString(), seeded);

        await storage.write(earlier, 'changed');
        expect(
          await file.readAsString(),
          jsonEncode({
            'version': 1,
            'values': {later: 'later', earlier: 'changed'},
            'blockedLegacyKeys': <String>[],
            'blockedLegacyPrefixes': [sitePrefix],
          }),
        );
      },
    );

    test('rereads mutations made after a preceding no-op update', () async {
      final first = ApplicationSupportDraftPersistence(file: file);
      final second = ApplicationSupportDraftPersistence(file: file);
      await first.write(key, 'original');
      await first.write(key, 'original');
      await second.write(otherKey, 'another writer');
      await second.write(key, 'latest');
      await first.write(key, 'saved after reread');

      expect(jsonDecode(await file.readAsString()), {
        'version': 1,
        'values': {key: 'saved after reread', otherKey: 'another writer'},
        'blockedLegacyKeys': [key, otherKey]..sort(),
        'blockedLegacyPrefixes': <String>[],
      });
    });

    test('retains drafts across reopened instances', () async {
      final storage = ApplicationSupportDraftPersistence(file: file);
      await storage.write(key, 'unfinished thought');

      final reopened = ApplicationSupportDraftPersistence(file: file);
      expect(await reopened.read(key), (
        value: 'unfinished thought',
        allowPreferenceFallback: false,
      ));
    });

    test('writes the stable v1 schema with sorted legacy blockers', () async {
      final storage = ApplicationSupportDraftPersistence(
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
      final storage = ApplicationSupportDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );

      await storage.write(key, 'new');

      expect(legacy.values, {key: 'old'});
      expect(legacy.events, isEmpty);
    });

    test('uses a primary file hit without consulting the Keychain', () async {
      final legacy = _LegacyDraftStorage({key: 'old'});
      final storage = ApplicationSupportDraftPersistence(
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
      final storage = ApplicationSupportDraftPersistence(
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
        final storage = ApplicationSupportDraftPersistence(
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
        final reopened = ApplicationSupportDraftPersistence(
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
      final storage = ApplicationSupportDraftPersistence(
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

    test(
      'retries migration after document access fails before reading Keychain',
      () async {
        final parentBlocker = File('${directory.path}/not-a-directory');
        await parentBlocker.writeAsString('block directory creation');
        final impossibleFile = File('${parentBlocker.path}/drafts-v1.json');
        final legacy = _LegacyDraftStorage({key: 'old'});
        final storage = ApplicationSupportDraftPersistence(
          file: impossibleFile,
          legacyStorage: legacy,
        );

        await expectLater(
          storage.read(key),
          throwsA(isA<FileSystemException>()),
        );
        expect(legacy.values, {key: 'old'});
        expect(legacy.events, isEmpty);

        await parentBlocker.delete();
        expect(await storage.read(key), (
          value: 'old',
          allowPreferenceFallback: false,
        ));
        expect(legacy.events, ['read:$key']);
      },
    );
  });

  group('legacy resurrection blockers', () {
    test('deletes an existing draft and blocks all legacy fallback', () async {
      final legacy = _LegacyDraftStorage({key: 'stale'});
      final storage = ApplicationSupportDraftPersistence(
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

    test(
      'clearing a site removes current drafts and preserves other sites',
      () async {
        final legacy = _LegacyDraftStorage({
          key: 'stale',
          otherKey: 'other-old',
        });
        final storage = ApplicationSupportDraftPersistence(
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
      },
    );

    test('persist a site blocker across reopened instances', () async {
      final legacy = _LegacyDraftStorage({key: 'stale'});
      await ApplicationSupportDraftPersistence(
        file: file,
        legacyStorage: legacy,
      ).deletePrefix(sitePrefix);

      final reopened = ApplicationSupportDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );

      expect(await reopened.read(key), (
        value: null,
        allowPreferenceFallback: false,
      ));
      expect(legacy.events, isEmpty);
    });

    test('records no key blocker which a site blocker covers', () async {
      final legacy = _LegacyDraftStorage({key: 'stale'});
      final storage = ApplicationSupportDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );
      await storage.deletePrefix(sitePrefix);

      await storage.write(key, 'current');
      await storage.delete(key);

      expect(jsonDecode(await file.readAsString()), {
        'version': 1,
        'values': <String, Object?>{},
        'blockedLegacyKeys': <Object?>[],
        'blockedLegacyPrefixes': [sitePrefix],
      });
      expect(await storage.read(key), (
        value: null,
        allowPreferenceFallback: false,
      ));
      expect(legacy.events, isEmpty);
    });

    test('drops stored key blockers a site blocker covers on write', () async {
      const coveredKey = '${sitePrefix}topic_7';
      final seeded = jsonEncode({
        'version': 1,
        'values': <String, Object?>{},
        'blockedLegacyKeys': [coveredKey, otherKey],
        'blockedLegacyPrefixes': [sitePrefix],
      });
      await file.parent.create(recursive: true);
      await file.writeAsString(seeded);
      final legacy = _LegacyDraftStorage({
        coveredKey: 'stale',
        otherKey: 'other-stale',
      });
      final storage = ApplicationSupportDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );

      await storage.delete(coveredKey);
      expect(await file.readAsString(), seeded);

      await storage.write(key, 'current');

      expect(jsonDecode(await file.readAsString()), {
        'version': 1,
        'values': {key: 'current'},
        'blockedLegacyKeys': [otherKey],
        'blockedLegacyPrefixes': [sitePrefix],
      });
      for (final blocked in [coveredKey, otherKey]) {
        expect(await storage.read(blocked), (
          value: null,
          allowPreferenceFallback: false,
        ));
      }
      expect(legacy.events, isEmpty);
    });
  });

  group('corrupt file handling', () {
    test('preserves the caller locale for background codec errors', () async {
      await file.parent.create(recursive: true);
      await file.writeAsString('[]');
      final storage = ApplicationSupportDraftPersistence(file: file);

      await Intl.withLocale('fr', () async {
        final expected = appL10n.invalidDraftStorageFormat;
        await expectLater(
          storage.write(key, 'new'),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'localized message',
              expected,
            ),
          ),
        );
      });
      expect(await file.readAsString(), '[]');
    });

    test('preserves the corrupt file when a write fails', () async {
      await file.parent.create(recursive: true);
      await file.writeAsString('not json');
      final storage = ApplicationSupportDraftPersistence(file: file);

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
        persistence: ApplicationSupportDraftPersistence(file: file),
      );

      expect(await store.read('https://one.example', 'topic_42'), isNull);
      expect(
        (await SharedPreferences.getInstance()).getString(key),
        'previous account text',
      );
    });
  });

  group('concurrent mutations', () {
    test('lets the latest save win over a delayed Keychain read', () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final started = Completer<void>();
      final legacy = _LegacyDraftStorage({key: 'old'})
        ..readGate = gate
        ..readStarted = started;
      final storage = ApplicationSupportDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );

      final migration = storage.read(key);
      await started.future;
      await storage.write(key, 'latest');
      await storage.write(key, 'latest');
      gate.complete();

      expect(await migration, (
        value: 'latest',
        allowPreferenceFallback: false,
      ));
      expect(await storage.read(key), (
        value: 'latest',
        allowPreferenceFallback: false,
      ));
      expect(legacy.events, ['read:$key']);
    });

    test('lets a deletion win over a delayed Keychain read', () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final started = Completer<void>();
      final legacy = _LegacyDraftStorage({key: 'old'})
        ..readGate = gate
        ..readStarted = started;
      final storage = ApplicationSupportDraftPersistence(
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
