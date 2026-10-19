import 'dart:async';
import 'dart:io';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'voice_controller.dart';
import 'voice_media.dart';
import 'voice_video_handle.dart';

/// An observer of the call's existing tracks. It never creates or stops media.
/// Calls are serialized so an old configure cannot resurrect PiP after leave.
class NativeVoicePictureInPicture extends ChangeNotifier {
  NativeVoicePictureInPicture({
    required this.onRestore,
    @visibleForTesting bool? enabled,
  }) : _enabled = enabled ?? Platform.isIOS {
    if (_enabled) {
      _owner = this;
      _channel.setMethodCallHandler(_handle);
    }
  }

  static const _channel = MethodChannel('org.discourse.native/voice_pip');
  static NativeVoicePictureInPicture? _owner;
  final VoidCallback onRestore;
  final bool _enabled;
  bool _closed = false;
  bool _active = false;
  String? _session;
  Future<void> _pending = Future.value();
  Map<String, Object?>? _last;

  bool get active => _active;

  Future<void> _handle(MethodCall call) async {
    if (_closed || _owner != this) return;
    final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
    if (args['sessionId'] != _session) return;
    if (call.method == 'restore') onRestore();
    if (call.method == 'activeChanged') {
      final active = args['active'] == true;
      if (active != _active) {
        _active = active;
        notifyListeners();
      }
    }
  }

  Future<void> configure({
    required String sessionId,
    required String roomName,
    required VoiceVideoHandle? track,
    required bool cameraEnabled,
    required bool recording,
    required String recordingLabel,
  }) {
    if (_closed) return Future.value();
    if (_session != sessionId && _active) {
      _active = false;
      notifyListeners();
    }
    _session = sessionId;
    final descriptor = track?.nativeDescriptor;
    final args = <String, Object?>{
      'sessionId': sessionId,
      'roomName': roomName,
      'trackId': descriptor?.trackId,
      'peerConnectionId': descriptor?.peerConnectionId,
      'cameraEnabled': cameraEnabled,
      'recording': recording,
      'recordingLabel': recordingLabel,
    };
    if (mapEquals(args, _last)) return _pending;
    _last = args;
    return _enqueue('configure', args);
  }

  Future<void> clear() {
    _session = null;
    _last = null;
    if (_active) {
      _active = false;
      notifyListeners();
    }
    return _enqueue('clear', null);
  }

  Future<void> _enqueue(String method, Map<String, Object?>? args) {
    if (!_enabled || _owner != this) return Future.value();
    return _pending = _pending.then((_) async {
      if (_owner != this) return;
      try {
        final accepted = await _channel.invokeMethod<Object?>(method, args);
        if (method == 'configure' && accepted == false) _last = null;
      } on MissingPluginException {
        // Older native builds and non-iOS test hosts retain the in-app view.
      } on PlatformException {
        // PiP availability must never interrupt the call itself.
        _last = null;
      }
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await clear();
    if (_owner == this) {
      _channel.setMethodCallHandler(null);
      _owner = null;
    }
    dispose();
  }
}

/// Share the selected video between the floating preview and native PiP.
/// Prefer a remote speaker, then any remote video, then the local camera.
VoiceVideoHandle? voiceCallPreviewTrack(VoiceCallSnapshot call) {
  if (call.status == VoiceCallStatus.leaving) return null;
  final media = call.media;
  final local = media.localVideoTrack;
  VoiceVideoHandle? remote;
  for (final person in call.room.participants) {
    final track = media.videoTrackFor(person.id);
    if (track == null || identical(track, local)) continue;
    if (media.speakingParticipantIds.contains(person.id)) return track;
    remote ??= track;
  }
  return remote ?? local;
}

/// Keeps the active call's video subscription alive across route transitions.
/// A tucked preview is still a call surface; only leaving releases this lease.
class VoiceCallVideoSession extends ChangeNotifier {
  VoiceCallVideoSession({
    required this.controller,
    required this.pictureInPicture,
  }) {
    controller.addListener(_changed);
    _changed();
  }

  final VoiceController controller;
  final NativeVoicePictureInPicture pictureInPicture;
  VoiceMediaSession? _media;
  ({String site, int room})? _watched;
  VoiceVideoHandle? _track;
  bool _closed = false;
  bool _syncing = false;

  VoiceVideoHandle? get track => _track;

  void _changed() {
    if (_closed || _syncing) return;
    _syncing = true;
    try {
      final call = controller.call;
      final next = call == null || call.status == VoiceCallStatus.leaving
          ? null
          : call;
      if (!identical(next?.media, _media)) {
        _media?.removeListener(_mediaChanged);
        _media = next?.media;
        _media?.addListener(_mediaChanged);
      }
      final watched = next == null
          ? null
          : (site: next.siteUrl, room: next.room.id);
      if (_watched != watched) {
        final old = _watched;
        _watched = watched;
        if (old != null) {
          controller.stopWatchingRoomVideo(siteUrl: old.site, roomId: old.room);
        }
        if (watched != null) {
          controller.watchRoomVideo(
            siteUrl: watched.site,
            roomId: watched.room,
          );
        }
      }
      _track = next == null ? null : voiceCallPreviewTrack(next);
      _syncNative(next);
    } finally {
      _syncing = false;
    }
    notifyListeners();
  }

  void _mediaChanged() {
    if (_closed) return;
    final call = controller.call;
    final next = call == null ? null : voiceCallPreviewTrack(call);
    if (identical(next, _track)) return;
    _track = next;
    _syncNative(call);
    notifyListeners();
  }

  void _syncNative(VoiceCallSnapshot? call) {
    if (call == null || call.status == VoiceCallStatus.leaving) {
      unawaited(pictureInPicture.clear());
      return;
    }
    unawaited(
      pictureInPicture.configure(
        sessionId: identityHashCode(call.media).toString(),
        roomName: call.room.name,
        track: _track,
        cameraEnabled: call.cameraEnabled,
        recording: call.room.recording?.active == true,
        recordingLabel: appL10n.recording,
      ),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    controller.removeListener(_changed);
    _media?.removeListener(_mediaChanged);
    final watched = _watched;
    _watched = null;
    if (watched != null) {
      controller.stopWatchingRoomVideo(
        siteUrl: watched.site,
        roomId: watched.room,
      );
    }
    await pictureInPicture.close();
    dispose();
  }
}
