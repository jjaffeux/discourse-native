import 'package:discourse_native/src/plugins/voice/voice_idle.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/manual_scheduler.dart';

typedef _StateChange = ({VoiceIdleState state, bool wasAutoMuted});

final class _Harness {
  _Harness({
    this.thresholds = const (
      idle: Duration(minutes: 5),
      afk: Duration(minutes: 15),
      disconnect: Duration(minutes: 30),
    ),
  }) {
    tracker = VoiceIdleTracker(
      thresholds: () => thresholds,
      onStateChanged: (state, {required wasAutoMuted}) =>
          changes.add((state: state, wasAutoMuted: wasAutoMuted)),
      onAutoMute: () => autoMutes++,
      onDisconnect: () => disconnects++,
      clock: scheduler.now,
      timerFactory: scheduler.createTimer,
    );
  }

  final ManualScheduler scheduler = ManualScheduler();
  late final VoiceIdleTracker tracker;
  VoiceIdleThresholds thresholds;
  final List<_StateChange> changes = [];
  int autoMutes = 0;
  int disconnects = 0;
}

void main() {
  group('voiceIdleThresholds', () {
    test('converts the site ladder to durations', () {
      expect(
        voiceIdleThresholds(
          const VoiceClientConfig(
            idleThresholdMinutes: 3,
            afkAutoMuteThresholdMinutes: 10,
            afkDisconnectThresholdMinutes: 20,
          ),
        ),
        (
          idle: const Duration(minutes: 3),
          afk: const Duration(minutes: 10),
          disconnect: const Duration(minutes: 20),
        ),
      );
    });

    test('disables an earlier stage set at or past a later one', () {
      expect(
        voiceIdleThresholds(
          const VoiceClientConfig(
            idleThresholdMinutes: 15,
            afkAutoMuteThresholdMinutes: 15,
            afkDisconnectThresholdMinutes: 30,
          ),
        ),
        (
          idle: Duration.zero,
          afk: const Duration(minutes: 15),
          disconnect: const Duration(minutes: 30),
        ),
      );
      expect(
        voiceIdleThresholds(
          const VoiceClientConfig(
            idleThresholdMinutes: 5,
            afkAutoMuteThresholdMinutes: 40,
            afkDisconnectThresholdMinutes: 30,
          ),
        ),
        (
          idle: const Duration(minutes: 5),
          afk: Duration.zero,
          disconnect: const Duration(minutes: 30),
        ),
      );
      expect(
        voiceIdleThresholds(
          const VoiceClientConfig(
            idleThresholdMinutes: 30,
            afkAutoMuteThresholdMinutes: 0,
            afkDisconnectThresholdMinutes: 30,
          ),
        ),
        (
          idle: Duration.zero,
          afk: Duration.zero,
          disconnect: const Duration(minutes: 30),
        ),
      );
    });
  });

  group('VoiceIdleTracker', () {
    test('climbs idle, away with an auto-mute, then disconnects', () {
      final harness = _Harness();
      harness.tracker.start();

      harness.scheduler.advance(const Duration(minutes: 4, seconds: 59));
      expect(harness.changes, isEmpty);
      expect(harness.tracker.state, VoiceIdleState.active);

      harness.scheduler.advance(const Duration(seconds: 31));
      expect(harness.changes, [
        (state: VoiceIdleState.idle, wasAutoMuted: false),
      ]);

      harness.scheduler.advance(const Duration(minutes: 10));
      expect(harness.changes.last, (
        state: VoiceIdleState.afk,
        wasAutoMuted: false,
      ));
      expect(harness.autoMutes, 1);
      expect(harness.tracker.wasAutoMuted, isTrue);
      expect(harness.disconnects, 0);

      harness.scheduler.advance(const Duration(minutes: 10));
      expect(harness.autoMutes, 1);
      expect(harness.disconnects, 0);

      harness.scheduler.advance(const Duration(minutes: 5));
      expect(harness.disconnects, 1);
      expect(harness.changes, hasLength(2));
    });

    test('activity restarts the ladder and reports an automatic mute', () {
      final harness = _Harness();
      harness.tracker.start();
      harness.scheduler.advance(const Duration(minutes: 16));
      expect(harness.tracker.state, VoiceIdleState.afk);

      harness.tracker.recordActivity();

      expect(harness.changes.last, (
        state: VoiceIdleState.active,
        wasAutoMuted: true,
      ));
      expect(harness.tracker.state, VoiceIdleState.active);

      harness.scheduler.advance(const Duration(minutes: 14, seconds: 30));
      expect(harness.autoMutes, 1);
      harness.scheduler.advance(const Duration(minutes: 1));
      expect(harness.autoMutes, 2);
    });

    test('a deliberate unmute clears the automatic-mute memory', () {
      final harness = _Harness();
      harness.tracker.start();
      harness.scheduler.advance(const Duration(minutes: 16));
      harness.tracker.wasAutoMuted = false;

      harness.tracker.recordActivity();

      expect(harness.changes.last, (
        state: VoiceIdleState.active,
        wasAutoMuted: false,
      ));
    });

    test('voice activity counts as presence but is throttled', () {
      final harness = _Harness();
      harness.tracker.start();
      harness.scheduler.advance(const Duration(minutes: 5, seconds: 30));
      expect(harness.tracker.state, VoiceIdleState.idle);

      harness.tracker.recordVoiceActivity();
      expect(harness.tracker.state, VoiceIdleState.active);
      expect(harness.changes, hasLength(2));

      // Sampled several times a second while talking: the throttle keeps
      // the activity timestamp from moving until the window passes.
      harness.scheduler.advance(const Duration(seconds: 5));
      harness.tracker.recordVoiceActivity();
      harness.scheduler.advance(const Duration(minutes: 5));
      expect(harness.tracker.state, VoiceIdleState.idle);
    });

    test('repeated interaction produces one state change', () {
      final harness = _Harness();
      harness.tracker.start();
      harness.scheduler.advance(const Duration(minutes: 6));
      expect(harness.tracker.state, VoiceIdleState.idle);

      for (var i = 0; i < 5; i++) {
        harness.tracker.recordActivity();
      }

      expect(
        harness.changes.where(
          (change) => change.state == VoiceIdleState.active,
        ),
        hasLength(1),
      );
    });

    test('zero stages are skipped and the ladder can be disconnect-only', () {
      final harness = _Harness(
        thresholds: (
          idle: Duration.zero,
          afk: Duration.zero,
          disconnect: const Duration(minutes: 2),
        ),
      );
      harness.tracker.start();

      harness.scheduler.advance(const Duration(minutes: 1, seconds: 30));
      expect(harness.changes, isEmpty);
      expect(harness.autoMutes, 0);

      harness.scheduler.advance(const Duration(minutes: 1));
      expect(harness.disconnects, 1);
    });

    test('an entirely disabled ladder never fires', () {
      final harness = _Harness(
        thresholds: (
          idle: Duration.zero,
          afk: Duration.zero,
          disconnect: Duration.zero,
        ),
      );
      harness.tracker.start();

      harness.scheduler.advance(const Duration(hours: 5));

      expect(harness.changes, isEmpty);
      expect(harness.autoMutes, 0);
      expect(harness.disconnects, 0);
    });

    test('reads the thresholds on every check so setting changes apply', () {
      final harness = _Harness();
      harness.tracker.start();
      harness.scheduler.advance(const Duration(minutes: 4));
      harness.thresholds = (
        idle: const Duration(minutes: 1),
        afk: Duration.zero,
        disconnect: Duration.zero,
      );

      harness.scheduler.advance(const Duration(seconds: 30));

      expect(harness.tracker.state, VoiceIdleState.idle);
    });

    test('stop cancels the check and ignores later activity', () {
      final harness = _Harness();
      harness.tracker.start();
      harness.scheduler.advance(const Duration(minutes: 6));

      harness.tracker.stop();
      harness.tracker.recordActivity();
      harness.scheduler.advance(const Duration(hours: 1));

      expect(harness.tracker.running, isFalse);
      expect(harness.tracker.state, VoiceIdleState.active);
      expect(harness.scheduler.activeTimerCount, 0);
      expect(harness.changes, [
        (state: VoiceIdleState.idle, wasAutoMuted: false),
      ]);
      expect(harness.disconnects, 0);
    });

    test('restarting begins a fresh ladder from now', () {
      final harness = _Harness();
      harness.tracker.start();
      harness.scheduler.advance(const Duration(minutes: 16));
      harness.tracker.stop();
      harness.changes.clear();

      harness.tracker.start();
      harness.scheduler.advance(const Duration(minutes: 4));

      expect(harness.tracker.state, VoiceIdleState.active);
      expect(harness.tracker.wasAutoMuted, isFalse);
      expect(harness.changes, isEmpty);
    });
  });
}
