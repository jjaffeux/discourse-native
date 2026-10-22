import 'dart:async';

import 'package:discourse_native/src/data/scalar_preference_repository.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {});

  tearDown(() async {});

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
      },
    );
  });

  group('width store facades', () {});
}

ScalarPreferenceRepository<double> _repository(
  ScalarPreferencePersistence<double> persistence, {
  Object? owner,
  String key = 'width',
}) => ScalarPreferenceRepository<double>(
  persistence: persistence,
  owner: owner,
  key: key,
);

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
