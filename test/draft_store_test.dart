import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/linux_preferences_store.dart';
import 'package:discourse_native/src/data/private_storage.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const siteUrl = 'https://meta.discourse.org';
  const draftKey = 'topic_42';
  const storageKey =
      'discourse_native.draft::https://meta.discourse.org::topic_42';

  late MemoryDraftPersistence persistence;
  late DraftStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    persistence = MemoryDraftPersistence();
    store = DraftStore(persistence: persistence);
  });

  group('secure persistence and write ordering', () {
    test('writes drafts to secure persistence', () async {
      await store.write(siteUrl, draftKey, '{"reply": "Half a thought"}');

      expect(persistence.values[storageKey], '{"reply": "Half a thought"}');
      expect(
        (await SharedPreferences.getInstance()).containsKey(storageKey),
        isFalse,
      );
    });

    test('reports when secure persistence cannot retain a draft', () async {
      persistence.failWrites = true;

      await expectLater(
        store.write(siteUrl, draftKey, 'unsaved text'),
        throwsA(isA<DraftWriteException>()),
      );

      expect(persistence.values, isEmpty);
    });

    test('reads drafts from secure persistence', () async {
      persistence.values[storageKey] = '{"reply": "Half a thought"}';

      expect(
        await store.read(siteUrl, draftKey),
        '{"reply": "Half a thought"}',
      );
    });

    test('reads nothing back for a draft never written', () async {
      expect(await store.read(siteUrl, draftKey), isNull);
    });

    test('checked reads distinguish storage failure from no draft', () async {
      persistence.failReads = true;

      expect(await store.readChecked(siteUrl, draftKey), (
        value: null,
        succeeded: false,
      ));
    });

    test('conditional writing rejects a stale session', () async {
      await store.write(
        siteUrl,
        draftKey,
        'old account text',
        ifCurrent: () => false,
      );

      expect(await store.read(siteUrl, draftKey), isNull);
    });

    test('conditional writing rechecks after storage initialization', () async {
      var current = true;
      final write = store.write(
        siteUrl,
        draftKey,
        'old account text',
        ifCurrent: () => current,
      );
      current = false;

      await write;

      expect(persistence.values, isEmpty);
    });

    test(
      'a newer write wins when an older secure write is still running',
      () async {
        final gate = Completer<void>();
        persistence.firstWriteGate = gate;
        var oldSessionIsCurrent = true;

        final oldWrite = store.write(
          siteUrl,
          draftKey,
          'old account text',
          ifCurrent: () => oldSessionIsCurrent,
        );
        await persistence.firstWriteStarted.future;

        oldSessionIsCurrent = false;
        final newWrite = store.write(siteUrl, draftKey, 'new account text');
        await Future<void>.delayed(Duration.zero);
        expect(persistence.writeCount, 1);

        gate.complete();
        await Future.wait([oldWrite, newWrite]);

        expect(persistence.values[storageKey], 'new account text');
      },
    );
  });

  group('clearing and site isolation', () {
    test('site clearing waits for an older write before deleting it', () async {
      final gate = Completer<void>();
      persistence.firstWriteGate = gate;

      final write = store.write(siteUrl, draftKey, 'old account text');
      await persistence.firstWriteStarted.future;
      final clear = store.clearSite(siteUrl);

      gate.complete();
      await Future.wait([write, clear]);

      expect(persistence.values, isEmpty);
    });

    test('clearing removes only the one draft', () async {
      await store.write(siteUrl, draftKey, 'kept elsewhere');
      await store.write(siteUrl, 'topic_43', 'also kept');
      await store.clear(siteUrl, draftKey);

      expect(await store.read(siteUrl, draftKey), isNull);
      expect(await store.read(siteUrl, 'topic_43'), 'also kept');
    });

    test('clearing a draft that was never written is nothing', () async {
      await store.clear(siteUrl, draftKey);
      expect(await store.read(siteUrl, draftKey), isNull);
    });

    test('checked clearing reports when secure deletion fails', () async {
      await store.write(siteUrl, draftKey, 'must remain recoverable');
      persistence.deleteError = StateError('secure storage unavailable');

      expect(await store.clearChecked(siteUrl, draftKey), isFalse);
      expect(persistence.values[storageKey], 'must remain recoverable');
    });

    test('conditional clearing keeps a newer session draft', () async {
      await store.write(siteUrl, draftKey, 'newer account text');

      await store.clear(siteUrl, draftKey, ifCurrent: () => false);

      expect(await store.read(siteUrl, draftKey), 'newer account text');
    });

    test('the same draft key on two sites is two drafts', () async {
      await store.write(siteUrl, draftKey, 'first site');
      await store.write('https://other.example.com', draftKey, 'second site');

      expect(await store.read(siteUrl, draftKey), 'first site');
      expect(
        await store.read('https://other.example.com', draftKey),
        'second site',
      );
    });

    test('clearing a site removes all of its drafts and no others', () async {
      await store.write(siteUrl, draftKey, 'first');
      await store.write(siteUrl, 'topic_43', 'second');
      await store.write('https://other.example.com', draftKey, 'other site');

      await store.clearSite(siteUrl);

      expect(await store.read(siteUrl, draftKey), isNull);
      expect(await store.read(siteUrl, 'topic_43'), isNull);
      expect(
        await store.read('https://other.example.com', draftKey),
        'other site',
      );
    });

    test(
      'site clearing fails closed when its blocker is not durable',
      () async {
        const error = FileSystemException('draft file unavailable');
        await store.write(siteUrl, draftKey, 'previous account text');
        persistence.deletePrefixError = error;

        await expectLater(store.clearSite(siteUrl), throwsA(same(error)));

        expect(persistence.values[storageKey], 'previous account text');
      },
    );

    test('conditional site clearing keeps a newer session draft', () async {
      await store.write(siteUrl, draftKey, 'newer account text');

      await store.clearSite(siteUrl, ifCurrent: () => false);

      expect(await store.read(siteUrl, draftKey), 'newer account text');
    });
  });

  group('Linux legacy retirement across restarts', () {
    late Directory directory;
    late File preferencesFile;

    DraftStore reopenDrafts() => DraftStore(
      persistence: PrivateDraftPersistence(
        storage: LinuxFileStorage(
          directory: Directory('${directory.path}/private'),
        ),
      ),
    );

    Future<SharedPreferences> restartPreferences() async {
      SharedPreferencesStorePlatform.instance = LinuxPreferencesStore(
        file: () => preferencesFile,
      );
      SharedPreferences.resetStatic();
      return SharedPreferences.getInstance();
    }

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'linux-draft-retirement-',
      );
      preferencesFile = File('${directory.path}/shared_preferences.json');
      store = reopenDrafts();
      await restartPreferences();
    });

    tearDown(() async {
      SharedPreferences.setMockInitialValues({});
      await directory.delete(recursive: true);
    });

    for (final throwsOnRemoval in [false, true]) {
      final failure = throwsOnRemoval ? 'throws' : 'returns false';

      test(
        'site clear survives restart when legacy removal $failure',
        () async {
          final preferences = await SharedPreferences.getInstance();
          await preferences.setString(storageKey, 'account A private text');
          const uncachedKey =
              'discourse_native.draft::https://meta.discourse.org::topic_43';
          const otherSiteKey =
              'discourse_native.draft::https://other.example.com::topic_42';
          final elsewhere = LinuxPreferencesStore(file: () => preferencesFile);
          expect(
            await elsewhere.setValue(
              'String',
              'flutter.$uncachedKey',
              'account A uncached private text',
            ),
            isTrue,
          );
          expect(
            await elsewhere.setValue(
              'String',
              'flutter.$otherSiteKey',
              'other site legacy text',
            ),
            isTrue,
          );
          final failedDisk = _FailPreferenceWrites(
            preferencesFile.path,
            throwsOnRemoval: throwsOnRemoval,
          );

          await IOOverrides.runWithIOOverrides(
            () => store.clearSite(siteUrl),
            failedDisk,
          );

          expect(failedDisk.failedWrites, greaterThan(0));
          expect(preferences.containsKey(storageKey), isFalse);
          expect(
            await preferences.setString(
              'discourse_native.instances',
              '[{"url":"https://meta.discourse.org","username":"B"}]',
            ),
            isTrue,
          );
          final reloaded = await restartPreferences();
          expect(reloaded.getString(storageKey), 'account A private text');
          expect(
            reloaded.getString(uncachedKey),
            'account A uncached private text',
          );
          store = reopenDrafts();

          expect(await store.read(siteUrl, draftKey), isNull);
          expect(await store.read(siteUrl, 'topic_43'), isNull);
          expect(
            await store.read('https://other.example.com', draftKey),
            'other site legacy text',
          );
          await store.write(siteUrl, draftKey, 'account B new text');
          expect(
            await reopenDrafts().read(siteUrl, draftKey),
            'account B new text',
          );
        },
      );

      test('key clear survives restart when legacy removal $failure', () async {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(storageKey, 'cleared private text');
        const keptKey =
            'discourse_native.draft::https://meta.discourse.org::topic_43';
        await preferences.setString(keptKey, 'kept legacy text');
        final failedDisk = _FailPreferenceWrites(
          preferencesFile.path,
          throwsOnRemoval: throwsOnRemoval,
        );

        await IOOverrides.runWithIOOverrides(
          () => store.clear(siteUrl, draftKey),
          failedDisk,
        );

        expect(failedDisk.failedWrites, greaterThan(0));
        expect(preferences.containsKey(storageKey), isFalse);
        expect(
          await preferences.setString('discourse_native.instances', '[]'),
          isTrue,
        );
        final reloaded = await restartPreferences();
        expect(reloaded.getString(storageKey), 'cleared private text');
        store = reopenDrafts();

        expect(await store.read(siteUrl, draftKey), isNull);
        expect(await store.read(siteUrl, 'topic_43'), 'kept legacy text');
        await store.write(siteUrl, draftKey, 'replacement text');
        expect(
          await reopenDrafts().read(siteUrl, draftKey),
          'replacement text',
        );
      });
    }

    test('untouched legacy drafts migrate and survive restart', () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(storageKey, 'recoverable legacy text');

      expect(await store.read(siteUrl, draftKey), 'recoverable legacy text');
      await restartPreferences();
      expect(
        await reopenDrafts().read(siteUrl, draftKey),
        'recoverable legacy text',
      );
      expect(
        (await SharedPreferences.getInstance()).containsKey(storageKey),
        isFalse,
      );
    });
  });

  group('legacy preference migration', () {
    for (final (type, legacyValue) in <(String, Object)>[
      ('int', 42),
      ('bool', true),
      ('double', 1.5),
      ('list', <String>['private draft text']),
    ]) {
      test('$type legacy drafts fail conservatively and can retry', () async {
        SharedPreferences.setMockInitialValues({storageKey: legacyValue});
        final prefs = await SharedPreferences.getInstance();

        expect(await store.readChecked(siteUrl, draftKey), (
          value: null,
          succeeded: false,
        ));
        expect(await store.read(siteUrl, draftKey), isNull);
        expect(prefs.get(storageKey), legacyValue);
        expect(persistence.values, isEmpty);
        expect(persistence.writeCount, 0);

        await prefs.setString(storageKey, 'recovered legacy text');

        expect(await store.readChecked(siteUrl, draftKey), (
          value: 'recovered legacy text',
          succeeded: true,
        ));
        expect(persistence.values[storageKey], 'recovered legacy text');
        expect(prefs.containsKey(storageKey), isFalse);
      });
    }

    test('migrates a plaintext legacy draft into secure persistence', () async {
      SharedPreferences.setMockInitialValues({storageKey: 'legacy text'});

      expect(await store.read(siteUrl, draftKey), 'legacy text');
      expect(persistence.values[storageKey], 'legacy text');
      expect(
        (await SharedPreferences.getInstance()).containsKey(storageKey),
        isFalse,
      );
    });

    test('keeps the legacy draft when secure migration fails', () async {
      SharedPreferences.setMockInitialValues({storageKey: 'legacy text'});
      persistence.failWrites = true;

      expect(await store.read(siteUrl, draftKey), 'legacy text');
      expect(
        (await SharedPreferences.getInstance()).getString(storageKey),
        'legacy text',
      );
    });

    test(
      'does not reveal or overwrite fallback data when secure read fails',
      () async {
        persistence
          ..values[storageKey] = 'new secure text'
          ..failReads = true;
        SharedPreferences.setMockInitialValues({storageKey: 'old legacy text'});

        expect(await store.read(siteUrl, draftKey), isNull);
        expect(persistence.values[storageKey], 'new secure text');
        expect(persistence.writeCount, 0);
        expect(
          (await SharedPreferences.getInstance()).getString(storageKey),
          'old legacy text',
        );
      },
    );

    test('secure persistence takes precedence over a legacy draft', () async {
      persistence.values[storageKey] = 'secure text';
      SharedPreferences.setMockInitialValues({storageKey: 'stale legacy text'});

      expect(await store.read(siteUrl, draftKey), 'secure text');
      expect(
        (await SharedPreferences.getInstance()).containsKey(storageKey),
        isFalse,
      );
    });

    test('a durable blocker suppresses a stale preference draft', () async {
      persistence.allowPreferenceFallback = false;
      SharedPreferences.setMockInitialValues({storageKey: 'stale text'});

      expect(await store.read(siteUrl, draftKey), isNull);
      expect(
        (await SharedPreferences.getInstance()).containsKey(storageKey),
        isFalse,
      );
    });

    test(
      'private values and blockers bypass malformed legacy drafts',
      () async {
        final prefs = await SharedPreferences.getInstance();
        persistence
          ..values[storageKey] = 'secure text'
          ..allowPreferenceFallback = false;
        await prefs.setInt(storageKey, 42);

        expect(await store.readChecked(siteUrl, draftKey), (
          value: 'secure text',
          succeeded: true,
        ));
        expect(prefs.containsKey(storageKey), isFalse);

        persistence.values.remove(storageKey);
        await prefs.setBool(storageKey, true);

        expect(await store.readChecked(siteUrl, draftKey), (
          value: null,
          succeeded: true,
        ));
        expect(prefs.containsKey(storageKey), isFalse);
        expect(persistence.writeCount, 0);
      },
    );
  });
}

