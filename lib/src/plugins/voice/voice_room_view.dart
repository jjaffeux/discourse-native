import 'dart:async';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'voice_agent_invite.dart';
import 'voice_controller.dart';
import 'voice_diagnostics.dart';
import 'voice_icons.dart';
import 'voice_incoming_call.dart';
import 'voice_join.dart';
import 'voice_media.dart';
import 'voice_models.dart';
import 'voice_room_editor.dart';
import 'voice_services.dart';
import 'voice_shell_service.dart';

export 'voice_room_editor.dart' show showVoiceRoomEditor;

class VoiceRoomView extends StatelessWidget {
  const VoiceRoomView({
    super.key,
    required this.roomId,
    this.controller,
    this.shell,
  });

  final int roomId;
  final VoiceController? controller;
  final VoiceShellService? shell;

  @override
  Widget build(BuildContext context) {
    final shell =
        this.shell ?? PluginUiScope.require(context, voiceShellService);
    final controller =
        this.controller ??
        (this.shell?.controller ??
            PluginUiScope.require(context, voiceControllerService));
    final site = shell.currentInstance;
    if (site == null) return const SizedBox.shrink();
    return _VoiceRoomControllerView(
      controller: controller,
      shell: shell,
      roomId: roomId,
      siteUrl: site.url,
      siteName: site.title,
    );
  }
}

typedef _VoiceRoomPresentation = ({
  VoiceRoom? room,
  VoiceCallSnapshot? call,
  bool cameraStarting,
  int? currentUserId,
  bool recordingEnabled,
  bool meshPrivacyWarningEnabled,
  bool autoStatusAvailable,
  String? inviteLink,
  String? error,
});

/// Selects room-wide state out of the controller's broad notification stream.
/// Media sessions still notify the controller for idle tracking and connection
/// recovery, while speaker and track-only events update participant tiles.
class _VoiceRoomControllerView extends StatefulWidget {
  const _VoiceRoomControllerView({
    required this.controller,
    required this.shell,
    required this.roomId,
    required this.siteUrl,
    required this.siteName,
  });

  final VoiceController controller;
  final VoiceShellService shell;
  final int roomId;
  final String siteUrl;
  final String siteName;

  @override
  State<_VoiceRoomControllerView> createState() =>
      _VoiceRoomControllerViewState();
}

class _VoiceRoomControllerViewState extends State<_VoiceRoomControllerView> {
  late _VoiceRoomPresentation _presentation;
  bool _pushToTalkHeld = false;

  @override
  void initState() {
    super.initState();
    _presentation = _select();
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(_VoiceRoomControllerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _releasePushToTalk(oldWidget.controller);
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
    }
    _presentation = _select();
  }

  /// Mutes a push-to-talk hold whose Space release can no longer reach this
  /// room: focus left it, which on desktop includes the window deactivating,
  /// or the room closed.
  void _releasePushToTalk(VoiceController controller) {
    if (!_pushToTalkHeld) return;
    _pushToTalkHeld = false;
    // Muting notifies every listener synchronously, and a room can close while
    // the widget tree is locked.
    scheduleMicrotask(() => unawaited(controller.setMuted(true)));
  }

  _VoiceRoomPresentation _select() {
    final directoryRoom = widget.controller.room(widget.siteUrl, widget.roomId);
    if (directoryRoom == null) {
      return (
        room: null,
        call: null,
        cameraStarting: false,
        currentUserId: widget.shell.currentUserIdFor(widget.siteUrl),
        recordingEnabled: false,
        meshPrivacyWarningEnabled: widget.shell.meshPrivacyWarningEnabledFor(
          widget.siteUrl,
        ),
        autoStatusAvailable: widget.shell.autoStatusEnabledFor(widget.siteUrl),
        inviteLink: null,
        error: widget.controller.errorFor(widget.siteUrl),
      );
    }
    final heldCall = widget.controller.call;
    final call =
        heldCall?.siteUrl == widget.siteUrl &&
            heldCall?.room.id == directoryRoom.id
        ? heldCall
        : null;
    final room = call?.room ?? directoryRoom;
    return (
      room: room,
      call: call,
      cameraStarting: call != null && widget.controller.cameraStarting,
      currentUserId: widget.shell.currentUserIdFor(widget.siteUrl),
      recordingEnabled:
          call != null &&
          room.canManage &&
          call.media.transport == VoiceTransport.livekit &&
          widget.shell.recordingEnabledFor(widget.siteUrl),
      meshPrivacyWarningEnabled: widget.shell.meshPrivacyWarningEnabledFor(
        widget.siteUrl,
      ),
      autoStatusAvailable: widget.shell.autoStatusEnabledFor(widget.siteUrl),
      inviteLink: widget.shell.inviteLinkFor(widget.siteUrl, directoryRoom),
      error: call?.error ?? widget.controller.errorFor(widget.siteUrl),
    );
  }

  void _controllerChanged() {
    final next = _select();
    if (next == _presentation) return;
    setState(() => _presentation = next);
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation;
    final room = presentation.room;
    if (room == null) {
      return Center(child: Text(context.l10n.thisVoiceRoomIsUnavailable));
    }
    return Focus(
      autofocus: true,
      onFocusChange: (focused) {
        if (!focused) _releasePushToTalk(widget.controller);
      },
      onKeyEvent: (_, event) {
        if (!widget.controller.pushToTalkEnabled ||
            (!Platform.isMacOS && !Platform.isLinux) ||
            event.logicalKey != LogicalKeyboardKey.space) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent) {
          _pushToTalkHeld = true;
          unawaited(widget.controller.setMuted(false));
        } else if (event is KeyUpEvent) {
          _pushToTalkHeld = false;
          unawaited(widget.controller.setMuted(true));
        }
        return KeyEventResult.handled;
      },
      child: VoiceRoomContent(
        controller: widget.controller,
        room: room,
        call: presentation.call,
        siteUrl: widget.siteUrl,
        siteName: widget.siteName,
        currentUserId: presentation.currentUserId,
        recordingEnabled: presentation.recordingEnabled,
        meshPrivacyWarningEnabled: presentation.meshPrivacyWarningEnabled,
        autoStatusAvailable: presentation.autoStatusAvailable,
        inviteLink: presentation.inviteLink,
        error: presentation.error,
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _releasePushToTalk(widget.controller);
    super.dispose();
  }
}

class VoiceRoomContent extends StatefulWidget {
  const VoiceRoomContent({
    super.key,
    required this.controller,
    required this.room,
    required this.call,
    required this.siteUrl,
    required this.siteName,
    required this.currentUserId,
    required this.recordingEnabled,
    required this.error,
    this.meshPrivacyWarningEnabled = false,
    this.autoStatusAvailable = false,
    this.inviteLink,
    this.controllerResolver,
    this.ringingClock = DateTime.now,
  });

  final VoiceController controller;
  final VoiceRoom? room;
  final VoiceCallSnapshot? call;
  final String siteUrl;
  final String siteName;
  final int? currentUserId;
  final bool recordingEnabled;
  final String? error;
  final bool meshPrivacyWarningEnabled;
  final bool autoStatusAvailable;
  final String? inviteLink;
  final VoiceController Function()? controllerResolver;
  final DateTime Function() ringingClock;

