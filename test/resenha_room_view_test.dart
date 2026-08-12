import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/plugins/resenha/resenha_api.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_callkit.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_controller.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_diagnostics.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_media.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_models.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_preferences.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_room_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
// The regression verifies flutter_webrtc's native renderer contract.
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_track_impl.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://voice.example.com';

void main() {
  testWidgets(
    'keeps borrowed WebRTC tracks out of native streams across replacement',
    (tester) async {
      const webRtcChannel = MethodChannel('FlutterWebRTC.Method');
      const eventChannel = EventChannel('FlutterWebRTC.Event');
      const textureChannel = EventChannel('FlutterWebRTC/Texture73');
      final messenger = tester.binding.defaultBinaryMessenger;
      final releaseRenderer = Completer<void>();
      final rendererDisposed = Completer<void>();
      final calls = <String>[];
      final rendererScopes = <Object?>[];
      var directBindings = 0;

      rtc.WebRTC.initialized = false;
      const streamHandler = MockStreamHandler.inline(onListen: _ignoreEvents);
      messenger.setMockStreamHandler(eventChannel, streamHandler);
      messenger.setMockStreamHandler(textureChannel, streamHandler);
      messenger.setMockMethodCallHandler(webRtcChannel, (call) async {
        calls.add(call.method);
        if (call.method == 'mediaStreamAddTrack') {
          throw TestFailure('Borrowed tracks must not enter a native stream');
        }
        final arguments = call.arguments as Map<Object?, Object?>?;
        if (call.method == 'videoRendererSetSrcObject' &&
            arguments?['trackId'] == 'stale-video') {
          directBindings++;
          rendererScopes.add(arguments?['peerConnectionId']);
          if (directBindings == 1) await releaseRenderer.future;
          return null;
        }
        if (call.method == 'videoRendererDispose') {
          if (calls.where((method) => method == call.method).length == 2) {
            rendererDisposed.complete();
          }
          return null;
        }
        return switch (call.method) {
          'initialize' => null,
          'createVideoRenderer' => <String, Object?>{'textureId': 73},
          'createLocalMediaStream' => <String, Object?>{
            'streamId': 'resenha-test-stream',
          },
          'videoRendererSetSrcObject' || 'streamDispose' => null,
          _ => throw UnsupportedError('Unexpected WebRTC call: ${call.method}'),
        };
      });
      addTearDown(() {
        rtc.WebRTC.initialized = false;
        messenger.setMockMethodCallHandler(webRtcChannel, null);
        messenger.setMockStreamHandler(eventChannel, null);
        messenger.setMockStreamHandler(textureChannel, null);
      });

      await tester.pumpWidget(
        MaterialApp(home: ResenhaVideoSurface(track: _nativeVideoTrack())),
      );
      expect(calls, contains('videoRendererSetSrcObject'));

      await tester.pumpWidget(
        MaterialApp(home: ResenhaVideoSurface(track: _nativeVideoTrack())),
      );
      expect(
        calls.where((method) => method == 'createVideoRenderer'),
        hasLength(2),
      );
      expect(directBindings, 2);
      expect(rendererScopes, everyElement('remote-peer'));

      await tester.pumpWidget(const SizedBox.shrink());
      releaseRenderer.complete();
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(rendererDisposed.isCompleted, isTrue);
      expect(calls, isNot(contains('mediaStreamAddTrack')));
      expect(calls.where((method) => method == 'streamDispose'), hasLength(2));
      expect(
        calls.where((method) => method == 'videoRendererDispose'),
        hasLength(2),
        reason: '$calls',
      );
    },
  );

  testWidgets('renders unavailable and empty rooms without a shell', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_app(harness.controller, room: null));
    expect(find.text('This voice room is unavailable.'), findsOneWidget);
    expect(find.text('Join room'), findsNothing);

    await tester.pumpWidget(
      _app(
        harness.controller,
        room: _room(
          participants: const [],
          description: 'A calm place to catch up.',
        ),
      ),
    );

    expect(find.text('Nobody is in Lounge yet.'), findsOneWidget);
    expect(find.text('A calm place to catch up.'), findsOneWidget);
    expect(find.text('Join room'), findsOneWidget);
  });

  testWidgets('join, media failure, moderation, and leave stay wired', (
    tester,
  ) async {
    final activeRoom = _room(
      canManage: true,
      videoAllowed: true,
      creatorId: 1,
      participants: [
        const ResenhaParticipant(
          id: 1,
          username: 'sam',
          role: ResenhaRole.moderator,
        ),
        ResenhaParticipant(
          id: 2,
          username: 'lee',
          name: 'Lee',
          role: ResenhaRole.participant,
          muted: true,
          handRaisedAt: DateTime.utc(2026),
        ),
      ],
    );
    final harness = _Harness(joinRoom: activeRoom, speakingIds: const {2});
    addTearDown(harness.dispose);
    final initialRoom = _room(
      participants: const [],
      description: 'A calm place to catch up.',
    );

    await tester.pumpWidget(
      _app(harness.controller, room: initialRoom, followCall: true),
    );
    await tester.tap(find.text('Join room'));
    await tester.pumpAndSettle();

    expect(harness.media.sessions, hasLength(1));
    expect(harness.media.sessions.single.connectCount, 1);
    expect(find.byTooltip('Mute'), findsOneWidget);
    expect(find.byTooltip('Deafen'), findsOneWidget);
    expect(find.byTooltip('Camera on'), findsOneWidget);
    expect(find.text('Leave room'), findsOneWidget);

    harness.media.sessions.single.failNextMute = true;
    await tester.tap(find.byTooltip('Mute'));
    await tester.pumpAndSettle();

    expect(find.text('The media setting was not applied.'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(find.text('The media setting was not applied.'), findsNothing);

    await tester.tap(find.byTooltip('Mute'));
    await tester.pumpAndSettle();
    expect(harness.media.sessions.single.muted, isTrue);
    expect(find.byTooltip('Unmute'), findsOneWidget);

    await tester.tap(find.byTooltip('Participant actions'));
    await tester.pumpAndSettle();
    expect(find.text('Local volume'), findsOneWidget);
    expect(find.text('Notify moderators'), findsOneWidget);
    expect(find.text('Dismiss raised hand'), findsOneWidget);
    expect(find.text('Remove from room'), findsOneWidget);

    await tester.tap(find.text('Remove from room'));
    await tester.pumpAndSettle();
    final kick = harness.transport.pluginWrites.singleWhere(
      (write) => write.path == '/resenha/rooms/7/kick.json',
    );
    expect(kick.method, 'DELETE');
    expect(kick.body['user_id'], 2);

    await tester.tap(find.text('Leave room'));
    await tester.pumpAndSettle();
    expect(harness.media.sessions.single.disposeCount, 1);
    expect(harness.controller.call, isNull);
    expect(find.text('Join room'), findsOneWidget);
  });

  testWidgets('participant semantics and responsive columns are explicit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = _Harness(speakingIds: const {2});
    addTearDown(harness.dispose);
    final room = _room(
      canManage: true,
      creatorId: 1,
      participants: [
        const ResenhaParticipant(
          id: 1,
          username: 'sam',
          role: ResenhaRole.moderator,
        ),
        ResenhaParticipant(
          id: 2,
          username: 'lee',
          name: 'Lee',
          role: ResenhaRole.participant,
          muted: true,
          handRaisedAt: DateTime.utc(2026),
        ),
      ],
    );
    final media = harness.media.createSession();
    final call = _call(room, media);
    await tester.pumpWidget(_app(harness.controller, room: room, call: call));
    expect(_columns(tester), 3);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Lee, speaking, muted, hand raised',
      ),
      findsOneWidget,
    );

    tester.view.physicalSize = const Size(700, 800);
    await tester.pump();
    expect(_columns(tester), 2);

    tester.view.physicalSize = const Size(500, 800);
    await tester.pump();
    expect(_columns(tester), 1);
  });

  testWidgets('listeners cannot see moderator-only participant actions', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final room = _room(
      participants: [
        const ResenhaParticipant(
          id: 1,
          username: 'sam',
          role: ResenhaRole.participant,
        ),
        ResenhaParticipant(
          id: 2,
          username: 'lee',
          role: ResenhaRole.participant,
          handRaisedAt: DateTime.utc(2026),
        ),
      ],
    );
    final call = _call(room, harness.media.createSession());

    await tester.pumpWidget(_app(harness.controller, room: room, call: call));
    await tester.tap(find.byTooltip('Participant actions'));
    await tester.pumpAndSettle();

    expect(find.text('Local volume'), findsOneWidget);
    expect(find.text('Notify moderators'), findsOneWidget);
    expect(find.text('Dismiss raised hand'), findsNothing);
    expect(find.text('Remove from room'), findsNothing);
  });

  testWidgets('room content watches video from mount until unmount', (
    tester,
  ) async {
    final room = _room(
      participants: const [
        ResenhaParticipant(
          id: 1,
          username: 'sam',
          role: ResenhaRole.participant,
        ),
      ],
    );
    final harness = _Harness(joinRoom: room);
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      _app(harness.controller, room: room, followCall: true),
    );
    expect(
      harness.transport.pluginWrites.where(
        (write) => write.path.endsWith('/state.json'),
      ),
      isEmpty,
    );

    await tester.tap(find.text('Join room'));
    await tester.pumpAndSettle();

    var stateWrites = harness.transport.pluginWrites
        .where((write) => write.path.endsWith('/state.json'))
        .toList();
    expect(stateWrites, isNotEmpty);
    expect(stateWrites.last.body['watching'], isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    stateWrites = harness.transport.pluginWrites
        .where((write) => write.path.endsWith('/state.json'))
        .toList();
    expect(stateWrites.last.body['watching'], isFalse);

    await harness.controller.leave();
    await tester.pump();
  });

  testWidgets('stage listeners are only offered receive-only controls', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final room = _room(
      type: ResenhaRoomType.stage,
      videoAllowed: true,
      participants: const [
        ResenhaParticipant(
          id: 1,
          username: 'sam',
          role: ResenhaRole.participant,
        ),
      ],
    );

    await tester.pumpWidget(
      _app(
        harness.controller,
        room: room,
        call: _call(room, harness.media.createSession()),
      ),
    );

    expect(find.byTooltip('Mute'), findsNothing);
    expect(find.byTooltip('Unmute'), findsNothing);
    expect(find.byTooltip('Camera on'), findsNothing);
    expect(find.byTooltip('Camera off'), findsNothing);
    expect(find.byTooltip('Share screen'), findsNothing);
    expect(find.byTooltip('Stop sharing'), findsNothing);
    expect(find.byTooltip('Deafen'), findsOneWidget);
    expect(find.byTooltip('Raise hand'), findsOneWidget);
    expect(find.text('Leave room'), findsOneWidget);
  });

  for (final role in [ResenhaRole.speaker, ResenhaRole.moderator]) {
    testWidgets('stage ${role.name}s retain publishing controls', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final room = _room(
        type: ResenhaRoomType.stage,
        videoAllowed: true,
        participants: [ResenhaParticipant(id: 1, username: 'sam', role: role)],
      );

      await tester.pumpWidget(
        _app(
          harness.controller,
          room: room,
          call: _call(room, harness.media.createSession()),
        ),
      );

      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.byTooltip('Camera on'), findsOneWidget);
      expect(
        find.byTooltip('Share screen'),
        (Platform.isMacOS || Platform.isLinux) ? findsOneWidget : findsNothing,
      );
      expect(find.byTooltip('Raise hand'), findsNothing);
    });
  }

  testWidgets('room editor validates its name as the user types', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final room = _room(
      canManage: true,
      participants: const [
        ResenhaParticipant(id: 1, username: 'sam', role: ResenhaRole.moderator),
      ],
    );
    final call = _call(room, harness.media.createSession());

    await tester.pumpWidget(_app(harness.controller, room: room, call: call));
    await tester.tap(find.byTooltip('Edit room'));
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'Renamed lounge');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.transport.pluginWrites, isEmpty);
  });

  testWidgets('room editor resolves a replacement controller when saving', (
    tester,
  ) async {
    final original = _Harness();
    final replacement = _Harness();
    addTearDown(original.dispose);
    addTearDown(replacement.dispose);
    var current = original.controller;
    final room = _room(
      canManage: true,
      participants: const [
        ResenhaParticipant(id: 1, username: 'sam', role: ResenhaRole.moderator),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => unawaited(
              showResenhaRoomEditor(
                context,
                siteUrl: _siteUrl,
                room: room,
                controllerResolver: () => current,
              ),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    current = replacement.controller;
    await tester.enterText(find.byType(TextField).first, 'Replacement save');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(original.transport.pluginWrites, isEmpty);
    expect(
      replacement.transport.pluginWrites.map((write) => write.path),
      contains('/resenha/rooms/7.json'),
    );
  });

  testWidgets('flag dialog resolves a replacement controller when confirmed', (
    tester,
  ) async {
    final room = _room(
      canManage: true,
      creatorId: 1,
      participants: const [
        ResenhaParticipant(id: 1, username: 'sam', role: ResenhaRole.moderator),
        ResenhaParticipant(
          id: 2,
          username: 'lee',
          role: ResenhaRole.participant,
        ),
      ],
    );
    final original = _Harness(joinRoom: room);
    final replacement = _Harness(joinRoom: room);
    addTearDown(original.dispose);
    addTearDown(replacement.dispose);
    await _join(original, room);
    await _join(replacement, room);
    var current = original.controller;

    await tester.pumpWidget(
      _app(
        original.controller,
        room: room,
        call: original.controller.call,
        controllerResolver: () => current,
      ),
    );
    await tester.tap(find.byTooltip('Participant actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notify moderators'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Please review this');

    current = replacement.controller;
    await tester.tap(find.widgetWithText(FilledButton, 'Notify'));
    await tester.pumpAndSettle();

    expect(
      original.transport.pluginWrites.where(
        (write) => write.path.endsWith('/flag.json'),
      ),
      isEmpty,
    );
    expect(
      replacement.transport.pluginWrites.where(
        (write) => write.path.endsWith('/flag.json'),
      ),
      hasLength(1),
    );
    original.dispose();
    replacement.dispose();
  });

  testWidgets(
    'recording dialog resolves a replacement controller when confirmed',
    (tester) async {
      final room = _room(
        canManage: true,
        participants: const [
          ResenhaParticipant(
            id: 1,
            username: 'sam',
            role: ResenhaRole.moderator,
          ),
        ],
      );
      final original = _Harness(
        joinRoom: room,
        joinTransport: ResenhaTransport.livekit,
      );
      final replacement = _Harness(
        joinRoom: room,
        joinTransport: ResenhaTransport.livekit,
      );
      addTearDown(original.dispose);
      addTearDown(replacement.dispose);
      await _join(original, room);
      await _join(replacement, room);
      var current = original.controller;

      await tester.pumpWidget(
        _app(
          original.controller,
          room: room,
          call: original.controller.call,
          controllerResolver: () => current,
        ),
      );
      await tester.tap(find.byTooltip('Start recording'));
      await tester.pumpAndSettle();

      current = replacement.controller;
      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pumpAndSettle();

      expect(
        original.transport.pluginWrites.where(
          (write) => write.path.endsWith('/recording.json'),
        ),
        isEmpty,
      );
      expect(
        replacement.transport.pluginWrites.where(
          (write) => write.path.endsWith('/recording.json'),
        ),
        hasLength(1),
      );
      original.dispose();
      replacement.dispose();
    },
  );
}

MediaStreamTrackNative _nativeVideoTrack() => MediaStreamTrackNative(
  'stale-video',
  'Remote video',
  'video',
  true,
  'remote-peer',
);

void _ignoreEvents(Object? _, MockStreamHandlerEventSink _) {}

Future<void> _join(_Harness harness, ResenhaRoom room) =>
    harness.controller.join(siteUrl: _siteUrl, siteName: 'Voice', room: room);

ResenhaCallSnapshot _call(ResenhaRoom room, ResenhaMediaSession media) =>
    ResenhaCallSnapshot(
      siteUrl: _siteUrl,
      siteName: 'Voice',
      room: room,
      status: ResenhaCallStatus.connected,
      media: media,
    );

int _columns(WidgetTester tester) =>
    (tester.widget<GridView>(find.byType(GridView)).gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount)
        .crossAxisCount;

Widget _app(
  ResenhaController controller, {
  required ResenhaRoom? room,
  ResenhaCallSnapshot? call,
  bool followCall = false,
  ResenhaController Function()? controllerResolver,
}) => MaterialApp(
  home: Scaffold(
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final active = followCall ? controller.call : call;
        return ResenhaRoomContent(
          controller: controller,
          room: active?.room ?? room,
          call: active,
          siteUrl: _siteUrl,
          siteName: 'Voice',
          currentUserId: 1,
          recordingEnabled: true,
          controllerResolver: controllerResolver,
        );
      },
    ),
  ),
);

ResenhaRoom _room({
  required List<ResenhaParticipant> participants,
  String? description,
  int? creatorId,
  bool canManage = false,
  bool videoAllowed = false,
  ResenhaRoomType type = ResenhaRoomType.open,
}) => ResenhaRoom(
  id: 7,
  name: 'Lounge',
  slug: 'lounge',
  description: description,
  isPublic: true,
  ephemeral: false,
  type: type,
  participants: participants,
  creatorId: creatorId,
  canManage: canManage,
  videoEnabled: videoAllowed,
  videoAllowed: videoAllowed,
);

Map<String, dynamic> _joinPayload(
  ResenhaRoom room, {
  ResenhaTransport transport = ResenhaTransport.mesh,
}) => {
  'transport': transport.name,
  'ice': {'servers': <Object>[]},
  if (transport == ResenhaTransport.livekit)
    'livekit': {'url': 'wss://livekit.example.com', 'token': 'test-token'},
  'room': {
    'id': room.id,
    'name': room.name,
    'slug': room.slug,
    'public': room.isPublic,
    'ephemeral': room.ephemeral,
    'room_type': room.type.wireName,
    'creator_id': room.creatorId,
    'can_manage': room.canManage,
    'video_enabled': room.videoEnabled,
    'video_allowed': room.videoAllowed,
    'active_participants': [
      for (final participant in room.participants)
        {
          'id': participant.id,
          'username': participant.username,
          'name': participant.name,
          'role': participant.role.wireName,
          'is_muted': participant.muted,
          'hand_raised_at': participant.handRaisedAt?.toIso8601String(),
        },
    ],
  },
};

final class _Harness {
  _Harness({
    ResenhaRoom? joinRoom,
    ResenhaTransport joinTransport = ResenhaTransport.mesh,
    Set<int> speakingIds = const {},
  }) : transport = FakeDiscourseApi(
         pluginResponses: {
           if (joinRoom != null)
             'POST /resenha/rooms/7/join.json': _joinPayload(
               joinRoom,
               transport: joinTransport,
             ),
           'POST /resenha/rooms/7/state.json': const {},
           'DELETE /resenha/rooms/7/kick.json': const {},
           'DELETE /resenha/rooms/7/leave.json': const {},
           'GET /site.json': const {
             'post_action_types': [
               {'name_key': 'notify_moderators', 'id': 3},
             ],
           },
           'POST /resenha/rooms/7/flag.json': const {},
           'POST /resenha/rooms/7/recording.json': const {},
         },
       ),
       media = _MediaFactory(speakingIds) {
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    controller = ResenhaController(
      api: ResenhaApi(transport),
      chatApi: transport,
      credentials: credentials,
      trackerFor: (_) => null,
      userIdFor: (_) => 1,
      onCallSiteChanged: () {},
      mediaFactory: media,
      systemCall: _SystemCall(),
      preferences: const _Preferences(),
      heartbeatInterval: const Duration(days: 1),
    );
  }

  final FakeDiscourseApi transport;
  final _MediaFactory media;
  late final ResenhaController controller;

  void dispose() => controller.dispose();
}

final class _MediaFactory implements ResenhaMediaFactory {
  _MediaFactory(this.speakingIds);

  final Set<int> speakingIds;
  final List<_MediaSession> sessions = [];

  _MediaSession createSession([
    ResenhaTransport transport = ResenhaTransport.mesh,
  ]) {
    final session = _MediaSession(transport, speakingIds);
    sessions.add(session);
    return session;
  }

  @override
  ResenhaMediaSession create({
    required ResenhaJoinResponse join,
    required int localUserId,
    required ResenhaSignalSender sendSignal,
    required ResenhaLiveKitCredentialRefresher refreshLiveKitCredentials,
    ResenhaDiagnosticsRecorder diagnostics =
        const NoopResenhaDiagnosticsRecorder(),
    String correlationId = 'uncorrelated',
  }) => createSession(join.transport);
}

final class _MediaSession extends ChangeNotifier
    implements ResenhaMediaSession {
  _MediaSession(this.transport, this.speakingParticipantIds);

  @override
  final ResenhaTransport transport;
  @override
  final Set<int> speakingParticipantIds;
  int connectCount = 0;
  int disposeCount = 0;
  bool muted = false;
  bool failNextMute = false;

  @override
  ResenhaMediaConnectionState get connectionState =>
      ResenhaMediaConnectionState.connected;
  @override
  Object? get localVideoTrack => null;
  @override
  bool get screenSharing => false;
  @override
  Object? videoTrackFor(int participantId) => null;
  @override
  Future<void> connect() async => connectCount++;
  @override
  Future<List<rtc.MediaDeviceInfo>> devices() async => const [];
  @override
  Future<void> handleSignal(int senderId, Map<String, dynamic> data) async {}
  @override
  Future<void> selectAudioInput(String deviceId) async {}
  @override
  Future<void> selectAudioOutput(String deviceId) async {}
  @override
  Future<void> setAudioPublishingAllowed(bool allowed) async {}
  @override
  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) async {}
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
  Future<void> setParticipantVolume(int participantId, double volume) async {}
  @override
  Future<void> setScreenShareEnabled(bool enabled) async {}
  @override
  Future<void> syncParticipants(List<ResenhaParticipant> participants) async {}
  @override
  Future<void> dispose() async {
    disposeCount++;
    super.dispose();
  }
}

final class _Preferences implements ResenhaPreferences {
  const _Preferences();

  @override
  Future<ResenhaDevicePreferences> readDevices() async =>
      const ResenhaDevicePreferences();
  @override
  Future<double?> readParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
  ) async => null;
  @override
  Future<void> writeDevice(
    ResenhaDevicePreference preference,
    String value,
  ) async {}
  @override
  Future<void> writeParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
    double volume,
  ) async {}
  @override
  Future<void> writePushToTalk(bool enabled) async {}
}

final class _SystemCall implements ResenhaSystemCall {
  final StreamController<ResenhaSystemCallAction> _actions =
      StreamController.broadcast();

  @override
  Stream<ResenhaSystemCallAction> get actions => _actions.stream;
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
