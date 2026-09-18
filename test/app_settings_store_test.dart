import 'dart:async';

import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('topic metadata choices default on and persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppSettingsStore();
    expect((await store.read()).topicListShowTags, isTrue);
    expect((await store.read()).topicListShowLastPoster, isTrue);
    expect((await store.read()).topicListShowAssignments, isTrue);
    await store.update(topicListShowTags: false);
    await store.update(topicListShowLastPoster: false);
    var restored = await AppSettingsStore().read();
    expect(restored.topicListShowTags, isFalse);
    expect(restored.topicListShowLastPoster, isFalse);
    expect(restored.topicListShowAssignments, isTrue);
    await store.update(topicListShowAssignments: false);
    restored = await AppSettingsStore().read();
    expect(restored.topicListShowTags, isFalse);
    expect(restored.topicListShowLastPoster, isFalse);
    expect(restored.topicListShowAssignments, isFalse);
    await store.update(topicListShowTags: true, topicListShowAssignments: true);
    await store.update(
      topicListShowLastPoster: true,
      topicListShowAssignments: true,
    );
    restored = await AppSettingsStore().read();
    expect(restored.topicListShowTags, isTrue);
    expect(restored.topicListShowLastPoster, isTrue);
    expect(restored.topicListShowAssignments, isTrue);
  });

  test(
    'topic list mode defaults to cards and survives a fresh store',
    () async {
      final persistence = MemoryAppSettingsPersistence(
        topicListMode: 'unknown',
      );
      final store = AppSettingsStore(persistence: persistence);
      expect((await store.read()).topicListMode, TopicListDisplayMode.card);
      await store.update(topicListMode: TopicListDisplayMode.compact);
      expect(
        (await AppSettingsStore(persistence: persistence).read()).topicListMode,
        TopicListDisplayMode.compact,
      );
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults missing and unknown enum values', () async {
    final platformStore = AppSettingsStore();

    expect(await platformStore.read(), AppSettings.defaults);

    SharedPreferences.setMockInitialValues({
      AppSettingsStore.limitContentSizeKey: 'justify',
      AppSettingsStore.textScaleKey: 'percent137',
      AppSettingsStore.themeModeKey: 'sepia',
      AppSettingsStore.topicListModeKey: 'table',
    });
    expect(await platformStore.read(), AppSettings.defaults);
  });

  test(
    'display preferences survive restart and unrelated setting changes',
    () async {
      final store = AppSettingsStore();
      await store.update(topicListLargerText: true);
      await store.update(topicListMode: TopicListDisplayMode.compact);
      final restored = await AppSettingsStore().read();
      expect(restored.topicListLargerText, isTrue);
      expect(restored.topicListMode, TopicListDisplayMode.compact);
      await store.update(topicListLargerText: false);
      final updated = await AppSettingsStore().read();
      expect(updated.topicListLargerText, isFalse);
      expect(updated.topicListMode, TopicListDisplayMode.compact);
    },
  );

  test('defines the bounded browser-like text scale', () {
    expect(AppTextScale.values.map((scale) => scale.factor), [
      0.8,
      0.9,
      1.0,
      1.1,
      1.25,
      1.5,
      1.75,
      2.0,
    ]);
    expect(AppSettings.defaults.textScale, AppTextScale.percent100);
  });

  test('round-trips the GIF animation preference', () async {
    final store = AppSettingsStore();

    await store.write(const AppSettings(disableGifAnimations: true));

    expect(
      (await SharedPreferences.getInstance()).getBool(
        AppSettingsStore.disableGifAnimationsKey,
      ),
      isTrue,
    );
    expect(await store.read(), const AppSettings(disableGifAnimations: true));
  });

  test('legacy alignment does not enable the new content size limit', () async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.content_alignment': 'right',
    });
    expect((await AppSettingsStore().read()).limitContentSize, isFalse);
    await AppSettingsStore().update(limitContentSize: true);
    expect((await AppSettingsStore().read()).limitContentSize, isTrue);
  });

  test('round-trips the content size limit through one app-wide key', () async {
    final store = AppSettingsStore();

    for (final alignment in [false, true]) {
      await store.write(AppSettings(limitContentSize: alignment));

      expect(
        (await SharedPreferences.getInstance()).getBool(
          AppSettingsStore.limitContentSizeKey,
        ),
        alignment,
      );
      expect(await store.read(), AppSettings(limitContentSize: alignment));
    }
  });

  test('round-trips every text scale by its stable enum name', () async {
    for (final scale in AppTextScale.values) {
      final store = AppSettingsStore();
      await store.write(AppSettings(textScale: scale));

      expect(
        (await SharedPreferences.getInstance()).getString(
          AppSettingsStore.textScaleKey,
        ),
        scale.name,
      );
      expect(await AppSettingsStore().read(), AppSettings(textScale: scale));
    }
  });

  test('restores every theme mode in a fresh store', () async {
    for (final mode in AppThemeMode.values) {
      await AppSettingsStore().update(themeMode: mode);

      expect(
        (await SharedPreferences.getInstance()).getString(
          AppSettingsStore.themeModeKey,
        ),
        mode.name,
      );
      expect(await AppSettingsStore().read(), AppSettings(themeMode: mode));
    }
  });

  test('restores every topic list mode in a fresh store', () async {
    for (final mode in TopicListDisplayMode.values) {
      await AppSettingsStore().update(topicListMode: mode);

      expect(
        (await SharedPreferences.getInstance()).getString(
          AppSettingsStore.topicListModeKey,
        ),
        mode.name,
      );
      expect(await AppSettingsStore().read(), AppSettings(topicListMode: mode));
    }
  });

  test('replacement stores persist writes in request order', () async {
    final persistence = _ControlledAppSettingsPersistence(
      firstWriteGate: Completer<void>(),
    );
    final first = AppSettingsStore(persistence: persistence);
    final replacement = AppSettingsStore(persistence: persistence);

    final writingDisabled = first.write(
      const AppSettings(
        limitContentSize: false,
        textScale: AppTextScale.percent90,
      ),
    );
    await persistence.firstWriteStarted.future;
    final writingEnabled = replacement.write(
      const AppSettings(
        limitContentSize: true,
        textScale: AppTextScale.percent150,
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(persistence.attemptedWrites, [false]);

    persistence.firstWriteGate!.complete();
    await Future.wait([writingDisabled, writingEnabled]);

    expect(persistence.attemptedWrites, [false, true]);
    expect(persistence.limitContentSize, true);
    expect(persistence.attemptedTextScaleWrites, [
      AppTextScale.percent90.name,
      AppTextScale.percent150.name,
    ]);
    expect(persistence.textScale, AppTextScale.percent150.name);
  });

  test('a replacement read waits for an accepted write', () async {
    final persistence = _ControlledAppSettingsPersistence(
      firstWriteGate: Completer<void>(),
    );
    final first = AppSettingsStore(persistence: persistence);
    final replacement = AppSettingsStore(persistence: persistence);

    final writing = first.write(
      const AppSettings(
        limitContentSize: false,
        textScale: AppTextScale.percent125,
      ),
    );
    await persistence.firstWriteStarted.future;
    final reading = replacement.read();

    await Future<void>.delayed(Duration.zero);
    expect(persistence.readCount, 0);

    persistence.firstWriteGate!.complete();
    await writing;
    expect(
      await reading,
      const AppSettings(
        limitContentSize: false,
        textScale: AppTextScale.percent125,
      ),
    );
    expect(persistence.readCount, 1);
  });

  test(
    'a replacement patch follows queued writes without replacing other fields',
    () async {
      final persistence = _ControlledAppSettingsPersistence(
        firstWriteGate: Completer<void>(),
      );
      final first = AppSettingsStore(persistence: persistence);
      final replacement = AppSettingsStore(persistence: persistence);
      final writing = first.write(
        const AppSettings(
          limitContentSize: false,
          disableGifAnimations: true,
          textScale: AppTextScale.percent175,
        ),
      );
      await persistence.firstWriteStarted.future;
      final updating = replacement.update(limitContentSize: true);
      final reading = replacement.read();
      final fresh = AppSettingsStore(persistence: persistence).read();

      await Future<void>.delayed(Duration.zero);
      expect(persistence.readCount, 0);
      expect(persistence.attemptedWrites, [false]);

      persistence.firstWriteGate!.complete();
      await Future.wait([writing, updating]);

      const expected = AppSettings(
        limitContentSize: true,
        disableGifAnimations: true,
        textScale: AppTextScale.percent175,
      );
      expect(await reading, expected);
      expect(await fresh, expected);
      expect(persistence.attemptedWrites, [false, true]);
      expect(persistence.attemptedGifAnimationWrites, [true]);
      expect(persistence.attemptedTextScaleWrites, [
        AppTextScale.percent175.name,
      ]);
    },
  );

  for (final throwWrites in [false, true]) {
    test(
      '${throwWrites ? 'throwing' : 'rejected'} patches retain only explicit session choices',
      () async {
        final diagnostics = await _installDiagnostics(
          'app-settings-patch-failure',
        );
        final persistence = _ControlledAppSettingsPersistence(
          limitContentSize: false,
          disableGifAnimations: true,
          textScale: AppTextScale.percent175.name,
          acceptWrites: false,
          throwWrites: throwWrites,
        );
        final store = AppSettingsStore(persistence: persistence);

        await store.update(limitContentSize: true);

        expect(
          await store.read(),
          const AppSettings(
            limitContentSize: true,
            disableGifAnimations: true,
            textScale: AppTextScale.percent175,
          ),
        );
        expect(
          await AppSettingsStore(persistence: persistence).read(),
          const AppSettings(
            limitContentSize: false,
            disableGifAnimations: true,
            textScale: AppTextScale.percent175,
          ),
        );
        expect(persistence.attemptedGifAnimationWrites, isEmpty);
        expect(persistence.attemptedTextScaleWrites, isEmpty);
        expect(diagnostics.events.whereType<ErrorDiagnosticEvent>(), [
          _isStorageFailure('appSettings.writeLimitContentSize', 'StateError'),
        ]);

        persistence.acceptWrites = true;
        persistence.throwWrites = false;
        await store.update(disableGifAnimations: false);
        expect((await store.read()).limitContentSize, true);
        expect(persistence.disableGifAnimations, isFalse);
      },
    );
  }

  test(
    'session edits retain hydrated fields if storage becomes unavailable',
    () async {
      final persistence = _ControlledAppSettingsPersistence(
        limitContentSize: false,
        disableGifAnimations: true,
        textScale: AppTextScale.percent175.name,
      );
      final store = AppSettingsStore(persistence: persistence);
      await store.read();
      persistence.failReads = true;
      persistence.acceptWrites = false;

      await store.update(limitContentSize: true);

      expect(
        await store.read(),
        const AppSettings(
          limitContentSize: true,
          disableGifAnimations: true,
          textScale: AppTextScale.percent175,
        ),
      );
      expect(persistence.readCount, 1);
    },
  );

  test(
    'a failed field read does not turn its fallback into a saved preference',
    () async {
      final diagnostics = await _installDiagnostics(
        'app-settings-partial-read',
      );
      final persistence = _ControlledAppSettingsPersistence(
        limitContentSize: false,
        disableGifAnimations: true,
        textScale: AppTextScale.percent175.name,
        failTextScaleRead: true,
      );
      final store = AppSettingsStore(persistence: persistence);

      final loaded = await store.read();
      expect(
        loaded,
        const AppSettings(limitContentSize: false, disableGifAnimations: true),
      );
      await store.update(limitContentSize: true);

      expect(persistence.limitContentSize, true);
      expect(persistence.disableGifAnimations, isTrue);
      expect(persistence.textScale, AppTextScale.percent175.name);
      expect(persistence.attemptedTextScaleWrites, isEmpty);
      expect(diagnostics.events.whereType<ErrorDiagnosticEvent>(), [
        _isStorageFailure('appSettings.readTextScale', 'StateError'),
      ]);
    },
  );

  test('storage failures degrade to defaults without escaping', () async {
    final diagnostics = await _installDiagnostics('app-settings-failures');
    final persistence = _ControlledAppSettingsPersistence(
      failReads: true,
      acceptWrites: false,
    );
    final store = AppSettingsStore(persistence: persistence);

    expect(await store.read(), AppSettings.defaults);
    await store.write(const AppSettings(limitContentSize: true));

    expect(
      diagnostics.events.whereType<ErrorDiagnosticEvent>(),
      containsAll([
        _isStorageFailure('appSettings.readLimitContentSize', 'StateError'),
        _isStorageFailure('appSettings.readDisableGifAnimations', 'StateError'),
        _isStorageFailure('appSettings.readTextScale', 'StateError'),
        _isStorageFailure('appSettings.readThemeMode', 'StateError'),
        _isStorageFailure('appSettings.writeLimitContentSize', 'StateError'),
        _isStorageFailure(
          'appSettings.writeDisableGifAnimations',
          'StateError',
        ),
        _isStorageFailure('appSettings.writeTextScale', 'StateError'),
        _isStorageFailure('appSettings.writeThemeMode', 'StateError'),
      ]),
    );
  });
}

Future<DiagnosticsController> _installDiagnostics(String sessionId) async {
  final diagnostics = await DiagnosticsController.create(
    persistence: MemoryDiagnosticsPersistence(),
    sessionId: sessionId,
  );
  final binding = DiagnosticsSink.install(diagnostics);
  addTearDown(() async {
    binding.close();
    await diagnostics.close();
  });
  return diagnostics;
}

Matcher _isStorageFailure(String operation, String errorType) =>
    isA<ErrorDiagnosticEvent>()
        .having((event) => event.operation, 'operation', operation)
        .having((event) => event.source, 'source', 'storage')
        .having(
          (event) => event.severity,
          'severity',
          DiagnosticSeverity.warning,
        )
        .having((event) => event.errorType, 'error type', errorType)
        .having((event) => event.handled, 'handled', isTrue)
        .having((event) => event.degraded, 'degraded', isTrue);

final class _ControlledAppSettingsPersistence
    implements AppSettingsPersistence {
  @override
  Future<bool?> readTopicListLargerText() async => null;
  @override
  Future<bool> writeTopicListLargerText(bool value) async => true;
  @override
  Future<bool?> readTopicListShowTags() async => null;
  @override
  Future<bool?> readTopicListShowLastPoster() async => null;
  @override
  Future<bool> writeTopicListShowTags(bool value) async => true;
  @override
  Future<bool> writeTopicListShowLastPoster(bool value) async => true;
  @override
  Future<bool?> readTopicListShowAssignments() async => null;
  @override
  Future<bool> writeTopicListShowAssignments(bool value) async => true;

  _ControlledAppSettingsPersistence({
    this.limitContentSize,
    this.disableGifAnimations,
    this.textScale,
    this.firstWriteGate,
    this.failReads = false,
    this.failTextScaleRead = false,
    this.acceptWrites = true,
    this.throwWrites = false,
  });

  bool? limitContentSize;
  bool? disableGifAnimations;
  String? textScale;
  String? themeMode;
  String? topicListMode;
  final Completer<void>? firstWriteGate;
  bool failReads;
  final bool failTextScaleRead;
  bool acceptWrites;
  bool throwWrites;
  final Completer<void> firstWriteStarted = Completer<void>();
  final List<bool> attemptedWrites = [];
  final List<bool> attemptedGifAnimationWrites = [];
  final List<String> attemptedTextScaleWrites = [];
  final List<String> attemptedThemeModeWrites = [];
  int readCount = 0;

  @override
  Future<bool?> readLimitContentSize() async {
    readCount++;
    if (failReads) throw StateError('preferences unavailable');
    return limitContentSize;
  }

  @override
  Future<bool?> readDisableGifAnimations() async {
    if (failReads) throw StateError('preferences unavailable');
    return disableGifAnimations;
  }

  @override
  Future<String?> readTextScale() async {
    if (failReads || failTextScaleRead) {
      throw StateError('preferences unavailable');
    }
    return textScale;
  }

  @override
  Future<String?> readThemeMode() async {
    if (failReads) throw StateError('preferences unavailable');
    return themeMode;
  }

  @override
  Future<bool> writeLimitContentSize(bool value) async {
    attemptedWrites.add(value);
    if (attemptedWrites.length == 1) {
      firstWriteStarted.complete();
      await firstWriteGate?.future;
    }
    if (throwWrites) throw StateError('preferences unavailable');
    if (!acceptWrites) return false;
    limitContentSize = value;
    return true;
  }

  @override
  Future<bool> writeDisableGifAnimations(bool value) async {
    attemptedGifAnimationWrites.add(value);
    if (throwWrites) throw StateError('preferences unavailable');
    if (!acceptWrites) return false;
    disableGifAnimations = value;
    return true;
  }

  @override
  Future<bool> writeTextScale(String value) async {
    attemptedTextScaleWrites.add(value);
    if (throwWrites) throw StateError('preferences unavailable');
    if (!acceptWrites) return false;
    textScale = value;
    return true;
  }

  @override
  Future<String?> readTopicListMode() async {
    if (failReads) throw StateError('preferences unavailable');
    return topicListMode;
  }

  @override
  Future<bool> writeTopicListMode(String value) async {
    if (throwWrites) throw StateError('preferences unavailable');
    if (!acceptWrites) return false;
    topicListMode = value;
    return true;
  }

  @override
  Future<bool> writeThemeMode(String value) async {
    attemptedThemeModeWrites.add(value);
    if (throwWrites) throw StateError('preferences unavailable');
    if (!acceptWrites) return false;
    themeMode = value;
    return true;
  }
}
