import 'dart:async';

import 'package:discourse_native/src/plugins/voice/voice_picture_in_picture.dart';
import 'package:discourse_native/src/plugins/voice/voice_room_view.dart';
import 'package:discourse_native/src/plugins/voice/voice_video_adapter.dart';
import 'package:discourse_native/src/plugins/voice/voice_video_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:flutter_webrtc/src/native/media_stream_track_impl.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const webRtc = MethodChannel('FlutterWebRTC.Method');
  const events = EventChannel('FlutterWebRTC.Event');
  const texture = EventChannel('FlutterWebRTC/Texture91');
  const pipChannel = MethodChannel('org.discourse.native/voice_pip');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late Completer<void> rendererDisposed;

  setUp(() {
    calls.clear();
    rendererDisposed = Completer<void>();
    rtc.WebRTC.initialized = false;
    const handler = MockStreamHandler.inline(onListen: _ignoreEvents);
    messenger.setMockStreamHandler(events, handler);
    messenger.setMockStreamHandler(texture, handler);
    messenger.setMockMethodCallHandler(webRtc, (call) async {
      calls.add(call);
      if (call.method == 'videoRendererDispose') rendererDisposed.complete();
      return switch (call.method) {
        'initialize' ||
        'videoRendererSetSrcObject' ||
        'videoRendererDispose' => null,
        'createVideoRenderer' => <String, Object?>{'textureId': 91},
        _ => throw TestFailure('Unexpected capture operation: ${call.method}'),
      };
    });
    messenger.setMockMethodCallHandler(pipChannel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    rtc.WebRTC.initialized = false;
    messenger.setMockMethodCallHandler(webRtc, null);
    messenger.setMockMethodCallHandler(pipChannel, null);
    messenger.setMockStreamHandler(events, null);
    messenger.setMockStreamHandler(texture, null);
  });

  test('handles preserve object identity and native peer ownership', () {
    final adapter = VoiceVideoHandleAdapter();
    final first = _NativeTrack('shared-id', 'first-peer');
    final replacement = _NativeTrack('shared-id', 'second-peer');
    final handle = adapter.fromRtc(first)!;
    expect(adapter.fromRtc(first), same(handle));
    expect(adapter.fromRtc(replacement), isNot(same(handle)));
    expect(handle.nativeDescriptor.trackId, 'shared-id');
    expect(handle.nativeDescriptor.peerConnectionId, 'first-peer');
    expect(
      adapter.fromRtc(replacement)!.nativeDescriptor.peerConnectionId,
      'second-peer',
    );
    expect(adapter.fromRtc(null), isNull);
    expect(adapter.fromLiveKit(null), isNull);
    expect(first.stopCalls, 0);
    expect(replacement.stopCalls, 0);
  });

  test('PiP reads current native IDs for Mesh and restarted LiveKit', () async {
    final adapter = VoiceVideoHandleAdapter();
    final mesh = _NativeTrack('mesh-camera', 'mesh-peer');
    final first = _NativeTrack('livekit-camera', 'livekit-peer');
    final replacement = _NativeTrack('restarted-camera', 'restarted-peer');
    final video = _RestartingVideo(first);
    final handle = adapter.fromLiveKit(video)!;
    final pip = NativeVoicePictureInPicture(enabled: true, onRestore: () {});
    addTearDown(pip.close);

    Future<void> configure(String session, VoiceVideoHandle? track) =>
        pip.configure(
          sessionId: session,
          roomName: 'Room',
          track: track,
          cameraEnabled: true,
          recording: false,
          recordingLabel: 'Recording',
        );

    await configure('mesh-call', adapter.fromRtc(mesh));
    await configure('livekit-call', handle);
    video.mediaStreamTrack = replacement;
    expect(adapter.fromLiveKit(video), same(handle));
    await configure('livekit-call', handle);
    await pip.clear();
    await pip.close();

    final presentations = calls
        .where((call) => call.method == 'configure')
        .map((call) => call.arguments as Map<Object?, Object?>)
        .toList();
    expect(presentations.map((args) => args['trackId']), [
      'mesh-camera',
      'livekit-camera',
      'restarted-camera',
    ]);
    expect(presentations.map((args) => args['peerConnectionId']), [
      'mesh-peer',
      'livekit-peer',
      'restarted-peer',
    ]);
    expect([mesh.stopCalls, first.stopCalls, replacement.stopCalls], [0, 0, 0]);
  });

  for (final source in [
    lk.TrackSource.camera,
    lk.TrackSource.screenShareVideo,
  ]) {
    testWidgets(
      'keeps ${source.name} uncropped for portrait or shared content',
      (tester) async {
        final nativeTrack = _NativeTrack('uncropped-video', 'peer')
          ..settings = source == lk.TrackSource.camera
              ? {'width': 360, 'height': 640}
              : {'width': 1920, 'height': 1080};
        final video = lk.RemoteVideoTrack(
          source,
          _BorrowedStream(nativeTrack),
          nativeTrack,
        );
        addTearDown(video.dispose);
        final handle = VoiceVideoHandleAdapter().fromLiveKit(video)!;
        await tester.pumpWidget(
          MaterialApp(home: VoiceVideoSurface(track: handle)),
        );
        await tester.pumpAndSettle();
        final renderer = tester.widget<lk.VideoTrackRenderer>(
          find.byType(lk.VideoTrackRenderer),
        );
        expect(renderer.fit, lk.VideoViewFit.contain);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(nativeTrack.stopCalls, 0);
      },
    );
  }

  testWidgets('LiveKit surface borrows its track and preserves cover fit', (
    tester,
  ) async {
    final nativeTrack = _NativeTrack('livekit-camera', 'livekit-peer');
    final stream = _BorrowedStream(nativeTrack);
    final video = lk.RemoteVideoTrack(
      lk.TrackSource.camera,
      stream,
      nativeTrack,
    );
    addTearDown(() async {
      await video.dispose();
    });
    final handle = VoiceVideoHandleAdapter().fromLiveKit(video)!;

    await tester.pumpWidget(
      MaterialApp(home: VoiceVideoSurface(track: handle)),
    );
    await tester.pumpAndSettle();
    final renderer = tester.widget<lk.VideoTrackRenderer>(
      find.byType(lk.VideoTrackRenderer),
    );
    expect(renderer.track, same(video));
    expect(renderer.fit, lk.VideoViewFit.cover);
    expect(find.byType(rtc.RTCVideoView), findsOneWidget);
    expect(
      calls
          .where((call) => call.method == 'videoRendererSetSrcObject')
          .first
          .arguments,
      containsPair('streamId', 'livekit-stream'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
    await tester.runAsync(
      () => rendererDisposed.future.timeout(const Duration(seconds: 5)),
    );
    expect(tester.takeException(), isNull);
    expect(calls.map((call) => call.method), contains('videoRendererDispose'));
    expect(video.isDisposed, isFalse);
    expect(stream.disposeCalls, 0);
    expect(nativeTrack.stopCalls, 0);
  });

  testWidgets(
    'retiring during renderer initialization never attaches capture',
    (tester) async {
      final initialized = Completer<Map<String, Object?>>();
      messenger.setMockMethodCallHandler(webRtc, (call) async {
        calls.add(call);
        return switch (call.method) {
          'initialize' || 'videoRendererDispose' => null,
          'createVideoRenderer' => initialized.future,
          _ => throw TestFailure('Retired renderer attached: ${call.method}'),
        };
      });
      final track = _NativeTrack('late-video', 'late-peer');
      final handle = VoiceVideoHandleAdapter().fromRtc(track)!;
      await tester.pumpWidget(
        MaterialApp(home: VoiceVideoSurface(track: handle)),
      );
      expect(calls.map((call) => call.method), contains('createVideoRenderer'));
      await tester.pumpWidget(const SizedBox.shrink());
      initialized.complete({'textureId': 91});
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(calls.map((call) => call.method), [
        'initialize',
        'createVideoRenderer',
        'videoRendererDispose',
      ]);
      expect(track.stopCalls, 0);
    },
  );
}

void _ignoreEvents(Object? _, MockStreamHandlerEventSink _) {}

final class _NativeTrack extends MediaStreamTrackNative {
  _NativeTrack(String id, String owner) : super(id, id, 'video', true, owner);

  int stopCalls = 0;
  Map<String, dynamic> settings = {};

  @override
  Map<String, dynamic> getSettings() => settings;

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

final class _RestartingVideo extends Fake implements lk.VideoTrack {
  _RestartingVideo(this.mediaStreamTrack);

  @override
  rtc.MediaStreamTrack mediaStreamTrack;
}

final class _BorrowedStream extends rtc.MediaStream {
  _BorrowedStream(this.track) : super('livekit-stream', 'livekit-peer');

  final rtc.MediaStreamTrack track;
  int disposeCalls = 0;

  @override
  List<rtc.MediaStreamTrack> getVideoTracks() => [track];
  @override
  List<rtc.MediaStreamTrack> getAudioTracks() => [];
  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
