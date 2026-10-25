import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart'
    show PluginLiveChannelHandle, PluginLiveChannelSubscription;
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
    harness.navigationGate = Completer<VoiceSystemAnswerPlan?>();
    harness.ring();
    final answering = harness.owner.answerFromSystem();
    await pumpEventQueue();
    expect(harness.navigations, 1);
    harness.account = Object();
    harness.navigationGate!.complete((siteName: 'Voice', confirmInApp: false));
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

  test('the system names the caller by username and site', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    harness.ring();
    await pumpEventQueue();
    expect(harness.system.reported, [
      (callerName: '@Kim · voice.example.com', handle: 'Kim@voice.example.com'),
    ]);
  });

  test('detaching the ringing site ends its ring', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    harness.ring();
    await pumpEventQueue();
    expect(harness.owner.handledBySystem, isTrue);

    harness.owner.detach(_site);
    await pumpEventQueue();
    expect(harness.owner.call, isNull);
    expect(harness.system.ends, [VoiceIncomingCallEndReason.unanswered]);
    expect(harness.scheduler.activeTimerCount, 0);
    expect(harness.tracker.subscription.cancelCount, 1);
  });

  for (final presented in [true, false]) {
    test('an in-app answer takes over the system ring only when the system '
        '${presented ? 'presented' : 'declined to present'} it', () async {
      final harness = _Harness();
      addTearDown(harness.close);
      harness.system.presentation = Completer<bool>()..complete(presented);
      harness.ring();
      await pumpEventQueue();

      final accepted = await harness.owner.accept();
      expect(accepted?.isCurrent, isTrue);
      expect(harness.system.answers, presented ? 1 : 0);
    });
  }

  test('joining another room leaves the ring alone', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    harness.ring();
    await pumpEventQueue();

    harness.owner.roomJoined(_site, 10);
    expect(harness.owner.call?.roomId, 9);
    harness.owner.roomJoined(_site, 9);
    await pumpEventQueue();
    expect(harness.owner.call, isNull);
    expect(harness.system.ends, [VoiceIncomingCallEndReason.answeredElsewhere]);
  });

  test('retiring an answer that was not waiting publishes nothing', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    var changes = 0;
    harness.ring();
    await harness.owner.accept();
    harness.onChanged = () => changes++;

    harness.owner.retireAnswer();
    expect(changes, 0);
  });

  test('hanging up a parked answer spares an answer still joining', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    harness.ring();
    await pumpEventQueue();
    final accepted = await harness.owner.accept();

    harness.owner.cancelAwaitingAnswer();
    await pumpEventQueue();
    expect(accepted?.isCurrent, isTrue);
    expect(harness.system.hangUps, 0);
  });

  for (final (ringSeconds, rings) in [(10, false), (11, true)]) {
    test('a ring ${rings ? 'with time left' : 'whose window ends now'} '
        '${rings ? 'rings' : 'is dropped'}', () async {
      final harness = _Harness();
      addTearDown(harness.close);
      harness.ring(ringSeconds: ringSeconds);
      await pumpEventQueue();
      expect(harness.owner.call != null, rings);
      expect(harness.system.reported, hasLength(rings ? 1 : 0));
    });
  }

  test('a newer ring ends the ring the system is showing', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    harness.ring();
    await pumpEventQueue();

    harness.ring(sentAt: 1786204805);
    await pumpEventQueue();
    expect(harness.owner.call?.sentAt, DateTime.utc(2026, 8, 8, 16, 0, 5));
    expect(harness.system.ends, [VoiceIncomingCallEndReason.unanswered]);
    expect(harness.system.reported, hasLength(2));
  });

  test('a redelivered earlier ring cannot replace a newer one', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    harness.ring();
    harness.ring(sentAt: 1786204805);
    await pumpEventQueue();

    harness.ring();
    await pumpEventQueue();
    expect(harness.owner.call?.sentAt, DateTime.utc(2026, 8, 8, 16, 0, 5));
    expect(harness.system.reported, hasLength(2));
  });

  test('a ring never outlives one window, whatever it claims', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    harness.ring(sentAt: 1786204800 + 3600, ringSeconds: 86400);
    await pumpEventQueue();
    harness.scheduler.advance(const Duration(seconds: 59));
    expect(harness.owner.call, isNotNull);
    harness.scheduler.advance(const Duration(seconds: 1));
    expect(harness.owner.call, isNull);
    expect(harness.system.ends, [VoiceIncomingCallEndReason.unanswered]);
  });

  group('a system answer that needs the privacy warning', () {
    late _Harness harness;
    late int changes;

    setUp(() async {
      harness = _Harness()..confirmInApp = true;
      changes = 0;
      harness.onChanged = () => changes++;
      harness.ring();
      await pumpEventQueue();
      await harness.owner.answerFromSystem();
    });

    tearDown(() => harness.close());

    test('opens the room and waits for the app without joining', () async {
      expect(harness.navigations, 1);
      expect(harness.joined, isEmpty);
      final awaiting = harness.owner.awaitingConfirmation;
      expect(
        (room: awaiting?.room.id, caller: awaiting?.call.caller.username),
        (room: 9, caller: 'Kim'),
      );
      expect(changes, greaterThan(1));

      await harness.owner.answerFromSystem();
      expect(harness.resolutions, 1);
      expect(harness.owner.awaitingConfirmation, same(awaiting));
    });

    test('ends the system call when nobody confirms in time', () async {
      harness.scheduler.advance(const Duration(seconds: 59));
      expect(harness.owner.awaitingConfirmation, isNotNull);
      expect(harness.system.failures, 0);
      final before = changes;

      harness.scheduler.advance(const Duration(seconds: 1));
      await pumpEventQueue();
      expect(harness.owner.awaitingConfirmation, isNull);
      expect(harness.system.failures, 1);
      expect(harness.joined, isEmpty);
      expect(changes, before + 1);
    });

    test('hanging up ends the system call once', () async {
      harness.owner.cancelAwaitingAnswer();
      harness.owner.cancelAwaitingAnswer();
      await pumpEventQueue();
      expect(harness.owner.awaitingConfirmation, isNull);
      expect(harness.system.hangUps, 1);

      harness.scheduler.advance(voiceAnswerConfirmationWindow);
      await pumpEventQueue();
      expect(harness.system.failures, 0);
      expect(harness.scheduler.activeTimerCount, 0);
    });

    for (final (retirement, endsSystemCall) in [
      ('a join', false),
      ('a joined room', false),
      ('a leave', false),
      ('a replacement ring', true),
      ('account retirement', true),
      ('close', false),
    ]) {
      test('stops waiting after $retirement', () async {
        switch (retirement) {
          case 'a join':
            harness.admissionIdentity = Object();
          case 'a joined room':
            harness.owner.roomJoined(_site, 9);
          case 'a leave':
            harness.owner.retireAnswer();
          case 'a replacement ring':
            harness.ring(sentAt: 1786204805);
          case 'account retirement':
            harness.account = Object();
          case 'close':
            await harness.close();
        }
        expect(harness.owner.awaitingConfirmation, isNull);
        if (retirement == 'a replacement ring') {
          expect(
            harness.owner.call?.sentAt,
            DateTime.utc(2026, 8, 8, 16, 0, 5),
          );
        }

        harness.scheduler.advance(voiceAnswerConfirmationWindow);
        await pumpEventQueue();
        expect(harness.system.failures, endsSystemCall ? 1 : 0);
        expect(harness.system.hangUps, 0);
        expect(harness.joined, isEmpty);
      });
    }
  });
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
  Completer<VoiceSystemAnswerPlan?>? navigationGate;
  bool confirmInApp = false;
  void Function()? onChanged;

  void ring({int sentAt = 1786204800, int ringSeconds = 60}) =>
      tracker.deliver({
        'room_id': 9,
        'room_slug': 'call-1a2b',
        'room_name': 'Kim and Sam',
        'caller_username': 'Kim',
        'caller_name': 'Apple Support',
        'sent_at': sentAt,
        'ring_seconds': ringSeconds,
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
  FutureOr<VoiceSystemAnswerPlan?> prepare(
    VoiceIncomingCallAcceptance acceptance,
  ) {
    navigations++;
    return navigationGate?.future ??
        (siteName: 'Voice', confirmInApp: confirmInApp);
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
  final reported = <({String callerName, String handle})>[];
  final ends = <VoiceIncomingCallEndReason>[];
  int answers = 0;
  int failures = 0;
  int hangUps = 0;
  @override
  Stream<VoiceSystemCallAction> get actions => const Stream.empty();
  @override
  Future<bool> reportIncomingCall({
    required String callerName,
    required String roomName,
    required String handle,
  }) async {
    reported.add((callerName: callerName, handle: handle));
    return presentation?.future ?? true;
  }

  @override
  Future<void> endIncomingCall(VoiceIncomingCallEndReason reason) async =>
      ends.add(reason);
  @override
  Future<void> answerIncomingCall() async => answers++;
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
  Future<void> end() async => hangUps++;
  @override
  Future<void> dispose() async {}
}
