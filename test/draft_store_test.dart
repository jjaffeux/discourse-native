import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test(
    'diagnostics never retain a storage parser source or draft text',
    () async {
      const secretDraft = 'private draft body sentinel';
      final diagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'draft-privacy',
      );
      final binding = DiagnosticsSink.install(diagnostics);
      addTearDown(() async {
        binding.close();
        await diagnostics.close();
      });
      final privateStore = DraftStore(
        persistence: const _ThrowingDraftPersistence(
          FormatException('secure write failed', secretDraft, 1),
        ),
      );

      await expectLater(
        privateStore.write(siteUrl, draftKey, secretDraft),
        throwsA(
          isA<DraftWriteException>().having(
            (error) => '$error',
            'toString',
            isNot(contains(secretDraft)),
          ),
        ),
      );

      final report = diagnostics.buildJsonReport();
      expect(report, contains('secure write failed'));
      expect(report, isNot(contains(secretDraft)));
    },
  );

  test('reads drafts from secure persistence', () async {
    persistence.values[storageKey] = '{"reply": "Half a thought"}';

    expect(await store.read(siteUrl, draftKey), '{"reply": "Half a thought"}');
  });

  test('reads nothing back for a draft never written', () async {
    expect(await store.read(siteUrl, draftKey), isNull);
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

  test('site clearing fails closed when its blocker is not durable', () async {
    const error = FileSystemException('draft file unavailable');
    await store.write(siteUrl, draftKey, 'previous account text');
    persistence.deletePrefixError = error;

    await expectLater(store.clearSite(siteUrl), throwsA(same(error)));

    expect(persistence.values[storageKey], 'previous account text');
  });

  test('conditional site clearing keeps a newer session draft', () async {
    await store.write(siteUrl, draftKey, 'newer account text');

    await store.clearSite(siteUrl, ifCurrent: () => false);

    expect(await store.read(siteUrl, draftKey), 'newer account text');
  });

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
}

final class MemoryDraftPersistence implements DraftPersistence {
  final Map<String, String> values = {};
  bool failReads = false;
  bool failWrites = false;
  bool allowPreferenceFallback = true;
  Object? deletePrefixError;
  Completer<void>? firstWriteGate;
  final Completer<void> firstWriteStarted = Completer<void>();
  int writeCount = 0;

  @override
  Future<void> delete(String key) async {
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

final class _ThrowingDraftPersistence implements DraftPersistence {
  const _ThrowingDraftPersistence(this.error);

  final Object error;

  @override
  Future<void> delete(String key) async {}

  @override
  Future<void> deletePrefix(String prefix) async {}

  @override
  Future<DraftPersistenceRead> read(String key) async =>
      (value: null, allowPreferenceFallback: true);

  @override
  Future<void> write(String key, String value) async => throw error;
}
