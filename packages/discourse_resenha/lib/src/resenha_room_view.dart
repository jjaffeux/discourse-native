import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'resenha_controller.dart';
import 'resenha_models.dart';
import 'resenha_room_editor.dart';
import 'resenha_services.dart';
import 'resenha_shell_service.dart';

export 'resenha_room_editor.dart' show showResenhaRoomEditor;

class ResenhaRoomView extends StatelessWidget {
  const ResenhaRoomView({
    super.key,
    required this.roomId,
    this.controller,
    this.shell,
  });

  final int roomId;
  final ResenhaController? controller;
  final ResenhaShellService? shell;

  @override
  Widget build(BuildContext context) {
    final shell =
        this.shell ?? PluginUiScope.require(context, resenhaShellService);
    final controller =
        this.controller ??
        (this.shell?.controller ??
            PluginUiScope.require(context, resenhaControllerService));
    final site = shell.currentInstance;
    if (site == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final room = controller.room(site.url, roomId);
        if (room == null) {
          return const Center(child: Text('This voice room is unavailable.'));
        }
        final call = controller.call;
        final inRoom = call?.siteUrl == site.url && call?.room.id == room.id;
        final recordingEnabled =
            inRoom &&
            call!.room.canManage &&
            call.media.transport == ResenhaTransport.livekit &&
            shell.recordingEnabledFor(site.url);
        return Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (!controller.pushToTalkEnabled ||
                (!Platform.isMacOS && !Platform.isLinux) ||
                event.logicalKey != LogicalKeyboardKey.space) {
              return KeyEventResult.ignored;
            }
            if (event is KeyDownEvent) {
              unawaited(controller.setMuted(false));
            } else if (event is KeyUpEvent) {
              unawaited(controller.setMuted(true));
            }
            return KeyEventResult.handled;
          },
          child: ResenhaRoomContent(
            controller: controller,
            room: inRoom ? call!.room : room,
            call: inRoom ? call : null,
            siteUrl: site.url,
            siteName: site.title,
            currentUserId: shell.currentUserIdFor(site.url),
            recordingEnabled: recordingEnabled,
          ),
        );
      },
    );
  }
}

class ResenhaRoomContent extends StatefulWidget {
  const ResenhaRoomContent({
    super.key,
    required this.controller,
    required this.room,
    required this.call,
    required this.siteUrl,
    required this.siteName,
    required this.currentUserId,
    required this.recordingEnabled,
    this.controllerResolver,
  });

  final ResenhaController controller;
  final ResenhaRoom? room;
  final ResenhaCallSnapshot? call;
  final String siteUrl;
  final String siteName;
  final int? currentUserId;
  final bool recordingEnabled;
  final ResenhaController Function()? controllerResolver;

  @override
  State<ResenhaRoomContent> createState() => _ResenhaRoomContentState();
}

class _ResenhaRoomContentState extends State<ResenhaRoomContent> {
  @override
  void initState() {
    super.initState();
    _startWatching(widget);
  }