  @override
  State<VoiceRoomContent> createState() => _VoiceRoomContentState();
}

class _VoiceRoomContentState extends State<VoiceRoomContent> {
  @override
  void initState() {
    super.initState();
    _startWatching(widget);
  }

  @override
  void didUpdateWidget(VoiceRoomContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller) &&
        oldWidget.siteUrl == widget.siteUrl &&
        oldWidget.room?.id == widget.room?.id) {
      return;
    }
    _stopWatching(oldWidget);
    _startWatching(widget);
  }

  void _startWatching(VoiceRoomContent content) {
    if (content.room case final room?) {
      content.controller.watchRoomVideo(
        siteUrl: content.siteUrl,
        roomId: room.id,
      );
    }
  }

  void _stopWatching(VoiceRoomContent content) {
    if (content.room case final room?) {
      content.controller.stopWatchingRoomVideo(
        siteUrl: content.siteUrl,
        roomId: room.id,
      );
    }
  }

  @override
  void dispose() {
    _stopWatching(widget);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final room = widget.room;
    if (room == null) {
      return Center(child: Text(context.l10n.thisVoiceRoomIsUnavailable));
    }
    final active = widget.call;
    // Leaving releases the call's media before the server confirms the leave,
    // so tiles stop reading and listening to it as soon as leaving starts.
    final media = active?.status == VoiceCallStatus.leaving
        ? null
        : active?.media;
    final siteUrl = widget.siteUrl;
    final siteName = widget.siteName;
    final currentUserId = widget.currentUserId;
    final recordingEnabled = widget.recordingEnabled;
    final controllerResolver = widget.controllerResolver;
    final error = widget.error;
    final recording = room.recording;
    return Column(
      children: [
        if (error != null)
          MaterialBanner(
            content: Text(error),
            actions: [
              DButton(
                onPressed: () => controller.dismissCallError(siteUrl),
                label: Text(context.l10n.dismiss),
                variant: DButtonVariant.ghost,
              ),
            ],
          ),
        if (recording != null && recording.active)
          _RecordingBadge(recording: recording),
        Expanded(
          child: VoiceRingingClock(
            room: room,
            clock: widget.ringingClock,
            builder: (context, ringing) => LayoutBuilder(
              builder: (context, constraints) {
                final participants = room.participants;
                if (participants.isEmpty && ringing.isEmpty) {
                  return _EmptyRoom(room: room);
                }
                final columns = constraints.maxWidth >= 900
                    ? 3
                    : constraints.maxWidth >= 560
                    ? 2
                    : 1;
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 16 / 10,
                  ),
                  itemCount: participants.length + ringing.length,
                  itemBuilder: (context, index) {
                    if (index >= participants.length) {
                      return _RingingTile(
                        entry: ringing[index - participants.length],
                        siteUrl: siteUrl,
                      );
                    }
                    final participant = participants[index];
                    return _ParticipantTile(
                      key: ValueKey(('voice-participant', participant.id)),
                      controller: controller,
                      participant: participant,
                      siteUrl: siteUrl,
                      roomId: room.id,
                      media: media,
                      canManage: active?.room.canManage ?? false,
                      canKick:
                          active?.room.canManage == true &&
                          participant.id != currentUserId &&
                          participant.id != room.creatorId,
                      canAdjustLocally:
                          active != null && participant.id != currentUserId,
                      stageRoleChange: _stageRoleChange(
                        active,
                        participant,
                        currentUserId,
                      ),
                      controllerResolver: controllerResolver,
                    );
                  },
                );
              },
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: active == null
                ? Wrap(
                    spacing: DSpacing.controlGap,
                    children: [
                      VoiceAgentInviteAction(
                        controller: controller,
                        siteUrl: siteUrl,
                        roomId: room.id,
                      ),
                      DButton(
                        onPressed: () => joinVoiceRoom(
                          context,
                          controller: controller,
                          siteUrl: siteUrl,
                          siteName: siteName,
                          room: room,
                          meshPrivacyWarningEnabled:
                              widget.meshPrivacyWarningEnabled,
                        ),
                        icon: const DIcon(DIcons.microphoneLines),
                        label: Text(context.l10n.joinRoom),
                        variant: DButtonVariant.primary,
                      ),
                    ],
                  )
                : _CallControls(
                    controller: controller,
                    call: active,
                    siteUrl: siteUrl,
                    currentUserId: currentUserId,
                    recordingEnabled: recordingEnabled,
                    autoStatusAvailable: widget.autoStatusAvailable,
                    inviteLink: widget.inviteLink,
                    controllerResolver: controllerResolver,
                  ),
          ),
        ),
      ],
    );
  }
}

/// The role a manager may move [participant] to from the tile menu, in a
/// stage room: listeners become speakers (which also approves a raised
/// hand), speakers go back to the listeners. Moderators and the local user
/// are managed elsewhere.
VoiceRole? _stageRoleChange(
  VoiceCallSnapshot? call,
  VoiceParticipant participant,
  int? currentUserId,
) {
  if (call == null ||
      !call.room.canManage ||
      call.room.type != VoiceRoomType.stage ||
      participant.id == currentUserId ||
      participant.isAgent) {
    return null;
  }
  return switch (participant.role) {
    VoiceRole.participant => VoiceRole.speaker,
    VoiceRole.speaker => VoiceRole.participant,
    VoiceRole.moderator => null,
  };
}

