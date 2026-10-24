import 'dart:async';

import 'package:discourse_native/src/plugin_api/live_channels.dart';
import 'package:discourse_native/src/plugins/voice/voice_callkit.dart';
import 'package:discourse_native/src/plugins/voice/voice_incoming_calls.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/manual_scheduler.dart';

const _site = 'https://voice.example.com';
final _now = DateTime.utc(2026, 8, 8, 16, 0, 10);
final _room = VoiceRoom.fromJson(const {
  'id': 9,
  'slug': 'call-1a2b',
  'name': 'Kim and Sam',
  'ephemeral': true,
  'room_type': 'open',
});

void main() {
  test(
    'close cancels the ring synchronously and memoizes subscription drain',
    () async {
      final harness = _Harness();
      harness.ring();
      await pumpEventQueue();
      final closing = harness.owner.close();
      expect(harness.owner.close(), same(closing));
      expect(harness.owner.call, isNull);
      expect(harness.scheduler.activeTimerCount, 0);
      expect(harness.tracker.subscription.cancelCount, 1);
      expect(harness.system.ends, [VoiceIncomingCallEndReason.unanswered]);
      var closed = false;
      unawaited(closing.then((_) => closed = true));
      await pumpEventQueue();
      expect(closed, isFalse);
      harness.ring(sentAt: 1786204815);
      expect(harness.owner.call, isNull);
      harness.tracker.subscription.drained.complete();
      await closing;
      expect(harness.tracker.subscription.cancelCount, 1);
    },
  );

  for (final retirement in ['account', 'join', 'replacement', 'close']) {
    test('a held answer cannot continue after $retirement', () async {
      final harness = _Harness();
      addTearDown(harness.close);
      harness.resolveGate = Completer<VoiceRoom?>();
      harness.ring();
      final answering = harness.owner.answerFromSystem();
      await pumpEventQueue();
      await harness.owner.answerFromSystem();
      expect(harness.resolutions, 1);
      switch (retirement) {
        case 'account':
          harness.account = Object();
        case 'join':
          harness.admissionIdentity = Object();
        case 'replacement':
          harness.ring(sentAt: 1786204815);
        case 'close':
          unawaited(harness.owner.close());
      }
      harness.resolveGate!.complete(_room);
      await answering;
      expect(harness.attributions, 0);
      expect(harness.navigations, 0);
      expect(harness.joined, isEmpty);
      expect(harness.system.failures, 0);
      if (retirement == 'account') {
        await harness.owner.answerFromSystem();
        expect(harness.system.failures, 0);
      }
    });
  }

  test('a fresh join invalidates acceptance before media exists', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    harness.ring();
    final accepted = await harness.owner.accept();
    expect(accepted?.isCurrent, isTrue);
    expect(harness.attributions, 1);
    expect(harness.scheduler.activeTimerCount, 0);
    harness.admissionIdentity = Object();
    expect(harness.hasCallOrPendingJoin, isFalse);
    expect(accepted?.isCurrent, isFalse);
  });

  test('navigation retirement prevents admitted join', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    harness.navigationGate = Completer<String?>();
    harness.ring();
    final answering = harness.owner.answerFromSystem();
    await pumpEventQueue();
    expect(harness.navigations, 1);
    harness.account = Object();
    harness.navigationGate!.complete('Voice');
    await answering;
    expect(harness.joined, isEmpty);
    expect(harness.system.failures, 0);
  });

  test(
    'late presentation after close cannot touch the borrowed bridge',
    () async {
      final harness = _Harness();
      harness.system.presentation = Completer<bool>();
      harness.ring();
      await harness.close();
      harness.system.presentation!.complete(true);
      await pumpEventQueue();
      expect(harness.system.ends, isEmpty);
      expect(harness.owner.call, isNull);
    },
  );

  test(
    'reentrant acceptance during ring publication owns late presentation',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      Future<VoiceIncomingCallAcceptance?>? accepting;
      harness.onChanged = () => accepting ??= harness.owner.accept();
      harness.ring();
      final accepted = await accepting;
      await pumpEventQueue();
      expect(accepted?.isCurrent, isTrue);
      expect(harness.owner.call, isNull);
      expect(harness.scheduler.activeTimerCount, 0);
      expect(harness.system.ends, [VoiceIncomingCallEndReason.unanswered]);
      expect(harness.attributions, 1);
    },
  );
}

