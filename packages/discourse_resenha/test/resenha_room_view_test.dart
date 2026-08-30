import 'dart:async';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_test.dart'
    show PluginTestRequestHost;
import 'package:discourse_plugin_api/testing.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/chat/chat_contract.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_resenha/src/resenha_api.dart';
import 'package:discourse_resenha/src/resenha_callkit.dart';
import 'package:discourse_resenha/src/resenha_controller.dart';
import 'package:discourse_resenha/src/resenha_diagnostics.dart';
import 'package:discourse_resenha/src/resenha_media.dart';
import 'package:discourse_resenha/src/resenha_models.dart';
import 'package:discourse_resenha/src/resenha_preferences.dart';
import 'package:discourse_resenha/src/resenha_room_view.dart';
import 'package:discourse_resenha/src/resenha_shell_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
// The regression verifies flutter_webrtc's native renderer contract.
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_track_impl.dart';

import 'support/fake_chat_conversations.dart';

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

  testWidgets('top-level room view handles a missing site and room', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ResenhaRoomView(
          roomId: 7,
          controller: harness.controller,
          shell: _resenhaShell(harness.controller),
        ),
      ),
    );
    expect(find.byType(ResenhaRoomContent), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: ResenhaRoomView(
          roomId: 7,
          controller: harness.controller,
          shell: _resenhaShell(
            harness.controller,
            site: const PluginRouteSite(
              url: _siteUrl,
              title: 'Voice',
              isConnected: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('This voice room is unavailable.'), findsOneWidget);
  });

  testWidgets('top-level room view handles desktop push-to-talk keys', (
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
    await _join(harness, room);
    final shell = _resenhaShell(
      harness.controller,
      site: const PluginRouteSite(
        url: _siteUrl,
        title: 'Voice',
        isConnected: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ResenhaRoomView(
          roomId: 7,
          controller: harness.controller,
          shell: shell,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final media = harness.media.sessions.single;

    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.space), isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

    await harness.controller.setPushToTalkEnabled(true);
    await tester.pumpAndSettle();
    expect(media.muted, isTrue);
    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA), isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);

    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.space), isTrue);
    await tester.pumpAndSettle();
    expect(media.muted, isFalse);
    expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.space), isTrue);
    await tester.pumpAndSettle();
    expect(media.muted, isTrue);

    await harness.controller.leave();
    await tester.pump();
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
    final kick = harness.transport.writes.singleWhere(
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
      harness.transport.writes.where(
        (write) => write.path.endsWith('/state.json'),
      ),
      isEmpty,
    );

    await tester.tap(find.text('Join room'));
    await tester.pumpAndSettle();

    var stateWrites = harness.transport.writes
        .where((write) => write.path.endsWith('/state.json'))
        .toList();
    expect(stateWrites, isNotEmpty);
    expect(stateWrites.last.body['watching'], isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    stateWrites = harness.transport.writes
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

  testWidgets('dismissed members dialog ignores a pending member write', (
    tester,
  ) async {
    final transport = _GatedMembershipTransport();
    final harness = _Harness(discourseApi: transport);
    addTearDown(harness.dispose);
    final room = _room(
      canManage: true,
      participants: const [
        ResenhaParticipant(id: 1, username: 'sam', role: ResenhaRole.moderator),
      ],
    );

    await tester.pumpWidget(
      _app(
        harness.controller,
        room: room,
        call: _call(room, harness.media.createSession()),
      ),
    );
    await tester.tap(find.byTooltip('Manage members'));
    await tester.pumpAndSettle();
    expect(transport.membershipReads, 1);

    await tester.enterText(find.byType(TextField), 'lee');
    await tester.tap(find.byTooltip('Add member'));
    await tester.pump();
    expect(transport.writeStarted.isCompleted, isTrue);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    transport.writeGate.complete();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(transport.membershipReads, 1);
  });

  testWidgets('participant volume is applied locally and persisted', (
    tester,
  ) async {
    final preferences = _Preferences(participantVolume: 0.4);
    final room = _room(
      participants: const [
        ResenhaParticipant(
          id: 1,
          username: 'sam',
          role: ResenhaRole.participant,
        ),
        ResenhaParticipant(
          id: 2,
          username: 'lee',
          role: ResenhaRole.participant,
        ),
      ],
    );
    final harness = _Harness(joinRoom: room, preferences: preferences);
    addTearDown(harness.dispose);
    await _join(harness, room);

    await tester.pumpWidget(
      _app(harness.controller, room: room, call: harness.controller.call),
    );
    await tester.tap(find.byTooltip('Participant actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local volume'));
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 0.4);
    slider.onChanged!(0.7);
    await tester.pumpAndSettle();

    expect(harness.media.sessions.single.participantVolumes.single, (
      participantId: 2,
      volume: 0.7,
    ));
    expect(preferences.participantVolumeWrites.single, (
      siteUrl: _siteUrl,
      roomId: 7,
      userId: 2,
      volume: 0.7,
    ));

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await harness.controller.leave();
    await tester.pump();
  });

  testWidgets('media settings select devices and exercise the microphone', (
    tester,
  ) async {
    const webRtcChannel = MethodChannel('FlutterWebRTC.Method');
    const eventChannel = EventChannel('FlutterWebRTC.Event');
    final messenger = tester.binding.defaultBinaryMessenger;
    final microphoneGate = Completer<void>();
    final microphoneStarted = Completer<void>();
    final nativeCalls = <String>[];
    rtc.WebRTC.initialized = false;
    messenger.setMockStreamHandler(
      eventChannel,
      const MockStreamHandler.inline(onListen: _ignoreEvents),
    );
    messenger.setMockMethodCallHandler(webRtcChannel, (call) async {
      nativeCalls.add(call.method);
      if (call.method == 'getUserMedia') {
        microphoneStarted.complete();
        await microphoneGate.future;
        return <String, Object?>{
          'streamId': 'microphone-test-stream',
          'audioTracks': <Object?>[
            <String, Object?>{
              'id': 'microphone-test-track',
              'label': 'Test microphone',
              'kind': 'audio',
              'enabled': true,
              'settings': <String, Object?>{},
            },
          ],
          'videoTracks': <Object?>[],
        };
      }
      return switch (call.method) {
        'initialize' || 'trackDispose' || 'streamDispose' => null,
        _ => throw UnsupportedError('Unexpected WebRTC call: ${call.method}'),
      };
    });
    addTearDown(() {
      if (!microphoneGate.isCompleted) microphoneGate.complete();
      rtc.WebRTC.initialized = false;
      messenger.setMockMethodCallHandler(webRtcChannel, null);
      messenger.setMockStreamHandler(eventChannel, null);
    });

    final preferences = _Preferences();
    final room = _room(
      videoAllowed: true,
      participants: const [
        ResenhaParticipant(
          id: 1,
          username: 'sam',
          role: ResenhaRole.participant,
        ),
      ],
    );
    final harness = _Harness(joinRoom: room, preferences: preferences);
    addTearDown(harness.dispose);
    await _join(harness, room);
    final media = harness.media.sessions.single;
    media.availableDevices = [
      rtc.MediaDeviceInfo(
        deviceId: 'microphone-1',
        groupId: 'audio-group',
        kind: 'audioinput',
        label: 'Desk microphone',
      ),
      rtc.MediaDeviceInfo(
        deviceId: 'microphone-2',
        groupId: 'audio-group',
        kind: 'audioinput',
        label: 'Travel microphone',
      ),
      rtc.MediaDeviceInfo(
        deviceId: 'speaker-1',
        groupId: 'audio-group',
        kind: 'audiooutput',
        label: '',
      ),
      rtc.MediaDeviceInfo(
        deviceId: 'speaker-2',
        groupId: 'audio-group',
        kind: 'audiooutput',
        label: 'Headphones',
      ),
      rtc.MediaDeviceInfo(
        deviceId: 'camera-1',
        groupId: 'camera-group',
        kind: 'videoinput',
        label: 'Desk camera',
      ),
      rtc.MediaDeviceInfo(
        deviceId: 'camera-2',
        groupId: 'camera-group',
        kind: 'videoinput',
        label: 'Travel camera',
      ),
    ];
    await harness.controller.selectAudioInput('microphone-1');
    await harness.controller.setCameraEnabled(true);
    media.audioInputs.clear();
    media.cameraChanges.clear();
    preferences.deviceWrites.clear();

    await tester.pumpWidget(
      _app(harness.controller, room: room, call: harness.controller.call),
    );
    await tester.tap(find.byTooltip('Media settings'));
    await tester.pumpAndSettle();

    expect(find.text('Desk microphone'), findsOneWidget);
    expect(find.text('Default Speaker'), findsOneWidget);
    expect(find.text('Desk camera'), findsOneWidget);

    final pickers = find.byType(DropdownButtonFormField<String>);
    await tester.tap(pickers.at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Travel microphone').last);
    await tester.pumpAndSettle();
    await tester.tap(pickers.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Headphones').last);
    await tester.pumpAndSettle();
    await tester.tap(pickers.at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Travel camera').last);
    await tester.pumpAndSettle();

    expect(media.audioInputs, ['microphone-2']);
    expect(media.audioOutputs, ['speaker-2']);
    expect(media.cameraChanges, [
      (enabled: false, deviceId: null),
      (enabled: true, deviceId: 'camera-2'),
    ]);
    expect(preferences.deviceWrites, [
      (preference: ResenhaDevicePreference.audioInput, value: 'microphone-2'),
      (preference: ResenhaDevicePreference.audioOutput, value: 'speaker-2'),
      (preference: ResenhaDevicePreference.camera, value: 'camera-2'),
    ]);

    await tester.tap(find.text('Push to talk'));
    await tester.pumpAndSettle();
    expect(harness.controller.pushToTalkEnabled, isTrue);
    expect(preferences.pushToTalkWrites, [true]);
    expect(media.muted, isTrue);

    final testMicrophone = find.text('Test microphone');
    await tester.ensureVisible(testMicrophone);
    await tester.pumpAndSettle();
    await tester.tap(testMicrophone);
    await microphoneStarted.future;
    await tester.pump();
    expect(find.text('Testing…'), findsOneWidget);
    microphoneGate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Microphone is available.'), findsOneWidget);
    expect(
      nativeCalls,
      containsAll(['getUserMedia', 'trackDispose', 'streamDispose']),
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await harness.controller.leave();
    await tester.pump();
  });

  testWidgets('room chat exposes loading and empty states', (tester) async {
    final transport = _GatedChatTransport();
    final harness = _Harness(discourseApi: transport);
    addTearDown(harness.dispose);
    addTearDown(() {
      if (!transport.sessionGate.isCompleted) transport.sessionGate.complete();
    });
    final room = _room(
      chatAvailable: true,
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
    await tester.tap(find.byTooltip('Room chat'));
    await transport.sessionStarted.future;
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    transport.sessionGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('No messages yet.'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('room chat pages messages and sends trimmed composer text', (
    tester,
  ) async {
    final transport = RecordingPluginTransport(
      responses: const {
        'GET /resenha/rooms/7/chat_session.json': {
          'channel_id': 42,
          'thread_id': 99,
        },
      },
    );
    final conversations = FakeChatConversationCapability();
    final conversation = conversations.seed(
      siteUrl: _siteUrl,
      channelId: 42,
      threadId: 99,
      snapshot: ChatConversationSnapshot(
        messages: _chatPage(
          id: 10,
          username: 'sam',
          name: 'Sam',
          canLoadMorePast: true,
        ).messages,
        canLoadMorePast: true,
      ),
      olderMessages: _chatPage(id: 5, username: 'lee', name: 'Lee').messages,
    );
    final harness = _Harness(
      discourseApi: transport,
      chatConversations: conversations,
    );
    addTearDown(harness.dispose);
    final room = _room(
      chatAvailable: true,
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
    await tester.tap(find.byTooltip('Room chat'));
    await tester.pumpAndSettle();

    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Load older messages'), findsOneWidget);
    await tester.tap(find.text('Load older messages'));
    await tester.pumpAndSettle();
    expect(find.text('Lee'), findsOneWidget);
    expect(find.text('Load older messages'), findsNothing);
    expect(conversation.loadOlderCalls, 1);

    final composer = find.widgetWithText(TextField, 'Message the room');
    await tester.enterText(composer, '  hello room  ');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(composer).controller?.text, isEmpty);
    expect(conversation.sentMessages, ['hello room']);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(conversation.closeCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('member management adds, updates, and removes memberships', (
    tester,
  ) async {
    final transport = RecordingPluginTransport(
      responses: {
        'GET /resenha/rooms/7/memberships.json': {
          'memberships': const [
            {
              'id': 8,
              'room_id': 7,
              'user_id': 1,
              'role_name': 'moderator',
              'user': {'id': 1, 'username': 'sam'},
            },
            {
              'id': 9,
              'room_id': 7,
              'user_id': 2,
              'role_name': 'speaker',
              'user': {'id': 2, 'username': 'lee', 'name': 'Lee Example'},
            },
            {'id': 10, 'room_id': 7, 'user_id': 3, 'role_name': 'participant'},
          ],
        },
        'POST /resenha/rooms/7/memberships.json': <String, Object?>{},
        'PUT /resenha/rooms/7/memberships/9.json': <String, Object?>{},
        'DELETE /resenha/rooms/7/memberships/9.json': <String, Object?>{},
      },
    );
    final harness = _Harness(discourseApi: transport);
    addTearDown(harness.dispose);
    final room = _room(
      canManage: true,
      creatorId: 1,
      participants: const [
        ResenhaParticipant(id: 1, username: 'sam', role: ResenhaRole.moderator),
      ],
    );

    await tester.pumpWidget(
      _app(
        harness.controller,
        room: room,
        call: _call(room, harness.media.createSession()),
      ),
    );
    await tester.tap(find.byTooltip('Manage members'));
    await tester.pumpAndSettle();

    final membersDialog = find.byType(AlertDialog);
    expect(find.text('Members of Lounge'), findsOneWidget);
    expect(
      find.descendant(of: membersDialog, matching: find.text('sam')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: membersDialog, matching: find.text('Lee Example')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: membersDialog, matching: find.text('User 3')),
      findsOneWidget,
    );
    expect(find.byTooltip('Remove member'), findsNWidgets(2));

    final username = find.widgetWithText(TextField, 'Username');
    await tester.enterText(username, '   ');
    await tester.tap(find.byTooltip('Add member'));
    await tester.pumpAndSettle();
    expect(
      transport.writes.where(
        (write) => write.path.endsWith('/memberships.json'),
      ),
      isEmpty,
    );

    await tester.tap(find.byType(DropdownButton<ResenhaRole>));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .widgetWithText(
            DropdownMenuItem<ResenhaRole>,
            ResenhaRole.moderator.name,
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(username, '  jordan  ');
    await tester.tap(find.byTooltip('Add member'));
    await tester.pumpAndSettle();

    final add = transport.writes.singleWhere((write) => write.method == 'POST');
    expect(add.body['username'], 'jordan');
    expect(add.body['role'], 'moderator');
    expect(tester.widget<TextField>(username).controller?.text, isEmpty);

    final leeTile = find.widgetWithText(ListTile, 'Lee Example');
    await tester.tap(
      find.descendant(of: leeTile, matching: find.byTooltip('Change role')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .widgetWithText(
            PopupMenuItem<ResenhaRole>,
            ResenhaRole.participant.name,
          )
          .last,
    );
    await tester.pumpAndSettle();
    final update = transport.writes.singleWhere(
      (write) => write.method == 'PUT',
    );
    expect(update.path, '/resenha/rooms/7/memberships/9.json');
    expect(update.body['role'], 'participant');

    await tester.tap(
      find.descendant(of: leeTile, matching: find.byTooltip('Remove member')),
    );
    await tester.pumpAndSettle();
    final remove = transport.writes.singleWhere(
      (write) => write.method == 'DELETE',
    );
    expect(remove.path, '/resenha/rooms/7/memberships/9.json');
    expect(remove.body, isEmpty);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
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
    final semantics = tester.ensureSemantics();
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

    final nameField = find.byType(TextField).first;
    expect(find.text('Required'), findsOneWidget);
    expect(
      tester.getSemantics(nameField),
      isSemantics(
        label: 'Name',
        value: 'Lounge',
        isTextField: true,
        isRequired: true,
      ),
    );

    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.enterText(nameField, '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.showKeyboard(nameField);
    tester.testTextInput.enterText('Renamed lounge');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.transport.writes, isEmpty);
    semantics.dispose();
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

    expect(original.transport.writes, isEmpty);
    expect(
      replacement.transport.writes.map((write) => write.path),
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
      original.transport.writes.where(
        (write) => write.path.endsWith('/flag.json'),
      ),
      isEmpty,
    );
    expect(
      replacement.transport.writes.where(
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
        original.transport.writes.where(
          (write) => write.path.endsWith('/recording.json'),
        ),
        isEmpty,
      );
      expect(
        replacement.transport.writes.where(
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

ChatMessagePage _chatPage({
  required int id,
  required String username,
  required String name,
  bool canLoadMorePast = false,
}) => (
  messages: [
    ChatMessage(
      id: id,
      channelId: 42,
      cooked: '<p>Message $id</p>',
      author: ChatMessageAuthor(id: id, username: username, name: name),
    ),
  ],
  canLoadMorePast: canLoadMorePast,
  canLoadMoreFuture: false,
  targetMessageId: null,
);

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
  bool chatAvailable = false,
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
  chatAvailable: chatAvailable,
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
    'chat_available': room.chatAvailable,
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
    RecordingPluginTransport? discourseApi,
    _Preferences? preferences,
    FakeChatConversationCapability? chatConversations,
  }) : preferences = preferences ?? _Preferences(),
       chatConversations =
           chatConversations ?? FakeChatConversationCapability(),
       transport =
           discourseApi ??
           RecordingPluginTransport(
             responses: {
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
    controller = ResenhaController(
      api: ResenhaApi(transport),
      chatConversations: this.chatConversations,
      requests: PluginTestRequestHost(apiKeys: const {_siteUrl: 'key'}),
      trackerFor: (_) => null,
      userIdFor: (_) => 1,
      onCallSiteChanged: () {},
      mediaFactory: media,
      systemCall: _SystemCall(),
      preferences: this.preferences,
      heartbeatInterval: const Duration(days: 1),
    );
  }

  final RecordingPluginTransport transport;
  final _MediaFactory media;
  final _Preferences preferences;
  final FakeChatConversationCapability chatConversations;
  late final ResenhaController controller;

  void dispose() => controller.dispose();
}

ResenhaShellService _resenhaShell(
  ResenhaController controller, {
  PluginRouteSite? site,
  bool recordingEnabled = false,
}) => ResenhaShellService(
  controller: controller,
  host: _RouteHost(site),
  recordingEnabled: (_) => recordingEnabled,
);

final class _RouteHost implements PluginRouteNavigationHost {
  _RouteHost(this.currentSite)
    : sites = currentSite == null ? const [] : [currentSite];

  @override
  final List<PluginRouteSite> sites;

  @override
  PluginRouteSite? currentSite;

  @override
  ContentRoute? currentContent;

  @override
  void pushContent(ContentRoute route) => currentContent = route;

  @override
  void replaceCurrentContent(ContentRoute route) => currentContent = route;

  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
  }) {}

  @override
  void selectInstance(int index) => currentSite = sites[index];
}

final class _GatedMembershipTransport extends RecordingPluginTransport {
  _GatedMembershipTransport()
    : super(
        responses: const {
          'GET /resenha/rooms/7/memberships.json': {'memberships': <Object>[]},
          'POST /resenha/rooms/7/memberships.json': <String, Object?>{},
        },
      );

  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> writeGate = Completer<void>();
  int membershipReads = 0;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    if (path == '/resenha/rooms/7/memberships.json') membershipReads++;
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    if (method == 'POST' && path == '/resenha/rooms/7/memberships.json') {
      writeStarted.complete();
      await writeGate.future;
    }
    return super.pluginWriteJson(
      siteUrl: siteUrl,
      path: path,
      method: method,
      apiKey: apiKey,
      body: body,
      clientId: clientId,
    );
  }
}

final class _GatedChatTransport extends RecordingPluginTransport {
  _GatedChatTransport()
    : super(
        responses: const {
          'GET /resenha/rooms/7/chat_session.json': <String, Object?>{},
        },
      );

  final Completer<void> sessionStarted = Completer<void>();
  final Completer<void> sessionGate = Completer<void>();

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    if (path == '/resenha/rooms/7/chat_session.json') {
      sessionStarted.complete();
      await sessionGate.future;
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
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
  List<rtc.MediaDeviceInfo> availableDevices = const [];
  final List<String> audioInputs = [];
  final List<String> audioOutputs = [];
  final List<({bool enabled, String? deviceId})> cameraChanges = [];
  final List<({int participantId, double volume})> participantVolumes = [];

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
  Future<void> syncParticipants(List<ResenhaParticipant> participants) async {}
  @override
  Future<void> dispose() async {
    disposeCount++;
    super.dispose();
  }
}

final class _Preferences implements ResenhaPreferences {
  _Preferences({this.participantVolume});

  final double? participantVolume;
  final List<({ResenhaDevicePreference preference, String value})>
  deviceWrites = [];
  final List<bool> pushToTalkWrites = [];
  final List<({String siteUrl, int roomId, int userId, double volume})>
  participantVolumeWrites = [];

  @override
  Future<ResenhaDevicePreferences> readDevices() async =>
      const ResenhaDevicePreferences();
  @override
  Future<double?> readParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
  ) async => participantVolume;
  @override
  Future<void> writeDevice(
    ResenhaDevicePreference preference,
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
