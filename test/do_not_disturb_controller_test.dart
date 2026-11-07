import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/shell/do_not_disturb_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  test(
    'retirement releases pause state and permits independent replacement writes',
    () async {
      final oldReply = Completer<void>();
      final newReply = Completer<void>();
      addTearDown(() {
        if (!oldReply.isCompleted) oldReply.complete();
        if (!newReply.isCompleted) newReply.complete();
      });
      final lifecycle = SiteLifecycle();
      final api = _Api()..pauseGate = oldReply;
      final controller = _controller(api, lifecycle: lifecycle)
        ..restoreSnapshot(_siteUrl, DateTime.utc(2035));
      addTearDown(controller.dispose);
      final old = controller.pause(
        _siteUrl,
        DoNotDisturbOption.halfHour.duration,
      );
      await pumpEventQueue();
      lifecycle.invalidate(_siteUrl);
      expect(controller.stateFor(_siteUrl).until, isNull);
      expect(controller.stateFor(_siteUrl).saving, isFalse);
      api.pauseGate = newReply;
      final replacement = controller.pause(
        _siteUrl,
        DoNotDisturbOption.oneHour.duration,
      );
      await pumpEventQueue();
      expect(api.pauseDurations, hasLength(2));
      oldReply.complete();
      await old;
      expect(controller.stateFor(_siteUrl).saving, isTrue);
      newReply.complete();
      expect(await replacement, isNull);
      expect(controller.stateFor(_siteUrl).saving, isFalse);
    },
  );

  test(
    'a live pause invalidation callback cannot publish into its successor',
    () {
      final lifecycle = SiteLifecycle();
      final committed = <DateTime?>[];
      late DoNotDisturbController controller;
      var rotated = false;
      final successorUntil = DateTime.utc(2036);
      controller = _controller(
        _Api(),
        lifecycle: lifecycle,
        onCommitted: (_, until) => committed.add(until),
        onSnapshotInvalidated: (_) {
          if (rotated) return;
          rotated = true;
          lifecycle.invalidate(_siteUrl);
          controller.restoreSnapshot(_siteUrl, successorUntil);
        },
      );
      addTearDown(controller.dispose);
      controller.applyMessage(_siteUrl, {
        'ends_at': DateTime.utc(2035).toIso8601String(),
      });
      expect(controller.stateFor(_siteUrl).until, successorUntil);
      expect(committed, isEmpty);
    },
  );

  test(
    'write cleanup cannot release a successor started by its invalidation hook',
    () async {
      final firstReply = Completer<void>();
      final secondReply = Completer<void>();
      addTearDown(() {
        if (!firstReply.isCompleted) firstReply.complete();
        if (!secondReply.isCompleted) secondReply.complete();
      });
      final lifecycle = SiteLifecycle();
      final api = _Api()..pauseGate = firstReply;
      late DoNotDisturbController controller;
      Future<String?>? successor;
      var invalidations = 0;
      controller = _controller(
        api,
        lifecycle: lifecycle,
        onSnapshotInvalidated: (_) {
          if (++invalidations != 2) return;
          lifecycle.invalidate(_siteUrl);
          controller.forget(_siteUrl);
          api.pauseGate = secondReply;
          successor = controller.pause(
            _siteUrl,
            DoNotDisturbOption.oneHour.duration,
          );
        },
      );
      addTearDown(controller.dispose);
      final initial = controller.pause(
        _siteUrl,
        DoNotDisturbOption.halfHour.duration,
      );
      await pumpEventQueue();
      firstReply.complete();
      await initial;
      await pumpEventQueue();
      expect(api.pauseDurations, hasLength(2));
      expect(controller.stateFor(_siteUrl).saving, isTrue);
      secondReply.complete();
      expect(await successor, isNull);
      expect(controller.stateFor(_siteUrl).saving, isFalse);
    },
  );

  testWidgets('retirement cancels the old pause expiry timer', (tester) async {
    final now = DateTime.utc(2030);
    final lifecycle = SiteLifecycle();
    final committed = <DateTime?>[];
    final controller = _controller(
      _Api(),
      lifecycle: lifecycle,
      clock: () => now,
      onCommitted: (_, until) => committed.add(until),
    )..restoreSnapshot(_siteUrl, now.add(const Duration(seconds: 10)));
    addTearDown(controller.dispose);
    lifecycle.invalidate(_siteUrl);
    await tester.pump(const Duration(seconds: 11));
    expect(committed, isEmpty);
    expect(controller.stateFor(_siteUrl).until, isNull);
  });

  for (final expires in [false, true]) {
    test(
      'a newer live snapshot during ${expires ? 'expiry' : 'live'} invalidation wins',
      () {
        var now = DateTime.utc(2030);
        final newer = now.add(const Duration(hours: 2));
        final committed = <DateTime?>[];
        late DoNotDisturbController controller;
        var reentered = false;
        controller = _controller(
          _Api(),
          clock: () => now,
          onCommitted: (_, until) => committed.add(until),
          onSnapshotInvalidated: (_) {
            if (reentered) return;
            reentered = true;
            controller.applyMessage(_siteUrl, {
              'ends_at': newer.toIso8601String(),
            });
          },
        );
        addTearDown(controller.dispose);
        if (expires) {
          controller.restoreSnapshot(
            _siteUrl,
            now.add(const Duration(minutes: 1)),
          );
          now = now.add(const Duration(minutes: 2));
          controller.checkExpirations();
        } else {
          controller.applyMessage(_siteUrl, {
            'ends_at': now.add(const Duration(hours: 1)).toIso8601String(),
          });
        }
        expect(controller.stateFor(_siteUrl).until, newer);
        expect(committed, [newer]);
      },
    );
  }

  testWidgets(
    'an earlier retirement observer preserves the successor pause timer',
    (tester) async {
      final now = DateTime.utc(2030);
      final lifecycle = SiteLifecycle();
      final committed = <DateTime?>[];
      late DoNotDisturbController controller;
      final successorUntil = now.add(const Duration(seconds: 20));
      lifecycle.capture(_siteUrl).onRetire(() {
        controller.restoreSnapshot(_siteUrl, successorUntil);
      });
      controller = _controller(
        _Api(),
        lifecycle: lifecycle,
        clock: () => now,
        onCommitted: (_, until) => committed.add(until),
      )..restoreSnapshot(_siteUrl, now.add(const Duration(seconds: 10)));
      addTearDown(controller.dispose);
      lifecycle.invalidate(_siteUrl);
      await tester.pump(const Duration(seconds: 11));
      expect(controller.stateFor(_siteUrl).until, successorUntil);
      expect(committed, isEmpty);
      await tester.pump(const Duration(seconds: 10));
      expect(controller.stateFor(_siteUrl).until, isNull);
      expect(committed, [null]);
    },
  );

  test('exposes core pause options and exact wire durations', () {
    expect(DoNotDisturbOption.values.map((option) => option.label), [
      '30 minutes',
      '1 hour',
      '2 hours',
      'Until tomorrow',
    ]);
    expect(
      DoNotDisturbOption.values.map((option) => option.duration.wireValue),
      [30, 60, 120, 'tomorrow'],
    );
  });

  test('matches core eternal-day and remaining-label semantics', () {
    expect(isEternalDoNotDisturb(DateTime.utc(3000, 1, 1, 23, 59)), isTrue);
    expect(isEternalDoNotDisturb(DateTime.utc(2999, 12, 31, 23, 59)), isFalse);
    expect(
      doNotDisturbRemainingLabel(
        DateTime.utc(2030, 1, 1, 14),
        now: DateTime.utc(2030, 1, 1, 12),
      ),
      '2h',
    );
  });

  test('commits the server expiration and resumes', () async {
    final api = _Api()..pauseResponse = DateTime.utc(2030, 1, 2, 3, 4, 5);
    final committed = <DateTime?>[];
    final controller = _controller(
      api,
      onCommitted: (_, until) => committed.add(until),
    );
    addTearDown(controller.dispose);

    expect(
      await controller.pause(_siteUrl, DoNotDisturbOption.halfHour.duration),
      isNull,
    );
    expect(api.pauseDurations.single.wireValue, 30);
    expect(
      controller.stateFor(_siteUrl).until,
      DateTime.utc(2030, 1, 2, 3, 4, 5),
    );

    expect(await controller.resume(_siteUrl), isNull);
    expect(api.resumeCalls, 1);
    expect(controller.stateFor(_siteUrl).until, isNull);
    expect(committed, [DateTime.utc(2030, 1, 2, 3, 4, 5), null]);
  });

  test('a refused resume leaves the confirmed pause intact', () async {
    final until = DateTime.utc(2030, 1, 2, 3, 4, 5);
    final api = _Api()
      ..failure = const WriteException(
        WriteFailure.validation,
        errors: ['Pause could not be removed'],
      );
    final committed = <DateTime?>[];
    final controller = _controller(
      api,
      onCommitted: (_, value) => committed.add(value),
    )..restoreSnapshot(_siteUrl, until);
    addTearDown(controller.dispose);

    expect(await controller.resume(_siteUrl), 'Pause could not be removed');
    expect(controller.stateFor(_siteUrl).until, until);
    expect(controller.stateFor(_siteUrl).saving, isFalse);
    expect(committed, isEmpty);
  });

  test('session rotation discards a stale pause completion', () async {
    final gate = Completer<void>();
    final lifecycle = SiteLifecycle();
    final api = _Api()
      ..pauseGate = gate
      ..pauseResponse = DateTime.utc(2040);
    final committed = <DateTime?>[];
    final invalidations = <String>[];
    final controller = _controller(
      api,
      lifecycle: lifecycle,
      onCommitted: (_, until) => committed.add(until),
      onSnapshotInvalidated: invalidations.add,
    );
    addTearDown(controller.dispose);

    final write = controller.pause(
      _siteUrl,
      DoNotDisturbOption.oneHour.duration,
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.stateFor(_siteUrl).saving, isTrue);

    lifecycle.invalidate(_siteUrl);
    gate.complete();

    expect(await write, isNull);
    expect(controller.stateFor(_siteUrl).until, isNull);
    expect(committed, isEmpty);
    expect(invalidations, [_siteUrl]);
  });

  test(
    'forget releases a pending change even when the account was paused',
    () async {
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      final firstReply = Completer<void>();
      final secondReply = Completer<void>();
      addTearDown(() {
        if (!firstReply.isCompleted) firstReply.complete();
        if (!secondReply.isCompleted) secondReply.complete();
      });
      final api = _Api()
        ..pauseGate = firstReply
        ..onPause = firstStarted.complete
        ..pauseResponse = DateTime.utc(2040);
      final committed = <DateTime?>[];
      final controller = _controller(
        api,
        onCommitted: (_, until) => committed.add(until),
      )..restoreSnapshot(_siteUrl, DateTime.utc(2030));
      addTearDown(controller.dispose);

      final first = controller.pause(
        _siteUrl,
        DoNotDisturbOption.oneHour.duration,
      );
      await firstStarted.future;
      controller.forget(_siteUrl);
      expect(controller.stateFor(_siteUrl).saving, isFalse);
      expect(controller.stateFor(_siteUrl).until, isNull);

      api
        ..pauseGate = secondReply
        ..onPause = secondStarted.complete;
      final second = controller.pause(
        _siteUrl,
        DoNotDisturbOption.twoHours.duration,
      );
      await secondStarted.future;
      firstReply.complete();
      expect(await first, isNull);
      expect(controller.stateFor(_siteUrl).saving, isTrue);
      expect(committed, isEmpty);
      secondReply.complete();
      expect(await second, isNull);
      expect(committed, [DateTime.utc(2040)]);
      expect(controller.stateFor(_siteUrl).saving, isFalse);
    },
  );

  test(
    'a rejected first change still accepts later account snapshots',
    () async {
      final api = _Api()
        ..failure = const WriteException(
          WriteFailure.validation,
          errors: ['Not saved'],
        );
      final controller = _controller(api);
      addTearDown(controller.dispose);

      expect(
        await controller.pause(_siteUrl, DoNotDisturbOption.oneHour.duration),
        'Not saved',
      );
      final until = DateTime.utc(2030);
      expect(
        controller.acceptSnapshot(_siteUrl, until, isCurrent: true),
        until,
      );
      expect(controller.stateFor(_siteUrl).until, until);
    },
  );

  test(
    'a live update during a rejected change wins over older snapshots',
    () async {
      final started = Completer<void>();
      final reply = Completer<void>();
      final api = _Api()
        ..pauseGate = reply
        ..onPause = started.complete
        ..failure = const WriteException(
          WriteFailure.validation,
          errors: ['Not saved'],
        );
      final controller = _controller(api);
      addTearDown(controller.dispose);

      final pause = controller.pause(
        _siteUrl,
        DoNotDisturbOption.oneHour.duration,
      );
      await started.future;
      controller.applyMessage(_siteUrl, const {
        'ends_at': '2030-01-01T00:00:00Z',
      });
      reply.complete();
      expect(await pause, 'Not saved');
      expect(
        controller.acceptSnapshot(_siteUrl, null, isCurrent: false),
        DateTime.utc(2030),
      );
      expect(
        controller.acceptSnapshot(_siteUrl, null, isCurrent: true),
        isNull,
      );
    },
  );

  test('pending writes reject snapshots even with a current ticket', () async {
    final started = Completer<void>();
    final reply = Completer<void>();
    final confirmedUntil = DateTime.utc(2030);
    final api = _Api()
      ..pauseGate = reply
      ..onPause = started.complete
      ..pauseResponse = DateTime.utc(2040);
    final controller = _controller(api)
      ..restoreSnapshot(_siteUrl, confirmedUntil);
    addTearDown(controller.dispose);
    addTearDown(() {
      if (!reply.isCompleted) reply.complete();
    });

    final pause = controller.pause(
      _siteUrl,
      DoNotDisturbOption.oneHour.duration,
    );
    await started.future;
    expect(
      controller.acceptSnapshot(_siteUrl, null, isCurrent: true),
      confirmedUntil,
    );
    reply.complete();
    expect(await pause, isNull);
    expect(controller.stateFor(_siteUrl).until, DateTime.utc(2040));
    expect(
      controller.acceptSnapshot(_siteUrl, null, isCurrent: false),
      DateTime.utc(2040),
    );
    expect(controller.acceptSnapshot(_siteUrl, null, isCurrent: true), isNull);
  });

  test('a live update supersedes an older in-flight response', () async {
    final gate = Completer<void>();
    final api = _Api()
      ..pauseGate = gate
      ..pauseResponse = DateTime.utc(2040);
    final controller = _controller(api);
    addTearDown(controller.dispose);

    final write = controller.pause(
      _siteUrl,
      DoNotDisturbOption.twoHours.duration,
    );
    await Future<void>.delayed(Duration.zero);
    controller.applyMessage(_siteUrl, const {
      'ends_at': 'Wed, 28 Aug 2030 12:00:00 GMT',
    });
    gate.complete();
    await write;

    expect(controller.stateFor(_siteUrl).until, DateTime.utc(2030, 8, 28, 12));
  });

  group('live-message dates', () {
    for (final value in [
      '',
      'not a date',
      '2030-01-01T',
      'Wed, 28 Bog 2030 12:00:00 GMT',
      'Wed, 28 Aug 2030 12:00:00',
      'Wed, 28 Aug 2030 12:00:00 GMT trailing',
    ]) {
      test('ignores malformed "$value" without changing state', () {
        final until = DateTime.utc(2030, 1, 2);
        final committed = <DateTime?>[];
        final controller = _controller(
          _Api(),
          clock: () => DateTime.utc(2030),
          onCommitted: (_, value) => committed.add(value),
        )..restoreSnapshot(_siteUrl, until);
        addTearDown(controller.dispose);
        var notifications = 0;
        controller.addListener(() => notifications++);

        controller.applyMessage(_siteUrl, {'ends_at': value});

        expect(controller.stateFor(_siteUrl).until, until);
        expect(controller.stateFor(_siteUrl).saving, isFalse);
        expect(committed, isEmpty);
        expect(notifications, 0);

        // Invalid messages must not become authoritative over snapshots.
        final nextUntil = until.add(const Duration(hours: 1));
        expect(
          controller.acceptSnapshot(_siteUrl, nextUntil, isCurrent: true),
          nextUntil,
        );
      });
    }

    for (final value in [
      '2030-08-28T12:00:00Z',
      '2030-08-28T14:00:00+02:00',
      'Wed, 28 Aug 2030 12:00:00 GMT',
      'Wed Aug 28 12:00:00 2030',
    ]) {
      test('commits a valid date "$value" in UTC', () {
        final committed = <DateTime?>[];
        final controller = _controller(
          _Api(),
          clock: () => DateTime.utc(2030),
          onCommitted: (_, until) => committed.add(until),
        );
        addTearDown(controller.dispose);
        var notifications = 0;
        controller.addListener(() => notifications++);

        controller.applyMessage(_siteUrl, {'ends_at': value});

        final until = DateTime.utc(2030, 8, 28, 12);
        expect(controller.stateFor(_siteUrl).until, until);
        expect(controller.stateFor(_siteUrl).until!.isUtc, isTrue);
        expect(committed, [until]);
        expect(notifications, 1);
      });
    }

    test('null clears the pause and commits the change', () {
      final committed = <DateTime?>[];
      final controller = _controller(
        _Api(),
        clock: () => DateTime.utc(2030),
        onCommitted: (_, until) => committed.add(until),
      )..restoreSnapshot(_siteUrl, DateTime.utc(2030, 1, 2));
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.applyMessage(_siteUrl, const {'ends_at': null});

      expect(controller.stateFor(_siteUrl).until, isNull);
      expect(committed, [null]);
      expect(notifications, 1);
    });
  });

  test('foreground expiration clears persisted display state', () {
    var now = DateTime.utc(2030, 1, 1, 12);
    final committed = <DateTime?>[];
    final controller = _controller(
      _Api(),
      clock: () => now,
      onCommitted: (_, until) => committed.add(until),
    )..restoreSnapshot(_siteUrl, now.add(const Duration(minutes: 30)));
    addTearDown(controller.dispose);

    now = now.add(const Duration(minutes: 31));
    controller.checkExpirations();

    expect(controller.stateFor(_siteUrl).until, isNull);
    expect(committed, [null]);
  });
}

