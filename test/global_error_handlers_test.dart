import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FlutterExceptionHandler? originalFlutterHandler;
  late bool Function(Object, StackTrace)? originalPlatformHandler;

  setUp(() {
    originalFlutterHandler = FlutterError.onError;
    originalPlatformHandler = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    FlutterError.onError = originalFlutterHandler;
    PlatformDispatcher.instance.onError = originalPlatformHandler;
  });

  group('global error dispatch', () {
    test(
      'records Flutter errors, chains the prior handler, and restores it',
      () {
        final sink = _RecordingSink();
        FlutterErrorDetails? forwardedDetails;
        void previous(FlutterErrorDetails details) {
          forwardedDetails = details;
        }

        FlutterError.onError = previous;
        final binding = DiagnosticsGlobalErrorBinding.install(sink);
        addTearDown(binding.close);
        final error = StateError('framework failure');
        final stackTrace = StackTrace.current;
        final details = FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
        );

        FlutterError.onError!(details);

        expect(forwardedDetails, same(details));
        expect(sink.records, hasLength(1));
        expect(sink.records.single.error, same(error));
        expect(sink.records.single.stackTrace, same(stackTrace));
        expect(sink.records.single.operation, 'unhandled');
        expect(sink.records.single.source, 'flutter');
        expect(sink.records.single.handled, isFalse);
        expect(sink.records.single.degraded, isFalse);

        binding.close();
        expect(FlutterError.onError, same(previous));
        binding.close();
        expect(FlutterError.onError, same(previous));
      },
    );

    test('returns the prior platform result or false without a handler', () {
      final sink = _RecordingSink();

      for (final priorResult in [true, false]) {
        bool previous(Object _, StackTrace _) => priorResult;
        PlatformDispatcher.instance.onError = previous;
        final binding = DiagnosticsGlobalErrorBinding.install(sink);
        addTearDown(binding.close);

        expect(
          PlatformDispatcher.instance.onError!(
            StateError('platform $priorResult'),
            StackTrace.current,
          ),
          priorResult,
        );

        binding.close();
        expect(PlatformDispatcher.instance.onError, same(previous));
      }

      PlatformDispatcher.instance.onError = null;
      final binding = DiagnosticsGlobalErrorBinding.install(sink);
      addTearDown(binding.close);
      expect(
        PlatformDispatcher.instance.onError!(
          StateError('unhandled platform failure'),
          StackTrace.current,
        ),
        isFalse,
      );
      expect(sink.records.last.source, 'platform');
      binding.close();
      expect(PlatformDispatcher.instance.onError, isNull);
    });

    test('still runs existing handlers when diagnostics recording fails', () {
      final sink = _RecordingSink(throwWhenRecording: true);
      var flutterCalls = 0;
      var platformCalls = 0;
      FlutterError.onError = (_) => flutterCalls += 1;
      PlatformDispatcher.instance.onError = (_, _) {
        platformCalls += 1;
        return true;
      };
      final binding = DiagnosticsGlobalErrorBinding.install(sink);
      addTearDown(binding.close);

      expect(
        () => FlutterError.onError!(
          FlutterErrorDetails(exception: StateError('framework failure')),
        ),
        returnsNormally,
      );
      expect(
        PlatformDispatcher.instance.onError!(
          StateError('platform failure'),
          StackTrace.current,
        ),
        isTrue,
      );
      expect(flutterCalls, 1);
      expect(platformCalls, 1);

      binding.close();
    });

    test('deduplicates the same error identity for one microtask', () async {
      final sink = _RecordingSink();
      PlatformDispatcher.instance.onError = (_, _) => false;
      final binding = DiagnosticsGlobalErrorBinding.install(sink);
      addTearDown(binding.close);
      final error = StateError('shared platform and zone failure');
      final stackTrace = StackTrace.current;

      PlatformDispatcher.instance.onError!(error, stackTrace);
      binding.reportUnhandledError(error, stackTrace, source: 'zone');

      expect(sink.records, hasLength(1));
      expect(sink.records.single.source, 'platform');

      await Future<void>.value();
      binding.reportUnhandledError(error, stackTrace, source: 'zone');

      expect(sink.records, hasLength(2));
      expect(sink.records.last.source, 'zone');
      binding.close();
    });
  });

  group('binding teardown and stacking', () {
    test('does not overwrite handlers installed after diagnostics', () {
      final binding = DiagnosticsGlobalErrorBinding.install(_RecordingSink());
      addTearDown(binding.close);
      void newerFlutterHandler(FlutterErrorDetails _) {}

      bool newerPlatformHandler(Object _, StackTrace _) => true;
      FlutterError.onError = newerFlutterHandler;
      PlatformDispatcher.instance.onError = newerPlatformHandler;

      binding.close();

      expect(FlutterError.onError, same(newerFlutterHandler));
      expect(PlatformDispatcher.instance.onError, same(newerPlatformHandler));
    });

    test('preserves nested global handlers through out-of-order teardown', () {
      void baselineFlutterHandler(FlutterErrorDetails _) {}

      bool baselinePlatformHandler(Object _, StackTrace _) => true;
      FlutterError.onError = baselineFlutterHandler;
      PlatformDispatcher.instance.onError = baselinePlatformHandler;

      final older = DiagnosticsGlobalErrorBinding.install(_RecordingSink());
      final newer = DiagnosticsGlobalErrorBinding.install(_RecordingSink());
      addTearDown(older.close);
      addTearDown(newer.close);

      older.close();
      expect(FlutterError.onError, isNot(same(baselineFlutterHandler)));
      expect(
        PlatformDispatcher.instance.onError,
        isNot(same(baselinePlatformHandler)),
      );

      newer.close();
      expect(FlutterError.onError, same(baselineFlutterHandler));
      expect(
        PlatformDispatcher.instance.onError,
        same(baselinePlatformHandler),
      );
    });

    test('preserves nested sink bindings through out-of-order teardown', () {
      final baseline = _RecordingSink();
      final baselineBinding = DiagnosticsSink.install(baseline);
      addTearDown(baselineBinding.close);
      final older = _RecordingSink();
      final newer = _RecordingSink();
      final olderBinding = DiagnosticsSink.install(older);
      final newerBinding = DiagnosticsSink.install(newer);
      addTearDown(olderBinding.close);
      addTearDown(newerBinding.close);

      olderBinding.close();
      expect(DiagnosticsSink.current, same(newer));

      newerBinding.close();
      expect(DiagnosticsSink.current, same(baseline));

      final repeated = DiagnosticsSink.install(newer);
      final repeatedAgain = DiagnosticsSink.install(newer);
      addTearDown(repeated.close);
      addTearDown(repeatedAgain.close);
      repeated.close();
      repeatedAgain.close();
      expect(DiagnosticsSink.current, same(baseline));
    });
  });

  group('frame-safe notification', () {
    testWidgets(
      'defers diagnostics changes for errors reported during a frame',
      (tester) async {
        final count = ValueNotifier(0);
        addTearDown(count.dispose);
        final sink = _NotifyingSink(count);
        final forwarded = <FlutterErrorDetails>[];
        FlutterError.onError = forwarded.add;
        final binding = DiagnosticsGlobalErrorBinding.install(sink);
        addTearDown(binding.close);

        tester.binding.addPostFrameCallback((_) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: StateError('paint failure'),
              stack: StackTrace.current,
            ),
          );
        });

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ValueListenableBuilder(
              valueListenable: count,
              builder: (context, value, child) => Text('$value'),
            ),
          ),
        );
        await tester.pump();

        expect(forwarded, hasLength(1));
        expect(sink.records, 1);
        expect(find.text('1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

final class _RecordingSink implements DiagnosticsSink {
  _RecordingSink({this.throwWhenRecording = false});

  final bool throwWhenRecording;
  final List<_RecordedError> records = [];

  @override
  void recordLog({
    required String name,
    String source = 'application',
    String? component,
    String? message,
    Map<String, Object?> attributes = const {},
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? operation,
    String? correlationId,
    bool handled = true,
    bool degraded = false,
  }) {}

  @override
  void reportError(
    Object error,
    StackTrace stackTrace, {
    String? operation,
    String source = 'application',
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    bool handled = true,
    bool degraded = true,
    String? correlationId,
  }) {
    if (throwWhenRecording) throw StateError('diagnostics unavailable');
    records.add(
      _RecordedError(
        error: error,
        stackTrace: stackTrace,
        operation: operation,
        source: source,
        handled: handled,
        degraded: degraded,
      ),
    );
  }
}

final class _NotifyingSink implements DiagnosticsSink {
  _NotifyingSink(this.count);

  final ValueNotifier<int> count;
  int records = 0;

  @override
  void recordLog({
    required String name,
    String source = 'application',
    String? component,
    String? message,
    Map<String, Object?> attributes = const {},
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? operation,
    String? correlationId,
    bool handled = true,
    bool degraded = false,
  }) {}

  @override
  void reportError(
    Object error,
    StackTrace stackTrace, {
    String? operation,
    String source = 'application',
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    bool handled = true,
    bool degraded = true,
    String? correlationId,
  }) {
    records += 1;
    count.value += 1;
  }
}

final class _RecordedError {
  const _RecordedError({
    required this.error,
    required this.stackTrace,
    required this.operation,
    required this.source,
    required this.handled,
    required this.degraded,
  });

  final Object error;
  final StackTrace stackTrace;
  final String? operation;
  final String source;
  final bool handled;
  final bool degraded;
}
