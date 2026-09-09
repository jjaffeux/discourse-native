import 'dart:async';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_callkit.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics.dart';
import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_preferences.dart';
import 'package:discourse_native/src/plugins/voice/voice_room_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../test/support/voice_fake_chat_conversations.dart';

const _siteUrl = 'https://native-select.invalid';

/// Real Voice widgets with an in-memory media session; no device acquisition.
class NativeSelectVoiceFixture extends StatefulWidget {
  const NativeSelectVoiceFixture({super.key});
  @override
  State<NativeSelectVoiceFixture> createState() =>
      _NativeSelectVoiceFixtureState();
}

class _NativeSelectVoiceFixtureState extends State<NativeSelectVoiceFixture> {
  static const room = VoiceRoom(
    id: 7,
    name: 'Local fixture',
    slug: 'fixture',
    isPublic: true,
    ephemeral: false,
    type: VoiceRoomType.open,
    participants: [
      VoiceParticipant(id: 1, username: 'fixture', role: VoiceRole.moderator),
    ],
    canManage: true,
    creatorId: 1,
    videoAllowed: true,
  );
  late final VoiceController controller;
  @override
  void initState() {
    super.initState();
    controller = VoiceController(
      api: VoiceApi(
        RecordingPluginTransport(
          responses: {
            'POST /voice/rooms/7/join.json': {
              'transport': 'mesh',
              'ice': {'servers': <Object>[]},
              'room': {
                'id': 7,
                'name': 'Local fixture',
                'slug': 'fixture',
                'public': true,
                'ephemeral': false,
                'room_type': 'open',
                'creator_id': 1,
                'can_manage': true,
                'video_allowed': true,
                'active_participants': [
                  {'id': 1, 'username': 'fixture', 'role': 'moderator'},
                ],
              },
            },
            'POST /voice/rooms/7/state.json': {},
            'DELETE /voice/rooms/7/leave.json': {},
            'GET /voice/rooms/7/memberships.json': {'memberships': <Object>[]},
            'POST /voice/rooms/7/memberships.json': {},
            'PUT /voice/rooms/7.json': {
              'room': {
                'id': 7,
                'name': 'Local fixture',
                'slug': 'fixture',
                'public': true,
                'can_manage': true,
              },
            },
          },
        ),
      ),
      chatConversations: FakeChatConversationCapability(),
      requests: PluginTestRequestHost(apiKeys: const {_siteUrl: 'fixture'}),
      trackerFor: (_) => null,
      userIdFor: (_) => 1,
      onCallSiteChanged: () {},
      mediaFactory: _MediaFactory({}),
      systemCall: _SystemCall(presentsIncomingCalls: false),
      preferences: _Preferences(participantVolume: null),
      heartbeatInterval: const Duration(days: 1),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      DButton(
        label: const Text('Room editor'),
        onPressed: () => showVoiceRoomEditor(
          context,
          siteUrl: _siteUrl,
          room: room,
          controller: controller,
        ),
      ),
      Expanded(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => VoiceRoomContent(
            controller: controller,
            room: controller.call?.room ?? room,
            call: controller.call,
            siteUrl: _siteUrl,
            siteName: 'Fixture',
            currentUserId: 1,
            recordingEnabled: false,
            error: controller.errorFor(_siteUrl),
          ),
        ),
      ),
    ],
  );
}

final class _MediaFactory implements VoiceMediaFactory {
  _MediaFactory(this.speakingIds);

  final Set<int> speakingIds;
  final List<_MediaSession> sessions = [];
  Object? nextConnectFailure;

  _MediaSession createSession([
    VoiceTransport transport = VoiceTransport.mesh,
  ]) {
    final session = _MediaSession(transport, speakingIds)
      ..connectFailure = nextConnectFailure;
    nextConnectFailure = null;
    sessions.add(session);
    return session;
  }

  @override
  VoiceMediaSession create({
    required VoiceJoinResponse join,
    required int localUserId,
    required VoiceSignalSender sendSignal,
    required VoiceLiveKitCredentialRefresher refreshLiveKitCredentials,
    VoiceDiagnosticsRecorder diagnostics = const NoopVoiceDiagnosticsRecorder(),
    String correlationId = 'uncorrelated',
  }) => createSession(join.transport);
}

final class _MediaSession extends ChangeNotifier implements VoiceMediaSession {
  _MediaSession(this.transport, Set<int> speakingParticipantIds)
    : _speakingParticipantIds = Set.unmodifiable(speakingParticipantIds);

  @override
  final VoiceTransport transport;
  Set<int> _speakingParticipantIds;
  final Map<int, Object> _videoTracks = {};
  @override
  Set<int> get speakingParticipantIds => _speakingParticipantIds;
  int connectCount = 0;
  int disposeCount = 0;
  Object? connectFailure;
  bool muted = false;
  bool failNextMute = false;
  List<rtc.MediaDeviceInfo> availableDevices = [
    rtc.MediaDeviceInfo(
      deviceId: 'mic1',
      label: 'Desk microphone',
      kind: 'audioinput',
      groupId: '',
    ),
    rtc.MediaDeviceInfo(
      deviceId: 'mic2',
      label: 'Travel microphone',
      kind: 'audioinput',
      groupId: '',
    ),
    rtc.MediaDeviceInfo(
      deviceId: 'speaker1',
      label: 'Desk speakers',
      kind: 'audiooutput',
      groupId: '',
    ),
    rtc.MediaDeviceInfo(
      deviceId: 'speaker2',
      label: 'Headphones',
      kind: 'audiooutput',
      groupId: '',
    ),
    rtc.MediaDeviceInfo(
      deviceId: 'camera1',
      label: 'Desk camera',
      kind: 'videoinput',
      groupId: '',
    ),
    rtc.MediaDeviceInfo(
      deviceId: 'camera2',
      label: 'Travel camera',
      kind: 'videoinput',
      groupId: '',
    ),
  ];
  final List<String> audioInputs = [];
  final List<String> audioOutputs = [];
  final List<({bool enabled, String? deviceId})> cameraChanges = [];
  final List<({int participantId, double volume})> participantVolumes = [];

