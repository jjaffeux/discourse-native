import 'dart:async';

import 'package:discourse_native/src/plugins/resenha/resenha_media.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_models.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_reconnect.dart';
import 'package:flutter_test/flutter_test.dart';

ResenhaJoinResponse join({
  required ResenhaRoomType roomType,
  required ResenhaRole role,
}) => ResenhaJoinResponse(
  transport: ResenhaTransport.mesh,
  ice: const ResenhaIceConfiguration(servers: [], relayOnly: false),
  room: ResenhaRoom(
    id: 1,
    name: 'Room',
    slug: 'room',
    isPublic: true,
    ephemeral: false,
    type: roomType,
    participants: [ResenhaParticipant(id: 10, username: 'sam', role: role)],
  ),
);

void main() {
  test('stage listeners do not acquire an outgoing audio publication', () {
    final media = const NativeResenhaMediaFactory().create(
      join: join(
        roomType: ResenhaRoomType.stage,
        role: ResenhaRole.participant,
      ),
      localUserId: 10,
      sendSignal: (_, _) async {},
      refreshLiveKitCredentials: () async =>
          const ResenhaLiveKitCredentials(url: '', token: ''),
    );

    expect((media as MeshResenhaMediaSession).audioPublishingAllowed, isFalse);
  });

  test('stage speakers and open-room participants may publish audio', () {
    for (final response in [
      join(roomType: ResenhaRoomType.stage, role: ResenhaRole.speaker),
      join(roomType: ResenhaRoomType.open, role: ResenhaRole.participant),
    ]) {
      final media = const NativeResenhaMediaFactory().create(
        join: response,
        localUserId: 10,
        sendSignal: (_, _) async {},
        refreshLiveKitCredentials: () async =>
            const ResenhaLiveKitCredentials(url: '', token: ''),
      );

      expect((media as MeshResenhaMediaSession).audioPublishingAllowed, isTrue);
    }
  });

  group('ResenhaReconnectCoordinator', () {
    test('rejects an unusable retry schedule in release builds', () {
      ResenhaReconnectCoordinator create(List<Duration> schedule) =>
          ResenhaReconnectCoordinator(
            attempt: () async {},
            onStateChanged: (_) {},
            schedule: schedule,
          );

      expect(() => create(const []), throwsArgumentError);
      expect(
        () => create(const [Duration(milliseconds: -1)]),
        throwsArgumentError,
      );
    });

    test('retries on its schedule and reports recovery', () async {
      var attempts = 0;
      final states = <ResenhaMediaConnectionState>[];
      final timers = <_ManualTimer>[];
      final coordinator = ResenhaReconnectCoordinator(
        attempt: () async {
          attempts++;
          if (attempts == 1) throw StateError('expired token');
        },
        onStateChanged: states.add,
        schedule: const [Duration.zero, Duration(seconds: 3)],
        timerFactory: (delay, callback) {
          final timer = _ManualTimer(delay, callback);
          timers.add(timer);
          return timer;
        },
      );

      final reconnect = coordinator.reconnect();
      await _pumpEventQueue();

      expect(attempts, 1);
      expect(timers, hasLength(1));
      expect(timers.single.delay, const Duration(seconds: 3));
      expect(
        coordinator.connectionState,
        ResenhaMediaConnectionState.reconnecting,
      );

      timers.single.fire();
      await reconnect;

      expect(attempts, 2);
      expect(
        coordinator.connectionState,
        ResenhaMediaConnectionState.connected,
      );
      expect(states, [
        ResenhaMediaConnectionState.reconnecting,
        ResenhaMediaConnectionState.connected,
      ]);
    });

    test('coalesces concurrent disconnect events into one attempt', () async {
      final attemptStarted = Completer<void>();
      final finishAttempt = Completer<void>();
      var attempts = 0;
      final coordinator = ResenhaReconnectCoordinator(
        attempt: () async {
          attempts++;
          attemptStarted.complete();
          await finishAttempt.future;
        },
        onStateChanged: (_) {},
        schedule: const [Duration.zero],
      );

      final first = coordinator.reconnect();
      final second = coordinator.reconnect();
      expect(identical(first, second), isTrue);
      await attemptStarted.future;

      expect(attempts, 1);
      finishAttempt.complete();
      await Future.wait([first, second]);
      expect(
        coordinator.connectionState,
        ResenhaMediaConnectionState.connected,
      );
    });

    test('exhaustion becomes failed without leaking attempt errors', () async {
      var attempts = 0;
      final states = <ResenhaMediaConnectionState>[];
      final coordinator = ResenhaReconnectCoordinator(
        attempt: () async {
          attempts++;
          throw StateError('still offline');
        },
        onStateChanged: states.add,
        schedule: const [Duration.zero, Duration.zero, Duration.zero],
      );

      await coordinator.reconnect();

      expect(attempts, 3);
      expect(coordinator.connectionState, ResenhaMediaConnectionState.failed);
      expect(states, [
        ResenhaMediaConnectionState.reconnecting,
        ResenhaMediaConnectionState.failed,
      ]);
    });

    test('cancel releases backoff and prevents later attempts', () async {
      var attempts = 0;
      final states = <ResenhaMediaConnectionState>[];
      final timers = <_ManualTimer>[];
      final coordinator = ResenhaReconnectCoordinator(
        attempt: () async {
          attempts++;
          throw StateError('offline');
        },
        onStateChanged: states.add,
        schedule: const [Duration.zero, Duration(seconds: 4)],
        timerFactory: (delay, callback) {
          final timer = _ManualTimer(delay, callback);
          timers.add(timer);
          return timer;
        },
      );

      final reconnect = coordinator.reconnect();
      await _pumpEventQueue();
      expect(timers, hasLength(1));

      coordinator.cancel();
      await reconnect;
      timers.single.fire();
      await coordinator.reconnect();

      expect(timers.single.isActive, isFalse);
      expect(attempts, 1);
      expect(
        coordinator.connectionState,
        ResenhaMediaConnectionState.reconnecting,
      );
      expect(states, [ResenhaMediaConnectionState.reconnecting]);
    });

    test('cancel before the immediate rung prevents its attempt', () async {
      var attempts = 0;
      final coordinator = ResenhaReconnectCoordinator(
        attempt: () async {
          attempts++;
        },
        onStateChanged: (_) {},
        schedule: const [Duration.zero],
      );

      final reconnect = coordinator.reconnect();
      coordinator.cancel();
      await reconnect;

      expect(attempts, 0);
      expect(
        coordinator.connectionState,
        ResenhaMediaConnectionState.reconnecting,
      );
    });

    test('cancel suppresses success from an in-flight attempt', () async {
      final attemptStarted = Completer<void>();
      final finishAttempt = Completer<void>();
      final states = <ResenhaMediaConnectionState>[];
      final coordinator = ResenhaReconnectCoordinator(
        attempt: () async {
          attemptStarted.complete();
          await finishAttempt.future;
        },
        onStateChanged: states.add,
        schedule: const [Duration.zero],
      );

      final reconnect = coordinator.reconnect();
      await attemptStarted.future;
      coordinator.cancel();
      finishAttempt.complete();
      await reconnect;

      expect(
        coordinator.connectionState,
        ResenhaMediaConnectionState.reconnecting,
      );
      expect(states, [ResenhaMediaConnectionState.reconnecting]);
    });
  });
}

Future<void> _pumpEventQueue() => Future<void>.delayed(Duration.zero);

final class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}
