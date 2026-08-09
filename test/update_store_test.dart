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

  group('the channel', () {
    test('reads as no preference when nothing was stored', () async {
      expect(await store.readChannel(), isNull);
    });

    test('survives a round trip', () async {
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
      'reads as no preference when the name is no longer a channel',
      () async {
        // A preference written by an older build must not stop this one from
        // launching.
        SharedPreferences.setMockInitialValues({
          'discourse_native.update_channel': 'beta',
        });
        expect(await store.readChannel(), isNull);
      },
    );
  });

  group('the last check', () {
    test('reads as never when nothing was stored', () async {
      expect(await store.readLastChecked(), isNull);
    });

    test('survives a round trip', () async {
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

    test('keeps the two facts apart', () async {
      await store.writeChannel(UpdateChannel.canary);
      final at = DateTime.fromMillisecondsSinceEpoch(1720000000000);
      await store.writeLastChecked(at);

      expect(await store.readChannel(), UpdateChannel.canary);
      expect(await store.readLastChecked(), at);
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
  });

  final bool acceptChannelWrites;
  final bool acceptLastCheckedWrites;
  String? channelName;
  int? lastCheckedMillis;

  @override
  Future<String?> readChannelName() async => channelName;

  @override
  Future<int?> readLastCheckedMillis() async => lastCheckedMillis;

  @override
  Future<bool> writeChannelName(String value) async {
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
