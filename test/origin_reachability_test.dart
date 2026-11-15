import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/origin_reachability.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _neverConnected = SocketException("Failed host lookup: 'forum.example'");

void main() {
  final forum = Uri.parse('https://forum.example/latest.json');
  final other = Uri.parse('https://other.example/latest.json');

  late OriginReachability reachability;
  late List<String> changes;
  late List<String> recovered;

  setUp(() {
    reachability = OriginReachability(random: Random(1));
    changes = [];
    recovered = [];
    reachability.addListener(
      () => changes.add(
        reachability.isUrlReachable(forum) ? 'reachable' : 'unreachable',
      ),
    );
    reachability.onRecovered(recovered.add);
  });

  tearDown(() => reachability.dispose());

  test('a connection that never opened marks only its origin unreachable', () {
    reachability.failed(forum, _neverConnected, reachability.dispatched());

    expect(reachability.isUrlReachable(forum), isFalse);
    expect(reachability.isUrlReachable(other), isTrue);
    expect(changes, ['unreachable']);
    expect(recovered, isEmpty);
  });

  test(
    'the next response marks the origin reachable and announces it once',
    () {
      reachability.failed(forum, _neverConnected, reachability.dispatched());
      reachability.succeeded(forum, reachability.dispatched());
      reachability.succeeded(forum, reachability.dispatched());

      expect(reachability.isUrlReachable(forum), isTrue);
      expect(changes, ['unreachable', 'reachable']);
      expect(recovered, ['https://forum.example']);
    },
  );

  test('repeated failures publish one change', () {
    reachability.failed(forum, _neverConnected, reachability.dispatched());
    reachability.failed(forum, _neverConnected, reachability.dispatched());

    expect(changes, ['unreachable']);
  });

  test('failures that may follow an open connection decide nothing', () {
    for (final error in <Object>[
      TimeoutException('slow'),
      const SocketException('Connection reset by peer'),
      const HandshakeException('bad certificate'),
      http.ClientException('closed'),
    ]) {
      reachability.failed(forum, error, reachability.dispatched());
    }

    expect(reachability.isUrlReachable(forum), isTrue);
    expect(changes, isEmpty);
  });

  test('a slow failure cannot overrule a response dispatched after it', () {
    final slowLookup = reachability.dispatched();
    final later = reachability.dispatched();

    reachability.succeeded(forum, later);
    reachability.failed(forum, _neverConnected, slowLookup);

    expect(reachability.isUrlReachable(forum), isTrue);
    expect(changes, isEmpty);
  });

  test('a slow response cannot overrule a failure dispatched after it', () {
    final slowResponse = reachability.dispatched();
    final later = reachability.dispatched();

    reachability.failed(forum, _neverConnected, later);
    reachability.succeeded(forum, slowResponse);

    expect(reachability.isUrlReachable(forum), isFalse);
    expect(recovered, isEmpty);
  });

  test('a removed recovery listener hears nothing', () {
    final heard = <String>[];
    final remove = reachability.onRecovered(heard.add);
    remove();

    reachability.failed(forum, _neverConnected, reachability.dispatched());
    reachability.succeeded(forum, reachability.dispatched());

    expect(heard, isEmpty);
  });

  test('an unreachable origin is probed with a growing, bounded wait', () {
    fakeAsync((async) {
      final probed = <Duration>[];
      final probing = OriginReachability(
        random: Random(1),
        firstProbeDelay: const Duration(seconds: 2),
        maximumProbeDelay: const Duration(seconds: 8),
      );
      probing.probe = (origin) async {
        probed.add(async.elapsed);
        probing.failed(origin, _neverConnected, probing.dispatched());
      };

      probing.failed(forum, _neverConnected, probing.dispatched());
      async.elapse(const Duration(minutes: 1));
      probing.dispose();

      final waits = [
        probed.first.inMilliseconds,
        for (var i = 1; i < probed.length; i++)
          (probed[i] - probed[i - 1]).inMilliseconds,
      ];
      expect(waits.take(4).toList(), [
        inInclusiveRange(_seconds(1.5), _seconds(2.5)),
        inInclusiveRange(_seconds(3), _seconds(5)),
        inInclusiveRange(_seconds(6), _seconds(10)),
        inInclusiveRange(_seconds(6), _seconds(10)),
      ]);
      expect(waits.skip(2), everyElement(lessThanOrEqualTo(_seconds(10))));
    });
  });

  test('a probe that answers ends the probing', () {
    fakeAsync((async) {
      final reachability = OriginReachability(random: Random(1));
      final recovered = <String>[];
      reachability.onRecovered(recovered.add);
      addTearDown(reachability.dispose);
      var probes = 0;
      reachability.probe = (origin) async {
        probes++;
        reachability.succeeded(origin, reachability.dispatched());
      };

      reachability.failed(forum, _neverConnected, reachability.dispatched());
      async.elapse(const Duration(minutes: 5));

      expect(probes, 1);
      expect(recovered, ['https://forum.example']);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a probe that proves nothing is followed by another', () {
    fakeAsync((async) {
      final reachability = OriginReachability(random: Random(1));
      final recovered = <String>[];
      reachability.onRecovered(recovered.add);
      addTearDown(reachability.dispose);
      var probes = 0;
      reachability.probe = (origin) async {
        probes++;
        throw TimeoutException('slow');
      };

      reachability.failed(forum, _neverConnected, reachability.dispatched());
      async.elapse(const Duration(seconds: 30));

      expect(probes, greaterThan(1));
      expect(reachability.isUrlReachable(forum), isFalse);
    });
  });

  test('an origin that never answers stops being probed', () {
    fakeAsync((async) {
      var probes = 0;
      final probing = OriginReachability(random: Random(1), maximumProbes: 3)
        ..probe = (_) async => probes++;

      probing.failed(forum, _neverConnected, probing.dispatched());
      async.elapse(const Duration(hours: 6));

      expect(probes, 3);
      expect(async.pendingTimers, isEmpty);
      expect(probing.isUrlReachable(forum), isFalse);

      probing.probeNow();
      async.flushMicrotasks();
      expect(probes, 4);
      probing.dispose();
    });
  });

  test('a throwing recovery listener cannot fail the request', () async {
    final coordinator = DiscourseRequestCoordinator(reachability: reachability);
    addTearDown(coordinator.close);
    final reported = <Object>[];
    runZonedGuarded(
      () => reachability.onRecovered((_) => throw StateError('listener')),
      (error, _) => reported.add(error),
    );
    reachability.failed(forum, _neverConnected, reachability.dispatched());

    final response = await coordinator.run(
      forum,
      () async => http.Response('', 201),
    );

    expect(response.statusCode, 201);
    expect(reported.single, isA<StateError>());
    expect(recovered, ['https://forum.example']);
  });

  test('probes and listeners do not inherit the reporting request zone', () {
    fakeAsync((async) {
      final reachability = OriginReachability(random: Random(1));
      final recovered = <String>[];
      reachability.onRecovered(recovered.add);
      addTearDown(reachability.dispose);
      final key = Object();
      final seen = <Object?>[];
      reachability.probe = (origin) async {
        seen.add(Zone.current[key]);
        reachability.succeeded(origin, reachability.dispatched());
      };
      reachability.onRecovered((_) => seen.add(Zone.current[key]));

      runZoned(
        () => reachability.failed(
          forum,
          _neverConnected,
          reachability.dispatched(),
        ),
        zoneValues: {key: 'request'},
      );
      async.elapse(const Duration(seconds: 10));

      expect(seen, [null, null]);
    });
  });

  test(
    'a rate-limit answer is in force before recovery is announced',
    () async {
      final coordinator = DiscourseRequestCoordinator(
        reachability: reachability,
      );
      addTearDown(coordinator.close);
      bool? coolingAtRecovery;
      reachability.onRecovered(
        (_) => coolingAtRecovery = coordinator.isCoolingDown(forum),
      );
      reachability.failed(forum, _neverConnected, reachability.dispatched());

      await coordinator.run(forum, () async => http.Response('', 429));

      expect(coolingAtRecovery, isTrue);
    },
  );

  test('a hint probes unreachable origins without waiting', () {
    fakeAsync((async) {
      final reachability = OriginReachability(random: Random(1));
      final recovered = <String>[];
      reachability.onRecovered(recovered.add);
      addTearDown(reachability.dispose);
      final probed = <Uri>[];
      reachability.probe = (origin) async => probed.add(origin);

      reachability.probeNow();
      expect(probed, isEmpty);

      reachability.failed(forum, _neverConnected, reachability.dispatched());
      reachability.probeNow();
      async.flushMicrotasks();

      expect(probed, [Uri.parse('https://forum.example')]);
    });
  });

  test('disposal cancels the pending probe', () {
    fakeAsync((async) {
      final probing = OriginReachability()..probe = (_) async {};
      probing.failed(forum, _neverConnected, probing.dispatched());
      expect(async.pendingTimers, isNotEmpty);

      probing.dispose();

      expect(async.pendingTimers, isEmpty);
    });
  });

  group('fed by the request coordinator', () {
    late DiscourseRequestCoordinator coordinator;

    setUp(() {
      coordinator = DiscourseRequestCoordinator(
        reachability: reachability,
        neverConnectedRetryDelay: () => Duration.zero,
      );
    });

    tearDown(() => coordinator.close());

    test('a write that never connected marks the origin unreachable', () async {
      await expectLater(
        coordinator.run(forum, () => throw _neverConnected),
        throwsA(isA<SocketException>()),
      );

      expect(reachability.isUrlReachable(forum), isFalse);
    });

    test('any response, even a refusal, marks it reachable again', () async {
      reachability.failed(forum, _neverConnected, reachability.dispatched());

      await coordinator.run(forum, () async => http.Response('', 503));

      expect(reachability.isUrlReachable(forum), isTrue);
      expect(recovered, ['https://forum.example']);
    });

    test('responses are ordered by dispatch, not by arrival', () async {
      final slow = Completer<http.Response>();
      final first = coordinator.run(forum, () => slow.future);
      await pumpEventQueue();
      await coordinator.run(forum, () async => http.Response('', 200));

      slow.completeError(_neverConnected);
      await expectLater(first, throwsA(isA<SocketException>()));

      expect(reachability.isUrlReachable(forum), isTrue);
    });
  });
}

int _seconds(double seconds) => (seconds * 1000).round();
