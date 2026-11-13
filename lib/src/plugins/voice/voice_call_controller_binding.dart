import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ObjectKey;

import 'voice_call_controller_port.dart';
import 'voice_call_port.dart';
import 'voice_controller.dart';
import 'voice_picture_in_picture.dart';
import 'voice_reaction_widgets.dart';
import 'voice_room_view.dart';
import 'voice_services.dart';
import 'voice_shell_service.dart';

VoiceCallControllerPort bindVoiceCallController({
  required VoiceController controller,
  required VoiceShellService shell,
  PluginEmojiHost? emoji,
}) {
  final pip = NativeVoicePictureInPicture(
    onRestore: () => unawaited(
      _performControllerAction(
        controller: controller,
        shell: shell,
        action: VoiceCallAction.openRoom,
      ),
    ),
  );
  final video = VoiceCallVideoSession(
    controller: controller,
    pictureInPicture: pip,
  );
  return VoiceCallControllerPort(
    runtime: Listenable.merge([video, pip, ?shell.navigationChanges]),
    readState: () => _controllerState(controller, shell, video, emoji),
    performAction: (action) => _performControllerAction(
      controller: controller,
      shell: shell,
      action: action,
    ),
    closeRuntime: video.close,
  );
}

Future<void> _performControllerAction({
  required VoiceController controller,
  required VoiceShellService shell,
  required VoiceCallAction action,
}) async {
  final call = controller.call;
  if (call == null) return;
  switch (action) {
    case VoiceCallAction.openRoom:
      shell.openRoom(
        siteUrl: call.siteUrl,
        route: ContentRoute(
          destination: ExtensionDestination(voiceRoomRouteId(call.room.id)),
          title: call.room.name,
          icon: DIcons.microphoneLines,
          subtitle: call.siteName,
        ),
      );
    case VoiceCallAction.toggleMuted:
      await controller.setMuted(!call.muted);
    case VoiceCallAction.leave:
      await controller.leave();
  }
}

VoiceCallPortState _controllerState(
  VoiceController controller,
  VoiceShellService shell,
  VoiceCallVideoSession video,
  PluginEmojiHost? emoji,
) {
  if (!controller.supportedPlatform) {
    return const VoiceCallPortState.unsupported();
  }
  final call = controller.call;
  if (call == null) return const VoiceCallPortState.idle();
  final selectedVideoTrack = video.track;
  final reactions = emoji == null ? null : controller.callReactions;
  return VoiceCallPortState(
    supported: true,
    roomVisible: shell.activeRoomVisible,
    usesMobileNavigation: shell.usesMobileNavigation,
    pictureInPictureActive: video.pictureInPicture.active,
    call: VoiceCallPresentation(
      identity: call.media,
      roomName: call.room.name,
      status: switch (call.status) {
        VoiceCallStatus.joining => VoiceCallPresentationStatus.joining,
        VoiceCallStatus.connected => VoiceCallPresentationStatus.connected,
        VoiceCallStatus.reconnecting =>
          VoiceCallPresentationStatus.reconnecting,
        VoiceCallStatus.leaving => VoiceCallPresentationStatus.leaving,
        VoiceCallStatus.failed => VoiceCallPresentationStatus.failed,
      },
      muted: call.muted,
      recording: call.room.isBeingRecorded,
      localVideoPreview: selectedVideoTrack == null
          ? null
          : VoiceVideoSurface(track: selectedVideoTrack),
      failureMessage: call.error,
      reactionOverlay: emoji == null || reactions == null
          ? null
          : VoiceReactionOverlay(
              key: ObjectKey(reactions),
              session: reactions,
              emoji: emoji,
            ),
      reactionControl: emoji == null || reactions == null
          ? null
          : VoiceReactionButton(
              key: ObjectKey(reactions),
              session: reactions,
              emoji: emoji,
            ),
    ),
  );
}
