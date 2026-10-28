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
  final Expando<VoiceVideoHandle> _rtcScreens = Expando();

  VoiceVideoHandle? fromRtc(
    rtc.MediaStreamTrack? track, {
    bool screenShare = false,
  }) {
    if (track == null) return null;
    final handles = screenShare ? _rtcScreens : _rtc;
    return handles[track] ??= _RtcVideoHandle(track, screenShare: screenShare);
  }

  VoiceVideoHandle? fromLiveKit(lk.VideoTrack? track) {
    if (track == null) return null;
    return _liveKit[track] ??= _LiveKitVideoHandle(track);
  }
}

final class _RtcVideoHandle implements VoiceVideoHandle {
  _RtcVideoHandle(this._track, {required this.screenShare});

  final rtc.MediaStreamTrack _track;
  final bool screenShare;

  @override
  Widget buildSurface() => _RtcTrackRenderer(
    key: ObjectKey(_track),
    track: _track,
    screenShare: screenShare,
  );

  @override
  VoiceNativeVideoDescriptor get nativeDescriptor => _nativeDescriptor(_track);
}

final class _LiveKitVideoHandle implements VoiceVideoHandle {
  _LiveKitVideoHandle(this._track);

  final lk.VideoTrack _track;

  @override
  Widget buildSurface() => _LiveKitTrackRenderer(track: _track);

  @override
  VoiceNativeVideoDescriptor get nativeDescriptor =>
      _nativeDescriptor(_track.mediaStreamTrack);
}

bool _portrait(rtc.MediaStreamTrack track, rtc.RTCVideoValue value) {
  if (value.width > 0 && value.height > 0) return value.height > value.width;
  final settings = track.getSettings();
  final width = settings['width'];
  final height = settings['height'];
  return width is num && height is num && width > 0 && height > width;
}

class _LiveKitTrackRenderer extends StatefulWidget {
  const _LiveKitTrackRenderer({required this.track});
  final lk.VideoTrack track;

  @override
  State<_LiveKitTrackRenderer> createState() => _LiveKitTrackRendererState();
}

class _LiveKitTrackRendererState extends State<_LiveKitTrackRenderer> {
  final _renderer = rtc.RTCVideoRenderer();
  late final Future<void> _initialization;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initialization = _renderer.initialize();
    unawaited(
      _initialization
          .then((_) {
            if (mounted) setState(() => _ready = true);
          })
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    unawaited(
      _initialization
          .then((_) => _renderer.dispose())
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_ready
      ? const SizedBox.shrink()
      : ValueListenableBuilder<rtc.RTCVideoValue>(
          valueListenable: _renderer,
          builder: (context, value, child) => lk.VideoTrackRenderer(
            widget.track,
            cachedRenderer: _renderer,
            autoDisposeRenderer: false,
            fit:
                widget.track.source == lk.TrackSource.screenShareVideo ||
                    _portrait(widget.track.mediaStreamTrack, value)
                ? lk.VideoViewFit.contain
                : lk.VideoViewFit.cover,
          ),
        );
}

VoiceNativeVideoDescriptor _nativeDescriptor(rtc.MediaStreamTrack track) =>
    VoiceNativeVideoDescriptor(
      trackId: track.id,
      peerConnectionId: track is MediaStreamTrackNative
          ? track.peerConnectionId
          : null,
    );

class _RtcTrackRenderer extends StatefulWidget {
  const _RtcTrackRenderer({
    super.key,
    required this.track,
    required this.screenShare,
  });
  final rtc.MediaStreamTrack track;
  final bool screenShare;

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
  Widget build(BuildContext context) =>
      ValueListenableBuilder<rtc.RTCVideoValue>(
        valueListenable: _renderer,
        builder: (context, value, child) => rtc.RTCVideoView(
          _renderer,
          objectFit: widget.screenShare || _portrait(widget.track, value)
              ? rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
              : rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      );

  @override
  void dispose() {
    _disposed = true;
    unawaited(_attachment.then((_) => _release()));
    super.dispose();
  }
}
