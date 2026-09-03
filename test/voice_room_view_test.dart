import 'dart:async';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_test.dart'
    show PluginTestRequestHost;
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/chat/chat_contract.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_callkit.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics.dart';
import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_preferences.dart';
import 'package:discourse_native/src/plugins/voice/voice_room_view.dart';
import 'package:discourse_native/src/plugins/voice/voice_shell_service.dart';
import 'package:discourse_plugin_api/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_track_impl.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'support/voice_fake_chat_conversations.dart';

const _siteUrl = 'https://voice.example.com';

void main() {
  _meshPrivacyTests();
  _roomSurfaceTests();

  group('room availability and layout', () {
    testWidgets('renders unavailable and empty states without a shell', (
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

    testWidgets('hides content without a site and reports a missing room', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: VoiceRoomView(
            roomId: 7,
            controller: harness.controller,
            shell: _voiceShell(harness.controller),
          ),
        ),
      );
      expect(find.byType(VoiceRoomContent), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: VoiceRoomView(
            roomId: 7,
            controller: harness.controller,
            shell: _voiceShell(
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

    testWidgets('exposes participant semantics and adapts columns to width', (
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
          const VoiceParticipant(
            id: 1,
            username: 'sam',
            role: VoiceRole.moderator,
          ),
          VoiceParticipant(
            id: 2,
            username: 'lee',
            name: 'Lee',
            role: VoiceRole.participant,
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
  });

  group('call, media, and moderation', () {
    testWidgets(
      'keeps borrowed WebRTC tracks out of streams during renderer replacement',
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
              'streamId': 'voice-test-stream',
            },
            'videoRendererSetSrcObject' || 'streamDispose' => null,
            _ => throw UnsupportedError(
              'Unexpected WebRTC call: ${call.method}',
            ),
          };
        });
        addTearDown(() {
          if (!releaseRenderer.isCompleted) releaseRenderer.complete();
          rtc.WebRTC.initialized = false;
          messenger.setMockMethodCallHandler(webRtcChannel, null);
          messenger.setMockStreamHandler(eventChannel, null);
          messenger.setMockStreamHandler(textureChannel, null);
        });

        await tester.pumpWidget(
          MaterialApp(home: VoiceVideoSurface(track: _nativeVideoTrack())),
        );
        expect(calls, contains('videoRendererSetSrcObject'));

        await tester.pumpWidget(
          MaterialApp(home: VoiceVideoSurface(track: _nativeVideoTrack())),
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
        expect(
          calls.where((method) => method == 'streamDispose'),
          hasLength(2),
        );
        expect(
          calls.where((method) => method == 'videoRendererDispose'),
          hasLength(2),
          reason: '$calls',
        );
      },
    );

    testWidgets('unmutes only while desktop push-to-talk is held', (
      tester,
    ) async {
      final room = _room(
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.participant),
        ],
      );
      final harness = _Harness(joinRoom: room);
      addTearDown(harness.dispose);
      await _join(harness, room);
      final shell = _voiceShell(
        harness.controller,
        site: const PluginRouteSite(
          url: _siteUrl,
          title: 'Voice',
          isConnected: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: VoiceRoomView(
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

    testWidgets('exposes controls after joining and reports mute failures', (
      tester,
    ) async {
      final harness = await _pumpJoinedManagedRoom(tester);
      try {
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
      } finally {
        harness.dispose();
      }
    });

    testWidgets('shows and dismisses an actionable failed-join message', (
      tester,
    ) async {
      final room = _room(participants: const []);
      final harness = _Harness(joinRoom: room);
      addTearDown(harness.dispose);
      harness.media.nextConnectFailure = const VoiceMicrophoneException(
        VoiceMicrophoneFailureKind.permissionDenied,
      );

      await _join(harness, room);
      await tester.pumpWidget(_app(harness.controller, room: room));

      expect(
        find.text(
          'Microphone access is blocked. Allow microphone access in your '
          'system settings, then try joining again.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('lets moderators remove other participants', (tester) async {
      final harness = await _pumpJoinedManagedRoom(tester);
      try {
        await tester.tap(find.byTooltip('Participant actions'));
        await tester.pumpAndSettle();
        expect(find.text('Local volume'), findsOneWidget);
        expect(find.text('Notify moderators'), findsOneWidget);
        expect(find.text('Dismiss raised hand'), findsOneWidget);
        expect(find.text('Remove from room'), findsOneWidget);

        await tester.tap(find.text('Remove from room'));
        await tester.pumpAndSettle();
        final kick = harness.transport.writes.singleWhere(
          (write) => write.path == '/voice/rooms/7/kick.json',
        );
        expect(kick.method, 'DELETE');
        expect(kick.body, {'user_id': 2});
      } finally {
        harness.dispose();
      }
    });

    testWidgets('disposes media on leave and restores the join action', (
      tester,
    ) async {
      final harness = await _pumpJoinedManagedRoom(tester);

      await tester.tap(find.text('Leave room'));
      await tester.pumpAndSettle();
      expect(harness.media.sessions.single.disposeCount, 1);
      expect(harness.controller.call, isNull);
      expect(find.text('Join room'), findsOneWidget);
    });

    testWidgets('hides moderator-only participant actions from listeners', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final room = _room(
        participants: [
          const VoiceParticipant(
            id: 1,
            username: 'sam',
            role: VoiceRole.participant,
          ),
          VoiceParticipant(
            id: 2,
            username: 'lee',
            role: VoiceRole.participant,
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

    testWidgets('publishes video-watching state from mount through unmount', (
      tester,
    ) async {
      final room = _room(
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.participant),
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
      expect(stateWrites.map((write) => write.body['watching']), [true]);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      stateWrites = harness.transport.writes
          .where((write) => write.path.endsWith('/state.json'))
          .toList();
      expect(stateWrites.map((write) => write.body['watching']), [true, false]);

      await harness.controller.leave();
      await tester.pump();
    });

    testWidgets('limits stage listeners to receive-only controls', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final room = _room(
        type: VoiceRoomType.stage,
        videoAllowed: true,
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.participant),
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

    for (final role in [VoiceRole.speaker, VoiceRole.moderator]) {
      testWidgets(
        'keeps publishing controls available to stage ${role.name}s',
        (tester) async {
          final harness = _Harness();
          addTearDown(harness.dispose);
          final room = _room(
            type: VoiceRoomType.stage,
            videoAllowed: true,
            participants: [
              VoiceParticipant(id: 1, username: 'sam', role: role),
            ],
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
            (Platform.isMacOS || Platform.isLinux)
                ? findsOneWidget
                : findsNothing,
          );
          expect(find.byTooltip('Raise hand'), findsNothing);
        },
      );
    }
  });

  group('settings and preferences', () {
    testWidgets('applies participant volume locally and persists it', (
      tester,
    ) async {
      final preferences = _Preferences(participantVolume: 0.4);
      final room = _room(
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.participant),
          VoiceParticipant(id: 2, username: 'lee', role: VoiceRole.participant),
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

    testWidgets(
      'persists device and push-to-talk settings and verifies the microphone',
      (tester) async {
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
            _ => throw UnsupportedError(
              'Unexpected WebRTC call: ${call.method}',
            ),
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
            VoiceParticipant(
              id: 1,
              username: 'sam',
              role: VoiceRole.participant,
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
          (preference: VoiceDevicePreference.audioInput, value: 'microphone-2'),
          (preference: VoiceDevicePreference.audioOutput, value: 'speaker-2'),
          (preference: VoiceDevicePreference.camera, value: 'camera-2'),
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
        expect(nativeCalls, [
          'initialize',
          'getUserMedia',
          'trackDispose',
          'streamDispose',
        ]);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        await harness.controller.leave();
        await tester.pump();
      },
    );
  });

  group('room Chat', () {
    testWidgets('shows loading before an empty conversation', (tester) async {
      final transport = _GatedChatTransport();
      final harness = _Harness(discourseApi: transport);
      addTearDown(harness.dispose);
      addTearDown(() {
        if (!transport.sessionGate.isCompleted) {
          transport.sessionGate.complete();
        }
      });
      final room = _room(
        chatAvailable: true,
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.participant),
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

    testWidgets('loads older messages and sends trimmed composer text', (
      tester,
    ) async {
      final transport = RecordingPluginTransport(
        responses: const {
          'GET /voice/rooms/7/chat_session.json': {
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
        snapshotAfterLoadOlder: ChatConversationSnapshot(
          messages: [
            ..._chatPage(id: 5, username: 'lee', name: 'Lee').messages,
            ..._chatPage(id: 10, username: 'sam', name: 'Sam').messages,
          ],
          canLoadMorePast: false,
        ),
      );
      final harness = _Harness(
        discourseApi: transport,
        chatConversations: conversations,
      );
      addTearDown(harness.dispose);
      final room = _room(
        chatAvailable: true,
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.participant),
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
      expect(conversation.value.messages.map((message) => message.id), [5, 10]);
      expect(conversation.value.canLoadMorePast, isFalse);
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
  });

  group('membership management', () {
    testWidgets('ignores a pending add after the dialog is dismissed', (
      tester,
    ) async {
      final transport = _GatedMembershipTransport();
      final harness = _Harness(discourseApi: transport);
      addTearDown(harness.dispose);
      addTearDown(() {
        if (!transport.writeGate.isCompleted) transport.writeGate.complete();
      });
      final room = _room(
        canManage: true,
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
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

    testWidgets('adds, changes, and removes room memberships', (tester) async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET /voice/rooms/7/memberships.json': {
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
              {
                'id': 10,
                'room_id': 7,
                'user_id': 3,
                'role_name': 'participant',
              },
            ],
          },
          'POST /voice/rooms/7/memberships.json': <String, Object?>{},
          'PUT /voice/rooms/7/memberships/9.json': <String, Object?>{},
          'DELETE /voice/rooms/7/memberships/9.json': <String, Object?>{},
        },
      );
      final harness = _Harness(discourseApi: transport);
      addTearDown(harness.dispose);
      final room = _room(
        canManage: true,
        creatorId: 1,
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
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

      await tester.tap(find.byType(DropdownButton<VoiceRole>));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .widgetWithText(
              DropdownMenuItem<VoiceRole>,
              VoiceRole.moderator.name,
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(username, '  jordan  ');
      await tester.tap(find.byTooltip('Add member'));
      await tester.pumpAndSettle();

      final add = transport.writes.singleWhere(
        (write) => write.method == 'POST',
      );
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
              PopupMenuItem<VoiceRole>,
              VoiceRole.participant.name,
            )
            .last,
      );
      await tester.pumpAndSettle();
      final update = transport.writes.singleWhere(
        (write) => write.method == 'PUT',
      );
      expect(update.path, '/voice/rooms/7/memberships/9.json');
      expect(update.body['role'], 'participant');

      await tester.tap(
        find.descendant(of: leeTile, matching: find.byTooltip('Remove member')),
      );
      await tester.pumpAndSettle();
      final remove = transport.writes.singleWhere(
        (write) => write.method == 'DELETE',
      );
      expect(remove.path, '/voice/rooms/7/memberships/9.json');
      expect(remove.body, isEmpty);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });
  });

  group('editor and dialog lifecycle', () {
    testWidgets('validates room names while the user types', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final room = _room(
          canManage: true,
          participants: const [
            VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
          ],
        );
        final call = _call(room, harness.media.createSession());

        await tester.pumpWidget(
          _app(harness.controller, room: room, call: call),
        );
        await tester.tap(find.byTooltip('Edit room'));
        await tester.pumpAndSettle();

        final nameField = find.byType(TextField).first;
        expect(find.text('Chat thread title template'), findsNothing);
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
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('uses the latest controller when saving a room', (
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
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => unawaited(
                showVoiceRoomEditor(
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
      final update = replacement.transport.writes.single;
      expect(update.method, 'PUT');
      expect(update.path, '/voice/rooms/7.json');
      expect(
        (update.body['room']! as Map<String, Object?>)['name'],
        'Replacement save',
      );
      expect(
        update.body['room']! as Map<String, Object?>,
        isNot(contains('chat_thread_title_template')),
      );
    });

    testWidgets('uses the latest controller when confirming a flag', (
      tester,
    ) async {
      final room = _room(
        canManage: true,
        creatorId: 1,
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
          VoiceParticipant(id: 2, username: 'lee', role: VoiceRole.participant),
        ],
      );
      final original = _Harness(joinRoom: room);
      final replacement = _Harness(joinRoom: room);
      addTearDown(original.dispose);
      addTearDown(replacement.dispose);
      try {
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
        final flag = replacement.transport.writes.singleWhere(
          (write) => write.path.endsWith('/flag.json'),
        );
        expect(flag.method, 'POST');
        expect(flag.path, '/voice/rooms/7/flag.json');
        expect(flag.body, {
          'user_id': 2,
          'flag_type_id': 3,
          'message': 'Please review this',
        });
      } finally {
        original.dispose();
        replacement.dispose();
      }
    });

    testWidgets('uses the latest controller when confirming recording', (
      tester,
    ) async {
      final room = _room(
        canManage: true,
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
        ],
      );
      final original = _Harness(
        joinRoom: room,
        joinTransport: VoiceTransport.livekit,
      );
      final replacement = _Harness(
        joinRoom: room,
        joinTransport: VoiceTransport.livekit,
      );
      addTearDown(original.dispose);
      addTearDown(replacement.dispose);
      try {
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
        final recording = replacement.transport.writes.singleWhere(
          (write) => write.path.endsWith('/recording.json'),
        );
        expect(recording.method, 'POST');
        expect(recording.path, '/voice/rooms/7/recording.json');
        expect(recording.body, isEmpty);
      } finally {
        original.dispose();
        replacement.dispose();
      }
    });
  });
}

void _roomSurfaceTests() {
  group('room surface', () {
    testWidgets('everyone sees that a call is being recorded', (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final room = _room(
        participants: const [
          VoiceParticipant(id: 2, username: 'lee', role: VoiceRole.moderator),
        ],
        recording: const VoiceRecording(
          active: true,
          startedById: 2,
          startedByUsername: 'lee',
        ),
      );

      await tester.pumpWidget(_app(harness.controller, room: room));

      expect(find.text('Recording'), findsOneWidget);
      expect(find.byTooltip('Recording started by @lee'), findsOneWidget);
      expect(find.text('Join room'), findsOneWidget);
    });

    testWidgets('an empty room shows its cooked description', (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final room = _room(
        participants: const [],
        description: 'A **calm** place',
        cookedDescription: '<p>A <strong>calm</strong> place</p>',
      );

      await tester.pumpWidget(_app(harness.controller, room: room));
      await tester.pumpAndSettle();

      expect(find.text('A **calm** place'), findsNothing);
      expect(find.byType(HtmlWidget), findsOneWidget);
      expect(find.text('A calm place', findRichText: true), findsOneWidget);
    });

    testWidgets('a manager promotes and demotes stage participants', (
      tester,
    ) async {
      final room = _room(
        type: VoiceRoomType.stage,
        canManage: true,
        creatorId: 1,
        participants: [
          const VoiceParticipant(
            id: 1,
            username: 'sam',
            role: VoiceRole.moderator,
          ),
          VoiceParticipant(
            id: 2,
            username: 'lee',
            role: VoiceRole.participant,
            handRaisedAt: DateTime.utc(2026),
          ),
          const VoiceParticipant(
            id: 3,
            username: 'kim',
            role: VoiceRole.speaker,
          ),
        ],
      );
      final harness = _Harness(joinRoom: room);
      addTearDown(harness.dispose);
      await _join(harness, room);
      await tester.pumpWidget(
        _app(harness.controller, room: room, call: harness.controller.call),
      );

      // The joined room is drawn in canonical order (kim, lee, sam) and the
      // local user has no menu, so the first menu is kim's, the second lee's.
      await tester.tap(find.byTooltip('Participant actions').at(0));
      await tester.pumpAndSettle();
      expect(find.text('Move to listeners'), findsOneWidget);
      expect(find.text('Make speaker'), findsNothing);
      await tester.tap(find.text('Move to listeners'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Participant actions').at(1));
      await tester.pumpAndSettle();
      expect(find.text('Make speaker'), findsOneWidget);
      await tester.tap(find.text('Make speaker'));
      await tester.pumpAndSettle();

      final writes = harness.transport.writes
          .where((write) => write.path.endsWith('/memberships.json'))
          .toList();
      expect(writes.map((write) => write.method), ['POST', 'POST']);
      expect(
        writes.map(
          (write) => {...write.body}..removeWhere((_, value) => value == null),
        ),
        [
          {'user_id': 3, 'role': 'participant'},
          {'user_id': 2, 'role': 'speaker'},
        ],
      );
      harness.dispose();
    });

    testWidgets('open rooms offer no role changes', (tester) async {
      final room = _room(
        canManage: true,
        creatorId: 1,
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
          VoiceParticipant(id: 2, username: 'lee', role: VoiceRole.participant),
        ],
      );
      final harness = _Harness(joinRoom: room);
      addTearDown(harness.dispose);
      await _join(harness, room);
      await tester.pumpWidget(
        _app(harness.controller, room: room, call: harness.controller.call),
      );

      await tester.tap(find.byTooltip('Participant actions'));
      await tester.pumpAndSettle();

      expect(find.text('Make speaker'), findsNothing);
      expect(find.text('Move to listeners'), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      harness.dispose();
    });
  });
}

void _meshPrivacyTests() {
  group('mesh privacy warning', () {
    VoiceRoom meshRoom() =>
        _room(expectedTransport: VoiceTransport.mesh, participants: const []);

    testWidgets('a cancelled warning joins nothing', (tester) async {
      final room = meshRoom();
      final harness = _Harness(joinRoom: room);
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        _app(harness.controller, room: room, meshPrivacyWarningEnabled: true),
      );

      await tester.tap(find.text('Join room'));
      await tester.pumpAndSettle();

      expect(find.text('Before you join this room'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(harness.controller.call, isNull);
      expect(
        harness.transport.writes.where((w) => w.path.endsWith('/join.json')),
        isEmpty,
      );
      expect(harness.preferences.meshPrivacyWrites, isEmpty);
    });

    testWidgets('accepting joins, and "don\'t show again" is remembered', (
      tester,
    ) async {
      final room = meshRoom();
      final harness = _Harness(joinRoom: room);
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        _app(harness.controller, room: room, meshPrivacyWarningEnabled: true),
      );

      await tester.tap(find.text('Join room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Don't show this again"));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Join room'),
        ),
      );
      await tester.pumpAndSettle();

      expect(harness.controller.call, isNotNull);
      expect(harness.preferences.meshPrivacyWrites, [true]);

      await harness.controller.leave();
      await tester.pumpWidget(
        _app(harness.controller, room: room, meshPrivacyWarningEnabled: true),
      );
      await tester.tap(find.text('Join room'));
      await tester.pumpAndSettle();

      expect(find.text('Before you join this room'), findsNothing);
      expect(harness.controller.call, isNotNull);
      // Disposed here, not only in a teardown: the joined call's timers
      // must be gone before the binding checks for pending timers.
      harness.dispose();
    });

    testWidgets(
      'no warning when the site turned it off or the call is not mesh',
      (tester) async {
        final livekitRoom = _room(
          expectedTransport: VoiceTransport.livekit,
          participants: const [],
        );
        final harness = _Harness(joinRoom: livekitRoom);
        addTearDown(harness.dispose);
        await tester.pumpWidget(
          _app(
            harness.controller,
            room: livekitRoom,
            meshPrivacyWarningEnabled: true,
          ),
        );
        await tester.tap(find.text('Join room'));
        await tester.pumpAndSettle();
        expect(find.text('Before you join this room'), findsNothing);
        expect(harness.controller.call, isNotNull);
        await harness.controller.leave();

        final room = meshRoom();
        final quiet = _Harness(joinRoom: room);
        addTearDown(quiet.dispose);
        await tester.pumpWidget(_app(quiet.controller, room: room));
        await tester.tap(find.text('Join room'));
        await tester.pumpAndSettle();
        expect(find.text('Before you join this room'), findsNothing);
        expect(quiet.controller.call, isNotNull);
        harness.dispose();
        quiet.dispose();
      },
    );
  });

  group('status choice', () {
    testWidgets(
      'media settings offer the status toggle when the site allows it',
      (tester) async {
        final room = _room(
          participants: const [
            VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
          ],
        );
        final harness = _Harness(joinRoom: room);
        addTearDown(harness.dispose);
        await _join(harness, room);
        await tester.pumpWidget(
          _app(
            harness.controller,
            room: room,
            call: harness.controller.call,
            autoStatusAvailable: true,
          ),
        );

        await tester.tap(find.byTooltip('Media settings'));
        await tester.pumpAndSettle();
        expect(find.text('Show my status while in a call'), findsOneWidget);
        await tester.tap(find.text('Show my status while in a call'));
        await tester.pumpAndSettle();

        expect(harness.controller.autoStatusEnabled, isFalse);
        expect(harness.preferences.autoStatusWrites, [false]);
        harness.dispose();
      },
    );
  });
}

Future<_Harness> _pumpJoinedManagedRoom(WidgetTester tester) async {
  final activeRoom = _room(
    canManage: true,
    videoAllowed: true,
    creatorId: 1,
    participants: [
      const VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
      VoiceParticipant(
        id: 2,
        username: 'lee',
        name: 'Lee',
        role: VoiceRole.participant,
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
  return harness;
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

Future<void> _join(_Harness harness, VoiceRoom room) =>
    harness.controller.join(siteUrl: _siteUrl, siteName: 'Voice', room: room);

VoiceCallSnapshot _call(VoiceRoom room, VoiceMediaSession media) =>
    VoiceCallSnapshot(
      siteUrl: _siteUrl,
      siteName: 'Voice',
      room: room,
      status: VoiceCallStatus.connected,
      media: media,
    );

int _columns(WidgetTester tester) =>
    (tester.widget<GridView>(find.byType(GridView)).gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount)
        .crossAxisCount;

Widget _app(
  VoiceController controller, {
  required VoiceRoom? room,
  VoiceCallSnapshot? call,
  bool followCall = false,
  bool meshPrivacyWarningEnabled = false,
  bool autoStatusAvailable = false,
  VoiceController Function()? controllerResolver,
}) => MaterialApp(
  home: Scaffold(
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final active = followCall ? controller.call : call;
        return VoiceRoomContent(
          controller: controller,
          room: active?.room ?? room,
          call: active,
          siteUrl: _siteUrl,
          siteName: 'Voice',
          currentUserId: 1,
          recordingEnabled: true,
          meshPrivacyWarningEnabled: meshPrivacyWarningEnabled,
          autoStatusAvailable: autoStatusAvailable,
          controllerResolver: controllerResolver,
        );
      },
    ),
  ),
);

VoiceRoom _room({
  required List<VoiceParticipant> participants,
  String? description,
  String? cookedDescription,
  int? creatorId,
  bool canManage = false,
  bool videoAllowed = false,
  bool chatAvailable = false,
  VoiceRoomType type = VoiceRoomType.open,
  VoiceTransport? expectedTransport,
  VoiceRecording? recording,
}) => VoiceRoom(
  id: 7,
  name: 'Lounge',
  slug: 'lounge',
  description: description,
  cookedDescription: cookedDescription,
  recording: recording,
  isPublic: true,
  ephemeral: false,
  type: type,
  participants: participants,
  creatorId: creatorId,
  canManage: canManage,
  videoEnabled: videoAllowed,
  videoAllowed: videoAllowed,
  chatAvailable: chatAvailable,
  expectedTransport: expectedTransport,
);

Map<String, dynamic> _joinPayload(
  VoiceRoom room, {
  VoiceTransport transport = VoiceTransport.mesh,
}) => {
  'transport': transport.name,
  'ice': {'servers': <Object>[]},
  if (transport == VoiceTransport.livekit)
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
    VoiceRoom? joinRoom,
    VoiceTransport joinTransport = VoiceTransport.mesh,
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
                 'POST /voice/rooms/7/join.json': _joinPayload(
                   joinRoom,
                   transport: joinTransport,
                 ),
               'POST /voice/rooms/7/state.json': const {},
               'DELETE /voice/rooms/7/kick.json': const {},
               'POST /voice/rooms/7/memberships.json': const {},
               'DELETE /voice/rooms/7/leave.json': const {},
               'GET /site.json': const {
                 'post_action_types': [
                   {'name_key': 'notify_moderators', 'id': 3},
                 ],
               },
               'POST /voice/rooms/7/flag.json': const {},
               'POST /voice/rooms/7/recording.json': const {},
             },
           ),
       media = _MediaFactory(speakingIds) {
    controller = VoiceController(
      api: VoiceApi(transport),
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
  late final VoiceController controller;

  void dispose() => controller.dispose();
}

VoiceShellService _voiceShell(
  VoiceController controller, {
  PluginRouteSite? site,
  bool recordingEnabled = false,
}) => VoiceShellService(
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
          'GET /voice/rooms/7/memberships.json': {'memberships': <Object>[]},
          'POST /voice/rooms/7/memberships.json': <String, Object?>{},
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
    if (path == '/voice/rooms/7/memberships.json') membershipReads++;
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
    if (method == 'POST' && path == '/voice/rooms/7/memberships.json') {
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
          'GET /voice/rooms/7/chat_session.json': <String, Object?>{},
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
    if (path == '/voice/rooms/7/chat_session.json') {
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
  _MediaSession(this.transport, this.speakingParticipantIds);

  @override
  final VoiceTransport transport;
  @override
  final Set<int> speakingParticipantIds;
  int connectCount = 0;
  int disposeCount = 0;
  Object? connectFailure;
  bool muted = false;
  bool failNextMute = false;
  List<rtc.MediaDeviceInfo> availableDevices = const [];
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
  Object? videoTrackFor(int participantId) => null;
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
  final List<bool> meshPrivacyWrites = [];
  bool? autoStatusEnabled;
  final List<bool> autoStatusWrites = [];

  @override
  Future<bool> readMeshPrivacyAcknowledged() async => meshPrivacyAcknowledged;

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
  final StreamController<VoiceSystemCallAction> _actions =
      StreamController.broadcast();

  @override
  Stream<VoiceSystemCallAction> get actions => _actions.stream;
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
