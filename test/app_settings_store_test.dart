import 'dart:async';

import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults missing and unknown enum values', () async {
    final platformStore = AppSettingsStore();

    expect(await platformStore.read(), AppSettings.defaults);

    SharedPreferences.setMockInitialValues({
      AppSettingsStore.contentAlignmentKey: 'justify',
      AppSettingsStore.textScaleKey: 'percent137',
    });
    expect(await platformStore.read(), AppSettings.defaults);
  });

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

  test('round-trips every alignment through one app-wide key', () async {
    final store = AppSettingsStore();

    for (final alignment in ContentAlignment.values) {
      await store.write(AppSettings(contentAlignment: alignment));

      expect(
        (await SharedPreferences.getInstance()).getString(
          AppSettingsStore.contentAlignmentKey,
        ),
        alignment.name,
      );
      expect(await store.read(), AppSettings(contentAlignment: alignment));
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

  test('replacement stores persist writes in request order', () async {
    final persistence = _ControlledAppSettingsPersistence(
      firstWriteGate: Completer<void>(),
    );
    final first = AppSettingsStore(persistence: persistence);
    final replacement = AppSettingsStore(persistence: persistence);

    final writingLeft = first.write(
      const AppSettings(
        contentAlignment: ContentAlignment.left,
        textScale: AppTextScale.percent90,
      ),
    );
    await persistence.firstWriteStarted.future;
    final writingRight = replacement.write(
      const AppSettings(
        contentAlignment: ContentAlignment.right,
        textScale: AppTextScale.percent150,
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(persistence.attemptedWrites, ['left']);

    persistence.firstWriteGate!.complete();
    await Future.wait([writingLeft, writingRight]);

    expect(persistence.attemptedWrites, ['left', 'right']);
    expect(persistence.contentAlignment, 'right');
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
        contentAlignment: ContentAlignment.left,
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
        contentAlignment: ContentAlignment.left,
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
          contentAlignment: ContentAlignment.left,
          disableGifAnimations: true,
          textScale: AppTextScale.percent175,
        ),
      );
      await persistence.firstWriteStarted.future;
      final updating = replacement.update(
        contentAlignment: ContentAlignment.right,
      );
      final reading = replacement.read();
      final fresh = AppSettingsStore(persistence: persistence).read();

      await Future<void>.delayed(Duration.zero);
      expect(persistence.readCount, 0);
      expect(persistence.attemptedWrites, ['left']);

      persistence.firstWriteGate!.complete();
      await Future.wait([writing, updating]);

      const expected = AppSettings(
        contentAlignment: ContentAlignment.right,
        disableGifAnimations: true,
        textScale: AppTextScale.percent175,
      );
      expect(await reading, expected);
      expect(await fresh, expected);
      expect(persistence.attemptedWrites, ['left', 'right']);
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
          contentAlignment: 'left',
          disableGifAnimations: true,
          textScale: AppTextScale.percent175.name,
          acceptWrites: false,
          throwWrites: throwWrites,
        );
        final store = AppSettingsStore(persistence: persistence);

        await store.update(contentAlignment: ContentAlignment.right);

        expect(
          await store.read(),
          const AppSettings(
            contentAlignment: ContentAlignment.right,
            disableGifAnimations: true,
            textScale: AppTextScale.percent175,
          ),
        );
        expect(
          await AppSettingsStore(persistence: persistence).read(),
          const AppSettings(
            contentAlignment: ContentAlignment.left,
            disableGifAnimations: true,
            textScale: AppTextScale.percent175,
          ),
        );
        expect(persistence.attemptedGifAnimationWrites, isEmpty);
        expect(persistence.attemptedTextScaleWrites, isEmpty);
        expect(diagnostics.events.whereType<ErrorDiagnosticEvent>(), [
          _isStorageFailure('appSettings.writeContentAlignment', 'StateError'),
        ]);

        persistence.acceptWrites = true;
        persistence.throwWrites = false;
        await store.update(disableGifAnimations: false);
        expect((await store.read()).contentAlignment, ContentAlignment.right);
        expect(persistence.disableGifAnimations, isFalse);
      },
    );
  }

  test(
    'session edits retain hydrated fields if storage becomes unavailable',
    () async {
      final persistence = _ControlledAppSettingsPersistence(
        contentAlignment: 'left',
        disableGifAnimations: true,
        textScale: AppTextScale.percent175.name,
      );
      final store = AppSettingsStore(persistence: persistence);
      await store.read();
      persistence.failReads = true;
      persistence.acceptWrites = false;

      await store.update(contentAlignment: ContentAlignment.right);

      expect(
        await store.read(),
        const AppSettings(
          contentAlignment: ContentAlignment.right,
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
        contentAlignment: 'left',
        disableGifAnimations: true,
        textScale: AppTextScale.percent175.name,
        failTextScaleRead: true,
      );
      final store = AppSettingsStore(persistence: persistence);

      final loaded = await store.read();
      expect(
        loaded,
        const AppSettings(
          contentAlignment: ContentAlignment.left,
          disableGifAnimations: true,
        ),
      );
      await store.update(contentAlignment: ContentAlignment.right);

      expect(persistence.contentAlignment, 'right');
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
    await store.write(
      const AppSettings(contentAlignment: ContentAlignment.right),
    );

    expect(
      diagnostics.events.whereType<ErrorDiagnosticEvent>(),
      containsAll([
        _isStorageFailure('appSettings.readContentAlignment', 'StateError'),
        _isStorageFailure('appSettings.readDisableGifAnimations', 'StateError'),
        _isStorageFailure('appSettings.readTextScale', 'StateError'),
        _isStorageFailure('appSettings.writeContentAlignment', 'StateError'),
        _isStorageFailure(
          'appSettings.writeDisableGifAnimations',
          'StateError',
        ),
        _isStorageFailure('appSettings.writeTextScale', 'StateError'),
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
  _ControlledAppSettingsPersistence({
    this.contentAlignment,
    this.disableGifAnimations,
    this.textScale,
    this.firstWriteGate,
    this.failReads = false,
    this.failTextScaleRead = false,
    this.acceptWrites = true,
    this.throwWrites = false,
  });

  String? contentAlignment;
  bool? disableGifAnimations;
  String? textScale;
  final Completer<void>? firstWriteGate;
  bool failReads;
  final bool failTextScaleRead;
  bool acceptWrites;
  bool throwWrites;
  final Completer<void> firstWriteStarted = Completer<void>();
  final List<String> attemptedWrites = [];
  final List<bool> attemptedGifAnimationWrites = [];
  final List<String> attemptedTextScaleWrites = [];
  int readCount = 0;

  @override
  Future<String?> readContentAlignment() async {
    readCount++;
    if (failReads) throw StateError('preferences unavailable');
    return contentAlignment;
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
  Future<bool> writeContentAlignment(String value) async {
    attemptedWrites.add(value);
    if (attemptedWrites.length == 1) {
      firstWriteStarted.complete();
      await firstWriteGate?.future;
    }
    if (throwWrites) throw StateError('preferences unavailable');
    if (!acceptWrites) return false;
    contentAlignment = value;
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
}