  @override
  VoiceMediaConnectionState get connectionState =>
      VoiceMediaConnectionState.connected;
  @override
  Object? get localVideoTrack => null;
  @override
  bool get screenSharing => false;
  @override
  Object? videoTrackFor(int participantId) => _videoTracks[participantId];

  void setSpeakingParticipantIds(Set<int> value) {
    _speakingParticipantIds = Set.unmodifiable(value);
    notifyListeners();
  }

  void setVideoTrack(int participantId, Object? track) {
    if (track == null) {
      _videoTracks.remove(participantId);
    } else {
      _videoTracks[participantId] = track;
    }
    notifyListeners();
  }

  void notifyUnchanged() => notifyListeners();

  @override
  Future<void> connect() async {
    connectCount++;
    if (connectFailure case final failure?) throw failure;
  }

  @override
  Future<List<rtc.MediaDeviceInfo>> devices() async => availableDevices;
  @override
  Future<void> handleSignal(int senderId, Map<String, dynamic> data) async {}
  @override
  Future<void> selectAudioInput(String deviceId) async {
    audioInputs.add(deviceId);
  }

  @override
  Future<void> selectAudioOutput(String deviceId) async {
    audioOutputs.add(deviceId);
  }

  @override
  Future<void> setAudioPublishingAllowed(bool allowed) async {}
  @override
  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) async {
    cameraChanges.add((enabled: enabled, deviceId: deviceId));
  }

  @override
  Future<void> setDeafened(bool enabled) async {}
  @override
  Future<void> setMuted(bool enabled) async {
    if (failNextMute) {
      failNextMute = false;
      throw StateError('microphone rejected the change');
    }
    muted = enabled;
  }

  @override
  Future<void> setParticipantVolume(int participantId, double volume) async {
    participantVolumes.add((participantId: participantId, volume: volume));
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled) async {}
  @override
  Future<void> syncParticipants(List<VoiceParticipant> participants) async {}
  @override
  Future<void> dispose() async {
    disposeCount++;
    super.dispose();
  }
}

final class _Preferences implements VoicePreferences {
  _Preferences({this.participantVolume});

  final double? participantVolume;
  final List<({VoiceDevicePreference preference, String value})> deviceWrites =
      [];
  final List<bool> pushToTalkWrites = [];
  final List<({String siteUrl, int roomId, int userId, double volume})>
  participantVolumeWrites = [];

  @override
  Future<VoiceDevicePreferences> readDevices() async =>
      const VoiceDevicePreferences();
  @override
  Future<double?> readParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
  ) async => participantVolume;
  @override
  Future<void> writeDevice(
    VoiceDevicePreference preference,
    String value,
  ) async {
    deviceWrites.add((preference: preference, value: value));
  }

  @override
  Future<void> writeParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
    double volume,
  ) async {
    participantVolumeWrites.add((
      siteUrl: siteUrl,
      roomId: roomId,
      userId: userId,
      volume: volume,
    ));
  }

  @override
  Future<void> writePushToTalk(bool enabled) async {
    pushToTalkWrites.add(enabled);
  }

  bool meshPrivacyAcknowledged = false;
  Completer<void>? meshPrivacyReadGate;
  int meshPrivacyReads = 0;
  final List<bool> meshPrivacyWrites = [];
  bool? autoStatusEnabled;
  final List<bool> autoStatusWrites = [];

  @override
  Future<bool> readMeshPrivacyAcknowledged() async {
    meshPrivacyReads++;
    await meshPrivacyReadGate?.future;
    return meshPrivacyAcknowledged;
  }

  @override
  Future<void> writeMeshPrivacyAcknowledged(bool acknowledged) async {
    meshPrivacyWrites.add(acknowledged);
    meshPrivacyAcknowledged = acknowledged;
  }

  @override
  Future<bool?> readAutoStatusEnabled() async => autoStatusEnabled;

  @override
  Future<void> writeAutoStatusEnabled(bool enabled) async {
    autoStatusWrites.add(enabled);
    autoStatusEnabled = enabled;
  }
}

final class _SystemCall implements VoiceSystemCall {
  _SystemCall({this.presentsIncomingCalls = false});

  final bool presentsIncomingCalls;
  final StreamController<VoiceSystemCallAction> _actions =
      StreamController.broadcast();

  void send(VoiceSystemCallAction action) => _actions.add(action);

  @override
  Stream<VoiceSystemCallAction> get actions => _actions.stream;
  @override
  Future<bool> reportIncomingCall({
    required String callerName,
    required String roomName,
    required String handle,
  }) async => presentsIncomingCalls;
  @override
  Future<void> answerIncomingCall() async {}
  @override
  Future<void> declineIncomingCall() async {}
  @override
  Future<void> endIncomingCall(VoiceIncomingCallEndReason reason) async {}
  @override
  Future<void> connected() async {}
  @override
  Future<void> dispose() => _actions.close();
  @override
  Future<void> end() async {}
  @override
  Future<void> failed() async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> start({
    required String roomName,
    required String siteName,
  }) async {}
}
