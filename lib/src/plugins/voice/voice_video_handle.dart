import 'package:flutter/widgets.dart';

/// A borrowed presentation of a call-owned video track, without capture controls.
abstract interface class VoiceVideoHandle {
  Widget buildSurface();

  /// Reads the current native identity, including after a provider track restart.
  VoiceNativeVideoDescriptor get nativeDescriptor;
}

final class VoiceNativeVideoDescriptor {
  const VoiceNativeVideoDescriptor({
    required this.trackId,
    required this.peerConnectionId,
  });

  final String? trackId;
  final String? peerConnectionId;
}
