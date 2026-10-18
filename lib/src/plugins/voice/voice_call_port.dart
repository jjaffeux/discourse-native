import 'package:flutter/widgets.dart';

enum VoiceCallPresentationStatus {
  joining,
  connected,
  reconnecting,
  leaving,
  failed,
}

enum VoiceCallAction { openRoom, toggleMuted, leave }

@immutable
final class VoiceCallPresentation {
  const VoiceCallPresentation({
    required this.roomName,
    required this.status,
    required this.muted,
    this.recording = false,
    this.localVideoPreview,
    this.failureMessage,
    this.identity,
  });

  final String roomName;
  final VoiceCallPresentationStatus status;
  final bool muted;

  /// The call is being recorded server-side. Shown wherever the call is,
  /// so nobody can be in a recorded call without seeing it.
  final bool recording;

  /// Selected remote speaker video, falling back to the local camera.
  final Widget? localVideoPreview;
  final String? failureMessage;

  /// Stable for one call so a replacement starts with a visible preview.
  final Object? identity;
}

@immutable
final class VoiceCallPortState {
  const VoiceCallPortState({
    required this.supported,
    this.call,
    this.failureMessage,
    this.roomVisible = false,
    this.usesMobileNavigation = false,
    this.pictureInPictureActive = false,
  });

  const VoiceCallPortState.unsupported()
    : supported = false,
      call = null,
      failureMessage = null,
      roomVisible = false,
      usesMobileNavigation = false,
      pictureInPictureActive = false;

  const VoiceCallPortState.idle()
    : supported = true,
      call = null,
      failureMessage = null,
      roomVisible = false,
      usesMobileNavigation = false,
      pictureInPictureActive = false;

  final bool supported;
  final VoiceCallPresentation? call;
  final String? failureMessage;
  final bool roomVisible;
  final bool usesMobileNavigation;
  final bool pictureInPictureActive;
}

/// The complete runtime authority available to the app-global call overlay.
///
/// Platform SDK objects, room models, navigation hosts, and native teardown
/// remain behind this boundary. The view receives only immutable presentation
/// state and semantic actions.
abstract interface class VoiceCallPort implements Listenable {
  VoiceCallPortState get state;

  void dispatch(VoiceCallAction action);

  Future<void> close();
}
