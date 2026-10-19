import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
// The native lookup needs the track's peer owner as well as its ID.
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_track_impl.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'voice_video_handle.dart';

/// Adapts call-owned provider tracks without taking ownership of capture.
final class VoiceVideoHandleAdapter {
  final Expando<VoiceVideoHandle> _rtc = Expando();
  final Expando<VoiceVideoHandle> _liveKit = Expando();

  VoiceVideoHandle? fromRtc(rtc.MediaStreamTrack? track) {
    if (track == null) return null;
    return _rtc[track] ??= _RtcVideoHandle(track);
  }

  VoiceVideoHandle? fromLiveKit(lk.VideoTrack? track) {
    if (track == null) return null;
    return _liveKit[track] ??= _LiveKitVideoHandle(track);
  }
}

final class _RtcVideoHandle implements VoiceVideoHandle {
  _RtcVideoHandle(this._track);

  final rtc.MediaStreamTrack _track;

  @override
  Widget buildSurface() =>
      _RtcTrackRenderer(key: ObjectKey(_track), track: _track);

  @override
  VoiceNativeVideoDescriptor get nativeDescriptor => _nativeDescriptor(_track);
}

final class _LiveKitVideoHandle implements VoiceVideoHandle {
  _LiveKitVideoHandle(this._track);

  final lk.VideoTrack _track;

  @override
  Widget buildSurface() =>
      lk.VideoTrackRenderer(_track, fit: lk.VideoViewFit.cover);

  @override
  VoiceNativeVideoDescriptor get nativeDescriptor =>
      _nativeDescriptor(_track.mediaStreamTrack);
}

VoiceNativeVideoDescriptor _nativeDescriptor(rtc.MediaStreamTrack track) =>
    VoiceNativeVideoDescriptor(
      trackId: track.id,
      peerConnectionId: track is MediaStreamTrackNative
          ? track.peerConnectionId
          : null,
    );

class _RtcTrackRenderer extends StatefulWidget {
  const _RtcTrackRenderer({super.key, required this.track});
  final rtc.MediaStreamTrack track;

  @override
  State<_RtcTrackRenderer> createState() => _RtcTrackRendererState();
}

class _RtcTrackRendererState extends State<_RtcTrackRenderer> {
  final rtc.RTCVideoRenderer _renderer = rtc.RTCVideoRenderer();
  late final Future<void> _attachment;
  rtc.MediaStream? _stream;
  bool _rendererReady = false;
  bool _disposed = false;
  bool _released = false;

  @override
  void initState() {
    super.initState();
    _attachment = _tryAttach();
    unawaited(_attachment);
  }

  Future<void> _tryAttach() async {
    rtc.MediaStream? pendingStream;
    try {
      await _renderer.initialize();
      _rendererReady = true;
      if (_disposed) return;
      pendingStream = await rtc.createLocalMediaStream('voice-video-surface');
      if (_disposed) return;

      final track = widget.track;
      // Keep the bridge stream empty on the native side. Disposing a native
      // stream also disposes its tracks in flutter_webrtc, but this renderer
      // only borrows tracks owned by the call's media session.
      await pendingStream.addTrack(track, addToNative: false);
      if (_disposed) return;
      await _renderer.setSrcObject(stream: pendingStream, trackId: track.id);
      if (_disposed) return;

      _stream = pendingStream;
      pendingStream = null;
      if (mounted) setState(() {});
    } catch (_) {
    } finally {
      if (pendingStream case final stream?) {
        if (_disposed) {
          _stream = stream;
        } else {
          await _tryDisposeStream(stream);
        }
      }
    }
  }

  Future<void> _disposeRenderer() async {
    try {
      await _renderer.dispose();
    } catch (_) {}
  }

  Future<void> _tryDisposeStream(rtc.MediaStream stream) async {
    try {
      await stream.dispose();
    } catch (_) {}
  }

  Future<void> _release() async {
    if (_released) return;
    _released = true;
    if (_rendererReady) await _disposeRenderer();
    if (_stream case final stream?) {
      _stream = null;
      await _tryDisposeStream(stream);
    }
  }

  @override
  Widget build(BuildContext context) => rtc.RTCVideoView(
    _renderer,
    objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  );

  @override
  void dispose() {
    _disposed = true;
    unawaited(_attachment.then((_) => _release()));
    super.dispose();
  }
}