/// A tile for someone being rung who has not picked up: styled apart from
/// participant tiles so nobody mistakes them for present.
class _RingingTile extends StatelessWidget {
  const _RingingTile({required this.entry, required this.siteUrl});
  final VoiceRingingEntry entry;
  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = entry.user;
    return Semantics(
      label: context.l10n.calling((user.name ?? user.username).toString()),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DAvatar.frame(
              child: SizedBox.square(
                dimension: 56,
                child: AvatarImage(
                  url: user.avatarUrl(siteUrl, size: 112),
                  size: 56,
                  fallback: ColoredBox(
                    color: theme.colorScheme.surfaceContainerHigh,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DIcon(
                  VoiceIcons.phone,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  context.l10n.callingVoiceroomview(
                    (user.name ?? user.username).toString(),
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The room-wide "this call is being recorded" indicator. Drawn for
/// everyone looking at the room, not only for whoever can stop it.
class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge({required this.recording});
  final VoiceRecording recording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final startedBy = recording.startedByUsername;
    return DTooltip(
      message: startedBy == null
          ? context.l10n.thisCallIsBeingRecorded
          : context.l10n.recordingStartedBy((startedBy).toString()),
      child: Container(
        width: double.infinity,
        color: theme.colorScheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            DIcon(DIcons.circle, size: 12, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Text(
              context.l10n.recording,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRoom extends StatelessWidget {
  const _EmptyRoom({required this.room});
  final VoiceRoom room;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(
            children: [
              const DEmptyMedia(
                variant: DEmptyMediaVariant.icon,
                child: DIcon(DIcons.microphoneLines),
              ),
              DEmptyTitle(context.l10n.nobodyIsInYet((room.name).toString())),
              // Preserve cooked markup ownership, including links and embedded content.
              if (room.cookedDescription case final cooked?)
                DEmptyDescription.child(child: CookedHtml(html: cooked))
              else if (room.description case final description?)
                DEmptyDescription(description),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ParticipantTile extends StatefulWidget {
  const _ParticipantTile({
    super.key,
    required this.controller,
    required this.participant,
    required this.siteUrl,
    required this.roomId,
    required this.media,
    required this.canManage,
    required this.canKick,
    required this.canAdjustLocally,
    this.stageRoleChange,
    this.controllerResolver,
  });

  final VoiceController controller;
  final VoiceParticipant participant;
  final String siteUrl;
  final int roomId;
  final VoiceMediaSession? media;
  final bool canManage;
  final bool canKick;
  final bool canAdjustLocally;
  final VoiceRole? stageRoleChange;
  final VoiceController Function()? controllerResolver;

  @override
  State<_ParticipantTile> createState() => _ParticipantTileState();
}

class _ParticipantTileState extends State<_ParticipantTile> {
  Object? _videoTrack;
  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    widget.media?.addListener(_mediaChanged);
    _readMedia();
  }

  @override
  void didUpdateWidget(_ParticipantTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.media, widget.media)) {
      oldWidget.media?.removeListener(_mediaChanged);
      widget.media?.addListener(_mediaChanged);
    }
    _readMedia();
  }

  void _readMedia() {
    _videoTrack = widget.media?.videoTrackFor(widget.participant.id);
    _speaking =
        widget.media?.speakingParticipantIds.contains(widget.participant.id) ??
        false;
  }

  void _mediaChanged() {
    final videoTrack = widget.media?.videoTrackFor(widget.participant.id);
    final speaking =
        widget.media?.speakingParticipantIds.contains(widget.participant.id) ??
        false;
    if (identical(videoTrack, _videoTrack) && speaking == _speaking) return;
    setState(() {
      _videoTrack = videoTrack;
      _speaking = speaking;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final participant = widget.participant;
    final siteUrl = widget.siteUrl;
    final roomId = widget.roomId;
    final videoTrack = _videoTrack;
    final speaking = _speaking;
    final canManage = widget.canManage;
    final canKick = widget.canKick;
    final canAdjustLocally = widget.canAdjustLocally;
    final stageRoleChange = widget.stageRoleChange;
    final controllerResolver = widget.controllerResolver;
    final theme = Theme.of(context);
    return Semantics(
      label: [
        participant.name ?? participant.username,
        if (speaking) 'speaking',
        if (participant.muted) 'muted',
        if (participant.handRaisedAt != null) context.l10n.handRaised,
      ].join(', '),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: speaking
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (videoTrack != null)
                VoiceVideoSurface(track: videoTrack)
              else
                Center(
                  child: DAvatar.frame(
                    child: SizedBox.square(
                      dimension: 72,
                      child: AvatarImage(
                        url: participant.avatarUrl(siteUrl, size: 144),
                        size: 72,
                        fallback: ColoredBox(
                          color: theme.colorScheme.surfaceContainerHigh,
                        ),
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.58),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          participant.name ?? participant.username,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      if (canManage && participant.handRaisedAt != null)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Text('✋'),
                        ),
                      if (participant.muted)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: DIcon(
                            DIcons.microphoneSlash,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (canAdjustLocally)
                Align(
                  alignment: Alignment.topRight,
                  child: Builder(
                    builder: (menuContext) {
                      Future<void> onSelect(Object? action) async {
                        if (action == 'kick') {
                          await controller.kick(participant.id);
                        }
                        if (action == 'dismiss') {
                          await controller.requestToSpeak(
                            userId: participant.id,
                            raised: false,
                          );
                        }
                        if (action == 'role' && stageRoleChange != null) {
                          await controller.setParticipantRole(
                            participant.id,
                            stageRoleChange,
                          );
                        }
                        if (action == 'volume' && context.mounted) {
                          await _showParticipantVolume(
                            context,
                            controller,
                            participant.id,
                          );
                        }
                        if (action == 'flag' && context.mounted) {
                          await _showParticipantFlag(
                            context,
                            controller,
                            participant,
                            siteUrl: siteUrl,
                            roomId: roomId,
                            controllerResolver: controllerResolver,
                          );
                        }
                      }

                      return Semantics(
                        container: true,
                        explicitChildNodes: true,
                        child: DDropdownMenu(
                          content: DDropdownMenuContent(
                            semanticLabel: context.l10n.participantActions,
                            width: 280,
                            children: [
                              DDropdownMenuItem(
                                onPressed: () => onSelect('volume'),
                                child: Text(context.l10n.localVolume),
                              ),
                              DDropdownMenuItem(
                                onPressed: () => onSelect('flag'),
                                child: Text(context.l10n.notifyModerators),
                              ),
                              if (stageRoleChange case final role?)
                                DDropdownMenuItem(
                                  onPressed: () => onSelect('role'),
                                  child: Text(
                                    role == VoiceRole.speaker
                                        ? context.l10n.makeSpeaker
                                        : context.l10n.moveToListeners,
                                  ),
                                ),
                              if (canManage && participant.handRaisedAt != null)
                                DDropdownMenuItem(
                                  onPressed: () => onSelect('dismiss'),
                                  child: Text(context.l10n.dismissRaisedHand),
                                ),
                              if (canKick)
                                DDropdownMenuItem(
                                  onPressed: () => onSelect('kick'),
                                  variant: DDropdownMenuItemVariant.destructive,
                                  child: Text(context.l10n.removeFromRoom),
                                ),
                            ],
                          ),
                          child: DDropdownMenuTrigger(
                            builder: (triggerContext, state) =>
                                DButton.iconOnly(
                                  tooltip: context.l10n.participantActions,
                                  variant: DButtonVariant.secondary,
                                  icon: const DIcon(DIcons.ellipsis, size: 16),
                                  focusNode: state.focusNode,
                                  hasPopup: true,
                                  expanded: state.open,
                                  onPressed: state.toggle,
                                ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.media?.removeListener(_mediaChanged);
    super.dispose();
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.controller,
    required this.call,
    required this.siteUrl,
    required this.currentUserId,
    required this.recordingEnabled,
    this.autoStatusAvailable = false,
    this.inviteLink,
    this.controllerResolver,
  });
  final VoiceController controller;
  final VoiceCallSnapshot call;
  final String siteUrl;
  final int? currentUserId;
  final bool recordingEnabled;
  final bool autoStatusAvailable;
  final String? inviteLink;
  final VoiceController Function()? controllerResolver;

  @override
  Widget build(BuildContext context) {
    final me = call.room.participants
        .where((participant) => participant.id == currentUserId)
        .firstOrNull;
    final role = me?.role ?? call.room.membership?.role;
    final canPublish =
        call.room.type != VoiceRoomType.stage ||
        role == VoiceRole.moderator ||
        role == VoiceRole.speaker;
    final canPublishVideo = canPublish && call.room.videoAllowed;
    final cameraOn = call.cameraEnabled || controller.cameraStarting;
    final canShare = (Platform.isMacOS || Platform.isLinux) && canPublishVideo;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canPublish)
          VoiceToolbarControl(
            label: call.muted ? context.l10n.unmute : context.l10n.mute,
            icon: call.muted ? DIcons.microphoneSlash : DIcons.microphoneLines,
            selected: call.muted,
            onPressed: () => controller.setMuted(!call.muted),
          ),
        VoiceToolbarControl(
          label: call.deafened ? context.l10n.listen : context.l10n.deafen,
          icon: DIcons.earListen,
          selected: call.deafened,
          onPressed: () => controller.setDeafened(!call.deafened),
        ),
        if (canPublishVideo)
          VoiceToolbarControl(
            label: cameraOn ? context.l10n.cameraOff : context.l10n.cameraOn,
            icon: cameraOn ? DIcons.videoSlash : DIcons.video,
            selected: cameraOn,
            onPressed: () => controller.setCameraEnabled(!cameraOn),
          ),
        if (canShare)
          VoiceToolbarControl(
            label: call.screenSharing
                ? context.l10n.stopSharing
                : context.l10n.shareScreen,
            icon: DIcons.display,
            selected: call.screenSharing,
            onPressed: () => controller.setScreenSharing(!call.screenSharing),
          ),
        if (call.room.type == VoiceRoomType.stage &&
            role == VoiceRole.participant)
          VoiceToolbarControl(
            label: me?.handRaisedAt == null
                ? context.l10n.raiseHand
                : context.l10n.lowerHand,
            icon: DIcons.hand,
            selected: me?.handRaisedAt != null,
            onPressed: () =>
                controller.requestToSpeak(raised: me?.handRaisedAt == null),
          ),
        VoiceAgentInviteAction(
          controller: controller,
          siteUrl: siteUrl,
          roomId: call.room.id,
        ),
        if (call.room.canInvite)
          VoiceToolbarControl(
            label: context.l10n.invitePeople,
            icon: DIcons.userPlus,
            selected: null,
            onPressed: () => _showVoiceInvite(
              context,
              controller,
              siteUrl: siteUrl,
              room: call.room,
              inviteLink: inviteLink,
            ),
          ),
        if (call.room.chatAvailable)
          VoiceToolbarControl(
            label: context.l10n.roomChat,
            icon: DIcons.comment,
            selected: null,
            onPressed: () => _showVoiceChat(
              context,
              controller,
              siteUrl: siteUrl,
              roomId: call.room.id,
            ),
          ),
        if (call.room.canManage &&
            call.media.transport == VoiceTransport.livekit &&
            recordingEnabled)
          VoiceToolbarControl(
            label: call.room.recording?.active == true
                ? context.l10n.stopRecording
                : context.l10n.startRecording,
            icon: DIcons.circle,
            selected: call.room.recording?.active == true,
            onPressed: () => _confirmRecording(
              context,
              controller,
              siteUrl: call.siteUrl,
              roomId: call.room.id,
              active: call.room.recording?.active == true,
              controllerResolver: controllerResolver,
            ),
          ),
        VoiceToolbarControl(
          label: context.l10n.mediaSettings,
          icon: DIcons.gear,
          selected: null,
          onPressed: () => _showMediaSettings(
            context,
            controller,
            autoStatusAvailable: autoStatusAvailable,
          ),
        ),
        if (call.room.canManage)
          VoiceToolbarControl(
            label: context.l10n.editRoom,
            icon: DIcons.gear,
            selected: null,
            onPressed: () => showVoiceRoomEditor(
              context,
              siteUrl: siteUrl,
              room: call.room,
              // A dialog can outlive the plugin session that opened it when
              // the root app is replaced. Resolve at save time; the explicit
              // controller remains the fallback for standalone widget hosts.
              controllerResolver: () =>
                  _resolveController(context, controller, controllerResolver),
            ),
          ),
        if (call.room.canManage)
          VoiceToolbarControl(
            label: context.l10n.manageMembers,
            icon: DIcons.users,
            selected: null,
            onPressed: () => _showVoiceMembers(
              context,
              controller,
              siteUrl: siteUrl,
              room: call.room,
            ),
          ),
        DButton(
          onPressed: controller.leave,
          icon: const DIcon(DIcons.phoneSlash),
          label: Text(context.l10n.leaveRoom),
          variant: DButtonVariant.destructive,
        ),
      ],
    );
  }
}

/// A Voice toolbar action that preserves controlled toggle state when present.
///
/// This remains plugin-owned: callers outside Voice should use [DToggle] or
/// [DButton] directly. It is public within this library so the isolated review
/// harness can mount the exact production adapter without network/media state.
class VoiceToolbarControl extends StatelessWidget {
  const VoiceToolbarControl({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final DIconData icon;

  /// Null identifies a momentary action; non-null values are controlled
  /// independent toggle state owned by the voice controller.
  final bool? selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => selected == null
      ? DButton.iconOnly(
          onPressed: onPressed,
          variant: DButtonVariant.secondary,
          tooltip: label,
          icon: DIcon(icon),
        )
      : DTooltip(
          message: label,
          excludeFromSemantics: true,
          child: DToggle.iconOnly(
            pressed: selected,
            onPressedChanged: (_) => onPressed(),
            semanticLabel: label,
            icon: DIcon(icon),
          ),
        );
}

class VoiceVideoSurface extends StatelessWidget {
  const VoiceVideoSurface({super.key, required this.track});
  final Object track;

  @override
  Widget build(BuildContext context) => switch (track) {
    final lk.VideoTrack track => lk.VideoTrackRenderer(
      track,
      fit: lk.VideoViewFit.cover,
    ),
    final rtc.MediaStreamTrack track => _RtcTrackRenderer(
      key: ObjectKey(track),
      track: track,
    ),
    _ => const SizedBox.shrink(),
  };
}

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
    _attachment = _attach();
    unawaited(_attachment);
  }

  Future<void> _attach() async {
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
      // A remote peer can disappear while the renderer crosses the platform
      // channel. Video rendering is best-effort and the next track update will
      // create a fresh surface.
    } finally {
      if (pendingStream case final stream?) {
        if (_disposed) {
          _stream = stream;
        } else {
          await _disposeStream(stream);
        }
      }
    }
  }

  Future<void> _disposeRenderer() async {
    try {
      await _renderer.dispose();
    } catch (_) {}
  }

  Future<void> _disposeStream(rtc.MediaStream stream) async {
    try {
      await stream.dispose();
    } catch (_) {
      // The media session may already have released the native resources.
    }
  }

  Future<void> _release() async {
    if (_released) return;
    _released = true;
    if (_rendererReady) await _disposeRenderer();
    if (_stream case final stream?) {
      _stream = null;
      await _disposeStream(stream);
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

Future<void> _showVoiceInvite(
  BuildContext context,
  VoiceController controller, {
  required String siteUrl,
  required VoiceRoom room,
  required String? inviteLink,
}) {
  final ownsAccount = controller.captureSiteSession(siteUrl);
  return showDDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (context, dialog) => _VoiceInviteDialog(
      controller: controller,
      siteUrl: siteUrl,
      room: room,
      inviteLink: inviteLink,
      ownsAccount: ownsAccount,
      dialog: dialog,
    ),
  );
}

class _VoiceInviteDialog extends StatefulWidget {
  const _VoiceInviteDialog({
    required this.controller,
    required this.siteUrl,
    required this.room,
    required this.inviteLink,
    required this.ownsAccount,
    required this.dialog,
  });

  final VoiceController controller;
  final String siteUrl;
  final VoiceRoom room;
  final String? inviteLink;
  final bool Function() ownsAccount;
  final DDialogController<void> dialog;

  @override
  State<_VoiceInviteDialog> createState() => _VoiceInviteDialogState();
}

class _VoiceInviteDialogState extends State<_VoiceInviteDialog> {
  final TextEditingController _username = TextEditingController();
  List<VoiceInviteSuggestion>? _suggestions;
  final Set<String> _invited = {};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSuggestions());
  }

  Future<void> _loadSuggestions() async {
    if (!widget.ownsAccount()) return;
    final suggestions = await widget.controller.inviteSuggestions(
      widget.siteUrl,
      widget.room.id,
    );
    if (mounted && widget.ownsAccount()) {
      setState(() => _suggestions = suggestions);
    }
  }

  /// Whether the invite went through: false when it was refused, and when
  /// nothing was sent because another invite is still in flight.
  Future<bool> _invite(List<String> usernames) async {
    final names = [
      for (final name in usernames)
        if (name.trim().isNotEmpty) name.trim().replaceFirst('@', ''),
    ];
    if (!mounted || !widget.ownsAccount() || names.isEmpty || _sending) {
      return false;
    }
    setState(() => _sending = true);
    try {
      final result = await widget.controller.invite(
        widget.siteUrl,
        widget.room.id,
        names,
      );
      if (!mounted || !widget.ownsAccount()) return false;
      setState(() => _invited.addAll(result.invitedUsernames));
      if (result.invitedUsernames.isNotEmpty) {
        final count = result.invitedUsernames.length;
        DToast.show(
          context,
          count == 1
              ? appL10n.inviteSent
              : appL10n.invitesSent((count).toString()),
          type: DToastType.success,
        );
      }
      if (result.skippedUsernames.isNotEmpty) {
        DToast.show(
          context,
          appL10n.canTBeInvitedBecauseTheyDonTHaveAccessTo(
            (result.skippedUsernames.map((name) => '@$name').join(', '))
                .toString(),
          ),
          type: DToastType.warning,
        );
      }
      return true;
    } catch (error) {
      if (!mounted || !widget.ownsAccount()) return false;
      DToast.show(
        context,
        error is WriteException ? error.message : appL10n.couldnTSendTheInvite,
        type: DToastType.error,
      );
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _inviteTyped() async {
    final typed = _username.text;
    // Cleared only once sent, and never over a name typed since.
    if (await _invite([typed]) && mounted && _username.text == typed) {
      _username.clear();
    }
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    final link = widget.inviteLink;
    final available = widget.ownsAccount() && !_sending;
    return DDialogContent(
      showCloseButton: false,
      maxWidth: 520,
      semanticLabel: context.l10n.inviteTo(widget.room.name),
      children: [
        DDialogHeader(
          children: [
            DDialogTitle(child: Text(context.l10n.inviteTo(widget.room.name))),
          ],
        ),
        DDialogScrollArea(
          maxHeightFactor: .65,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DInput(
                      controller: _username,
                      autofocus: true,
                      labelText: context.l10n.inviteByName,
                      hintText: context.l10n.usernameLowercase,
                      onSubmitted: (_) => unawaited(_inviteTyped()),
                    ),
                  ),
                  const SizedBox(width: DSpacing.sm),
                  DButton(
                    onPressed: available ? _inviteTyped : null,
                    icon: const DIcon(DIcons.paperPlane),
                    label: Text(context.l10n.sendInvite),
                    variant: DButtonVariant.primary,
                    loading: _sending,
                  ),
                ],
              ),
              if (suggestions != null && suggestions.isNotEmpty) ...[
                const SizedBox(height: DSpacing.lg),
                Text(context.l10n.peopleYouVeSharedThisRoomWith),
                for (final suggestion in suggestions)
                  DItem(
                    children: [
                      DItemMedia(
                        variant: DItemMediaVariant.avatar,
                        child: DAvatar.frame(
                          child: SizedBox.square(
                            dimension: 36,
                            child: AvatarImage(
                              url: suggestion.user.avatarUrl(
                                widget.siteUrl,
                                size: 72,
                              ),
                              size: 36,
                              fallback: ColoredBox(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                              ),
                            ),
                          ),
                        ),
                      ),
                      DItemContent(
                        children: [
                          DItemTitle(child: Text(suggestion.user.username)),
                          DItemDescription(
                            child: Text(
                              context.l10n.togetherRecently(
                                _timeTogether(suggestion.totalSeconds),
                              ),
                            ),
                          ),
                        ],
                      ),
                      DItemActions(
                        children: [
                          if (_invited.contains(suggestion.user.username))
                            Text(context.l10n.invited)
                          else
                            DButton(
                              onPressed: available
                                  ? () => _invite([suggestion.user.username])
                                  : null,
                              label: Text(context.l10n.invite),
                            ),
                        ],
                      ),
                    ],
                  ),
              ],
              if (link != null) ...[
                const SizedBox(height: DSpacing.lg),
                Text(context.l10n.orShareAnInviteLink),
                const SizedBox(height: DSpacing.xs),
                Row(
                  children: [
                    Expanded(child: SelectableText(link)),
                    const SizedBox(width: DSpacing.sm),
                    DButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) {
                          DToast.show(
                            context,
                            context.l10n.linkCopiedToClipboard,
                            type: DToastType.success,
                          );
                        }
                      },
                      icon: const DIcon(DIcons.copy),
                      label: Text(context.l10n.copy),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        DDialogFooter(
          children: [
            DButton(
              onPressed: widget.dialog.close,
              label: Text(context.l10n.done),
            ),
          ],
        ),
      ],
    );
  }

  static String _timeTogether(int seconds) {
    if (seconds >= 3600) return '${(seconds / 3600).round()}h';
    if (seconds >= 60) return '${(seconds / 60).round()}m';
    return '${seconds}s';
  }
}

Future<void> _showParticipantVolume(
  BuildContext context,
  VoiceController controller,
  int participantId,
) async {
  final call = controller.call;
  if (call == null) return;
  var volume = await controller.participantVolume(
    call.siteUrl,
    call.room.id,
    participantId,
  );
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(appL10n.participantVolumeVoiceroomview),
        content: VoiceParticipantVolumeSlider(
          value: volume,
          onChanged: (value) {
            setState(() => volume = value);
            unawaited(
              controller.setParticipantVolume(
                call.siteUrl,
                call.room.id,
                participantId,
                value,
              ),
            );
          },
        ),
        actions: [
          DButton(
            onPressed: () => Navigator.pop(context),
            label: Text(appL10n.done),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showMediaSettings(
  BuildContext context,
  VoiceController controller, {
  bool autoStatusAvailable = false,
}) async {
  final devices = await controller.mediaDevices();
  if (!context.mounted) return;
  final inputs = devices
      .where((device) => device.kind == 'audioinput')
      .toList();
  final outputs = devices
      .where((device) => device.kind == 'audiooutput')
      .toList();
  final cameras = devices
      .where((device) => device.kind == 'videoinput')
      .toList();
  var input = _heldDevice(controller.audioInputDeviceId, inputs);
  var output = _heldDevice(controller.audioOutputDeviceId, outputs);
  var camera = _heldDevice(controller.cameraDeviceId, cameras);
  var pushToTalk = controller.pushToTalkEnabled;
  var autoStatus = controller.autoStatusEnabled;
  var testing = false;
  final ownerContext = context;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(appL10n.mediaSettings),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DevicePicker(
                  label: appL10n.microphone,
                  devices: inputs,
                  value: input,
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => input = value);
                    await controller.selectAudioInput(value);
                  },
                ),
                _DevicePicker(
                  label: appL10n.speaker,
                  devices: outputs,
                  value: output,
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => output = value);
                    await controller.selectAudioOutput(value);
                  },
                ),
                _DevicePicker(
                  label: appL10n.camera,
                  devices: cameras,
                  value: camera,
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => camera = value);
                    await controller.selectCamera(value);
                  },
                ),
                if (Platform.isMacOS || Platform.isLinux)
                  DSwitchTile(
                    value: pushToTalk,
                    title: DLabel(child: Text(appL10n.pushToTalk)),
                    subtitle: Text(appL10n.holdSpaceWhileTheRoomIsFocused),
                    onChanged: (value) async {
                      setState(() => pushToTalk = value);
                      await controller.setPushToTalkEnabled(value);
                    },
                  ),
                if (autoStatusAvailable)
                  DSwitchTile(
                    value: autoStatus,
                    title: DLabel(
                      child: Text(appL10n.showMyStatusWhileInACall),
                    ),
                    subtitle: Text(appL10n.setsYourUserStatusToTheRoomYouAreIn),
                    onChanged: (value) async {
                      setState(() => autoStatus = value);
                      await controller.setAutoStatusEnabled(value);
                    },
                  ),
                ListTile(
                  title: Text(appL10n.nativeNoiseSuppression),
                  subtitle: Text(
                    appL10n
                        .echoCancellationNoiseSuppressionAndAutomaticGainControlAreActive,
                  ),
                  trailing: const DIcon(DIcons.check, size: 18),
                ),
                DButton(
                  onPressed: testing
                      ? null
                      : () async {
                          if (testing) return;
                          setState(() => testing = true);
                          try {
                            final available = await _testMicrophone(
                              input,
                              controller.diagnostics,
                            );
                            if (ownerContext.mounted &&
                                context.mounted &&
                                ModalRoute.of(context)?.isCurrent == true) {
                              DToast.show(
                                context,
                                available
                                    ? appL10n.microphoneIsAvailable
                                    : appL10n
                                          .couldnTTestTheMicrophonePleaseTryAgain,
                                type: available
                                    ? DToastType.success
                                    : DToastType.error,
                              );
                            }
                          } finally {
                            if (ownerContext.mounted &&
                                context.mounted &&
                                ModalRoute.of(context)?.isActive == true) {
                              setState(() => testing = false);
                            }
                          }
                        },
                  icon: const DIcon(DIcons.microphoneLines),
                  label: Text(appL10n.testMicrophone),
                  loading: testing,
                  loadingLabel: Text(appL10n.testing),
                ),
              ],
            ),
          ),
        ),
        actions: [
          DButton(
            onPressed: () => Navigator.pop(context),
            label: Text(appL10n.done),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _testMicrophone(
  String? input,
  VoiceDiagnosticsRecorder diagnostics,
) async {
  rtc.MediaStream? stream;
  var available = true;

  void failed(Object error, StackTrace stackTrace, String operation) {
    available = false;
    try {
      diagnostics.record(
        'microphone.test.failed',
        component: 'media',
        severity: DiagnosticSeverity.warning,
        data: {'operation': operation, 'errorType': '${error.runtimeType}'},
      );
      diagnostics.recordRaw(
        'microphone.test.failure_detail',
        component: 'media',
        severity: DiagnosticSeverity.warning,
        message: error.toString(),
        data: {'operation': operation, 'stackTrace': stackTrace.toString()},
      );
    } catch (_) {
      // Diagnostics must not interrupt the remaining native cleanup.
    }
  }

  try {
    stream = await rtc.navigator.mediaDevices.getUserMedia({
      'audio': {
        'deviceId': ?input,
        'echoCancellation': true,
        'noiseSuppression': true,
      },
      'video': false,
    });
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (error, stackTrace) {
        failed(error, stackTrace, 'voice.microphone.test.stopTrack');
      }
    }
  } catch (error, stackTrace) {
    failed(error, stackTrace, 'voice.microphone.test.capture');
  } finally {
    if (stream != null) {
      try {
        await stream.dispose();
      } catch (error, stackTrace) {
        failed(error, stackTrace, 'voice.microphone.test.disposeStream');
      }
    }
  }
  return available;
}

String? _heldDevice(String? held, List<rtc.MediaDeviceInfo> devices) =>
    devices.any((device) => device.deviceId == held)
    ? held
    : devices.firstOrNull?.deviceId;

class _DevicePicker extends StatelessWidget {
  const _DevicePicker({
    required this.label,
    required this.devices,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<rtc.MediaDeviceInfo> devices;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DSelect<String>.controlled(
    isExpanded: true,
    value: value,
    label: Text(label),
    onChanged: devices.isEmpty ? null : onChanged,
    entries: [
      for (final device in devices)
        DSelectOption(
          value: device.deviceId,
          label: device.label.isEmpty
              ? context.l10n.messageDefaultVoiceroomview((label).toString())
              : device.label,
          child: Text(
            device.label.isEmpty
                ? context.l10n.messageDefaultVoiceroomview((label).toString())
                : device.label,
          ),
        ),
    ],
    initialValue: value,
    enabled: devices.isNotEmpty,
  );
}

Future<void> _showParticipantFlag(
  BuildContext context,
  VoiceController controller,
  VoiceParticipant participant, {
  required String siteUrl,
  required int roomId,
  VoiceController Function()? controllerResolver,
}) async {
  final ownsAccount = controller.captureSiteSession(siteUrl);
  final message = await showDDialog<String>(
    context: context,
    builder: (context, dialog) => _ParticipantFlagDialog(
      username: participant.username,
      onClose: dialog.close,
    ),
  );
  if (message == null || message.trim().isEmpty || !context.mounted) return;
  final current = _resolveController(context, controller, controllerResolver);
  final call = current.call;
  if (!ownsAccount() || call?.siteUrl != siteUrl || call?.room.id != roomId) {
    return;
  }
  final sent = await current.flagParticipant(participant.id, message);
  if (!sent && context.mounted) {
    DToast.show(
      context,
      appL10n.moderatorNotificationIsUnavailable,
      type: DToastType.error,
    );
  }
}

class _ParticipantFlagDialog extends StatefulWidget {
  const _ParticipantFlagDialog({required this.username, required this.onClose});

  final String username;
  final ValueChanged<String?> onClose;

  @override
  State<_ParticipantFlagDialog> createState() => _ParticipantFlagDialogState();
}

class _ParticipantFlagDialogState extends State<_ParticipantFlagDialog> {
  final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DDialogContent(
    maxWidth: 528,
    semanticLabel: context.l10n.notifyModeratorsAbout(widget.username),
    showCloseButton: false,
    children: [
      DDialogHeader(
        children: [
          DDialogTitle(
            child: Text(context.l10n.notifyModeratorsAbout(widget.username)),
          ),
        ],
      ),
      DTextarea(
        controller: _message,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        labelText: context.l10n.whatShouldModeratorsKnow,
      ),
      DDialogFooter(
        children: [
          DButton(
            onPressed: () => widget.onClose(null),
            label: Text(context.l10n.cancel),
            variant: DButtonVariant.outline,
          ),
          DButton(
            onPressed: () => widget.onClose(_message.text),
            label: Text(context.l10n.notify),
            variant: DButtonVariant.primary,
          ),
        ],
      ),
    ],
  );
}

Future<void> _confirmRecording(
  BuildContext context,
  VoiceController controller, {
  required String siteUrl,
  required int roomId,
  required bool active,
  VoiceController Function()? controllerResolver,
}) async {
  final ownsAccount = controller.captureSiteSession(siteUrl);
  final confirmed = await showDiscourseAlertDialog<bool>(
    context: context,
    title: Text(
      active
          ? appL10n.stopRecordingVoiceroomview
          : appL10n.startRecordingVoiceroomview,
    ),
    description: Text(
      active
          ? appL10n.theCurrentRoomRecordingWillStop
          : appL10n.everyParticipantWillSeeThatThisRoomIsBeingRecorded,
    ),
    cancelLabel: Text(appL10n.cancel),
    actionLabel: Text(active ? appL10n.stop : appL10n.start),
    cancelResult: false,
    actionResult: true,
    actionVariant: active ? DButtonVariant.destructive : DButtonVariant.primary,
  );
  if (confirmed == true && context.mounted) {
    final current = _resolveController(context, controller, controllerResolver);
    final call = current.call;
    if (!ownsAccount() || call?.siteUrl != siteUrl || call?.room.id != roomId) {
      return;
    }
    await current.setRecording(!active);
  }
}

VoiceController _resolveController(
  BuildContext context,
  VoiceController fallback,
  VoiceController Function()? resolver,
) =>
    resolver?.call() ??
    PluginUiScope.maybe(context, voiceControllerService) ??
    fallback;

Future<void> _showVoiceChat(
  BuildContext context,
  VoiceController controller, {
  required String siteUrl,
  required int roomId,
}) async {
  unawaited(controller.openChat(siteUrl, roomId));
  try {
    await showDSheet<void>(
      context: context,
      side: DSheetSide.bottom,
      builder: (context, _) => DSheetContent(
        side: DSheetSide.bottom,
        topBottomMaxHeightFactor: .85,
        semanticLabel: appL10n.roomChat,
        children: [
          DSheetHeader(children: [DSheetTitle(child: Text(appL10n.roomChat))]),
          _VoiceChatSheet(
            controller: controller,
            siteUrl: siteUrl,
            roomId: roomId,
          ),
        ],
      ),
    );
  } finally {
    controller.closeChat(siteUrl, roomId);
  }
}

class _VoiceChatSheet extends StatefulWidget {
  const _VoiceChatSheet({
    required this.controller,
    required this.siteUrl,
    required this.roomId,
  });

  final VoiceController controller;
  final String siteUrl;
  final int roomId;

  @override
  State<_VoiceChatSheet> createState() => _VoiceChatSheetState();
}

class _VoiceChatSheetState extends State<_VoiceChatSheet> {
  final TextEditingController _composer = TextEditingController();

  /// Spans this sheet's whole send, including the credential read the
  /// controller awaits before it reports the room chat as sending.
  bool _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  VoiceChatSnapshot? get _chat =>
      widget.controller.chat(widget.siteUrl, widget.roomId);

  Future<void> _send() async {
    final text = _composer.text;
    if (_sending || (_chat?.sending ?? false) || text.trim().isEmpty) return;
    // Cleared up front so the next message can be written while this one is
    // in flight. A failed send hands its text back only to an empty
    // composer, never over what was typed since.
    _composer.clear();
    setState(() => _sending = true);
    await widget.controller.sendChatMessage(
      widget.siteUrl,
      widget.roomId,
      text,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (_chat?.error != null && _composer.text.isEmpty) {
      _composer.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final chat = _chat;
                return Column(
                  children: [
                    if (chat?.error case final error?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: DSpacing.sm),
                        child: DAlert(
                          variant: DAlertVariant.destructive,
                          description: DAlertDescription(child: Text(error)),
                        ),
                      ),
                    Expanded(child: _messages(chat)),
                  ],
                );
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: DTextarea(
                  controller: _composer,
                  minLines: 1,
                  maxLines: 4,
                  hintText: context.l10n.messageTheRoom,
                ),
              ),
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) => DButton.iconOnly(
                  onPressed: _send,
                  loading: _sending || (_chat?.sending ?? false),
                  variant: DButtonVariant.primary,
                  tooltip: context.l10n.sendMessage,
                  icon: const DIcon(DIcons.paperPlane),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _messages(VoiceChatSnapshot? chat) {
    if (chat == null) return const SizedBox.shrink();
    if (chat.messages.isEmpty) {
      // Lists draw no loading indicator, and a failure is told by the alert
      // rather than read as an empty room.
      return chat.loading || chat.error != null
          ? const SizedBox.shrink()
          : Center(child: Text(appL10n.noMessagesYetVoiceroomview));
    }
    return ListView.builder(
      itemCount: chat.messages.length + (chat.canLoadMorePast ? 1 : 0),
      itemBuilder: (context, index) {
        if (chat.canLoadMorePast && index == 0) {
          return Center(
            child: DButton(
              onPressed: () => widget.controller.loadOlderChat(
                widget.siteUrl,
                widget.roomId,
              ),
              label: Text(appL10n.loadOlderMessages),
              variant: DButtonVariant.link,
            ),
          );
        }
        final message = chat.messages[index - (chat.canLoadMorePast ? 1 : 0)];
        return ListTile(
          title: Text(message.author.displayName),
          subtitle: CookedHtml(html: message.cooked, siteUrl: widget.siteUrl),
        );
      },
    );
  }
}

Future<void> _showVoiceMembers(
  BuildContext context,
  VoiceController controller, {
  required String siteUrl,
  required VoiceRoom room,
}) async {
  final ownsAccount = controller.captureSiteSession(siteUrl);
  final memberships = await controller.memberships(siteUrl, room.id);
  if (!context.mounted || !ownsAccount()) return;
  if (memberships == null) {
    DToast.show(
      context,
      appL10n.couldnTLoadTheRoomSMembers,
      type: DToastType.error,
    );
    return;
  }
  await showDDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (context, dialog) => _VoiceMembersDialog(
      controller: controller,
      siteUrl: siteUrl,
      room: room,
      initialMemberships: memberships,
      ownsAccount: ownsAccount,
      dialog: dialog,
    ),
  );
}

class _VoiceMembersDialog extends StatefulWidget {
  const _VoiceMembersDialog({
    required this.controller,
    required this.siteUrl,
    required this.room,
    required this.initialMemberships,
    required this.ownsAccount,
    required this.dialog,
  });

  final VoiceController controller;
  final String siteUrl;
  final VoiceRoom room;
  final List<VoiceMembership> initialMemberships;
  final bool Function() ownsAccount;
  final DDialogController<void> dialog;

  @override
  State<_VoiceMembersDialog> createState() => _VoiceMembersDialogState();
}

class _VoiceMembersDialogState extends State<_VoiceMembersDialog> {
  final TextEditingController _username = TextEditingController();
  late List<VoiceMembership> _memberships = widget.initialMemberships;
  VoiceRole _newRole = VoiceRole.participant;

  /// Spans a write and the roster read after it, so no second change starts
  /// against rows that are about to be replaced.
  bool _writing = false;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _updateMember(VoiceMembership membership, VoiceRole role) =>
      _write(
        () => widget.controller.updateMember(
          widget.siteUrl,
          widget.room.id,
          membership.id,
          role,
        ),
      );

  Future<void> _removeMember(VoiceMembership membership) => _write(
    () => widget.controller.removeMember(
      widget.siteUrl,
      widget.room.id,
      membership.id,
    ),
  );

  Future<void> _addMember() async {
    final typed = _username.text;
    final value = typed.trim();
    if (value.isEmpty) return;
    await _write(
      () => widget.controller.addMember(
        widget.siteUrl,
        widget.room.id,
        value,
        _newRole,
      ),
      onSuccess: () {
        // Cleared only once added, and never over a name typed since.
        if (_username.text == typed) _username.clear();
      },
    );
  }

  Future<void> _write(
    Future<String?> Function() write, {
    VoidCallback? onSuccess,
  }) async {
    if (!mounted || !widget.ownsAccount() || _writing) return;
    setState(() => _writing = true);
    try {
      final error = await write();
      if (!mounted || !widget.ownsAccount()) return;
      if (error != null) {
        DToast.show(context, error, type: DToastType.error);
        return;
      }
      onSuccess?.call();
      await _refreshMemberships();
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _refreshMemberships() async {
    if (!mounted || !widget.ownsAccount()) return;
    final memberships = await widget.controller.memberships(
      widget.siteUrl,
      widget.room.id,
    );
    if (!mounted || !widget.ownsAccount()) return;
    if (memberships == null) {
      DToast.show(
        context,
        appL10n.couldnTRefreshTheRoomSMembers,
        type: DToastType.error,
      );
      return;
    }
    setState(() => _memberships = memberships);
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.ownsAccount() && !_writing;
    return DDialogContent(
      showCloseButton: false,
      maxWidth: 560,
      semanticLabel: context.l10n.membersOf(widget.room.name),
      children: [
        DDialogHeader(
          children: [
            DDialogTitle(child: Text(context.l10n.membersOf(widget.room.name))),
          ],
        ),
        DDialogScrollArea(
          maxHeightFactor: .5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final membership in _memberships)
                DItem(
                  children: [
                    DItemContent(
                      children: [
                        DItemTitle(
                          child: Text(
                            membership.user?.name ??
                                membership.user?.username ??
                                context.l10n.user(membership.userId.toString()),
                          ),
                        ),
                        DItemDescription(child: Text(membership.role.name)),
                      ],
                    ),
                    DItemActions(
                      children: [
                        DDropdownMenu(
                          content: DDropdownMenuContent(
                            semanticLabel: context.l10n.changeRole,
                            width: 280,
                            children: [
                              for (final role in VoiceRole.values)
                                DDropdownMenuItem(
                                  onPressed: () =>
                                      _updateMember(membership, role),
                                  child: Text(role.name),
                                ),
                            ],
                          ),
                          child: DDropdownMenuTrigger(
                            builder: (triggerContext, state) =>
                                DButton.iconOnly(
                                  tooltip: context.l10n.changeRole,
                                  variant: DButtonVariant.ghost,
                                  icon: const DIcon(DIcons.ellipsisVertical),
                                  focusNode: state.focusNode,
                                  hasPopup: true,
                                  expanded: state.open,
                                  onPressed: available ? state.toggle : null,
                                ),
                          ),
                        ),
                        if (membership.userId != widget.room.creatorId)
                          DButton.iconOnly(
                            onPressed: available
                                ? () => _removeMember(membership)
                                : null,
                            variant: DButtonVariant.ghost,
                            tooltip: context.l10n.removeMember,
                            icon: const DIcon(DIcons.trashCan),
                          ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
        const DSeparator(),
        Row(
          children: [
            Expanded(
              child: DInput(
                controller: _username,
                labelText: context.l10n.username,
              ),
            ),
            const SizedBox(width: DSpacing.sm),
            SizedBox(
              width: 120,
              child: DSelect<VoiceRole>.controlled(
                isExpanded: true,
                value: _newRole,
                onChanged: (value) =>
                    setState(() => _newRole = value ?? _newRole),
                entries: [
                  for (final role in VoiceRole.values)
                    DSelectOption(
                      value: role,
                      label: role.name,
                      child: Text(role.name),
                    ),
                ],
                initialValue: _newRole,
              ),
            ),
            DButton.iconOnly(
              onPressed: available ? _addMember : null,
              variant: DButtonVariant.secondary,
              tooltip: context.l10n.addMember,
              icon: const DIcon(DIcons.userPlus),
            ),
          ],
        ),
        DDialogFooter(
          children: [
            DButton(
              onPressed: widget.dialog.close,
              label: Text(context.l10n.done),
            ),
          ],
        ),
      ],
    );
  }
}

/// Local participant-volume input; persistence and call ownership stay in the caller.
class VoiceParticipantVolumeSlider extends StatelessWidget {
  const VoiceParticipantVolumeSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final double value;
  final ValueChanged<double>? onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 280,
    height: 48,
    child: DSlider(
      value: value,
      max: 1,
      step: 0.1,
      semanticLabel: context.l10n.participantVolumeVoiceroomview,
      semanticFormatterCallback: (value) => '${(value * 100).round()}%',
      onChanged: onChanged,
    ),
  );
}
