import 'package:discourse_native/src/plugins/voice/voice_video_handle.dart';
import 'package:flutter/widgets.dart';

final class FakeVoiceVideoHandle implements VoiceVideoHandle {
  FakeVoiceVideoHandle({this.trackId, this.peerConnectionId});

  final String? trackId;
  final String? peerConnectionId;

  @override
  Widget buildSurface() => const SizedBox.shrink();

  @override
  VoiceNativeVideoDescriptor get nativeDescriptor => VoiceNativeVideoDescriptor(
    trackId: trackId,
    peerConnectionId: peerConnectionId,
  );
}
