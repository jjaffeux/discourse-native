import 'dart:async';

import 'package:discourse_native/src/data/diagnostics_panel_width_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/data/sidebar_width_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DiagnosticsController diagnostics;
  late DiagnosticsSinkBinding diagnosticsBinding;

  setUp(() async {
    diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      sessionId: 'scalar-preferences',
    );
    diagnosticsBinding = DiagnosticsSink.install(diagnostics);
  });

  tearDown(() async {
    diagnosticsBinding.close();
    await diagnostics.close();
  });

  group('ScalarPreferenceRepository', () {
    test('a read observes every already-requested write in order', () async {
      final persistence = _MemoryScalarPersistence(
        firstWriteGate: Completer<void>(),
      );
      final first = _repository(persistence);
      final replacement = _repository(persistence);

      final firstWrite = first.write(320);
      await persistence.firstWriteStarted.future;
      final secondWrite = replacement.write(360);
      final read = replacement.read();

      expect(persistence.writes, [320]);
      expect(persistence.readKeys, isEmpty);

      persistence.firstWriteGate!.complete();
      await Future.wait([firstWrite, secondWrite]);

      expect(persistence.writes, [320, 360]);
      expect(await read, 360);
      expect(persistence.readKeys, ['width']);
    });

    test('pending work remains isolated by owner and key', () async {
      final persistence = _MemoryScalarPersistence(
        firstWriteGate: Completer<void>(),
        values: {'width': 240, 'other-width': 480},
      );
      final sharedOwner = Object();
      final blocked = _repository(persistence, owner: sharedOwner);
      final otherKey = _repository(
        persistence,
        owner: sharedOwner,
        key: 'other-width',
      );
      final otherOwner = _repository(persistence, owner: Object());

      final write = blocked.write(320);
      await persistence.firstWriteStarted.future;
      final blockedRead = blocked.read();

      expect(await otherKey.read(), 480);
      expect(await otherOwner.read(), 240);
      expect(persistence.readKeys, ['other-width', 'width']);

      persistence.firstWriteGate!.complete();
      await write;
      expect(await blockedRead, 320);
      expect(persistence.readKeys, ['other-width', 'width', 'width']);
    });

    test('a false persistence result reports a degraded write', () async {
      final persistence = _MemoryScalarPersistence(acceptWrites: false);

      await _repository(persistence).write(360);

      expect(persistence.writes, [360]);
      expect(persistence.values, isEmpty);
      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
        _isStorageFailure('scalar.write', 'StateError'),
      );
    });

    test(
      'thrown persistence reads and writes degrade without escaping',
      () async {
        final persistence = _MemoryScalarPersistence(
          readError: StateError('read unavailable'),
          writeError: StateError('write unavailable'),
        );
        final repository = _repository(persistence);

        expect(await repository.read(), isNull);
        await repository.write(360);

        expect(
          diagnostics.events.whereType<ErrorDiagnosticEvent>().map(
            (event) => (event.operation, event.errorType),
          ),
          [('scalar.read', 'StateError'), ('scalar.write', 'StateError')],
        );
      },
    );
  });

  group('width store facades', () {
    test(
      'SidebarWidthStore preserves its API and diagnostic operations',
      () async {
        final persistence = _SidebarWidthPersistence(320);
        final store = SidebarWidthStore(persistence: persistence);

        expect(await store.read(), 320);
        await store.write(360);
        expect(persistence.value, 360);

        persistence
          ..readError = StateError('read unavailable')
          ..acceptWrites = false;
        expect(await store.read(), isNull);
        await store.write(400);

        expect(persistence.attemptedWrites, [360, 400]);
        expect(persistence.value, 360);
        expect(
          diagnostics.events.whereType<ErrorDiagnosticEvent>().map(
            (event) => event.operation,
          ),
          ['sidebar.readWidth', 'sidebar.writeWidth'],
        );
      },
    );

    test(
      'DiagnosticsPanelWidthStore preserves its API and diagnostic operations',
      () async {
        final persistence = _DiagnosticsPanelWidthPersistence(480);
        final store = DiagnosticsPanelWidthStore(persistence: persistence);

        expect(await store.read(), 480);
        await store.write(560);
        expect(persistence.value, 560);

        persistence
          ..readError = StateError('read unavailable')
          ..acceptWrites = false;
        expect(await store.read(), isNull);
        await store.write(640);

        expect(persistence.attemptedWrites, [560, 640]);
        expect(persistence.value, 560);
        expect(
          diagnostics.events.whereType<ErrorDiagnosticEvent>().map(
            (event) => event.operation,
          ),
          ['diagnosticsPanel.readWidth', 'diagnosticsPanel.writeWidth'],
        );
      },
    );
  });
}

ScalarPreferenceRepository<double> _repository(
  ScalarPreferencePersistence<double> persistence, {
  Object? owner,
  String key = 'width',
}) => ScalarPreferenceRepository<double>(
  persistence: persistence,
  owner: owner,
  key: key,
  readOperation: 'scalar.read',
  writeOperation: 'scalar.write',
  writeFailureMessage: 'Could not persist the scalar preference.',
);

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

final class _MemoryScalarPersistence
    implements ScalarPreferencePersistence<double> {
  _MemoryScalarPersistence({
    this.firstWriteGate,
    this.acceptWrites = true,
    this.readError,
    this.writeError,
    Map<String, double>? values,
  }) : values = values ?? {};

  final Completer<void>? firstWriteGate;
  final bool acceptWrites;
  final Object? readError;
  final Object? writeError;
  final Map<String, double> values;
  final Completer<void> firstWriteStarted = Completer<void>();
  final List<String> readKeys = [];
  final List<double> writes = [];

  @override
  Future<double?> read(String key) async {
    readKeys.add(key);
    final error = readError;
    if (error != null) throw error;
    return values[key];
  }

  @override
  Future<bool> write(String key, double value) async {
    writes.add(value);
    final error = writeError;
    if (error != null) throw error;
    if (writes.length == 1 && firstWriteGate != null) {
      firstWriteStarted.complete();
      await firstWriteGate!.future;
    }
    if (acceptWrites) values[key] = value;
    return acceptWrites;
  }
}

final class _SidebarWidthPersistence implements SidebarWidthPersistence {
  _SidebarWidthPersistence(this.value);

  double? value;
  Object? readError;
  bool acceptWrites = true;
  final List<double> attemptedWrites = [];

  @override
  Future<double?> readWidth() async {
    final error = readError;
    if (error != null) throw error;
    return value;
  }

  @override
  Future<bool> writeWidth(double width) async {
    attemptedWrites.add(width);
    if (acceptWrites) value = width;
    return acceptWrites;
  }
}

final class _DiagnosticsPanelWidthPersistence
    implements DiagnosticsPanelWidthPersistence {
  _DiagnosticsPanelWidthPersistence(this.value);

  double? value;
  Object? readError;
  bool acceptWrites = true;
  final List<double> attemptedWrites = [];

  @override
  Future<double?> readWidth() async {
    final error = readError;
    if (error != null) throw error;
    return value;
  }

  @override
  Future<bool> writeWidth(double width) async {
    attemptedWrites.add(width);
    if (acceptWrites) value = width;
    return acceptWrites;
  }
}
