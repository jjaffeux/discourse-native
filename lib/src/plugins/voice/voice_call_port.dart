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
    this.localVideoPreview,
    this.failureMessage,
  });

  final String roomName;
  final String siteName;
  final int participantCount;
  final VoiceCallPresentationStatus status;
  final bool muted;
  final Widget? localVideoPreview;
  final String? failureMessage;

  VoiceCallPresentation copyWith({
    String? roomName,
    String? siteName,
    int? participantCount,
    VoiceCallPresentationStatus? status,
    bool? muted,
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
    localVideoPreview: clearLocalVideoPreview
        ? null
        : localVideoPreview ?? this.localVideoPreview,
    failureMessage: clearFailure ? null : failureMessage ?? this.failureMessage,
  );
}

@immutable
final class VoiceCallPortState {
  const VoiceCallPortState({
    required this.supported,
    this.call,
    this.failureMessage,
  });

  const VoiceCallPortState.unsupported()
    : supported = false,
      call = null,
      failureMessage = null;

  const VoiceCallPortState.idle()
    : supported = true,
      call = null,
      failureMessage = null;

  final bool supported;
  final VoiceCallPresentation? call;
  final String? failureMessage;
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
