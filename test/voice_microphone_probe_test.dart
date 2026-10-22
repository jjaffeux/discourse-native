import 'dart:async';

import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

void main() {
  for (final deviceId in <String?>[null, 'desk-microphone']) {
    test(
      'captures exact constraints for ${deviceId ?? 'default input'}',
      () async {
        final track = _Track('microphone');
        final stream = _Stream([track]);
        final result = await probeVoiceMicrophone(
          deviceId: deviceId,
          getUserMedia: (constraints) async {
            expect(constraints, {
              'audio': {
                'deviceId': ?deviceId,
                'echoCancellation': true,
                'noiseSuppression': true,
              },
              'video': false,
            });
            return stream;
          },
        );
        expect(result, isTrue);
        expect(track.stopCalls, 1);
        expect(stream.disposeCalls, 1);
      },
    );
  }

  for (final error in [
    PlatformException(code: 'NotAllowedError'),
    StateError('capture unavailable'),
  ]) {
    test('contains capture failure ${error.runtimeType}', () async {
      expect(
        await probeVoiceMicrophone(getUserMedia: (_) async => throw error),
        isFalse,
      );
    });
  }

  for (final failStop in [false, true]) {
    for (final failDispose in [false, true]) {
      test(
        'completes all cleanup with stop=$failStop dispose=$failDispose',
        () async {
          final first = _Track('first', failStop: failStop);
          final second = _Track('second');
          final stream = _Stream([first, second], failDispose: failDispose);
          final result = await probeVoiceMicrophone(
            getUserMedia: (_) async => stream,
          );
          expect(result, !failStop && !failDispose);
          expect(first.stopCalls, 1);
          expect(second.stopCalls, 1);
          expect(stream.disposeCalls, 1);
        },
      );
    }
  }

  test('disposes acquired stream when track enumeration fails', () async {
    final stream = _Stream([], failEnumeration: true);
    expect(
      await probeVoiceMicrophone(getUserMedia: (_) async => stream),
      isFalse,
    );
    expect(stream.disposeCalls, 1);
  });

  test('empty capture still disposes its stream', () async {
    final stream = _Stream([]);
    expect(
      await probeVoiceMicrophone(getUserMedia: (_) async => stream),
      isTrue,
    );
    expect(stream.disposeCalls, 1);
  });

  test(
    'waits for stopping and disposal before reporting availability',
    () async {
      final stopGate = Completer<void>();
      final disposeGate = Completer<void>();
      final track = _Track('microphone', stopGate: stopGate.future);
      final stream = _Stream([track], disposeGate: disposeGate.future);
      var completed = false;
      final probe = probeVoiceMicrophone(getUserMedia: (_) async => stream)
          .then((available) {
            completed = true;
            return available;
          });
      await pumpEventQueue();
      expect(track.stopCalls, 1);
      expect(stream.disposeCalls, 0);
      expect(completed, isFalse);
      stopGate.complete();
      await pumpEventQueue();
      expect(stream.disposeCalls, 1);
      expect(completed, isFalse);
      disposeGate.complete();
      expect(await probe, isTrue);
      expect(completed, isTrue);
    },
  );

  test('overlapping probes release only their own temporary streams', () async {
    final firstCapture = Completer<rtc.MediaStream>();
    final firstStream = _Stream([_Track('first')]);
    final secondStream = _Stream([_Track('second')]);
    final first = probeVoiceMicrophone(
      getUserMedia: (_) => firstCapture.future,
    );
    expect(
      await probeVoiceMicrophone(getUserMedia: (_) async => secondStream),
      isTrue,
    );
    expect(secondStream.disposeCalls, 1);
    expect(firstStream.disposeCalls, 0);
    firstCapture.complete(firstStream);
    expect(await first, isTrue);
    expect(firstStream.disposeCalls, 1);
    expect(secondStream.disposeCalls, 1);
  });
}

final class _Track implements rtc.MediaStreamTrack {
  _Track(this.id, {this.failStop = false, this.stopGate});

  @override
  final String id;
  final bool failStop;
  final Future<void>? stopGate;
  int stopCalls = 0;

  @override
  Future<void> stop() async {
    stopCalls++;
    await stopGate;
    if (failStop) throw StateError('stop failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Stream extends rtc.MediaStream {
  _Stream(
    this.tracks, {
    this.failDispose = false,
    this.failEnumeration = false,
    this.disposeGate,
  }) : super('probe', 'test');

  final List<rtc.MediaStreamTrack> tracks;
  final bool failDispose;
  final bool failEnumeration;
  final Future<void>? disposeGate;
  int disposeCalls = 0;

  @override
  List<rtc.MediaStreamTrack> getTracks() {
    if (failEnumeration) throw StateError('enumeration failed');
    return tracks;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await disposeGate;
    if (failDispose) throw StateError('dispose failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
