import 'dart:async';

import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults missing and unknown alignment values to center', () async {
    final platformStore = AppSettingsStore();

    expect(await platformStore.read(), AppSettings.defaults);

    SharedPreferences.setMockInitialValues({
      AppSettingsStore.contentAlignmentKey: 'justify',
    });
    expect(await platformStore.read(), AppSettings.defaults);
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

  test('replacement stores persist writes in request order', () async {
    final persistence = _ControlledAppSettingsPersistence(
      firstWriteGate: Completer<void>(),
    );
    final first = AppSettingsStore(persistence: persistence);
    final replacement = AppSettingsStore(persistence: persistence);

    final writingLeft = first.write(
      const AppSettings(contentAlignment: ContentAlignment.left),
    );
    await persistence.firstWriteStarted.future;
    final writingRight = replacement.write(
      const AppSettings(contentAlignment: ContentAlignment.right),
    );

    await Future<void>.delayed(Duration.zero);
    expect(persistence.attemptedWrites, ['left']);

    persistence.firstWriteGate!.complete();
    await Future.wait([writingLeft, writingRight]);

    expect(persistence.attemptedWrites, ['left', 'right']);
    expect(persistence.contentAlignment, 'right');
  });

  test('a replacement read waits for an accepted write', () async {
    final persistence = _ControlledAppSettingsPersistence(
      firstWriteGate: Completer<void>(),
    );
    final first = AppSettingsStore(persistence: persistence);
    final replacement = AppSettingsStore(persistence: persistence);

    final writing = first.write(
      const AppSettings(contentAlignment: ContentAlignment.left),
    );
    await persistence.firstWriteStarted.future;
    final reading = replacement.read();

    await Future<void>.delayed(Duration.zero);
    expect(persistence.readCount, 0);

    persistence.firstWriteGate!.complete();
    await writing;
    expect(
      await reading,
      const AppSettings(contentAlignment: ContentAlignment.left),
    );
    expect(persistence.readCount, 1);
  });

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
        _isStorageFailure('appSettings.writeContentAlignment', 'StateError'),
        _isStorageFailure(
          'appSettings.writeDisableGifAnimations',
          'StateError',
        ),
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
    this.firstWriteGate,
    this.failReads = false,
    this.acceptWrites = true,
  });

  String? contentAlignment;
  bool? disableGifAnimations;
  final Completer<void>? firstWriteGate;
  final bool failReads;
  final bool acceptWrites;
  final Completer<void> firstWriteStarted = Completer<void>();
  final List<String> attemptedWrites = [];
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
  Future<bool> writeContentAlignment(String value) async {
    attemptedWrites.add(value);
    if (attemptedWrites.length == 1) {
      firstWriteStarted.complete();
      await firstWriteGate?.future;
    }
    if (!acceptWrites) return false;
    contentAlignment = value;
    return true;
  }

  @override
  Future<bool> writeDisableGifAnimations(bool value) async {
    if (!acceptWrites) return false;
    disableGifAnimations = value;
    return true;
  }
}