  @override
  void didUpdateWidget(ResenhaRoomContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller) &&
        oldWidget.siteUrl == widget.siteUrl &&
        oldWidget.room?.id == widget.room?.id) {
      return;
    }
    _stopWatching(oldWidget);
    _startWatching(widget);
  }

  void _startWatching(ResenhaRoomContent content) {
    if (content.room case final room?) {
      content.controller.watchRoomVideo(
        siteUrl: content.siteUrl,
        roomId: room.id,
      );
    }
  }

  void _stopWatching(ResenhaRoomContent content) {
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
      return const Center(child: Text('This voice room is unavailable.'));
    }
    final active = widget.call;
    final siteUrl = widget.siteUrl;
    final siteName = widget.siteName;
    final currentUserId = widget.currentUserId;
    final recordingEnabled = widget.recordingEnabled;
    final controllerResolver = widget.controllerResolver;
    final error = active?.error ?? controller.errorFor(siteUrl);
    return Column(
      children: [
        if (error != null)
          MaterialBanner(
            content: Text(error),
            actions: [
              TextButton(
                onPressed: () => controller.dismissCallError(siteUrl),
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
                  return _ParticipantTile(
                    controller: controller,
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
                    controllerResolver: controllerResolver,
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
                : _CallControls(
                    controller: controller,
                    call: active,
                    siteUrl: siteUrl,
                    currentUserId: currentUserId,
                    recordingEnabled: recordingEnabled,
                    controllerResolver: controllerResolver,
                  ),
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
    required this.controller,
    required this.participant,
    required this.siteUrl,
    required this.videoTrack,
    required this.speaking,
    required this.canManage,
    required this.canKick,
    required this.canAdjustLocally,
    this.controllerResolver,
  });

  final ResenhaController controller;
  final ResenhaParticipant participant;
  final String siteUrl;
  final Object? videoTrack;
  final bool speaking;
  final bool canManage;
  final bool canKick;
  final bool canAdjustLocally;
  final ResenhaController Function()? controllerResolver;

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
                    popUpAnimationStyle: discoursePopupMenuAnimationStyle(
                      context,
                    ),
                    onSelected: (action) async {
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
                          controllerResolver: controllerResolver,
                        );
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
                      if (canManage && participant.handRaisedAt != null)
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
  const _CallControls({
    required this.controller,
    required this.call,
    required this.siteUrl,
    required this.currentUserId,
    required this.recordingEnabled,
    this.controllerResolver,
  });
  final ResenhaController controller;
  final ResenhaCallSnapshot call;
  final String siteUrl;
  final int? currentUserId;
  final bool recordingEnabled;
  final ResenhaController Function()? controllerResolver;

  @override
  Widget build(BuildContext context) {
    final me = call.room.participants
        .where((participant) => participant.id == currentUserId)
        .firstOrNull;
    final role = me?.role ?? call.room.membership?.role;
    final canPublish =
        call.room.type != ResenhaRoomType.stage ||
        role == ResenhaRole.moderator ||
        role == ResenhaRole.speaker;
    final canPublishVideo = canPublish && call.room.videoAllowed;
    final canShare = (Platform.isMacOS || Platform.isLinux) && canPublishVideo;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canPublish)
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
            role == ResenhaRole.participant)
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
            onPressed: () => _showResenhaChat(
              context,
              controller,
              siteUrl: siteUrl,
              roomId: call.room.id,
            ),
          ),
        if (call.room.canManage &&
            call.media.transport == ResenhaTransport.livekit &&
            recordingEnabled)
          _Control(
            label: call.room.recording?.active == true
                ? 'Stop recording'
                : 'Start recording',
            icon: DIcons.circle,
            selected: call.room.recording?.active == true,
            onPressed: () => _confirmRecording(
              context,
              controller,
              active: call.room.recording?.active == true,
              controllerResolver: controllerResolver,
            ),
          ),
        _Control(
          label: 'Media settings',
          icon: DIcons.gear,
          selected: false,
          onPressed: () => _showMediaSettings(context, controller),
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
              // A dialog can outlive the plugin session that opened it when
              // the root app is replaced. Resolve at save time; the explicit
              // controller remains the fallback for standalone widget hosts.
              controllerResolver: () =>
                  _resolveController(context, controller, controllerResolver),
            ),
          ),
        if (call.room.canManage)
          _Control(
            label: 'Manage members',
            icon: DIcons.users,
            selected: false,
            onPressed: () => _showResenhaMembers(
              context,
              controller,
              siteUrl: siteUrl,
              room: call.room,
            ),
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
      pendingStream = await rtc.createLocalMediaStream('resenha-video-surface');
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

Future<void> _showParticipantVolume(
  BuildContext context,
  ResenhaController controller,
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

Future<void> _showMediaSettings(
  BuildContext context,
  ResenhaController controller,
) async {
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
                  SwitchListTile.adaptive(
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
                const ListTile(
                  title: Text('Native noise suppression'),
                  subtitle: Text(
                    'Echo cancellation, noise suppression, and automatic gain control are active.',
                  ),
                  trailing: DIcon(DIcons.check, size: 18),
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
  Widget build(BuildContext context) => DSelectField<String>(
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
  ResenhaController controller,
  ResenhaParticipant participant, {
  ResenhaController Function()? controllerResolver,
}) async {
  final message = await showDialog<String>(
    context: context,
    builder: (context) =>
        _ParticipantFlagDialog(username: participant.username),
  );
  if (message == null || message.trim().isEmpty || !context.mounted) return;
  final sent = await _resolveController(
    context,
    controller,
    controllerResolver,
  ).flagParticipant(participant.id, message);
  if (!sent && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Moderator notification is unavailable.')),
    );
  }
}

class _ParticipantFlagDialog extends StatefulWidget {
  const _ParticipantFlagDialog({required this.username});

  final String username;

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
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Notify moderators about @${widget.username}'),
    content: TextField(
      controller: _message,
      autofocus: true,
      minLines: 3,
      maxLines: 6,
      decoration: const InputDecoration(
        labelText: 'What should moderators know?',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _message.text),
        child: const Text('Notify'),
      ),
    ],
  );
}

Future<void> _confirmRecording(
  BuildContext context,
  ResenhaController controller, {
  required bool active,
  ResenhaController Function()? controllerResolver,
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
    await _resolveController(
      context,
      controller,
      controllerResolver,
    ).setRecording(!active);
  }
}

ResenhaController _resolveController(
  BuildContext context,
  ResenhaController fallback,
  ResenhaController Function()? resolver,
) =>
    resolver?.call() ??
    PluginUiScope.maybe(context, resenhaControllerService) ??
    fallback;

Future<void> showResenhaChat(
  BuildContext context, {
  required String siteUrl,
  required int roomId,
}) => _showResenhaChat(
  context,
  PluginUiScope.require(context, resenhaControllerService),
  siteUrl: siteUrl,
  roomId: roomId,
);

Future<void> _showResenhaChat(
  BuildContext context,
  ResenhaController controller, {
  required String siteUrl,
  required int roomId,
}) async {
  unawaited(controller.openChat(siteUrl, roomId));
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (context) => _ResenhaChatSheet(
        controller: controller,
        siteUrl: siteUrl,
        roomId: roomId,
      ),
    );
  } finally {
    controller.closeChat(siteUrl, roomId);
  }
}

class _ResenhaChatSheet extends StatefulWidget {
  const _ResenhaChatSheet({
    required this.controller,
    required this.siteUrl,
    required this.roomId,
  });

  final ResenhaController controller;
  final String siteUrl;
  final int roomId;

  @override
  State<_ResenhaChatSheet> createState() => _ResenhaChatSheetState();
}

class _ResenhaChatSheetState extends State<_ResenhaChatSheet> {
  final TextEditingController _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
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
                listenable: widget.controller,
                builder: (context, _) {
                  final chat = widget.controller.chat(
                    widget.siteUrl,
                    widget.roomId,
                  );
                  if (chat == null || chat.loading) {
                    return const Center(
                      child: CircularProgressIndicator.adaptive(),
                    );
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
                            onPressed: () => widget.controller.loadOlderChat(
                              widget.siteUrl,
                              widget.roomId,
                            ),
                            child: const Text('Load older messages'),
                          ),
                        );
                      }
                      final message =
                          chat.messages[index - (chat.canLoadMorePast ? 1 : 0)];
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
                    controller: _composer,
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
                    final text = _composer.text;
                    _composer.clear();
                    await widget.controller.sendChatMessage(
                      widget.siteUrl,
                      widget.roomId,
                      text,
                    );
                  },
                  icon: const DIcon(DIcons.paperPlane, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showResenhaMembers(
  BuildContext context, {
  required String siteUrl,
  required ResenhaRoom room,
}) => _showResenhaMembers(
  context,
  PluginUiScope.require(context, resenhaControllerService),
  siteUrl: siteUrl,
  room: room,
);

Future<void> _showResenhaMembers(
  BuildContext context,
  ResenhaController controller, {
  required String siteUrl,
  required ResenhaRoom room,
}) async {
  final memberships = await controller.memberships(siteUrl, room.id);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _ResenhaMembersDialog(
      controller: controller,
      siteUrl: siteUrl,
      room: room,
      initialMemberships: memberships,
    ),
  );
}

