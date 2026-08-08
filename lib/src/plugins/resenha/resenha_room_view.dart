import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../shell/avatar_image.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'resenha_controller.dart';
import 'resenha_models.dart';

class ResenhaRoomView extends StatelessWidget {
  const ResenhaRoomView({super.key, required this.roomId});

  final int roomId;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final site = shell.currentInstance;
    if (site == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: shell.resenha,
      builder: (context, _) {
        final room = shell.resenha.room(site.url, roomId);
        if (room == null) {
          return const Center(child: Text('This voice room is unavailable.'));
        }
        final call = shell.resenha.call;
        final inRoom = call?.siteUrl == site.url && call?.room.id == room.id;
        return Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (!shell.resenha.pushToTalkEnabled ||
                (!Platform.isMacOS && !Platform.isLinux) ||
                event.logicalKey != LogicalKeyboardKey.space) {
              return KeyEventResult.ignored;
            }
            if (event is KeyDownEvent) {
              unawaited(shell.resenha.setMuted(false));
            } else if (event is KeyUpEvent) {
              unawaited(shell.resenha.setMuted(true));
            }
            return KeyEventResult.handled;
          },
          child: _RoomBody(
            room: inRoom ? call!.room : room,
            call: inRoom ? call : null,
            siteUrl: site.url,
            siteName: site.title,
          ),
        );
      },
    );
  }
}

class _RoomBody extends StatelessWidget {
  const _RoomBody({
    required this.room,
    required this.call,
    required this.siteUrl,
    required this.siteName,
  });

