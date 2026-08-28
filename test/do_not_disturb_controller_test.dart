import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/shell/do_not_disturb_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
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

  test('matches core eternal-day and custom-status minute semantics', () {
    expect(isEternalDoNotDisturb(DateTime.utc(3000, 1, 1, 23, 59)), isTrue);
    expect(isEternalDoNotDisturb(DateTime.utc(2999, 12, 31, 23, 59)), isFalse);
    expect(
      doNotDisturbDurationUntil(
        DateTime.utc(2030, 1, 1, 12, 30, 59),
        now: DateTime.utc(2030, 1, 1, 12),
      ).wireValue,
      30,
    );
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
    final controller = _controller(
      api,
      lifecycle: lifecycle,
      onCommitted: (_, until) => committed.add(until),
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
}) => DoNotDisturbController(
  api: api,
  credentials: _Credentials(),
  lifecycle: lifecycle ?? SiteLifecycle(),
  clock: clock,
  onCommitted: onCommitted ?? (_, _) {},
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