final class _Harness
    implements VoiceIncomingRooms, VoiceIncomingJoins, VoiceIncomingNavigation {
  _Harness() {
    owner = VoiceIncomingCalls(
      rooms: this,
      joins: this,
      navigation: this,
      systemCall: system,
      onChanged: () => onChanged?.call(),
      clock: () => _now,
      timerFactory: scheduler.createTimer,
    );
    owner.attach(_site, 1, tracker);
  }

  late final VoiceIncomingCalls owner;
  final tracker = _Tracker();
  final system = _SystemCall();
  final scheduler = ManualScheduler();
  Object account = Object();
  @override
  Object? admissionIdentity;
  @override
  bool hasCallOrPendingJoin = false;
  int resolutions = 0;
  int attributions = 0;
  int navigations = 0;
  final joined = <VoiceIncomingCallAcceptance>[];
  Completer<VoiceRoom?>? resolveGate;
  Completer<String?>? navigationGate;
  void Function()? onChanged;

  void ring({int sentAt = 1786204800}) => tracker.deliver({
    'room_id': 9,
    'room_slug': 'call-1a2b',
    'room_name': 'Kim and Sam',
    'caller_username': 'Kim',
    'sent_at': sentAt,
    'ring_seconds': 60,
  });

  Future<void> close() {
    if (!tracker.subscription.drained.isCompleted) {
      tracker.subscription.drained.complete();
    }
    return owner.close();
  }

  @override
  bool Function() captureAccount(String siteUrl) {
    final captured = account;
    return () => identical(captured, account);
  }

  @override
  Future<VoiceRoom?> resolve(
    String siteUrl,
    String slug, {
    required bool Function() ifCurrent,
  }) async {
    resolutions++;
    return resolveGate?.future ?? _room;
  }

  @override
  void rememberCaller(String siteUrl, VoiceIncomingCall call) => attributions++;

  @override
  bool isInRoom(String siteUrl, int roomId) => false;

  @override
  Future<void> join(
    VoiceIncomingCallAcceptance acceptance, {
    required String siteName,
  }) async => joined.add(acceptance);

  @override
  FutureOr<String?> prepare(VoiceIncomingCallAcceptance acceptance) {
    navigations++;
    return navigationGate?.future ?? 'Voice';
  }
}

final class _Tracker implements PluginLiveChannelHandle {
  final subscription = _Subscription();
  void Function(Object?, int)? _onMessage;

  void deliver(Object data) => _onMessage?.call(data, 1);

  @override
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    _onMessage = onMessage;
    return subscription;
  }
}

final class _Subscription
    implements
        PluginLiveChannelSubscription,
        VoiceAwaitableSubscriptionTeardown {
  int cancelCount = 0;
  final drained = Completer<void>();
  @override
  void cancel() => cancelCount++;
  @override
  Future<void> cancelAndWait() {
    cancel();
    return drained.future;
  }
}

final class _SystemCall implements VoiceSystemCall {
  Completer<bool>? presentation;
  final ends = <VoiceIncomingCallEndReason>[];
  int failures = 0;
  @override
  Stream<VoiceSystemCallAction> get actions => const Stream.empty();
  @override
  Future<bool> reportIncomingCall({
    required String callerName,
    required String roomName,
    required String handle,
  }) async => presentation?.future ?? true;
  @override
  Future<void> endIncomingCall(VoiceIncomingCallEndReason reason) async =>
      ends.add(reason);
  @override
  Future<void> answerIncomingCall() async {}
  @override
  Future<void> declineIncomingCall() async {}
  @override
  Future<void> failed() async => failures++;
  @override
  Future<void> start({
    required String roomName,
    required String siteName,
  }) async {}
  @override
  Future<void> connected() async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> end() async {}
  @override
  Future<void> dispose() async {}
}
