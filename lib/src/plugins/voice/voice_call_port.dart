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
    required this.siteName,
    required this.participantCount,
    required this.status,
    required this.muted,
    this.recording = false,
    this.localVideoPreview,
    this.failureMessage,
    this.identity,
  });

  final String roomName;
  final String siteName;
  final int participantCount;
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

  VoiceCallPresentation copyWith({
    String? roomName,
    String? siteName,
    int? participantCount,
    VoiceCallPresentationStatus? status,
    bool? muted,
    bool? recording,
    Widget? localVideoPreview,
    String? failureMessage,
    bool clearLocalVideoPreview = false,
    bool clearFailure = false,
  }) => VoiceCallPresentation(
    roomName: roomName ?? this.roomName,
    siteName: siteName ?? this.siteName,
    participantCount: participantCount ?? this.participantCount,
    status: status ?? this.status,
    muted: muted ?? this.muted,
    recording: recording ?? this.recording,
    localVideoPreview: clearLocalVideoPreview
        ? null
        : localVideoPreview ?? this.localVideoPreview,
    failureMessage: clearFailure ? null : failureMessage ?? this.failureMessage,
    identity: identity,
  );
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