class _ResenhaMembersDialog extends StatefulWidget {
  const _ResenhaMembersDialog({
    required this.controller,
    required this.siteUrl,
    required this.room,
    required this.initialMemberships,
  });

  final ResenhaController controller;
  final String siteUrl;
  final ResenhaRoom room;
  final List<ResenhaMembership> initialMemberships;

  @override
  State<_ResenhaMembersDialog> createState() => _ResenhaMembersDialogState();
}

class _ResenhaMembersDialogState extends State<_ResenhaMembersDialog> {
  final TextEditingController _username = TextEditingController();
  late List<ResenhaMembership> _memberships = widget.initialMemberships;
  ResenhaRole _newRole = ResenhaRole.participant;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _updateMember(
    ResenhaMembership membership,
    ResenhaRole role,
  ) async {
    await widget.controller.updateMember(
      widget.siteUrl,
      widget.room.id,
      membership.id,
      role,
    );
    if (!mounted) return;
    await _refreshMemberships();
  }

  Future<void> _removeMember(ResenhaMembership membership) async {
    await widget.controller.removeMember(
      widget.siteUrl,
      widget.room.id,
      membership.id,
    );
    if (!mounted) return;
    await _refreshMemberships();
  }

  Future<void> _addMember() async {
    final value = _username.text.trim();
    if (value.isEmpty) return;
    await widget.controller.addMember(
      widget.siteUrl,
      widget.room.id,
      value,
      _newRole,
    );
    if (!mounted) return;
    _username.clear();
    await _refreshMemberships();
  }

  Future<void> _refreshMemberships() async {
    if (!mounted) return;
    final memberships = await widget.controller.memberships(
      widget.siteUrl,
      widget.room.id,
    );
    if (!mounted) return;
    setState(() => _memberships = memberships);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Members of ${widget.room.name}'),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final membership in _memberships)
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
                          popUpAnimationStyle: discoursePopupMenuAnimationStyle(
                            context,
                          ),
                          onSelected: (role) => _updateMember(membership, role),
                          itemBuilder: (context) => [
                            for (final role in ResenhaRole.values)
                              PopupMenuItem(
                                value: role,
                                child: Text(role.name),
                              ),
                          ],
                        ),
                        if (membership.userId != widget.room.creatorId)
                          IconButton(
                            tooltip: 'Remove member',
                            onPressed: () => _removeMember(membership),
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
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
              ),
              const SizedBox(width: 8),
              DSelect<ResenhaRole>(
                value: _newRole,
                onChanged: (value) =>
                    setState(() => _newRole = value ?? _newRole),
                items: [
                  for (final role in ResenhaRole.values)
                    DropdownMenuItem(value: role, child: Text(role.name)),
                ],
              ),
              IconButton.filledTonal(
                tooltip: 'Add member',
                onPressed: _addMember,
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
  );
}