  final ResenhaRoom room;
  final ResenhaCallSnapshot? call;
  final String siteUrl;
  final String siteName;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context).resenha;
    final active = call;
    return Column(
      children: [
        if (active?.error case final error?)
          MaterialBanner(
            content: Text(error),
            actions: [
              TextButton(
                onPressed: controller.dismissCallError,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final participants = room.participants;
              if (participants.isEmpty) {
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
                itemCount: participants.length,
                itemBuilder: (context, index) {
                  final participant = participants[index];
                  final currentUserId = ShellScope.read(
                    context,
                  ).currentInstance?.user?.id;
                  return _ParticipantTile(
                    participant: participant,
                    siteUrl: siteUrl,
                    videoTrack: active?.media.videoTrackFor(participant.id),
                    speaking:
                        active?.media.speakingParticipantIds.contains(
                          participant.id,
                        ) ??
                        false,
                    canManage: active?.room.canManage ?? false,
                    canKick:
                        active?.room.canManage == true &&
                        participant.id != currentUserId &&
                        participant.id != room.creatorId,
                    canAdjustLocally:
                        active != null && participant.id != currentUserId,
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: active == null
                ? FilledButton.icon(
                    onPressed: () => controller.join(
                      siteUrl: siteUrl,
                      siteName: siteName,
                      room: room,
                    ),
                    icon: const DIcon(DIcons.microphoneLines, size: 18),
                    label: const Text('Join room'),
                  )
                : _CallControls(call: active, siteUrl: siteUrl),
          ),
        ),
      ],
    );
  }
}

class _EmptyRoom extends StatelessWidget {
  const _EmptyRoom({required this.room});
  final ResenhaRoom room;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const DIcon(DIcons.microphoneLines, size: 52),
        const SizedBox(height: 12),
        Text('Nobody is in ${room.name} yet.'),
        if (room.description case final description?) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(description, textAlign: TextAlign.center),
          ),
        ],
      ],
    ),
  );
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.siteUrl,
    required this.videoTrack,
    required this.speaking,
    required this.canManage,
    required this.canKick,
    required this.canAdjustLocally,
  });

  final ResenhaParticipant participant;
  final String siteUrl;
  final Object? videoTrack;
  final bool speaking;
  final bool canManage;
  final bool canKick;
  final bool canAdjustLocally;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: [
        participant.name ?? participant.username,
        if (speaking) 'speaking',
        if (participant.muted) 'muted',
        if (participant.handRaisedAt != null) 'hand raised',
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
                ResenhaVideoSurface(track: videoTrack!)
              else
                Center(
                  child: ClipOval(
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
                  child: PopupMenuButton<String>(
                    tooltip: 'Participant actions',
                    onSelected: (action) async {
                      final controller = ShellScope.read(context).resenha;
                      if (action == 'kick') {
                        await controller.kick(participant.id);
                      }
                      if (action == 'dismiss') {
                        await controller.requestToSpeak(
                          userId: participant.id,
                          raised: false,
                        );
                      }
                      if (action == 'volume' && context.mounted) {
                        await _showParticipantVolume(context, participant.id);
                      }
                      if (action == 'flag' && context.mounted) {
                        await _showParticipantFlag(context, participant);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'volume',
                        child: Text('Local volume'),
                      ),
                      const PopupMenuItem(
                        value: 'flag',
                        child: Text('Notify moderators'),
                      ),
                      if (participant.handRaisedAt != null)
                        const PopupMenuItem(
                          value: 'dismiss',
                          child: Text('Dismiss raised hand'),
                        ),
                      if (canKick)
                        const PopupMenuItem(
                          value: 'kick',
                          child: Text('Remove from room'),
                        ),
                    ],
                    icon: const DIcon(
                      DIcons.ellipsis,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({required this.call, required this.siteUrl});
  final ResenhaCallSnapshot call;
  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final controller = shell.resenha;
    final canPublishVideo = call.room.videoAllowed;
    final canShare = (Platform.isMacOS || Platform.isLinux) && canPublishVideo;
    final currentUserId = shell.currentInstance?.user?.id;
    final me = call.room.participants
        .where((participant) => participant.id == currentUserId)
        .firstOrNull;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _Control(
          label: call.muted ? 'Unmute' : 'Mute',
          icon: call.muted ? DIcons.microphoneSlash : DIcons.microphoneLines,
          selected: call.muted,
          onPressed: () => controller.setMuted(!call.muted),
        ),
        _Control(
          label: call.deafened ? 'Listen' : 'Deafen',
          icon: DIcons.earListen,
          selected: call.deafened,
          onPressed: () => controller.setDeafened(!call.deafened),
        ),
        if (canPublishVideo)
          _Control(
            label: call.cameraEnabled ? 'Camera off' : 'Camera on',
            icon: call.cameraEnabled ? DIcons.videoSlash : DIcons.video,
            selected: call.cameraEnabled,
            onPressed: () => controller.setCameraEnabled(!call.cameraEnabled),
          ),
        if (canShare)
          _Control(
            label: call.screenSharing ? 'Stop sharing' : 'Share screen',
            icon: DIcons.display,
            selected: call.screenSharing,
            onPressed: () => controller.setScreenSharing(!call.screenSharing),
          ),
        if (call.room.type == ResenhaRoomType.stage &&
            me?.role == ResenhaRole.participant)
          _Control(
            label: me?.handRaisedAt == null ? 'Raise hand' : 'Lower hand',
            icon: DIcons.hand,
            selected: me?.handRaisedAt != null,
            onPressed: () =>
                controller.requestToSpeak(raised: me?.handRaisedAt == null),
          ),
        if (call.room.chatAvailable)
          _Control(
            label: 'Room chat',
            icon: DIcons.comment,
            selected: false,
            onPressed: () => showResenhaChat(
              context,
              siteUrl: siteUrl,
              roomId: call.room.id,
            ),
          ),
        if (call.room.canManage &&
            call.media.transport == ResenhaTransport.livekit &&
            shell.siteConfigFor(siteUrl).resenha.recordingEnabled)
          _Control(
            label: call.room.recording?.active == true
                ? 'Stop recording'
                : 'Start recording',
            icon: DIcons.circle,
            selected: call.room.recording?.active == true,
            onPressed: () => _confirmRecording(
              context,
              active: call.room.recording?.active == true,
            ),
          ),
        _Control(
          label: 'Media settings',
          icon: DIcons.gear,
          selected: false,
          onPressed: () => _showMediaSettings(context),
        ),
        if (call.room.canManage)
          _Control(
            label: 'Edit room',
            icon: DIcons.gear,
            selected: false,
            onPressed: () => showResenhaRoomEditor(
              context,
              siteUrl: siteUrl,
              room: call.room,
            ),
          ),
        if (call.room.canManage)
          _Control(
            label: 'Manage members',
            icon: DIcons.users,
            selected: false,
            onPressed: () =>
                showResenhaMembers(context, siteUrl: siteUrl, room: call.room),
          ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: controller.leave,
          icon: const DIcon(DIcons.phoneSlash, size: 18),
          label: const Text('Leave room'),
        ),
      ],
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final DIconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: label,
    isSelected: selected,
    onPressed: onPressed,
    icon: DIcon(icon, size: 19),
  );
}

class ResenhaVideoSurface extends StatelessWidget {
  const ResenhaVideoSurface({super.key, required this.track});
  final Object track;

  @override
  Widget build(BuildContext context) => switch (track) {
    final lk.VideoTrack track => lk.VideoTrackRenderer(
      track,
      fit: lk.VideoViewFit.cover,
    ),
    final rtc.MediaStreamTrack track => _RtcTrackRenderer(track: track),
    _ => const SizedBox.shrink(),
  };
}

class _RtcTrackRenderer extends StatefulWidget {
  const _RtcTrackRenderer({required this.track});
  final rtc.MediaStreamTrack track;

  @override
  State<_RtcTrackRenderer> createState() => _RtcTrackRendererState();
}

class _RtcTrackRendererState extends State<_RtcTrackRenderer> {
  final rtc.RTCVideoRenderer _renderer = rtc.RTCVideoRenderer();
  rtc.MediaStream? _stream;

  @override
  void initState() {
    super.initState();
    unawaited(_attach());
  }

  Future<void> _attach() async {
    await _renderer.initialize();
    final stream = await rtc.createLocalMediaStream('resenha-video-surface');
    await stream.addTrack(widget.track);
    _stream = stream;
    _renderer.srcObject = stream;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_RtcTrackRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      unawaited(_stream?.removeTrack(oldWidget.track));
      unawaited(_stream?.addTrack(widget.track));
    }
  }

  @override
  Widget build(BuildContext context) => rtc.RTCVideoView(
    _renderer,
    objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  );

  @override
  void dispose() {
    _renderer.srcObject = null;
    unawaited(_renderer.dispose());
    unawaited(_stream?.dispose());
    super.dispose();
  }
}

Future<void> _showParticipantVolume(
  BuildContext context,
  int participantId,
) async {
  final controller = ShellScope.read(context).resenha;
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
        title: const Text('Participant volume'),
        content: Slider(
          value: volume,
          divisions: 10,
          label: '${(volume * 100).round()}%',
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showMediaSettings(BuildContext context) async {
  final controller = ShellScope.read(context).resenha;
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
  var testing = false;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Media settings'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DevicePicker(
                  label: 'Microphone',
                  devices: inputs,
                  value: input,
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => input = value);
                    await controller.selectAudioInput(value);
                  },
                ),
                _DevicePicker(
                  label: 'Speaker',
                  devices: outputs,
                  value: output,
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => output = value);
                    await controller.selectAudioOutput(value);
                  },
                ),
                _DevicePicker(
                  label: 'Camera',
                  devices: cameras,
                  value: camera,
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => camera = value);
                    await controller.selectCamera(value);
                  },
                ),
                if (Platform.isMacOS || Platform.isLinux)
                  SwitchListTile(
                    value: pushToTalk,
                    title: const Text('Push to talk'),
                    subtitle: const Text(
                      'Hold Space while the room is focused.',
                    ),
                    onChanged: (value) async {
                      setState(() => pushToTalk = value);
                      await controller.setPushToTalkEnabled(value);
                    },
                  ),
                ListTile(
                  title: const Text('Native noise suppression'),
                  subtitle: const Text(
                    'Echo cancellation, noise suppression, and automatic gain control are active.',
                  ),
                  trailing: const DIcon(DIcons.check, size: 18),
                ),
                FilledButton.tonalIcon(
                  onPressed: testing
                      ? null
                      : () async {
                          setState(() => testing = true);
                          try {
                            final stream = await rtc.navigator.mediaDevices
                                .getUserMedia({
                                  'audio': {
                                    'deviceId': ?input,
                                    'echoCancellation': true,
                                    'noiseSuppression': true,
                                  },
                                  'video': false,
                                });
                            for (final track in stream.getTracks()) {
                              await track.stop();
                            }
                            await stream.dispose();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Microphone is available.'),
                                ),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setState(() => testing = false);
                            }
                          }
                        },
                  icon: const DIcon(DIcons.microphoneLines, size: 17),
                  label: Text(testing ? 'Testing…' : 'Test microphone'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
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
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    onChanged: devices.isEmpty ? null : onChanged,
    items: [
      for (final device in devices)
        DropdownMenuItem(
          value: device.deviceId,
          child: Text(device.label.isEmpty ? 'Default $label' : device.label),
        ),
    ],
  );
}

