import 'dart:async';
import 'dart:io';
import 'dart:isolate';

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
    file = File('${directory.path}/drafts/drafts-v1.json');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'persists drafts across instances with owner-only permissions',
    () async {
      final storage = AppleFileDraftPersistence(file: file);
      await storage.write(key, 'unfinished thought');

      final reopened = AppleFileDraftPersistence(file: file);
      expect((await reopened.read(key)).value, 'unfinished thought');
      expect((await file.parent.stat()).mode & 0x1ff, 0x1c0); // 0700
      expect((await file.stat()).mode & 0x1ff, 0x180); // 0600
    },
  );

  test('serializes overlapping writes without losing drafts', () async {
    final storage = AppleFileDraftPersistence(file: file);

    await Future.wait([
      storage.write(key, 'first'),
      storage.write('${sitePrefix}topic_43', 'second'),
      storage.write(otherKey, 'other'),
    ]);

    expect((await storage.read(key)).value, 'first');
    expect((await storage.read('${sitePrefix}topic_43')).value, 'second');
    expect((await storage.read(otherKey)).value, 'other');
  });

  test('serializes complete-file writes across storage instances', () async {
    final first = AppleFileDraftPersistence(file: file);
    final second = AppleFileDraftPersistence(file: file);

    await Future.wait([
      first.write(key, 'first'),
      second.write(otherKey, 'second'),
    ]);

    final reopened = AppleFileDraftPersistence(file: file);
    expect((await reopened.read(key)).value, 'first');
    expect((await reopened.read(otherKey)).value, 'second');
  });

  test('the sidecar lock coordinates independent isolates', () async {
    final path = file.path;

    await Future.wait([
      Isolate.run(() => _writeDraftSeries(path, 'first')),
      Isolate.run(() => _writeDraftSeries(path, 'second')),
    ]);

    final reopened = AppleFileDraftPersistence(file: file);
    for (final series in ['first', 'second']) {
      for (var index = 0; index < 12; index++) {
        expect(
          (await reopened.read('$sitePrefix$series-$index')).value,
          '$series value $index',
        );
      }
    }
    expect(
      (await File('${file.path}.lock').stat()).mode & 0x1ff,
      0x180,
    ); // 0600
  });

  test('a primary file hit never asks the legacy Keychain', () async {
    final legacy = _LegacyDraftStorage({key: 'old'});
    final storage = AppleFileDraftPersistence(
      file: file,
      legacyStorage: legacy,
    );
    await storage.write(key, 'new');
    legacy.events.clear();

    expect((await storage.read(key)).value, 'new');
    expect(legacy.events, isEmpty);
  });

  test(
    'migrates one exact legacy draft and never enumerates storage',
    () async {
      final legacy = _LegacyDraftStorage({key: 'old'});
      final storage = AppleFileDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );

      expect((await storage.read(key)).value, 'old');
      expect(legacy.events, ['read:$key']);
      expect(legacy.values[key], 'old');

      legacy.events.clear();
      final reopened = AppleFileDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );
      expect((await reopened.read(key)).value, 'old');
      expect(legacy.events, isEmpty);
    },
  );

  test('a denied legacy read does not block a later retry', () async {
    final legacy = _LegacyDraftStorage({key: 'old'})
      ..readError = StateError('legacy ACL refused');
    final storage = AppleFileDraftPersistence(
      file: file,
      legacyStorage: legacy,
    );

    await expectLater(storage.read(key), throwsStateError);
    legacy.readError = null;

    expect((await storage.read(key)).value, 'old');
    expect(legacy.events, ['read:$key', 'read:$key']);
  });

  test('a retained legacy copy is inert after durable migration', () async {
    final legacy = _LegacyDraftStorage({key: 'old'});
    final storage = AppleFileDraftPersistence(
      file: file,
      legacyStorage: legacy,
    );

    expect((await storage.read(key)).value, 'old');
    expect(legacy.values[key], 'old');

    legacy.events.clear();
    final reopened = AppleFileDraftPersistence(
      file: file,
      legacyStorage: legacy,
    );
    expect((await reopened.read(key)).value, 'old');
    expect(legacy.events, isEmpty);
  });

  test('a failed file migration leaves the legacy draft retryable', () async {
    final parentBlocker = File('${directory.path}/not-a-directory');
    await parentBlocker.writeAsString('block directory creation');
    final impossibleFile = File('${parentBlocker.path}/drafts-v1.json');
    final legacy = _LegacyDraftStorage({key: 'old'});
    final storage = AppleFileDraftPersistence(
      file: impossibleFile,
      legacyStorage: legacy,
    );

    await expectLater(storage.read(key), throwsA(isA<FileSystemException>()));
    await expectLater(storage.read(key), throwsA(isA<FileSystemException>()));

    expect(legacy.values[key], 'old');
    expect(legacy.events, isEmpty);
  });

  test('write and clear never call the legacy Keychain', () async {
    final legacy = _LegacyDraftStorage({key: 'stale'});
    final storage = AppleFileDraftPersistence(
      file: file,
      legacyStorage: legacy,
    );

    await storage.write(key, 'current');
    await storage.delete(key);

    expect(legacy.events, isEmpty);
    final read = await storage.read(key);
    expect(read.value, isNull);
    expect(read.allowPreferenceFallback, isFalse);
    expect(legacy.events, isEmpty);
  });

  test(
    'site clearing blocks unknown legacy drafts without touching others',
    () async {
      final legacy = _LegacyDraftStorage({key: 'stale', otherKey: 'other-old'});
      final storage = AppleFileDraftPersistence(
        file: file,
        legacyStorage: legacy,
      );
      await storage.write(key, 'current');
      await storage.write(otherKey, 'other-current');
      legacy.events.clear();

      await storage.deletePrefix(sitePrefix);

      final cleared = await storage.read(key);
      expect(cleared.value, isNull);
      expect(cleared.allowPreferenceFallback, isFalse);
      expect((await storage.read(otherKey)).value, 'other-current');
      expect(legacy.events, isEmpty);
    },
  );

  test('a site blocker survives reopening the file', () async {
    final legacy = _LegacyDraftStorage({key: 'stale'});
    await AppleFileDraftPersistence(
      file: file,
      legacyStorage: legacy,
    ).deletePrefix(sitePrefix);

    final reopened = AppleFileDraftPersistence(
      file: file,
      legacyStorage: legacy,
    );
    final read = await reopened.read(key);

    expect(read.value, isNull);
    expect(read.allowPreferenceFallback, isFalse);
    expect(legacy.events, isEmpty);
  });

  test('does not overwrite a corrupt draft file', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString('not json');
    final storage = AppleFileDraftPersistence(file: file);

    await expectLater(
      storage.write(key, 'new'),
      throwsA(isA<FormatException>()),
    );

    expect(await file.readAsString(), 'not json');
  });

  test('a corrupt file cannot expose a stale preference draft', () async {
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

  test('a concurrent clear wins over a delayed legacy read', () async {
    final gate = Completer<void>();
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

    final result = await migration;
    expect(result.value, isNull);
    expect(result.allowPreferenceFallback, isFalse);
    expect((await storage.read(key)).value, isNull);
  });
}

Future<void> _writeDraftSeries(String path, String series) async {
  const prefix = 'discourse_native.draft::https://one.example::';
  final storage = AppleFileDraftPersistence(file: File(path));
  for (var index = 0; index < 12; index++) {
    await storage.write('$prefix$series-$index', '$series value $index');
  }
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
