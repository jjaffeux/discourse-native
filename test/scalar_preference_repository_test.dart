import 'dart:async';

import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/data/sidebar_width_store.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
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

  group('width store facades', () {
    test('SidebarWidthStore preserves its API', () async {
      final persistence = _SidebarWidthPersistence(320);
      final store = SidebarWidthStore(persistence: persistence);

      expect(await store.read(), 320);
      await store.write(360);
      expect(persistence.value, 360);

      persistence.readError = StateError('read unavailable');
      expect(await store.read(), isNull);
      await store.write(400);
      expect(persistence.attemptedWrites, [360, 400]);
    });
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
);

final class _MemoryScalarPersistence
    implements ScalarPreferencePersistence<double> {
  _MemoryScalarPersistence({
    this.firstWriteGate,
    this.readError,
    this.writeError,
    Map<String, double>? values,
  }) : values = values ?? {};

  final Completer<void>? firstWriteGate;
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
    values[key] = value;
    return true;
  }
}

final class _SidebarWidthPersistence implements SidebarWidthPersistence {
  _SidebarWidthPersistence(this.value);

  double? value;
  Object? readError;
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
    value = width;
    return true;
  }
}