Future<void> _showParticipantFlag(
  BuildContext context,
  ResenhaParticipant participant,
) async {
  final message = TextEditingController();
  final submit = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Notify moderators about @${participant.username}'),
      content: TextField(
        controller: message,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: 'What should moderators know?',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Notify'),
        ),
      ],
    ),
  );
  final text = message.text;
  message.dispose();
  if (submit != true || text.trim().isEmpty || !context.mounted) return;
  final sent = await ShellScope.read(
    context,
  ).resenha.flagParticipant(participant.id, text);
  if (!sent && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Moderator notification is unavailable.')),
    );
  }
}

Future<void> _confirmRecording(
  BuildContext context, {
  required bool active,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(active ? 'Stop recording?' : 'Start recording?'),
      content: Text(
        active
            ? 'The current room recording will stop.'
            : 'Every participant will see that this room is being recorded.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(active ? 'Stop' : 'Start'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await ShellScope.read(context).resenha.setRecording(!active);
  }
}

Future<void> showResenhaChat(
  BuildContext context, {
  required String siteUrl,
  required int roomId,
}) async {
  final controller = ShellScope.read(context).resenha;
  unawaited(controller.openChat(siteUrl, roomId));
  final composer = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'Room chat',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const DIcon(DIcons.xmark, size: 18),
                  ),
                ],
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final chat = controller.chat(siteUrl, roomId);
                    if (chat == null || chat.loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (chat.messages.isEmpty) {
                      return const Center(child: Text('No messages yet.'));
                    }
                    return ListView.builder(
                      itemCount:
                          chat.messages.length + (chat.canLoadMorePast ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (chat.canLoadMorePast && index == 0) {
                          return Center(
                            child: TextButton(
                              onPressed: () =>
                                  controller.loadOlderChat(siteUrl, roomId),
                              child: const Text('Load older messages'),
                            ),
                          );
                        }
                        final message = chat
                            .messages[index - (chat.canLoadMorePast ? 1 : 0)];
                        return ListTile(
                          title: Text(message.author.displayName),
                          subtitle: HtmlWidget(message.cooked),
                        );
                      },
                    );
                  },
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: composer,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Message the room',
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Send message',
                    onPressed: () async {
                      final text = composer.text;
                      composer.clear();
                      await controller.sendChatMessage(siteUrl, roomId, text);
                    },
                    icon: const DIcon(DIcons.paperPlane, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  composer.dispose();
}