DoNotDisturbController _controller(
  _Api api, {
  SiteLifecycle? lifecycle,
  DateTime Function()? clock,
  DoNotDisturbCommitted? onCommitted,
  void Function(String siteUrl)? onSnapshotInvalidated,
}) => DoNotDisturbController(
  api: api,
  credentials: _Credentials(),
  lifecycle: lifecycle ?? SiteLifecycle(),
  clock: clock,
  onCommitted: onCommitted ?? (_, _) {},
  onSnapshotInvalidated: onSnapshotInvalidated,
);

final class _Credentials implements ApiCredentialReader {
  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'api-key';

  @override
  Future<String> clientId() async => 'client-id';
}

final class _Api implements DoNotDisturbApi {
  DateTime pauseResponse = DateTime.utc(2030);
  Completer<void>? pauseGate;
  void Function()? onPause;
  WriteException? failure;
  final List<DoNotDisturbDuration> pauseDurations = [];
  int resumeCalls = 0;

  @override
  Future<DateTime> enterDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    required DoNotDisturbDuration duration,
    String? clientId,
  }) async {
    pauseDurations.add(duration);
    onPause?.call();
    await pauseGate?.future;
    if (failure case final error?) throw error;
    return pauseResponse;
  }

  @override
  Future<void> leaveDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    resumeCalls++;
    if (failure case final error?) throw error;
  }
}
