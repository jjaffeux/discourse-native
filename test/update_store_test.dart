import 'dart:async';

import 'package:discourse_native/src/data/update_store.dart';
import 'package:discourse_native/src/data/updater.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = UpdateStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('update channel preference', () {
    test('reads as no preference when nothing was stored', () async {
      expect(await store.readChannel(), isNull);
    });

    test('persists successive channel selections', () async {
      await store.writeChannel(UpdateChannel.canary);
      expect(await store.readChannel(), UpdateChannel.canary);

      await store.writeChannel(UpdateChannel.stable);
      expect(await store.readChannel(), UpdateChannel.stable);
    });

    test('reports a platform write rejection without failing', () async {
      final persistence = _ControlledUpdatePersistence(
        acceptChannelWrites: false,
      );
      final diagnostics = await _installDiagnostics('update-channel-write');

      await UpdateStore(
        persistence: persistence,
      ).writeChannel(UpdateChannel.canary);

      expect(persistence.channelName, isNull);
      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
        _isRejectedStorageWrite('updates.writeChannel'),
      );
    });

    test(
      'replacement stores persist channel writes in request order',
      () async {
        final gate = Completer<void>();
        final persistence = _ControlledUpdatePersistence(
          firstChannelWriteGate: gate,
        );
        final oldStore = UpdateStore(persistence: persistence);
        final replacementStore = UpdateStore(persistence: persistence);

        final oldWrite = oldStore.writeChannel(UpdateChannel.canary);
        await persistence.firstChannelWriteStarted.future;
        final replacementWrite = replacementStore.writeChannel(
          UpdateChannel.stable,
        );

        await Future<void>.delayed(Duration.zero);
        expect(persistence.channelWriteCount, 1);

        gate.complete();
        await Future.wait([oldWrite, replacementWrite]);

        expect(persistence.channelWriteCount, 2);
        expect(persistence.channelName, UpdateChannel.stable.name);
      },
    );

    test('replacement reads wait for an in-flight channel write', () async {
      final gate = Completer<void>();
      final persistence = _ControlledUpdatePersistence(
        firstChannelWriteGate: gate,
      );
      final oldStore = UpdateStore(persistence: persistence);
      final replacementStore = UpdateStore(persistence: persistence);

      final writing = oldStore.writeChannel(UpdateChannel.canary);
      await persistence.firstChannelWriteStarted.future;
      final reading = replacementStore.readChannel();

      await Future<void>.delayed(Duration.zero);
      expect(persistence.channelReadCount, 0);

      gate.complete();
      await writing;

      expect(await reading, UpdateChannel.canary);
      expect(persistence.channelReadCount, 1);
    });

    test(
      'reads as no preference when the name is no longer a channel',
      () async {
        SharedPreferences.setMockInitialValues({
          'discourse_native.update_channel': 'beta',
        });
        expect(await store.readChannel(), isNull);
      },
    );
  });

  group('last-checked timestamp', () {
    test('reads as never when nothing was stored', () async {
      expect(await store.readLastChecked(), isNull);
    });

    test('persists the last check time', () async {
      final at = DateTime.fromMillisecondsSinceEpoch(1720000000000);
      await store.writeLastChecked(at);

      expect(await store.readLastChecked(), at);
    });

    test('reports a platform write rejection without failing', () async {
      final persistence = _ControlledUpdatePersistence(
        acceptLastCheckedWrites: false,
      );
      final diagnostics = await _installDiagnostics(
        'update-last-checked-write',
      );
      final at = DateTime.fromMillisecondsSinceEpoch(1720000000000);

      await UpdateStore(persistence: persistence).writeLastChecked(at);

      expect(persistence.lastCheckedMillis, isNull);
      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
        _isRejectedStorageWrite('updates.writeLastChecked'),
      );
    });

    test('remains independent from the channel preference', () async {
      await store.writeChannel(UpdateChannel.canary);
      final at = DateTime.fromMillisecondsSinceEpoch(1720000000000);
      await store.writeLastChecked(at);

      expect(await store.readChannel(), UpdateChannel.canary);
      expect(await store.readLastChecked(), at);
    });

    test('a channel write does not block last-checked persistence', () async {
      final gate = Completer<void>();
      final persistence = _ControlledUpdatePersistence(
        firstChannelWriteGate: gate,
      );
      final controlledStore = UpdateStore(persistence: persistence);
      final at = DateTime.fromMillisecondsSinceEpoch(1720000000000);

      final channelWrite = controlledStore.writeChannel(UpdateChannel.canary);
      await persistence.firstChannelWriteStarted.future;

      await controlledStore
          .writeLastChecked(at)
          .timeout(const Duration(seconds: 1));
      expect(persistence.lastCheckedMillis, at.millisecondsSinceEpoch);

      gate.complete();
      await channelWrite;
    });
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

Matcher _isRejectedStorageWrite(String operation) => isA<ErrorDiagnosticEvent>()
    .having((event) => event.operation, 'operation', operation)
    .having((event) => event.source, 'source', 'storage')
    .having((event) => event.severity, 'severity', DiagnosticSeverity.warning)
    .having((event) => event.errorType, 'error type', 'StateError')
    .having((event) => event.handled, 'handled', isTrue)
    .having((event) => event.degraded, 'degraded', isTrue);

final class _ControlledUpdatePersistence implements UpdatePersistence {
  _ControlledUpdatePersistence({
    this.acceptChannelWrites = true,
    this.acceptLastCheckedWrites = true,
    this.firstChannelWriteGate,
  });

  final bool acceptChannelWrites;
  final bool acceptLastCheckedWrites;
  final Completer<void>? firstChannelWriteGate;
  final Completer<void> firstChannelWriteStarted = Completer<void>();
  String? channelName;
  int? lastCheckedMillis;
  int channelReadCount = 0;
  int channelWriteCount = 0;

  @override
  Future<String?> readChannelName() async {
    channelReadCount++;
    return channelName;
  }

  @override
  Future<int?> readLastCheckedMillis() async => lastCheckedMillis;

  @override
  Future<bool> writeChannelName(String value) async {
    channelWriteCount++;
    if (channelWriteCount == 1) {
      if (!firstChannelWriteStarted.isCompleted) {
        firstChannelWriteStarted.complete();
      }
      await firstChannelWriteGate?.future;
    }
    if (!acceptChannelWrites) return false;
    channelName = value;
    return true;
  }

  @override
  Future<bool> writeLastCheckedMillis(int value) async {
    if (!acceptLastCheckedWrites) return false;
    lastCheckedMillis = value;
    return true;
  }
}