Future<void> showResenhaMembers(
  BuildContext context, {
  required String siteUrl,
  required ResenhaRoom room,
}) async {
  final controller = ShellScope.read(context).resenha;
  var memberships = await controller.memberships(siteUrl, room.id);
  if (!context.mounted) return;
  final username = TextEditingController();
  var newRole = ResenhaRole.participant;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Members of ${room.name}'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final membership in memberships)
                      ListTile(
                        title: Text(
                          membership.user?.name ??
                              membership.user?.username ??
                              'User ${membership.userId}',
                        ),
                        subtitle: Text(membership.role.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PopupMenuButton<ResenhaRole>(
                              tooltip: 'Change role',
                              onSelected: (role) async {
                                await controller.updateMember(
                                  siteUrl,
                                  room.id,
                                  membership.id,
                                  role,
                                );
                                memberships = await controller.memberships(
                                  siteUrl,
                                  room.id,
                                );
                                setState(() {});
                              },
                              itemBuilder: (context) => [
                                for (final role in ResenhaRole.values)
                                  PopupMenuItem(
                                    value: role,
                                    child: Text(role.name),
                                  ),
                              ],
                            ),
                            if (membership.userId != room.creatorId)
                              IconButton(
                                tooltip: 'Remove member',
                                onPressed: () async {
                                  await controller.removeMember(
                                    siteUrl,
                                    room.id,
                                    membership.id,
                                  );
                                  memberships = await controller.memberships(
                                    siteUrl,
                                    room.id,
                                  );
                                  setState(() {});
                                },
                                icon: const DIcon(DIcons.trashCan, size: 17),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: username,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<ResenhaRole>(
                    value: newRole,
                    onChanged: (value) =>
                        setState(() => newRole = value ?? newRole),
                    items: [
                      for (final role in ResenhaRole.values)
                        DropdownMenuItem(value: role, child: Text(role.name)),
                    ],
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Add member',
                    onPressed: () async {
                      final value = username.text.trim();
                      if (value.isEmpty) return;
                      await controller.addMember(
                        siteUrl,
                        room.id,
                        value,
                        newRole,
                      );
                      username.clear();
                      memberships = await controller.memberships(
                        siteUrl,
                        room.id,
                      );
                      setState(() {});
                    },
                    icon: const DIcon(DIcons.userPlus, size: 17),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
  username.dispose();
}

Future<void> showResenhaRoomEditor(
  BuildContext context, {
  required String siteUrl,
  ResenhaRoom? room,
}) async {
  final name = TextEditingController(text: room?.name);
  final description = TextEditingController(text: room?.description);
  final maximum = TextEditingController(
    text: room?.maxParticipants?.toString(),
  );
  final chatChannel = TextEditingController(
    text: room?.chatChannelId?.toString(),
  );
  final chatIdle = TextEditingController(
    text: room?.chatIdleMinutes?.toString(),
  );
  final chatTitle = TextEditingController(text: room?.chatThreadTitleTemplate);
  var isPublic = room?.isPublic ?? true;
  var stage = room?.type == ResenhaRoomType.stage;
  var video = room?.videoEnabled ?? true;
  var livekit = room?.livekitEnabled ?? false;
  var quality = room?.maxQualityProfile ?? ResenhaQualityProfile.maximum;
  final result = await showDialog<ResenhaRoomDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(room == null ? 'Create voice room' : 'Edit voice room'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                  minLines: 2,
                  maxLines: 5,
                ),
                SwitchListTile(
                  value: isPublic,
                  onChanged: (value) => setState(() => isPublic = value),
                  title: const Text('Public room'),
                ),
                SwitchListTile(
                  value: stage,
                  onChanged: (value) => setState(() => stage = value),
                  title: const Text('Stage room'),
                ),
                SwitchListTile(
                  value: video,
                  onChanged: (value) => setState(() => video = value),
                  title: const Text('Allow video'),
                ),
                TextField(
                  controller: maximum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum participants',
                  ),
                ),
                DropdownButtonFormField<ResenhaQualityProfile>(
                  initialValue: quality,
                  decoration: const InputDecoration(
                    labelText: 'Maximum media quality',
                  ),
                  onChanged: (value) =>
                      setState(() => quality = value ?? quality),
                  items: [
                    for (final value in ResenhaQualityProfile.values)
                      DropdownMenuItem(value: value, child: Text(value.name)),
                  ],
                ),
                TextField(
                  controller: chatChannel,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Chat channel ID (optional)',
                  ),
                ),
                TextField(
                  controller: chatIdle,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Chat idle minutes',
                  ),
                ),
                TextField(
                  controller: chatTitle,
                  decoration: const InputDecoration(
                    labelText: 'Chat thread title template',
                  ),
                ),
                if (room?.livekitEnabled != null)
                  SwitchListTile(
                    value: livekit,
                    onChanged: (value) => setState(() => livekit = value),
                    title: const Text('Use LiveKit'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: name.text.trim().isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    ResenhaRoomDraft(
                      name: name.text.trim(),
                      description: description.text.trim(),
                      isPublic: isPublic,
                      type: stage
                          ? ResenhaRoomType.stage
                          : ResenhaRoomType.open,
                      videoEnabled: video,
                      maxParticipants: int.tryParse(maximum.text),
                      chatChannelId: int.tryParse(chatChannel.text),
                      chatIdleMinutes: int.tryParse(chatIdle.text),
                      chatThreadTitleTemplate: chatTitle.text.trim(),
                      livekitEnabled: room?.livekitEnabled == null
                          ? null
                          : livekit,
                      maxQualityProfile: quality,
                    ),
                  ),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  description.dispose();
  maximum.dispose();
  chatChannel.dispose();
  chatIdle.dispose();
  chatTitle.dispose();
  if (result == null || !context.mounted) return;
  await ShellScope.read(
    context,
  ).resenha.saveRoom(siteUrl: siteUrl, draft: result, roomId: room?.id);
}