final class MemoryDraftPersistence implements DraftPersistence {
  final Map<String, String> values = {};
  bool failReads = false;
  bool failWrites = false;
  bool allowPreferenceFallback = true;
  Object? deleteError;
  Object? deletePrefixError;
  Completer<void>? firstWriteGate;
  final Completer<void> firstWriteStarted = Completer<void>();
  int writeCount = 0;

  @override
  Future<void> delete(String key) async {
    if (deleteError case final error?) throw error;
    values.remove(key);
  }

  @override
  Future<DraftPersistenceRead> read(String key) async {
    if (failReads) throw StateError('secure storage unavailable');
    return (
      value: values[key],
      allowPreferenceFallback: allowPreferenceFallback,
    );
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    if (deletePrefixError case final error?) throw error;
    values.removeWhere((key, _) => key.startsWith(prefix));
  }

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    final gate = firstWriteGate;
    if (writeCount == 1 && gate != null) {
      firstWriteStarted.complete();
      await gate.future;
    }
    if (failWrites) throw StateError('secure storage unavailable');
    values[key] = value;
  }
}

final class _FailPreferenceWrites extends IOOverrides {
  _FailPreferenceWrites(this.document, {required this.throwsOnRemoval});

  final String document;
  final bool throwsOnRemoval;
  int failedWrites = 0;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path.startsWith('$document.') &&
            path.endsWith('.private-document.tmp')
        ? _FailedPreferenceStage(file, this)
        : file;
  }
}

final class _FailedPreferenceStage extends Fake implements File {
  _FailedPreferenceStage(this.file, this.failure);

  final File file;
  final _FailPreferenceWrites failure;

  @override
  String get path => file.path;

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await file.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  Future<bool> exists() => file.exists();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    failure.failedWrites++;
    if (failure.throwsOnRemoval) throw StateError('legacy cleanup unavailable');
    throw FileSystemException('legacy cleanup unavailable', path);
  }
}
