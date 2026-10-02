import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/discourse_plugin_sdk.dart'
    show
        PluginDescriptor,
        PluginInstaller,
        PluginManifest,
        PluginModule,
        PluginRegistrar,
        PluginRequestHost,
        PluginService,
        PluginSessionContribution,
        PluginSessionLifecycle,
        PluginUiScope,
        corePluginRequestPort,
        corePluginRouteNavigationPort;
import 'package:discourse_native/discourse_plugin_test.dart'
    show PluginTestRequestHost, RecordingPluginLiveChannels;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart'
    show WriteException, WriteFailure;
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/diagnostics/diagnostic_event.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_persistence.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/chat/chat_contract.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_callkit.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics.dart';
import 'package:discourse_native/src/plugins/voice/voice_incoming_call.dart';
import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_plugin.dart';
import 'package:discourse_native/src/plugins/voice/voice_preferences.dart';
import 'package:discourse_native/src/plugins/voice/voice_room_view.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_shell_service.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_plugin_api/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:flutter_webrtc/src/native/media_stream_track_impl.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/fakes.dart';
import 'support/voice_fake_chat_conversations.dart';

const _siteUrl = 'https://voice.example.com';

void main() {
  _preferenceRemovalTests();
  _roomDialogSessionTests();
  _meshPrivacyTests();
  _roomSurfaceTests();
  _directCallTests();
  _inviteTests();
  _microphoneTests();

  group('room availability and layout', () {
    testWidgets(
      'participant avatar in a subfolder room uses its wire path once',
      (tester) async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final participant = VoiceParticipant.fromJson(const {
          'id': 2,
          'username': 'lee',
          'role': 'participant',
          'avatar_template':
              '/forum/user_avatar/voice.example.com/lee/{size}/1_2.png',
        });
        await tester.pumpWidget(
          _app(
            harness.controller,
            room: _room(participants: [participant]),
            siteUrl: '$_siteUrl/forum',
          ),
        );
        final avatar = tester.widget<AvatarImage>(find.byType(AvatarImage));
        expect(
          avatar.url,
          '$_siteUrl/forum/user_avatar/voice.example.com/lee/144/1_2.png',
        );
        expect(avatar.size, 72);
        expect(tester.takeException(), isNull);
      },
    );

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
      'media changes rebuild only affected tiles until room state changes',
      (tester) async {
        final room = _room(
          participants: const [
            VoiceParticipant(
              id: 1,
              username: 'sam',
              role: VoiceRole.participant,
            ),
            VoiceParticipant(
              id: 2,
              username: 'lee',
              name: 'Lee',
              role: VoiceRole.participant,
            ),
          ],
        );
        final harness = _Harness(joinRoom: room);
        addTearDown(harness.dispose);
        await _join(harness, room);
        await tester.pumpWidget(
          MaterialApp(
            home: VoiceRoomView(
              roomId: room.id,
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

        final roomContent = tester.element(find.byType(VoiceRoomContent));
        final samTile = tester.element(
          find.byKey(const ValueKey(('voice-participant', 1))),
        );
        final leeTile = tester.element(
          find.byKey(const ValueKey(('voice-participant', 2))),
        );
        final rebuilt = <Element>{};
        final previousRebuildHook = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          previousRebuildHook?.call(element, builtOnce);
          rebuilt.add(element);
        };
        addTearDown(() => debugOnRebuildDirtyWidget = previousRebuildHook);

        final media = harness.media.sessions.single;
        media.setSpeakingParticipantIds(const {2});
        await tester.pump();

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Lee, speaking',
          ),
          findsOneWidget,
        );
        expect(rebuilt, contains(leeTile));
        expect(rebuilt, isNot(contains(samTile)));
        expect(rebuilt, isNot(contains(roomContent)));

        rebuilt.clear();
        media.notifyUnchanged();
        await tester.pump();

        expect(rebuilt, isNot(contains(leeTile)));
        expect(rebuilt, isNot(contains(samTile)));
        expect(rebuilt, isNot(contains(roomContent)));

        rebuilt.clear();
        media.setVideoTrack(2, Object());
        await tester.pump();

        expect(find.byType(VoiceVideoSurface), findsOneWidget);
        expect(rebuilt, contains(leeTile));
        expect(rebuilt, isNot(contains(samTile)));
        expect(rebuilt, isNot(contains(roomContent)));

        rebuilt.clear();
        await harness.controller.setMuted(true);
        await tester.pump();

        expect(find.byTooltip('Unmute'), findsOneWidget);
        expect(rebuilt, contains(roomContent));

        await harness.controller.leave();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('participant tiles replace their media subscription', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final room = _room(
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.participant),
        ],
      );
      final first = harness.media.createSession();
      final replacement = harness.media.createSession();
      addTearDown(first.dispose);
      addTearDown(replacement.dispose);

      await tester.pumpWidget(
        _app(harness.controller, room: room, call: _call(room, first)),
      );
      await tester.pumpWidget(
        _app(harness.controller, room: room, call: _call(room, replacement)),
      );

      first.setSpeakingParticipantIds(const {1});
      first.setVideoTrack(1, Object());
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'sam, speaking',
        ),
        findsNothing,
      );
      expect(find.byType(VoiceVideoSurface), findsNothing);

      replacement.setSpeakingParticipantIds(const {1});
      replacement.setVideoTrack(1, Object());
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'sam, speaking',
        ),
        findsOneWidget,
      );
      expect(find.byType(VoiceVideoSurface), findsOneWidget);
    });

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

    for (final release in ['loses focus', 'closes']) {
      testWidgets(
        'mutes push-to-talk held while the room $release before Space is released',
        (tester) async {
          final room = _room(
            participants: const [
              VoiceParticipant(
                id: 1,
                username: 'sam',
                role: VoiceRole.participant,
              ),
            ],
          );
          final harness = _Harness(joinRoom: room);
          addTearDown(harness.dispose);
          await _join(harness, room);
          await harness.controller.setPushToTalkEnabled(true);
          final shell = _voiceShell(
            harness.controller,
            site: const PluginRouteSite(
              url: _siteUrl,
              title: 'Voice',
              isConnected: true,
            ),
          );
          Widget app({required bool roomOpen}) => MaterialApp(
            home: Column(
              children: [
                // The shell keeps drawing the call after its room closes.
                ListenableBuilder(
                  listenable: harness.controller,
                  builder: (context, _) => Text(
                    harness.controller.call?.muted ?? false ? 'Muted' : 'Live',
                  ),
                ),
                if (roomOpen)
                  Expanded(
                    child: VoiceRoomView(
                      roomId: 7,
                      controller: harness.controller,
                      shell: shell,
                    ),
                  ),
              ],
            ),
          );
          await tester.pumpWidget(app(roomOpen: true));
          await tester.pumpAndSettle();
          final media = harness.media.sessions.single;
          expect(
            await tester.sendKeyDownEvent(LogicalKeyboardKey.space),
            isTrue,
          );
          await tester.pumpAndSettle();
          expect(media.muted, isFalse);
          expect(find.text('Live'), findsOneWidget);

          // Desktop focus leaves the room when the window deactivates, and
          // the Space release is then delivered elsewhere or not at all.
          if (release == 'loses focus') {
            tester.binding.focusManager.primaryFocus!.unfocus();
          } else {
            await tester.pumpWidget(app(roomOpen: false));
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(media.muted, isTrue);
          expect(harness.controller.call?.muted, isTrue);
          expect(find.text('Muted'), findsOneWidget);

          await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
          await harness.controller.leave();
          await tester.pump();
        },
      );
    }

    testWidgets('push-to-talk leaves a Space typed in room chat to its field', (
      tester,
    ) async {
      final room = _room(
        chatAvailable: true,
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.participant),
        ],
      );
      final harness = _Harness(
        discourseApi: RecordingPluginTransport(
          responses: {
            'POST /voice/rooms/7/join.json': _joinPayload(room),
            'POST /voice/rooms/7/state.json': const {},
            'GET /voice/rooms/7/chat_session.json': const {
              'channel_id': 42,
              'thread_id': 99,
            },
            'DELETE /voice/rooms/7/leave.json': const {},
          },
        ),
      );
      addTearDown(harness.dispose);
      await _join(harness, room);
      await harness.controller.setPushToTalkEnabled(true);
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
      await tester.pumpAndSettle();
      final media = harness.media.sessions.single;
      Future<void> holdSpaceInRoom() async {
        expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.space), isTrue);
        await tester.pumpAndSettle();
        expect(media.muted, isFalse);
        expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.space), isTrue);
        await tester.pumpAndSettle();
        expect(media.muted, isTrue);
      }

      await holdSpaceInRoom();

      await tester.tap(find.byTooltip('Room chat'));
      await tester.pumpAndSettle();
      final composer = find.widgetWithText(TextField, 'Message the room');
      await tester.tap(composer);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: composer,
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasPrimaryFocus,
        isTrue,
      );

      // A desktop engine hands the text input only the keys no framework
      // handler claimed, so an unhandled Space is a space typed in the field.
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.space), isFalse);
      expect(
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space),
        isFalse,
      );
      expect(
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space),
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(media.muted, isTrue);
      expect(harness.controller.call?.muted, isTrue);
      expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.space), isFalse);
      await tester.pumpAndSettle();
      expect(media.muted, isTrue);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await holdSpaceInRoom();

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
        expect(find.byType(DToggle), findsAtLeastNWidgets(3));

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

    for (final automatic in [false, true]) {
      for (final activation in ['pointer', 'Enter', 'Space']) {
        testWidgets(
          'camera off cancels a pending ${automatic ? 'automatic' : 'manual'} capture with $activation',
          (tester) async {
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
            final preferences = _Preferences()..cameraEnabled = automatic;
            final harness = _Harness(joinRoom: room, preferences: preferences);
            addTearDown(harness.dispose);
            await _join(harness, room);
            final media = harness.media.sessions.single;
            final capture = Completer<void>();
            media.cameraGate = capture;
            addTearDown(() {
              if (!capture.isCompleted) capture.complete();
            });
            await tester.pumpWidget(
              MaterialApp(
                home: VoiceRoomView(
                  roomId: room.id,
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
            if (!automatic) {
              await tester.tap(find.byTooltip('Camera on'));
            }
            await tester.pump();

            expect(harness.controller.cameraStarting, isTrue);
            expect(find.byTooltip('Camera off'), findsOneWidget);
            final toggle = find.descendant(
              of: find.byTooltip('Camera off'),
              matching: find.byType(DToggle),
            );
            expect(tester.widget<DToggle>(toggle).pressed, isTrue);
            if (activation == 'pointer') {
              await tester.tap(find.byTooltip('Camera off'));
            } else {
              final focus = tester.widget<FocusableActionDetector>(
                find.descendant(
                  of: toggle,
                  matching: find.byType(FocusableActionDetector),
                ),
              );
              focus.focusNode!.requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(
                activation == 'Enter'
                    ? LogicalKeyboardKey.enter
                    : LogicalKeyboardKey.space,
              );
            }
            await tester.pump();
            expect(preferences.cameraEnabled, isFalse);

            capture.complete();
            await tester.pumpAndSettle();
            expect(find.byTooltip('Camera on'), findsOneWidget);
            expect(media.cameraChanges, [
              (enabled: false, deviceId: null),
              (enabled: false, deviceId: null),
            ]);
            expect(harness.controller.call?.cameraEnabled, isFalse);
            expect(harness.controller.cameraStarting, isFalse);
            await harness.controller.leave();
            await tester.pump();
          },
        );
      }
    }

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

    testWidgets(
      'stops drawing released media while the leave request is pending',
      (tester) async {
        final room = _room(
          participants: const [
            VoiceParticipant(
              id: 1,
              username: 'sam',
              role: VoiceRole.participant,
            ),
            VoiceParticipant(
              id: 2,
              username: 'lee',
              role: VoiceRole.participant,
            ),
          ],
        );
        final leaveGate = Completer<Map<String, dynamic>>();
        final tracker = RecordingPluginLiveChannels();
        final harness = _Harness(
          tracker: tracker,
          discourseApi: RecordingPluginTransport(
            responses: {
              'POST /voice/rooms/7/join.json': _joinPayload(room),
              'POST /voice/rooms/7/state.json': const {},
            },
            responders: {
              'DELETE /voice/rooms/7/leave.json': (_) => leaveGate.future,
            },
          ),
        );
        addTearDown(harness.dispose);
        await tester.pumpWidget(
          _app(harness.controller, room: room, followCall: true),
        );
        await tester.tap(find.text('Join room'));
        await tester.pumpAndSettle();
        final media = harness.media.sessions.single;
        media.setVideoTrack(2, Object());
        await tester.pump();
        expect(find.byType(VoiceVideoSurface), findsOneWidget);

        final leaving = harness.controller.leave();
        await tester.pump();

        expect(harness.controller.call?.status, VoiceCallStatus.leaving);
        expect(media.disposeCount, 1);
        expect(find.byType(VoiceVideoSurface), findsNothing);

        tracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': [
            {'id': 2, 'username': 'lee', 'role': 'participant'},
            {'id': 3, 'username': 'kim', 'role': 'participant'},
          ],
        }, messageId: 100);
        await tester.pump();

        expect(
          find.byKey(const ValueKey(('voice-participant', 3))),
          findsOneWidget,
        );

        leaveGate.complete({});
        await leaving;
        await tester.pumpAndSettle();
        expect(harness.controller.call, isNull);
        expect(find.text('Join room'), findsOneWidget);
      },
    );

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
    for (final change in ['room', 'site', 'same-room']) {
      for (final delayedRead in [false, true]) {
        testWidgets('volume dialog keeps its call target '
            '(change: $change, delayed read: $delayedRead)', (tester) async {
          final preferences = _Preferences(participantVolume: 0.4);
          final room = _room(
            participants: const [
              VoiceParticipant(
                id: 1,
                username: 'sam',
                role: VoiceRole.participant,
              ),
              VoiceParticipant(
                id: 2,
                username: 'lee',
                role: VoiceRole.participant,
              ),
            ],
          );
          const otherSite = 'https://another-voice.example.com';
          final targetSite = change == 'site' ? otherSite : _siteUrl;
          final replacement = _room(
            id: change == 'room' ? 8 : 7,
            participants: room.participants,
          );
          final harness = _Harness(
            joinRoom: room,
            preferences: preferences,
            requests: PluginTestRequestHost(
              apiKeys: const {_siteUrl: 'key', otherSite: 'other-key'},
            ),
          );
          addTearDown(harness.dispose);
          await _join(harness, room);
          harness.transport.responses['GET /voice/rooms.json'] = {
            'rooms': [_joinPayload(room)['room']],
          };
          await harness.controller.ensureLoaded(_siteUrl);
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
          await tester.pumpAndSettle();
          final gate = delayedRead ? Completer<void>() : null;
          preferences.participantVolumeReadGate = gate;
          addTearDown(() {
            if (gate != null && !gate.isCompleted) gate.complete();
          });
          await tester.tap(find.byTooltip('Participant actions'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Local volume'));
          await tester.pumpAndSettle();
          expect(
            find.byType(DSlider),
            delayedRead ? findsNothing : findsOneWidget,
          );
          harness.transport.responses.addAll({
            'POST /voice/rooms/${replacement.id}/join.json': _joinPayload(
              replacement,
            ),
            'POST /voice/rooms/${replacement.id}/state.json': const {},
            'DELETE /voice/rooms/${replacement.id}/leave.json': const {},
          });
          await harness.controller.leave();
          await harness.controller.join(
            siteUrl: targetSite,
            siteName: 'Replacement call',
            room: replacement,
          );
          gate?.complete();
          await tester.pumpAndSettle();
          expect(harness.controller.call?.siteUrl, targetSite);
          expect(harness.controller.call?.room.id, replacement.id);
          if (delayedRead && change != 'same-room') {
            expect(find.byType(DSlider), findsNothing);
          } else {
            final rect = tester.getRect(find.byType(DSlider));
            await tester.tapAt(
              Offset(rect.left + 6 + (rect.width - 12) * 0.7, rect.center.dy),
            );
            await tester.pumpAndSettle();
          }
          final expected = change == 'same-room' ? 0.7 : 0.4;
          expect(
            harness.media.sessions.last.participantVolumes.last.volume,
            expected,
          );
          expect(
            preferences.participantVolumeWrites,
            change == 'same-room' ? hasLength(1) : isEmpty,
          );
          expect(tester.takeException(), isNull);
          harness.dispose();
        });
      }
    }

    testWidgets('applies participant volume locally and persists it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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

      expect(find.byType(DDialogContent), findsOneWidget);
      final slider = tester.widget<DSlider>(find.byType(DSlider));
      expect(slider.value, 0.4);
      final sliderRect = tester.getRect(find.byType(DSlider));
      await tester.tapAt(
        Offset(
          sliderRect.left + 6 + (sliderRect.width - 12) * 0.7,
          sliderRect.center.dy,
        ),
      );
      await tester.pumpAndSettle();

      expect(harness.media.sessions.single.participantVolumes, [
        (participantId: 2, volume: 0.4),
        (participantId: 2, volume: 0.7),
      ]);
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

    for (final rollback in [false, true]) {
      testWidgets('volume dialog rejects retired account after public '
          '${rollback ? 'rollback' : 'reconnect'}', (tester) async {
        final room = _room(
          participants: const [
            VoiceParticipant(
              id: 1,
              username: 'sam',
              role: VoiceRole.participant,
            ),
            VoiceParticipant(
              id: 2,
              username: 'lee',
              role: VoiceRole.participant,
            ),
          ],
        );
        final preferences = _Preferences(participantVolume: 0.4);
        final transport = RecordingPluginTransport(
          responses: {
            'GET /voice/rooms.json': {
              'rooms': [_joinPayload(room)['room']],
            },
            'POST /voice/rooms/7/join.json': _joinPayload(room),
            'POST /voice/rooms/7/state.json': const {},
            'DELETE /voice/rooms/7/leave.json': const {},
          },
        );
        final module = _EditorSessionModule(
          transport,
          preferences: preferences,
        );
        final plugins = PluginInstaller.install(PluginManifest([module]));
        addTearDown(plugins.close);
        const user = DiscourseUser(id: 1, username: 'sam');
        const replacement = DiscourseUser(
          id: 8,
          username: 'replacement',
          staff: true,
        );
        final auth = _EditorAuthenticator(rollback: rollback)
          ..keys[_siteUrl] = 'key';
        final api = FakeDiscourseApi(
          user: user,
          feeds: const {'/latest.json': []},
        )..accounts['replacement-key'] = replacement;
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance('voice.example.com').copyWith(user: user),
          ]),
          api: api,
          authenticator: auth,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          plugins: plugins,
        );
        var disposed = false;
        addTearDown(() {
          if (!disposed) shell.dispose();
        });
        await shell.load();
        final controller = module.harness.controller;
        await controller.ensureLoaded(_siteUrl);
        await controller.join(siteUrl: _siteUrl, siteName: 'Voice', room: room);
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              home: Scaffold(
                body: PluginUiScope.own(
                  voicePluginId,
                  const VoiceRoomView(roomId: 7),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Participant actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Local volume'));
        await tester.pumpAndSettle();
        final dialog = tester.element(
          find.byType(VoiceParticipantVolumeSlider),
        );
        await shell.connectCurrentInstance();
        await controller.ensureLoaded(_siteUrl, force: true);
        await controller.join(siteUrl: _siteUrl, siteName: 'Voice', room: room);
        await tester.pumpAndSettle();
        expect(auth.keys[_siteUrl], rollback ? 'key' : 'replacement-key');
        expect(shell.currentInstance?.user, rollback ? user : replacement);
        expect(
          tester.element(find.byType(VoiceParticipantVolumeSlider)),
          same(dialog),
        );
        final rect = tester.getRect(find.byType(DSlider));
        await tester.tapAt(
          Offset(rect.left + 6 + (rect.width - 12) * 0.7, rect.center.dy),
        );
        await tester.pumpAndSettle();
        expect(
          module.harness.media.sessions.last.participantVolumes.last.volume,
          0.4,
        );
        expect(preferences.participantVolumeWrites, isEmpty);
        expect(tester.takeException(), isNull);
        await controller.leave();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          disposed = true;
          shell.dispose();
          await shell.pluginTeardown;
        });
      });
    }

    testWidgets(
      'persists device and push-to-talk settings and verifies the microphone',
      (tester) async {
        const webRtcChannel = MethodChannel('FlutterWebRTC.Method');
        const eventChannel = EventChannel('FlutterWebRTC.Event');
        final messenger = tester.binding.defaultBinaryMessenger;
        final microphoneGate = Completer<void>();
        final microphoneStarted = Completer<void>();
        final nativeCalls = <String>[];
        Object? microphoneConstraints;
        rtc.WebRTC.initialized = false;
        messenger.setMockStreamHandler(
          eventChannel,
          const MockStreamHandler.inline(onListen: _ignoreEvents),
        );
        messenger.setMockMethodCallHandler(webRtcChannel, (call) async {
          nativeCalls.add(call.method);
          if (call.method == 'getUserMedia') {
            microphoneConstraints = call.arguments;
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

        final pickers = find.byType(DSelect<String>);
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
        expect(microphoneConstraints, {
          'constraints': {
            'audio': {
              'deviceId': 'microphone-2',
              'echoCancellation': true,
              'noiseSuppression': true,
            },
            'video': false,
          },
        });
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
    testWidgets('stays quiet while an empty conversation loads', (
      tester,
    ) async {
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

      expect(find.byType(DSheetContent), findsOneWidget);
      // Lists draw no loading indicator, and the empty state waits for the
      // conversation to load.
      expect(find.byType(DSpinner), findsNothing);
      expect(find.text('No messages yet.'), findsNothing);
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

      expect(find.byType(DSheetContent), findsOneWidget);
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

    testWidgets('shows a failed load instead of an empty conversation', (
      tester,
    ) async {
      final harness = _Harness(
        discourseApi: RecordingPluginTransport(
          failures: const {
            'GET /voice/rooms/7/chat_session.json': SocketException('offline'),
          },
        ),
      );
      addTearDown(harness.dispose);

      await _openRoomChat(tester, harness);

      expect(find.text("Couldn't load room chat."), findsOneWidget);
      expect(find.text('No messages yet.'), findsNothing);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('keeps the text of a failed send and shows why', (
      tester,
    ) async {
      final messages = _chatPage(id: 10, username: 'sam', name: 'Sam').messages;
      final conversations = FakeChatConversationCapability();
      final conversation = conversations.seed(
        siteUrl: _siteUrl,
        channelId: 42,
        threadId: 99,
        snapshot: ChatConversationSnapshot(messages: messages),
        snapshotAfterSend: ChatConversationSnapshot(
          messages: messages,
          error: 'Message not sent.',
        ),
      );
      final harness = _Harness(
        discourseApi: _roomChatTransport(),
        chatConversations: conversations,
      );
      addTearDown(harness.dispose);

      await _openRoomChat(tester, harness);
      final composer = find.widgetWithText(TextField, 'Message the room');
      final text = tester.widget<TextField>(composer).controller!;
      await tester.enterText(composer, 'hello room');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();

      expect(conversation.sentMessages, ['hello room']);
      expect(text.text, 'hello room');
      expect(find.text('Message not sent.'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('holds Send while a message is in flight', (tester) async {
      final conversations = FakeChatConversationCapability();
      final conversation = conversations.seed(
        siteUrl: _siteUrl,
        channelId: 42,
        threadId: 99,
        snapshot: ChatConversationSnapshot(
          messages: _chatPage(id: 10, username: 'sam', name: 'Sam').messages,
        ),
      );
      final gate = conversation.sendGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final harness = _Harness(
        discourseApi: _roomChatTransport(),
        chatConversations: conversations,
      );
      addTearDown(harness.dispose);

      await _openRoomChat(tester, harness);
      final composer = find.widgetWithText(TextField, 'Message the room');
      final text = tester.widget<TextField>(composer).controller!;
      await tester.enterText(composer, 'hi');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      await tester.enterText(composer, 'there');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byTooltip('Send message'),
          matching: find.byType(DSpinner),
        ),
        findsOneWidget,
      );
      expect(conversation.sentMessages, ['hi']);
      expect(text.text, 'there');

      gate.complete();
      await tester.pumpAndSettle();
      expect(conversation.sentMessages, ['hi']);
      expect(text.text, 'there');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(conversation.sentMessages, ['hi', 'there']);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('holds Send while the conversation reports a send', (
      tester,
    ) async {
      final messages = _chatPage(id: 10, username: 'sam', name: 'Sam').messages;
      final conversations = FakeChatConversationCapability();
      final conversation = conversations.seed(
        siteUrl: _siteUrl,
        channelId: 42,
        threadId: 99,
        snapshot: ChatConversationSnapshot(messages: messages),
      );
      final harness = _Harness(
        discourseApi: _roomChatTransport(),
        chatConversations: conversations,
      );
      addTearDown(harness.dispose);

      await _openRoomChat(tester, harness);
      conversation.setSnapshot(
        ChatConversationSnapshot(messages: messages, sending: true),
      );
      await tester.pump();
      final composer = find.widgetWithText(TextField, 'Message the room');
      final text = tester.widget<TextField>(composer).controller!;
      await tester.enterText(composer, 'later');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();

      expect(conversation.sentMessages, isEmpty);
      expect(text.text, 'later');

      conversation.setSnapshot(ChatConversationSnapshot(messages: messages));
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(conversation.sentMessages, ['later']);
      expect(text.text, isEmpty);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('keeps the conversation visible while older messages load', (
      tester,
    ) async {
      final messages = _chatPage(
        id: 10,
        username: 'sam',
        name: 'Sam',
        canLoadMorePast: true,
      ).messages;
      final conversations = FakeChatConversationCapability();
      final conversation = conversations.seed(
        siteUrl: _siteUrl,
        channelId: 42,
        threadId: 99,
        snapshot: ChatConversationSnapshot(
          messages: messages,
          canLoadMorePast: true,
        ),
      );
      final harness = _Harness(
        discourseApi: _roomChatTransport(),
        chatConversations: conversations,
      );
      addTearDown(harness.dispose);

      await _openRoomChat(tester, harness);
      // A conversation reports an older page's load as loading.
      conversation.setSnapshot(
        ChatConversationSnapshot(
          messages: messages,
          loading: true,
          canLoadMorePast: true,
        ),
      );
      await tester.pump();

      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('Load older messages'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
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
            'memberships': _membershipRows,
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

      final membersDialog = find.byType(DDialogContent);
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

      final username = find.widgetWithText(DInput, 'Username');
      await tester.enterText(username, '   ');
      await tester.tap(find.byTooltip('Add member'));
      await tester.pumpAndSettle();
      expect(
        transport.writes.where(
          (write) => write.path.endsWith('/memberships.json'),
        ),
        isEmpty,
      );

      await tester.tap(find.byType(DSelect<VoiceRole>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(VoiceRole.moderator.name).last);
      await tester.pumpAndSettle();
      await tester.enterText(username, '  jordan  ');
      await tester.tap(find.byTooltip('Add member'));
      await tester.pumpAndSettle();

      final add = transport.writes.singleWhere(
        (write) => write.method == 'POST',
      );
      expect(add.body['username'], 'jordan');
      expect(add.body['role'], 'moderator');
      expect(tester.widget<DInput>(username).controller?.text, isEmpty);

      final leeTile = find.widgetWithText(DItem, 'Lee Example');
      await tester.tap(
        find.descendant(of: leeTile, matching: find.byTooltip('Change role')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DDropdownMenuItem, VoiceRole.participant.name).last,
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

    testWidgets('keeps the roster when the read after a change fails', (
      tester,
    ) async {
      var reads = 0;
      final transport = RecordingPluginTransport(
        responses: const {
          'PUT /voice/rooms/7/memberships/9.json': <String, Object?>{},
        },
        responders: {
          'GET /voice/rooms/7/memberships.json': (_) {
            if (++reads > 1) throw const SocketException('offline');
            return {'memberships': _membershipRows};
          },
        },
      );
      final harness = _Harness(discourseApi: transport);
      addTearDown(harness.dispose);
      await _openMembers(tester, harness);

      final leeTile = find.widgetWithText(DItem, 'Lee Example');
      await tester.tap(
        find.descendant(of: leeTile, matching: find.byTooltip('Change role')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DDropdownMenuItem, VoiceRole.participant.name).last,
      );
      await tester.pumpAndSettle();

      expect(transport.writes.single.method, 'PUT');
      expect(reads, 2);
      final membersDialog = find.byType(DDialogContent);
      for (final name in ['sam', 'Lee Example', 'User 3']) {
        expect(
          find.descendant(of: membersDialog, matching: find.text(name)),
          findsOneWidget,
        );
      }
      expect(find.text("Couldn't refresh the room's members."), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });

    testWidgets('keeps a refused name, says why, and sends it once', (
      tester,
    ) async {
      final addGate = Completer<void>();
      final transport = RecordingPluginTransport(
        responses: const {
          'GET /voice/rooms/7/memberships.json': {
            'memberships': _membershipRows,
          },
        },
        responders: {
          'POST /voice/rooms/7/memberships.json': (_) async {
            await addGate.future;
            throw const WriteException(
              WriteFailure.validation,
              errors: ['There is no user named lee.'],
              statusCode: 422,
            );
          },
        },
      );
      final harness = _Harness(discourseApi: transport);
      addTearDown(harness.dispose);
      addTearDown(() {
        if (!addGate.isCompleted) addGate.complete();
      });
      await _openMembers(tester, harness);

      final username = find.widgetWithText(DInput, 'Username');
      await tester.enterText(username, 'lee');
      await tester.tap(find.byTooltip('Add member'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add member'));
      await tester.pump();
      addGate.complete();
      await tester.pumpAndSettle();

      expect(tester.widget<DInput>(username).controller?.text, 'lee');
      expect(find.text('There is no user named lee.'), findsOneWidget);
      expect(transport.writes, hasLength(1));
      expect(
        transport.reads.where(
          (read) => read.path == '/voice/rooms/7/memberships.json',
        ),
        hasLength(1),
      );
      expect(
        find.descendant(
          of: find.byType(DDialogContent),
          matching: find.text('Lee Example'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });

    testWidgets('says why instead of opening on a roster it could not read', (
      tester,
    ) async {
      final harness = _Harness(
        discourseApi: RecordingPluginTransport(
          failures: const {
            'GET /voice/rooms/7/memberships.json': SocketException('offline'),
          },
        ),
      );
      addTearDown(harness.dispose);
      await _openMembers(tester, harness);

      expect(find.text("Couldn't load the room's members."), findsOneWidget);
      expect(find.text('Members of Lounge'), findsNothing);
    });
  });

  group('editor and dialog lifecycle', () {
    for (final change in ['name', 'video']) {
      testWidgets(
        'room editor preserves untouched Markdown when changing $change',
        (tester) async {
          const description = '    code\n\nParagraph hard break  \nnext line\n';
          final wireRoom =
              _joinPayload(
                    _room(
                      canManage: true,
                      participants: const [
                        VoiceParticipant(
                          id: 1,
                          username: 'sam',
                          role: VoiceRole.moderator,
                        ),
                      ],
                    ),
                  )['room']
                  as Map<String, dynamic>;
          wireRoom['description'] = description;
          final transport = RecordingPluginTransport(
            responses: {
              'GET /voice/rooms.json': {
                'rooms': [wireRoom],
              },
              'POST /voice/rooms/7/join.json': {
                'room': wireRoom,
                'transport': 'mesh',
                'ice': {'servers': <Object?>[]},
              },
              'POST /voice/rooms/7/state.json': const {},
              'DELETE /voice/rooms/7/leave.json': const {},
              'PUT /voice/rooms/7.json': {'room': wireRoom},
            },
          );
          final harness = _Harness(discourseApi: transport);
          addTearDown(harness.dispose);
          await harness.controller.ensureLoaded(_siteUrl);
          final decoded = harness.controller.room(_siteUrl, 7)!;
          await _join(harness, decoded);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: VoiceRoomView(
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
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Edit room'));
          await tester.pumpAndSettle();
          if (change == 'name') {
            await tester.enterText(
              find.widgetWithText(DInput, 'Name'),
              'New room name',
            );
          } else {
            await tester.ensureVisible(find.text('Allow video'));
            await tester.tap(find.text('Allow video'));
          }
          await tester.tap(find.widgetWithText(DButton, 'Save changes'));
          await tester.pumpAndSettle();
          final write = transport.writes.singleWhere(
            (write) => write.method == 'PUT',
          );
          expect(write.apiKey, 'key');
          expect(write.path, '/voice/rooms/7.json');
          expect((write.body['room'] as Map)['description'], description);
          expect(
            (write.body['room'] as Map)['name'],
            change == 'name' ? 'New room name' : 'Lounge',
          );
          if (change == 'video') {
            expect((write.body['room'] as Map)['video_enabled'], isTrue);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          harness.dispose();
        },
      );
    }
    for (final rollback in [false, true]) {
      for (final framed in [false, true]) {
        testWidgets(
          'room editor rejects ${rollback ? 'rollback' : 'replacement'} draft (framed: $framed)',
          (tester) async {
            final room = _room(
              canManage: true,
              participants: const [
                VoiceParticipant(
                  id: 1,
                  username: 'sam',
                  role: VoiceRole.moderator,
                ),
              ],
            );
            final transport = RecordingPluginTransport(
              responses: {
                'GET /voice/rooms.json': {
                  'rooms': [_joinPayload(room)['room']],
                  'can_create_room': true,
                },
                'POST /voice/rooms/7/join.json': _joinPayload(room),
                'POST /voice/rooms/7/state.json': const {},
                'DELETE /voice/rooms/7/leave.json': const {},
                'PUT /voice/rooms/7.json': {'room': _joinPayload(room)['room']},
              },
            );
            final module = _EditorSessionModule(transport);
            final plugins = PluginInstaller.install(PluginManifest([module]));
            addTearDown(plugins.close);
            const user = DiscourseUser(id: 1, username: 'sam');
            const replacement = DiscourseUser(
              id: 8,
              username: 'replacement',
              staff: true,
            );
            final auth = _EditorAuthenticator(rollback: rollback)
              ..keys[_siteUrl] = 'key';
            final api = FakeDiscourseApi(
              user: user,
              feeds: const {'/latest.json': []},
            )..accounts['replacement-key'] = replacement;
            final shell = ShellController(
              instanceStore: FakeInstanceStore([
                instance('voice.example.com').copyWith(user: user),
              ]),
              api: api,
              authenticator: auth,
              drafts: FakeDraftStore(),
              trackers: FakeSiteTracker.reset(),
              plugins: plugins,
            );
            var disposed = false;
            addTearDown(() {
              if (!disposed) shell.dispose();
            });
            await shell.load();
            final controller = module.harness.controller;
            await controller.ensureLoaded(_siteUrl);
            await controller.join(
              siteUrl: _siteUrl,
              siteName: 'Voice',
              room: room,
            );
            await tester.pumpWidget(
              ShellScope(
                controller: shell,
                child: MaterialApp(
                  home: Scaffold(
                    body: PluginUiScope.own(
                      voicePluginId,
                      const VoiceRoomView(roomId: 7),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final trigger = tester.element(find.byTooltip('Edit room'));
            await tester.tap(find.byTooltip('Edit room'));
            await tester.pumpAndSettle();
            final field = find.widgetWithText(DInput, 'Name');
            final editor = tester.element(field);
            await tester.enterText(field, 'Previous account private name');
            await tester.pump();

            await shell.connectCurrentInstance();
            await controller.ensureLoaded(_siteUrl, force: true);
            expect(auth.keys[_siteUrl], rollback ? 'key' : 'replacement-key');
            expect(shell.currentInstance?.user, rollback ? user : replacement);
            expect(controller.room(_siteUrl, 7)?.canManage, isTrue);
            if (framed) await tester.pumpAndSettle();
            expect(trigger.mounted, !framed);
            expect(tester.element(field), same(editor));
            await tester.tap(find.widgetWithText(DButton, 'Save changes'));
            await tester.pumpAndSettle();
            expect(
              transport.writes.where(
                (write) =>
                    write.method == 'PUT' &&
                    write.path == '/voice/rooms/7.json',
              ),
              isEmpty,
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(() async {
              disposed = true;
              shell.dispose();
              await shell.pluginTeardown;
            });
          },
        );
      }
    }

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
        expect(find.text('Required'), findsNothing);
        expect(
          tester.getSemantics(nameField),
          isSemantics(
            label: 'Name',
            value: 'Lounge',
            isTextField: true,
            isRequired: true,
          ),
        );

        final description = find.byType(DTextarea);
        final descriptionEditable = find.descendant(
          of: description,
          matching: find.byType(EditableText),
        );
        expect(
          tester.getSemantics(descriptionEditable).label,
          'Description\nWhat will people talk about? (optional)',
        );
        await tester.tap(find.text('Description'));
        await tester.pump();
        expect(
          tester.widget<EditableText>(descriptionEditable).focusNode.hasFocus,
          isTrue,
        );
        expect(
          tester
              .getSemantics(descriptionEditable)
              .getSemanticsData()
              .hasAction(SemanticsAction.setText),
          isTrue,
        );

        final save = find.widgetWithText(DButton, 'Save changes');
        expect(tester.widget<DButton>(save).onPressed, isNotNull);

        await tester.enterText(nameField, '   ');
        await tester.pump();
        expect(tester.widget<DButton>(save).onPressed, isNull);

        await tester.showKeyboard(nameField);
        tester.testTextInput.enterText('Renamed lounge');
        await tester.pump();
        expect(tester.widget<DButton>(save).onPressed, isNotNull);

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
      await tester.tap(find.widgetWithText(DButton, 'Save changes'));
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

    Future<void> openEditor(
      WidgetTester tester,
      _Harness harness, {
      VoiceRoom? room,
      double scale = 1,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Center(
              child: DButton(
                label: const Text('Open editor'),
                onPressed: () => unawaited(
                  showVoiceRoomEditor(
                    context,
                    siteUrl: _siteUrl,
                    room: room,
                    controller: harness.controller,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
    }

    Finder input(String label) => find.descendant(
      of: find.widgetWithText(DInput, label),
      matching: find.byType(TextField),
    );

    Future<void> enter(WidgetTester tester, String label, String value) async {
      final field = input(label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pumpAndSettle();
    }

    for (final description in [
      '    code\n\nA hard break  \nnext line\n',
      '  \n',
    ]) {
      testWidgets(
        'new room description keeps its raw ${description.trim().isEmpty ? 'blank' : 'Markdown'} source',
        (tester) async {
          final harness = _Harness();
          addTearDown(harness.dispose);
          await openEditor(tester, harness);
          await enter(tester, 'Name', '  Community lounge  ');
          await tester.enterText(find.byType(DTextarea), description);
          await tester.tap(find.widgetWithText(DButton, 'Create room'));
          await tester.pumpAndSettle();
          final write = harness.transport.writes.single;
          expect(write.method, 'POST');
          expect(write.path, '/voice/rooms.json');
          expect((write.body['room'] as Map)['description'], description);
          expect((write.body['room'] as Map)['name'], 'Community lounge');
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('creates a room with defaults and no advanced setup', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await openEditor(tester, harness);
      final create = find.widgetWithText(DButton, 'Create room');
      expect(tester.widget<DButton>(create).onPressed, isNull);
      expect(find.text('Chat channel ID (optional)'), findsNothing);
      expect(find.text('Enter a room name.'), findsNothing);
      await enter(tester, 'Name', '  Community lounge  ');
      await tester.tap(create);
      await tester.pumpAndSettle();
      final write = harness.transport.writes.single;
      expect(write.method, 'POST');
      expect(write.path, '/voice/rooms.json');
      expect(write.body['room'], {
        'name': 'Community lounge',
        'description': '',
        'public': true,
        'room_type': 'open',
        'video_enabled': true,
        'max_participants': null,
        'chat_channel_id': null,
        'chat_idle_minutes': 15,
        'livekit_enabled': null,
        'max_quality_profile': 'maximum',
      });
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'validates numbers and reveals errors in collapsed advanced settings',
      (tester) async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await openEditor(tester, harness);
        await enter(tester, 'Name', 'Community lounge');
        await enter(tester, 'Maximum participants', '2.5');
        await tester.tap(find.text('Create room'));
        await tester.pumpAndSettle();
        expect(harness.transport.writes, isEmpty);
        expect(find.text('Enter a whole number from 2 to 50.'), findsOneWidget);
        await enter(tester, 'Maximum participants', '60');
        expect(find.text('Enter a whole number from 2 to 50.'), findsOneWidget);
        await tester.ensureVisible(find.text('Stage room'));
        await tester.tap(find.text('Stage room'));
        await tester.pumpAndSettle();
        expect(find.text('Enter a whole number from 2 to 50.'), findsNothing);

        await tester.ensureVisible(find.text('Advanced settings'));
        await tester.tap(find.text('Advanced settings'));
        await tester.pumpAndSettle();
        await enter(tester, 'Chat channel ID (optional)', 'abc');
        await enter(tester, 'New chat thread after (minutes)', '1');
        await tester.ensureVisible(find.text('Advanced settings'));
        await tester.tap(find.text('Advanced settings'));
        await tester.pumpAndSettle();
        expect(find.text('Chat channel ID (optional)'), findsNothing);
        await tester.tap(find.text('Create room'));
        await tester.pumpAndSettle();
        expect(harness.transport.writes, isEmpty);
        expect(find.text('Enter a whole number of 1 or more.'), findsOneWidget);
        expect(
          find.text('Enter a whole number from 2 to 1440.'),
          findsOneWidget,
        );
        await enter(tester, 'Chat channel ID (optional)', ' 42 ');
        await enter(tester, 'New chat thread after (minutes)', ' 30 ');
        await tester.ensureVisible(find.text('Advanced settings'));
        await tester.tap(find.text('Advanced settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create room'));
        await tester.pumpAndSettle();
        final body =
            harness.transport.writes.single.body['room']!
                as Map<String, Object?>;
        expect(body['max_participants'], 60);
        expect(body['room_type'], 'stage');
        expect(body['chat_channel_id'], 42);
        expect(body['chat_idle_minutes'], 30);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'keeps existing advanced values when saving at narrow width and large text',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final harness = _Harness();
        addTearDown(harness.dispose);
        const room = VoiceRoom(
          id: 7,
          name: 'Lounge',
          slug: 'lounge',
          isPublic: false,
          ephemeral: false,
          type: VoiceRoomType.stage,
          participants: [],
          maxParticipants: 100,
          videoEnabled: false,
          livekitEnabled: true,
          chatChannelId: 42,
          chatIdleMinutes: 30,
          maxQualityProfile: VoiceQualityProfile.high,
        );
        await openEditor(tester, harness, room: room, scale: 2);
        await enter(tester, 'Name', 'Renamed lounge');
        await tester.ensureVisible(find.text('Advanced settings'));
        await tester.tap(find.text('Advanced settings'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Use LiveKit'));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Advanced settings'));
        await tester.tap(find.text('Advanced settings'));
        await tester.pumpAndSettle();
        final save = find.widgetWithText(DButton, 'Save changes');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(harness.transport.writes.single.body['room'], {
          'name': 'Renamed lounge',
          'description': '',
          'public': false,
          'room_type': 'stage',
          'video_enabled': false,
          'max_participants': 100,
          'chat_channel_id': 42,
          'chat_idle_minutes': 30,
          'livekit_enabled': true,
          'max_quality_profile': 'high',
        });
        expect(tester.takeException(), isNull);
      },
    );

    for (final recording in [false, true]) {
      for (final (change, framed) in [
        ('room', false),
        ('site', false),
        ('account', false),
        if (!recording) ...[('room', true), ('site', true)],
      ]) {
        final otherSite = change == 'site';
        final retiredSession = change == 'account';
        testWidgets('confirmation stays with its rendered call '
            '(recording: $recording, change: $change, framed: $framed)', (
          tester,
        ) async {
          final room = _room(
            canManage: true,
            creatorId: 1,
            participants: const [
              VoiceParticipant(
                id: 1,
                username: 'sam',
                role: VoiceRole.moderator,
              ),
              VoiceParticipant(
                id: 2,
                username: 'lee',
                role: VoiceRole.participant,
              ),
            ],
          );
          final replacementRoom = _room(
            id: otherSite || retiredSession ? 7 : 8,
            canManage: true,
            participants: room.participants,
          );
          const replacementSite = 'https://another-voice.example.com';
          final requests = PluginTestRequestHost(
            apiKeys: const {_siteUrl: 'key', replacementSite: 'other-key'},
          );
          final transport = recording
              ? VoiceTransport.livekit
              : VoiceTransport.mesh;
          final harness = _Harness(
            joinRoom: room,
            joinTransport: transport,
            requests: requests,
          );
          addTearDown(harness.dispose);
          await _join(harness, room);
          if (framed) {
            harness.transport.responses['GET /voice/rooms.json'] = {
              'rooms': [_joinPayload(room)['room']],
            };
            await harness.controller.ensureLoaded(_siteUrl);
          }
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => DToaster(child: child!),
              home: VoiceRoomView(
                roomId: 7,
                controller: harness.controller,
                shell: _voiceShell(
                  harness.controller,
                  recordingEnabled: true,
                  site: const PluginRouteSite(
                    url: _siteUrl,
                    title: 'Voice',
                    isConnected: true,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (recording) {
            await tester.tap(find.byTooltip('Start recording'));
          } else {
            await tester.tap(find.byTooltip('Participant actions'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Notify moderators'));
          }
          await tester.pumpAndSettle();
          if (!recording) {
            await tester.enterText(find.byType(TextField), 'Review this call');
          }

          final id = replacementRoom.id;
          harness.transport.responses.addAll({
            'POST /voice/rooms/$id/join.json': _joinPayload(
              replacementRoom,
              transport: transport,
            ),
            'POST /voice/rooms/$id/state.json': const {},
            'DELETE /voice/rooms/$id/leave.json': const {},
            'POST /voice/rooms/$id/flag.json': const {},
            'POST /voice/rooms/$id/recording.json': const {},
          });
          if (retiredSession) {
            harness.controller.forget(_siteUrl);
            requests.forget(_siteUrl);
            requests.apiKeys[_siteUrl] = 'replacement-key';
          }
          await harness.controller.join(
            siteUrl: otherSite ? replacementSite : _siteUrl,
            siteName: 'Another voice call',
            room: replacementRoom,
          );
          expect(
            harness.controller.call?.siteUrl,
            otherSite ? replacementSite : _siteUrl,
          );
          expect(harness.controller.call?.room.id, id);
          if (framed) {
            await tester.pump();
            expect(harness.controller.room(_siteUrl, 7), isNotNull);
            expect(find.byType(VoiceRoomContent), findsOneWidget);
          }
          // Both the pre-frame controls and a retained roster can outlive the
          // call while this production dialog remains open.
          await tester.tap(
            find.widgetWithText(FilledButton, recording ? 'Start' : 'Notify'),
          );
          await tester.pumpAndSettle();
          final path = recording ? '/recording.json' : '/flag.json';
          expect(
            harness.transport.writes.where(
              (write) => write.path.endsWith(path),
            ),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
          harness.dispose();
        });
      }
    }

    testWidgets('Native flag dialog fits a narrow view and cancels', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
      await tester.tap(find.text('Notify moderators'));
      await tester.pumpAndSettle();
      final dialog = find.byType(DDialogContent);
      expect(dialog, findsOneWidget);
      expect(tester.getRect(dialog).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(dialog).right, lessThanOrEqualTo(390));
      await tester.enterText(find.byType(TextField), 'Please review this');
      final cancel = find.descendant(
        of: dialog,
        matching: find.widgetWithText(DButton, 'Cancel'),
      );
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(
        harness.transport.writes.where(
          (write) => write.path.endsWith('/flag.json'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      harness.dispose();
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

    testWidgets('agent stage menus retain kicking without human role actions', (
      tester,
    ) async {
      final room = _room(
        type: VoiceRoomType.stage,
        canManage: true,
        creatorId: 1,
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
          VoiceParticipant(
            id: -1400,
            username: 'bot',
            role: VoiceRole.speaker,
            externalAgent: true,
            livekitIdentity: 'agent-dashboard',
          ),
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
      expect(find.text('Remove from room'), findsOneWidget);
      await tester.tap(find.text('Remove from room'));
      await tester.pumpAndSettle();
      final kicks = harness.transport.writes.where(
        (write) => write.path.endsWith('/kick.json'),
      );
      expect(kicks.map((write) => write.method), ['DELETE']);
      expect(kicks.single.body['user_id'], -1400);
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

void _directCallTests() {
  group('direct calls', () {
    const sam = VoiceParticipant(
      id: 1,
      username: 'sam',
      role: VoiceRole.participant,
    );

    VoiceRoom callRoom({
      int id = 9,
      List<VoiceRingingEntry> ringing = const [],
    }) => VoiceRoom(
      id: id,
      name: '📞 kim + sam',
      slug: 'call-1a2b',
      isPublic: false,
      ephemeral: true,
      type: VoiceRoomType.open,
      participants: const [
        VoiceParticipant(id: 3, username: 'kim', role: VoiceRole.moderator),
      ],
      ringing: ringing,
    );

    void testRinging(
      String description,
      Future<void> Function(WidgetTester tester, _Harness harness) run,
    ) {
      testWidgets(description, (tester) async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        try {
          await run(tester, harness);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }

    Future<void> showRoom(
      WidgetTester tester,
      _Harness harness,
      VoiceRoom room,
    ) => tester.pumpWidget(
      _app(
        harness.controller,
        room: room,
        ringingClock: tester.binding.clock.now,
      ),
    );

    testRinging('stops rebuilding the room grid after rings expire', (
      tester,
      harness,
    ) async {
      final now = tester.binding.clock.now();
      final room = callRoom(
        ringing: [
          VoiceRingingEntry(user: sam, notifiedAt: now),
          VoiceRingingEntry(
            user: const VoiceParticipant(
              id: 4,
              username: 'old',
              role: VoiceRole.participant,
            ),
            notifiedAt: now.subtract(const Duration(minutes: 2)),
          ),
        ],
      );

      await showRoom(tester, harness, room);

      expect(find.text('Calling sam…'), findsOneWidget);
      expect(find.text('Calling old…'), findsNothing);
      expect(find.text('kim'), findsOneWidget);
      final gridBuilds = _observeRoomGridBuilds();

      await tester.pump(const Duration(seconds: 59));
      expect(find.text('Calling sam…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Calling sam…'), findsNothing);
      expect(find.text('kim'), findsOneWidget);
      expect(gridBuilds, isNotEmpty);

      gridBuilds.clear();
      await tester.pump(const Duration(seconds: 10));
      expect(gridBuilds, isEmpty);
    });

    testRinging('filters stale ring data immediately after an idle period', (
      tester,
      harness,
    ) async {
      final startedAt = tester.binding.clock.now();
      await showRoom(tester, harness, callRoom());
      await tester.pump(const Duration(minutes: 2));

      await showRoom(
        tester,
        harness,
        callRoom(
          ringing: [
            VoiceRingingEntry(
              user: sam,
              notifiedAt: startedAt.add(const Duration(seconds: 1)),
            ),
          ],
        ),
      );

      expect(find.text('Calling sam…'), findsNothing);
      expect(find.text('kim'), findsOneWidget);
      final gridBuilds = _observeRoomGridBuilds();
      await tester.pump(const Duration(seconds: 10));
      expect(gridBuilds, isEmpty);
    });

    testRinging('expires staggered rings at their own deadlines', (
      tester,
      harness,
    ) async {
      final now = tester.binding.clock.now();
      await showRoom(
        tester,
        harness,
        callRoom(
          ringing: [
            VoiceRingingEntry(
              user: sam,
              notifiedAt: now.subtract(const Duration(seconds: 59)),
            ),
            VoiceRingingEntry(
              user: const VoiceParticipant(
                id: 2,
                username: 'lee',
                role: VoiceRole.participant,
              ),
              notifiedAt: now.subtract(const Duration(seconds: 57)),
            ),
          ],
        ),
      );
      final gridBuilds = _observeRoomGridBuilds();

      await tester.pump(const Duration(milliseconds: 999));
      expect(find.text('Calling sam…'), findsOneWidget);
      expect(find.text('Calling lee…'), findsOneWidget);
      expect(gridBuilds, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Calling sam…'), findsNothing);
      expect(find.text('Calling lee…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Calling lee…'), findsNothing);
      expect(find.text('kim'), findsOneWidget);

      gridBuilds.clear();
      await tester.pump(const Duration(seconds: 10));
      expect(gridBuilds, isEmpty);
    });

    for (final (seconds, timing) in [(50, 'before'), (70, 'after')]) {
      testRinging('renews a ring received $timing the previous expiry', (
        tester,
        harness,
      ) async {
        final room = callRoom(
          ringing: [
            VoiceRingingEntry(
              user: sam,
              notifiedAt: tester.binding.clock.now(),
            ),
          ],
        );
        await showRoom(tester, harness, room);
        await tester.pump(Duration(seconds: seconds));
        expect(
          find.text('Calling sam…'),
          seconds < 60 ? findsOneWidget : findsNothing,
        );

        await showRoom(
          tester,
          harness,
          room.withRinging(
            VoiceRingingEntry(
              user: sam,
              notifiedAt: tester.binding.clock.now(),
            ),
          ),
        );
        expect(find.text('Calling sam…'), findsOneWidget);
        final gridBuilds = _observeRoomGridBuilds();
        await tester.pump(const Duration(seconds: 59));
        expect(find.text('Calling sam…'), findsOneWidget);
        expect(gridBuilds, isEmpty);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Calling sam…'), findsNothing);
      });
    }

    testRinging(
      'pauses rings for present participants and resumes on leaving',
      (tester, harness) async {
        final room = callRoom(
          ringing: [
            VoiceRingingEntry(
              user: sam,
              notifiedAt: tester.binding.clock.now(),
            ),
          ],
        );
        await showRoom(tester, harness, room);
        await tester.pump(const Duration(seconds: 10));
        await showRoom(
          tester,
          harness,
          room.copyWith(participants: [...room.participants, sam]),
        );
        expect(find.text('Calling sam…'), findsNothing);
        expect(find.text('sam'), findsOneWidget);
        expect(find.text('kim'), findsOneWidget);
        final gridBuilds = _observeRoomGridBuilds();
        await tester.pump(const Duration(seconds: 5));
        expect(gridBuilds, isEmpty);

        await showRoom(tester, harness, room);
        expect(find.text('Calling sam…'), findsOneWidget);
        expect(find.text('sam'), findsNothing);
        await tester.pump(const Duration(seconds: 44));
        expect(find.text('Calling sam…'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Calling sam…'), findsNothing);
      },
    );

    testRinging('uses the replacement room deadline and retires the old one', (
      tester,
      harness,
    ) async {
      await showRoom(
        tester,
        harness,
        callRoom(
          ringing: [
            VoiceRingingEntry(
              user: sam,
              notifiedAt: tester.binding.clock.now(),
            ),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 10));
      await showRoom(
        tester,
        harness,
        callRoom(
          id: 10,
          ringing: [
            VoiceRingingEntry(
              user: sam,
              notifiedAt: tester.binding.clock.now().subtract(
                const Duration(seconds: 59),
              ),
            ),
          ],
        ),
      );
      expect(find.text('Calling sam…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Calling sam…'), findsNothing);

      final gridBuilds = _observeRoomGridBuilds();
      await tester.pump(const Duration(minutes: 1));
      expect(gridBuilds, isEmpty);
      expect(find.text('kim'), findsOneWidget);
    });

    testRinging('unmounts a ringing room without leaving a pending refresh', (
      tester,
      harness,
    ) async {
      await showRoom(
        tester,
        harness,
        callRoom(
          ringing: [
            VoiceRingingEntry(
              user: sam,
              notifiedAt: tester.binding.clock.now(),
            ),
          ],
        ),
      );
      expect(find.text('Calling sam…'), findsOneWidget);
      final gridBuilds = _observeRoomGridBuilds();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));

      expect(find.text('Calling sam…'), findsNothing);
      expect(gridBuilds, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an incoming call can be declined or answered', (tester) async {
      final tracker = RecordingPluginLiveChannels();
      final room = callRoom();
      final transport = RecordingPluginTransport(
        responses: {
          'GET /voice/rooms.json': const {
            'rooms': <Object?>[],
            'can_create_room': false,
          },
          'GET /voice/rooms/call-1a2b.json':
              _joinPayload(room)['room'] as Map<String, dynamic>,
          'POST /voice/rooms/9/join.json': _joinPayload(room),
          'POST /voice/rooms/9/state.json': const {},
          'DELETE /voice/rooms/9/leave.json': const {},
        },
      );
      final harness = _Harness(discourseApi: transport, tracker: tracker);
      addTearDown(harness.dispose);
      final host = _RouteHost(
        const PluginRouteSite(url: _siteUrl, title: 'Voice', isConnected: true),
      );
      final shell = VoiceShellService(
        controller: harness.controller,
        host: host,
        recordingEnabled: (_) => false,
      );
      await harness.controller.ensureLoaded(_siteUrl);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceIncomingCallBanner(
              controller: harness.controller,
              shell: shell,
            ),
          ),
        ),
      );
      Map<String, dynamic> ring(int sentAt) => {
        'room_id': 9,
        'room_slug': 'call-1a2b',
        'room_name': '📞 kim + sam',
        'caller_username': 'kim',
        'caller_name': 'Kim',
        'sent_at': sentAt,
        'ring_seconds': 60,
      };
      final sentAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      tracker.deliver('/voice/call-ring/1', ring(sentAt));
      await tester.pump();
      expect(find.text('Kim'), findsOneWidget);
      expect(find.text('is calling you…'), findsOneWidget);

      await tester.tap(find.text('Decline'));
      await tester.pump();
      expect(find.text('is calling you…'), findsNothing);
      expect(harness.controller.incomingCall, isNull);

      tracker.deliver('/voice/call-ring/1', ring(sentAt + 1));
      await tester.pump();
      await tester.tap(find.text('Answer'));
      await tester.pumpAndSettle();

      expect(host.currentContent?.id, 'voice-room-9');
      expect(harness.controller.call?.room.id, 9);
      final join = transport.writes.singleWhere(
        (write) => write.path.endsWith('/join.json'),
      );
      expect(join.body['invited_by'], 'kim');
      expect(find.text('is calling you…'), findsNothing);
      harness.dispose();
    });

    testWidgets('the banner stays out of the way while the system rings', (
      tester,
    ) async {
      final tracker = RecordingPluginLiveChannels();
      final transport = RecordingPluginTransport(
        responses: {
          'GET /voice/rooms.json': const {
            'rooms': <Object?>[],
            'can_create_room': false,
          },
        },
      );
      final harness = _Harness(
        discourseApi: transport,
        tracker: tracker,
        systemCall: _SystemCall(presentsIncomingCalls: true),
      );
      addTearDown(harness.dispose);
      final shell = VoiceShellService(
        controller: harness.controller,
        host: _RouteHost(
          const PluginRouteSite(
            url: _siteUrl,
            title: 'Voice',
            isConnected: true,
          ),
        ),
        recordingEnabled: (_) => false,
      );
      await harness.controller.ensureLoaded(_siteUrl);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceIncomingCallBanner(
              controller: harness.controller,
              shell: shell,
            ),
          ),
        ),
      );

      tracker.deliver('/voice/call-ring/1', {
        'room_id': 9,
        'room_slug': 'call-1a2b',
        'room_name': '📞 kim + sam',
        'caller_username': 'kim',
        'caller_name': 'Kim',
        'sent_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'ring_seconds': 60,
      });
      await tester.pump();
      await tester.pump();

      expect(harness.controller.incomingCallHandledBySystem, isTrue);
      expect(find.text('is calling you…'), findsNothing);
      harness.controller.declineIncomingCall();
      await tester.pump();
    });

    for (final boundary in ['privacy read', 'privacy dialog', 'navigation']) {
      testWidgets('answer stops after account removal during $boundary', (
        tester,
      ) async {
        final tracker = RecordingPluginLiveChannels();
        final room = callRoom();
        final transport = RecordingPluginTransport(
          responses: {
            'GET /voice/rooms.json': const {'rooms': <Object?>[]},
            'GET /voice/rooms/call-1a2b.json': {
              ..._joinPayload(room)['room'] as Map<String, dynamic>,
              'expected_transport': 'mesh',
            },
            'POST /voice/rooms/9/join.json': _joinPayload(room),
            'POST /voice/rooms/9/state.json': const {},
            'DELETE /voice/rooms/9/leave.json': const {},
          },
        );
        final preferences = _Preferences();
        final gate = Completer<void>();
        if (boundary == 'privacy read') preferences.meshPrivacyReadGate = gate;
        final harness = _Harness(
          discourseApi: transport,
          tracker: tracker,
          preferences: preferences,
        );
        addTearDown(harness.dispose);
        final host = _RouteHost(
          const PluginRouteSite(
            url: _siteUrl,
            title: 'Voice',
            isConnected: true,
          ),
        );
        final shell = VoiceShellService(
          controller: harness.controller,
          host: host,
          recordingEnabled: (_) => false,
        );
        late BuildContext answerContext;
        await harness.controller.ensureLoaded(_siteUrl);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                answerContext = context;
                return const Scaffold();
              },
            ),
          ),
        );
        tracker.deliver('/voice/call-ring/1', {
          'room_id': 9,
          'room_slug': 'call-1a2b',
          'room_name': '📞 kim + sam',
          'caller_username': 'kim',
          'sent_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'ring_seconds': 60,
        });
        if (boundary == 'navigation') {
          host.onPushContent = () => harness.controller.forget(_siteUrl);
        }
        final answering = shell.answerIncomingCall(answerContext);
        await tester.pumpAndSettle();

        expect(preferences.meshPrivacyReads, boundary == 'navigation' ? 0 : 1);
        if (boundary == 'privacy dialog') {
          expect(find.text('Before you join this room'), findsOneWidget);
          harness.controller.forget(_siteUrl);
          await tester.tap(find.text('Join room'));
        } else if (boundary == 'privacy read') {
          harness.controller.forget(_siteUrl);
          gate.complete();
        }
        await tester.pumpAndSettle();

        final staleWarning = tester.any(find.text('Before you join this room'));
        if (staleWarning) {
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        }
        await answering;
        expect(staleWarning, isFalse);
        expect(harness.controller.call, isNull);
        expect(transport.writes, isEmpty);
      });
    }
  });
}

void _inviteTests() {
  group('invites', () {
    testWidgets(
      'keeps Invite after shared edits and follows authenticated revocations',
      (tester) async {
        final room = _room(
          canInvite: true,
          canManage: true,
          participants: const [
            VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
          ],
        );
        final tracker = RecordingPluginLiveChannels();
        final harness = _Harness(joinRoom: room, tracker: tracker);
        addTearDown(harness.dispose);
        final granted = _joinPayload(room)['room'] as Map<String, dynamic>;
        harness.transport.responses['GET /voice/rooms.json'] = {
          'rooms': [granted],
        };
        await harness.controller.ensureLoaded(_siteUrl);
        await _join(harness, room);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VoiceRoomView(
                roomId: room.id,
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
          ),
        );
        expect(find.byTooltip('Invite people'), findsOneWidget);

        final shared = Map<String, dynamic>.from(granted);
        for (final key in [
          'can_manage',
          'can_invite',
          'membership',
          'chat_available',
          'chat_channel_id',
          'chat_idle_minutes',
          'livekit_enabled',
        ]) {
          shared.remove(key);
        }
        shared['name'] = 'Renamed Lounge';
        tracker.deliver('/voice/rooms/index', {
          'type': 'updated',
          'room': shared,
        });
        await tester.pumpAndSettle();
        expect(find.byTooltip('Invite people'), findsOneWidget);
        await tester.tap(find.byTooltip('Invite people'));
        await tester.pumpAndSettle();
        expect(find.text('Invite to Renamed Lounge'), findsOneWidget);
        await tester.tap(find.widgetWithText(DButton, 'Done'));
        await tester.pumpAndSettle();

        harness.transport.responses['GET /voice/rooms.json'] = {
          'rooms': [
            {...granted, 'can_invite': false},
          ],
        };
        await harness.controller.ensureLoaded(_siteUrl, force: true);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Invite people'), findsNothing);
        tracker.deliver('/voice/rooms/index', {
          'type': 'updated',
          'room': shared,
        });
        await tester.pumpAndSettle();
        expect(find.byTooltip('Invite people'), findsNothing);

        harness.transport.responses['GET /voice/rooms.json'] = {
          'rooms': [granted],
        };
        await harness.controller.ensureLoaded(_siteUrl, force: true);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Invite people'), findsOneWidget);
        harness.dispose();
      },
    );

    testWidgets('the shell builds the invite link that credits the inviter', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final room = _room(participants: const []);

      expect(
        _voiceShell(
          harness.controller,
          username: 'Sam',
        ).inviteLinkFor(_siteUrl, room),
        'https://voice.example.com/voice/r/lounge/invited-by/sam',
      );
      expect(
        _voiceShell(harness.controller).inviteLinkFor(_siteUrl, room),
        isNull,
      );
    });

    testWidgets('invites by name and from the shortlist, and shows the link', (
      tester,
    ) async {
      final room = _room(
        canInvite: true,
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
          inviteLink: 'https://voice.example.com/voice/r/lounge/invited-by/sam',
        ),
      );

      await tester.tap(find.byTooltip('Invite people'));
      await tester.pumpAndSettle();
      expect(find.text('Invite to Lounge'), findsOneWidget);
      expect(find.text('kim'), findsOneWidget);
      expect(find.text('2h together recently'), findsOneWidget);
      expect(
        find.text('https://voice.example.com/voice/r/lounge/invited-by/sam'),
        findsOneWidget,
      );

      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      expect(find.text('Invited'), findsOneWidget);
      expect(find.text('Invite sent.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '@lee');
      await tester.tap(find.text('Send invite'));
      await tester.pumpAndSettle();

      final invites = harness.transport.writes
          .where((write) => write.path.endsWith('/invites.json'))
          .map((write) => write.body['usernames'])
          .toList();
      expect(invites, [
        ['kim'],
        ['lee'],
      ]);
      harness.dispose();
    });

    testWidgets('Enter during an invite in flight neither resends nor clears', (
      tester,
    ) async {
      final harness = await _openInvites(tester);
      final inviteGate = Completer<void>();
      addTearDown(() {
        if (!inviteGate.isCompleted) inviteGate.complete();
      });
      harness.transport.responders['POST /voice/rooms/7/invites.json'] =
          (_) async {
            await inviteGate.future;
            throw const WriteException(
              WriteFailure.rateLimited,
              errors: ['You have sent too many invites.'],
              statusCode: 429,
            );
          };

      final field = find.widgetWithText(DInput, 'Invite by name');
      final text = tester.widget<DInput>(field).controller!;
      await tester.enterText(field, 'lee');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.showKeyboard(field);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(text.text, 'lee');

      inviteGate.complete();
      await tester.pumpAndSettle();

      expect(
        harness.transport.writes.where(
          (write) => write.path.endsWith('/invites.json'),
        ),
        hasLength(1),
      );
      expect(text.text, 'lee');
      expect(find.text('You have sent too many invites.'), findsOneWidget);
      harness.dispose();
    });

    testWidgets('a refused invite keeps the name until one is sent', (
      tester,
    ) async {
      final harness = await _openInvites(tester);
      harness.transport.failures['POST /voice/rooms/7/invites.json'] =
          const WriteException(
            WriteFailure.forbidden,
            errors: ["You can't invite lee."],
            statusCode: 403,
          );

      final field = find.widgetWithText(DInput, 'Invite by name');
      final text = tester.widget<DInput>(field).controller!;
      await tester.enterText(field, 'lee');
      await tester.tap(find.text('Send invite'));
      await tester.pumpAndSettle();

      expect(text.text, 'lee');
      expect(find.text("You can't invite lee."), findsOneWidget);

      await tester.tap(find.text('Send invite'));
      await tester.pumpAndSettle();

      expect(text.text, isEmpty);
      expect(
        harness.transport.writes
            .where((write) => write.path.endsWith('/invites.json'))
            .map((write) => write.body['usernames']),
        [
          ['lee'],
          ['lee'],
        ],
      );
      harness.dispose();
    });

    testWidgets('no invite control without the permission', (tester) async {
      final room = _room(
        participants: const [
          VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
        ],
      );
      final harness = _Harness(joinRoom: room);
      addTearDown(harness.dispose);
      await _join(harness, room);
      await tester.pumpWidget(
        _app(harness.controller, room: room, call: harness.controller.call),
      );

      expect(find.byTooltip('Invite people'), findsNothing);
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

void _microphoneTests() {
  group('microphone test', () {
    late DiagnosticsController diagnostics;
    late VoiceDiagnosticsController microphoneDiagnostics;
    final harnesses = <_Harness>[];

    Future<_Harness> open(WidgetTester tester) async {
      final harness = await _openMicrophoneTest(tester, microphoneDiagnostics);
      harnesses.add(harness);
      return harness;
    }

    void testMicrophone(
      String description,
      Future<void> Function(WidgetTester) runTest,
    ) {
      testWidgets(description, (tester) async {
        diagnostics = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'voice-microphone-test',
        );
        microphoneDiagnostics = await VoiceDiagnosticsController.create(
          reporter: PluginDiagnosticsReporter.fixed(diagnostics),
          persistence: MemoryVoiceDiagnosticsPersistence(),
        );
        try {
          await runTest(tester);
        } finally {
          for (final harness in harnesses) {
            await harness.controller.leave();
          }
          await tester.pumpWidget(const SizedBox.shrink());
          for (final harness in harnesses) {
            harness.dispose();
          }
          await tester.pump();
          harnesses.clear();
          await microphoneDiagnostics.close();
          await diagnostics.close();
        }
      });
    }

    List<DiagnosticLogEvent> failures() => diagnostics.events
        .whereType<DiagnosticLogEvent>()
        .where((event) => event.name == 'microphone.test.failed')
        .toList();

    testMicrophone('handles permission denial and allows an explicit retry', (
      tester,
    ) async {
      var denied = true;
      final calls = _mockMicrophone(
        tester,
        beforeCall: (call) async {
          if (call.method == 'getUserMedia' && denied) {
            throw PlatformException(code: 'NotAllowedError', message: 'Denied');
          }
        },
      );
      await open(tester);
      expect(calls, isEmpty);

      await tester.tap(find.text('Test microphone'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text("Couldn't test the microphone. Please try again."),
        findsOneWidget,
      );
      expect(find.text('Microphone is available.'), findsNothing);
      expect(find.text('Testing…'), findsNothing);
      expect(calls.map((call) => call.method), ['initialize', 'getUserMedia']);
      expect(
        failures().single.attributes['operation'],
        'voice.microphone.test.capture',
      );
      expect(failures().single.handled, isTrue);
      expect(failures().single.severity, DiagnosticSeverity.warning);
      expect(failures().single.source, 'voice');

      denied = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test microphone'));
      await tester.pumpAndSettle();

      expect(find.text('Microphone is available.'), findsOneWidget);
      expect(
        calls.where((call) => call.method == 'getUserMedia'),
        hasLength(2),
      );
      _expectMicrophoneReleased(calls);
    });

    for (final failure in [
      (name: 'track cleanup', track: true, stream: false),
      (name: 'stream disposal', track: false, stream: true),
      (name: 'track cleanup and stream disposal', track: true, stream: true),
    ]) {
      testMicrophone(
        'contains ${failure.name} failure and attempts all cleanup',
        (tester) async {
          final calls = _mockMicrophone(
            tester,
            beforeCall: (call) async {
              if (failure.track &&
                  call.method == 'trackDispose' &&
                  (call.arguments as Map<Object?, Object?>)['trackId'] ==
                      'microphone-test-track-1') {
                throw PlatformException(code: 'TrackStopFailed');
              }
              if (failure.stream && call.method == 'streamDispose') {
                throw PlatformException(code: 'StreamDisposeFailed');
              }
            },
          );
          await open(tester);

          await tester.tap(find.text('Test microphone'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          _expectMicrophoneReleased(calls);
          expect(find.text('Microphone is available.'), findsNothing);
          expect(
            find.text("Couldn't test the microphone. Please try again."),
            findsOneWidget,
          );
          expect(find.text('Testing…'), findsNothing);
          expect(failures().map((event) => event.attributes['operation']), [
            if (failure.track) 'voice.microphone.test.stopTrack',
            if (failure.stream) 'voice.microphone.test.disposeStream',
          ]);
          expect(failures().every((event) => event.handled), isTrue);
          expect(
            calls.where((call) => call.method == 'getUserMedia'),
            hasLength(1),
          );
        },
      );
    }

    testMicrophone('admits only one native request while busy', (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final calls = _mockMicrophone(
        tester,
        beforeCall: (call) async {
          if (call.method == 'getUserMedia') await gate.future;
        },
      );
      final harness = await open(tester);
      await harness.controller.setMuted(true);
      final button = tester.widget<DButton>(
        find.widgetWithText(DButton, 'Test microphone'),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pump();

      expect(find.text('Testing…'), findsOneWidget);
      expect(
        tester
            .widget<DButton>(find.widgetWithText(DButton, 'Testing…'))
            .onPressed,
        isNull,
      );
      expect(
        calls.where((call) => call.method == 'getUserMedia'),
        hasLength(1),
      );
      gate.complete();
      await tester.pumpAndSettle();

      _expectMicrophoneReleased(calls);
      expect(find.text('Microphone is available.'), findsOneWidget);
      expect(harness.media.sessions.single.muted, isTrue);
      expect(failures(), isEmpty);
    });

    for (final retirement in [
      'closing dialog',
      'closed dialog',
      'disposed room',
      'disposed app',
    ]) {
      for (final denied in [false, true]) {
        testMicrophone(
          'suppresses late ${denied ? 'failure' : 'success'} for $retirement',
          (tester) async {
            final gate = Completer<void>();
            addTearDown(() {
              if (!gate.isCompleted) gate.complete();
            });
            final calls = _mockMicrophone(
              tester,
              beforeCall: (call) async {
                if (call.method == 'getUserMedia') {
                  await gate.future;
                  if (denied) {
                    throw PlatformException(
                      code: 'NotAllowedError',
                      message: 'Denied',
                    );
                  }
                }
              },
            );
            final harness = await open(tester);
            await tester.tap(find.text('Test microphone'));
            await tester.pump();
            expect(
              calls.where((call) => call.method == 'getUserMedia'),
              hasLength(1),
            );

            switch (retirement) {
              case 'closing dialog':
              case 'closed dialog':
                await tester.tap(find.text('Done'));
                if (retirement == 'closed dialog') {
                  await tester.pumpAndSettle();
                } else {
                  await tester.pump();
                  expect(find.byType(AlertDialog), findsOneWidget);
                }
              case 'disposed room':
                await tester.pumpWidget(
                  _app(
                    harness.controller,
                    room: harness.controller.call!.room,
                    call: harness.controller.call,
                    showRoom: false,
                  ),
                );
                expect(find.byType(VoiceRoomContent), findsNothing);
                expect(find.byType(AlertDialog), findsOneWidget);
              case 'disposed app':
                await tester.pumpWidget(const SizedBox.shrink());
            }

            gate.complete();
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(find.byType(SnackBar), findsNothing);
            if (!denied) _expectMicrophoneReleased(calls);
            expect(failures().map((event) => event.attributes['operation']), [
              if (denied) 'voice.microphone.test.capture',
            ]);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
        );
      }
    }
  });
}

Future<_Harness> _openMicrophoneTest(
  WidgetTester tester,
  VoiceDiagnosticsRecorder diagnostics,
) async {
  final room = _room(participants: const []);
  final harness = _Harness(joinRoom: room, diagnostics: diagnostics);
  addTearDown(harness.dispose);
  await _join(harness, room);
  await tester.pumpWidget(
    _app(harness.controller, room: room, call: harness.controller.call),
  );
  await tester.tap(find.byTooltip('Media settings'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Test microphone'));
  await tester.pumpAndSettle();
  return harness;
}

List<MethodCall> _mockMicrophone(
  WidgetTester tester, {
  Future<void> Function(MethodCall)? beforeCall,
}) {
  const channel = MethodChannel('FlutterWebRTC.Method');
  const eventChannel = EventChannel('FlutterWebRTC.Event');
  final messenger = tester.binding.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  rtc.WebRTC.initialized = false;
  messenger.setMockStreamHandler(
    eventChannel,
    const MockStreamHandler.inline(onListen: _ignoreEvents),
  );
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    await beforeCall?.call(call);
    return switch (call.method) {
      'initialize' || 'trackDispose' || 'streamDispose' => null,
      'getUserMedia' => <String, Object?>{
        'streamId': 'microphone-test-stream',
        'audioTracks': [
          for (final id in [
            'microphone-test-track-1',
            'microphone-test-track-2',
          ])
            <String, Object?>{
              'id': id,
              'label': 'Test microphone',
              'kind': 'audio',
              'enabled': true,
              'settings': <String, Object?>{},
            },
        ],
        'videoTracks': <Object?>[],
      },
      _ => throw UnsupportedError('Unexpected WebRTC call: ${call.method}'),
    };
  });
  addTearDown(() {
    rtc.WebRTC.initialized = false;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });
  return calls;
}

void _expectMicrophoneReleased(List<MethodCall> calls) {
  final cleanup = calls
      .where((call) => call.method.endsWith('Dispose'))
      .toList();
  expect(cleanup.map((call) => call.method), [
    'trackDispose',
    'trackDispose',
    'streamDispose',
  ]);
  expect(cleanup.map((call) => call.arguments), [
    {'trackId': 'microphone-test-track-1'},
    {'trackId': 'microphone-test-track-2'},
    {'streamId': 'microphone-test-stream'},
  ]);
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

RecordingPluginTransport _roomChatTransport() => RecordingPluginTransport(
  responses: const {
    'GET /voice/rooms/7/chat_session.json': {'channel_id': 42, 'thread_id': 99},
  },
);

Future<void> _openRoomChat(WidgetTester tester, _Harness harness) async {
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
}

Future<void> _openMembers(WidgetTester tester, _Harness harness) async {
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
}

Future<_Harness> _openInvites(WidgetTester tester) async {
  final room = _room(
    canInvite: true,
    participants: const [
      VoiceParticipant(id: 1, username: 'sam', role: VoiceRole.moderator),
    ],
  );
  final harness = _Harness(joinRoom: room);
  addTearDown(harness.dispose);
  await _join(harness, room);
  await tester.pumpWidget(
    _app(harness.controller, room: room, call: harness.controller.call),
  );
  await tester.tap(find.byTooltip('Invite people'));
  await tester.pumpAndSettle();
  return harness;
}

const _membershipRows = [
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
];

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

List<Element> _observeRoomGridBuilds() {
  final builds = <Element>[];
  final previousRebuildHook = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previousRebuildHook?.call(element, builtOnce);
    if (element.widget is GridView) builds.add(element);
  };
  addTearDown(() => debugOnRebuildDirtyWidget = previousRebuildHook);
  return builds;
}

Widget _app(
  VoiceController controller, {
  required VoiceRoom? room,
  VoiceCallSnapshot? call,
  bool followCall = false,
  bool meshPrivacyWarningEnabled = false,
  bool autoStatusAvailable = false,
  String? inviteLink,
  VoiceController Function()? controllerResolver,
  DateTime Function() ringingClock = DateTime.now,
  bool showRoom = true,
  String siteUrl = _siteUrl,
}) => MaterialApp(
  builder: (context, child) =>
      DToaster(position: DToastPosition.topEnd, child: child!),
  home: Scaffold(
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!showRoom) return const SizedBox.shrink();
        final active = followCall ? controller.call : call;
        return VoiceRoomContent(
          controller: controller,
          room: active?.room ?? room,
          call: active,
          siteUrl: siteUrl,
          siteName: 'Voice',
          currentUserId: 1,
          recordingEnabled: true,
          error: active?.error ?? controller.errorFor(siteUrl),
          meshPrivacyWarningEnabled: meshPrivacyWarningEnabled,
          autoStatusAvailable: autoStatusAvailable,
          inviteLink: inviteLink,
          controllerResolver: controllerResolver,
          ringingClock: ringingClock,
        );
      },
    ),
  ),
);

VoiceRoom _room({
  int id = 7,
  required List<VoiceParticipant> participants,
  String? description,
  String? cookedDescription,
  int? creatorId,
  bool canManage = false,
  bool canInvite = false,
  bool videoAllowed = false,
  bool chatAvailable = false,
  VoiceRoomType type = VoiceRoomType.open,
  VoiceTransport? expectedTransport,
  VoiceRecording? recording,
}) => VoiceRoom(
  id: id,
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
  canInvite: canInvite,
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
    'can_invite': room.canInvite,
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
    PluginRequestHost? requests,
    _Preferences? preferences,
    VoicePreferences? persistentPreferences,
    FakeChatConversationCapability? chatConversations,
    RecordingPluginLiveChannels? tracker,
    _SystemCall? systemCall,
    VoiceDiagnosticsRecorder diagnostics = const NoopVoiceDiagnosticsRecorder(),
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
               'POST /voice/rooms/7/invites.json': const {
                 'invited_usernames': ['kim'],
                 'skipped_usernames': <Object?>[],
               },
               'GET /voice/rooms/7/invites/suggestions.json': const {
                 'suggestions': [
                   {'id': 3, 'username': 'kim', 'total_seconds': 5400},
                 ],
               },
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
      requests:
          requests ?? PluginTestRequestHost(apiKeys: const {_siteUrl: 'key'}),
      trackerFor: (_) => tracker,
      userIdFor: (_) => 1,
      onCallSiteChanged: () {},
      mediaFactory: media,
      systemCall: systemCall ?? _SystemCall(),
      diagnostics: diagnostics,
      preferences: persistentPreferences ?? this.preferences,
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

void _preferenceRemovalTests() {
  for (final remove in [false, true]) {
    for (final camera in [false, true]) {
      testWidgets(
        'queued Voice ${camera ? 'camera' : 'volume'} choices ${remove ? 'stay forgotten after removal' : 'survive reconnect'}',
        (tester) async {
          final key = camera
              ? '${SharedPreferencesVoicePreferences.cameraEnabledKeys.of(_siteUrl)}.1'
              : '${SharedPreferencesVoicePreferences.volumeKeys.of(_siteUrl)}.7.2';
          const otherSite = 'https://other.example';
          final otherKey = camera
              ? '${SharedPreferencesVoicePreferences.cameraEnabledKeys.of(otherSite)}.1'
              : '${SharedPreferencesVoicePreferences.volumeKeys.of(otherSite)}.7.2';
          SharedPreferences.setMockInitialValues({});
          final persistence = _HeldVoicePreferences({
            'flutter.$key': camera ? true : 0.4,
            'flutter.$otherKey': camera ? true : 0.3,
            'flutter.voice.device.camera': 'global-camera',
          }, heldKey: 'flutter.$key');
          SharedPreferencesStorePlatform.instance = persistence;
          addTearDown(() {
            if (!persistence.release.isCompleted) {
              persistence.release.complete();
            }
          });
          const preferences = SharedPreferencesVoicePreferences();
          final room = _room(
            videoAllowed: true,
            participants: const [
              VoiceParticipant(
                id: 1,
                username: 'sam',
                role: VoiceRole.participant,
              ),
              VoiceParticipant(
                id: 2,
                username: 'lee',
                role: VoiceRole.participant,
              ),
            ],
          );
          final transport = RecordingPluginTransport(
            responses: {
              'GET /voice/rooms.json': {
                'rooms': [_joinPayload(room)['room']],
                'can_create_room': true,
              },
              'POST /voice/rooms/7/join.json': _joinPayload(room),
              'POST /voice/rooms/7/state.json': const {},
              'DELETE /voice/rooms/7/leave.json': const {},
            },
          );
          final module = _EditorSessionModule(
            transport,
            preferences: preferences,
          );
          final plugins = PluginInstaller.install(PluginManifest([module]));
          addTearDown(plugins.close);
          const user = DiscourseUser(id: 1, username: 'sam');
          final original = instance('voice.example.com').copyWith(user: user);
          final shell = ShellController(
            instanceStore: FakeInstanceStore([
              original,
              instance('other.example'),
            ]),
            api: FakeDiscourseApi(
              user: user,
              feeds: const {'/latest.json': []},
            ),
            authenticator: FakeAuthenticator()..keys[_siteUrl] = 'key',
            drafts: FakeDraftStore(),
            trackers: FakeSiteTracker.reset(),
            plugins: plugins,
          );
          addTearDown(shell.dispose);
          await shell.load();
          final controller = module.harness.controller;
          await controller.ensureLoaded(_siteUrl);
          await _join(module.harness, room);
          await tester.pumpWidget(
            ShellScope(
              controller: shell,
              child: MaterialApp(
                home: Scaffold(
                  body: PluginUiScope.own(
                    voicePluginId,
                    const VoiceRoomView(roomId: 7),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          if (camera) {
            expect(controller.call?.cameraEnabled, isTrue);
            await tester.tap(find.byTooltip('Camera off'));
            await tester.pumpAndSettle();
            await persistence.started.future;
            expect(
              await persistence.getAll(),
              containsPair('flutter.$key', false),
            );
            await tester.tap(find.byTooltip('Camera on'));
            await tester.pumpAndSettle();
            expect(controller.call?.cameraEnabled, isTrue);
          } else {
            await tester.tap(find.byTooltip('Participant actions'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Local volume'));
            await tester.pumpAndSettle();
            Future<void> setVolume(double value) async {
              final bounds = tester.getRect(find.byType(DSlider));
              await tester.tapAt(
                Offset(
                  bounds.left + 6 + (bounds.width - 12) * value,
                  bounds.center.dy,
                ),
              );
              await tester.pumpAndSettle();
            }

            await setVolume(0.7);
            await persistence.started.future;
            expect(
              await persistence.getAll(),
              containsPair('flutter.$key', 0.7),
            );
            await setVolume(0.2);
            await tester.tap(find.text('Done'));
            await tester.pumpAndSettle();
          }
          final oldRead = camera
              ? preferences.readCameraEnabled(_siteUrl, 1)
              : preferences.readParticipantVolume(_siteUrl, 7, 2);
          await tester.pumpWidget(const SizedBox.shrink());
          if (remove) {
            expect(await shell.removeInstance(original), isTrue);
            await tester.runAsync(pumpEventQueue);
            expect(await persistence.getAll(), isNot(contains('flutter.$key')));
            expect(await shell.addInstance(original), isTrue);
          }
          await shell.connectCurrentInstance();
          persistence.release.complete();
          expect(await oldRead, camera ? !remove : (remove ? null : 0.2));
          if (camera) {
            expect(await preferences.readCameraEnabled(_siteUrl, 1), !remove);
          } else {
            expect(
              await preferences.readParticipantVolume(_siteUrl, 7, 2),
              remove ? null : 0.2,
            );
          }
          expect(
            await persistence.getAll(),
            containsPair('flutter.$otherKey', camera ? true : 0.3),
          );
          expect(
            await persistence.getAll(),
            containsPair('flutter.voice.device.camera', 'global-camera'),
          );
          if (remove) {
            expect(await persistence.getAll(), isNot(contains('flutter.$key')));
          }
          await controller.ensureLoaded(_siteUrl, force: true);
          await _join(module.harness, room);
          await tester.pumpWidget(
            ShellScope(
              controller: shell,
              child: MaterialApp(
                home: Scaffold(
                  body: PluginUiScope.own(
                    voicePluginId,
                    const VoiceRoomView(roomId: 7),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (camera) {
            expect(controller.call?.cameraEnabled, !remove);
            if (remove) {
              await tester.tap(find.byTooltip('Camera on'));
              await tester.pumpAndSettle();
              expect(controller.call?.cameraEnabled, isTrue);
              expect(await preferences.readCameraEnabled(_siteUrl, 1), isTrue);
            }
          } else {
            await tester.tap(find.byTooltip('Participant actions'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Local volume'));
            await tester.pumpAndSettle();
            expect(
              tester.widget<DSlider>(find.byType(DSlider)).value,
              remove ? 1 : 0.2,
            );
            if (remove) {
              final bounds = tester.getRect(find.byType(DSlider));
              await tester.tapAt(
                Offset(
                  bounds.left + 6 + (bounds.width - 12) * 0.8,
                  bounds.center.dy,
                ),
              );
              await tester.pumpAndSettle();
              expect(
                await preferences.readParticipantVolume(_siteUrl, 7, 2),
                0.8,
              );
            }
            await tester.tap(find.text('Done'));
            await tester.pumpAndSettle();
          }
          await controller.leave();
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.iOS,
          TargetPlatform.android,
          TargetPlatform.macOS,
        }),
      );
    }
  }
}

final class _HeldVoicePreferences extends InMemorySharedPreferencesStore {
  _HeldVoicePreferences(super.data, {required this.heldKey}) : super.withData();
  final String heldKey;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final saved = await super.setValue(valueType, key, value);
    if (key == heldKey && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    return saved;
  }
}

void _roomDialogSessionTests() {
  group('room dialog account ownership', () {
    for (final inviting in [false, true]) {
      testWidgets(
        'Native ${inviting ? 'invite' : 'members'} dialog works at narrow width',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final harness = inviting
              ? await _openInvites(tester)
              : _Harness(
                  discourseApi: RecordingPluginTransport(
                    responses: {
                      'GET /voice/rooms/7/memberships.json': {
                        'memberships': _membershipRows,
                      },
                      'POST /voice/rooms/7/memberships.json': const {},
                    },
                  ),
                );
          addTearDown(harness.dispose);
          if (!inviting) {
            await _openMembers(tester, harness);
          }
          final field = find.widgetWithText(
            DInput,
            inviting ? 'Invite by name' : 'Username',
          );
          await tester.enterText(field, 'lee');
          final button = inviting
              ? find.widgetWithText(DButton, 'Send invite')
              : find.byTooltip('Add member');
          final bounds = tester.getRect(button);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(390));
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(
            harness.transport.writes.where(
              (write) => write.path.endsWith(
                inviting ? '/invites.json' : '/memberships.json',
              ),
            ),
            hasLength(1),
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.widgetWithText(DButton, 'Done'));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
          harness.dispose();
        },
      );
    }
    for (final rollback in [false, true]) {
      for (final action in [
        'typed invite',
        'suggested invite',
        'add',
        'role',
        'remove',
        'suggestions completion',
        'add completion',
      ]) {
        testWidgets(
          '$action stops after ${rollback ? 'rollback' : 'reconnect'}',
          (tester) async {
            final room = _room(
              canManage: true,
              canInvite: true,
              creatorId: 1,
              participants: const [
                VoiceParticipant(
                  id: 1,
                  username: 'sam',
                  role: VoiceRole.moderator,
                ),
              ],
            );
            final transport = RecordingPluginTransport(
              responses: {
                'GET /voice/rooms.json': {
                  'rooms': [_joinPayload(room)['room']],
                  'can_create_room': true,
                },
                'POST /voice/rooms/7/join.json': _joinPayload(room),
                'POST /voice/rooms/7/state.json': const {},
                'DELETE /voice/rooms/7/leave.json': const {},
                'GET /voice/rooms/7/invites/suggestions.json': {
                  'suggestions': [
                    {'id': 2, 'username': 'kim', 'total_seconds': 7200},
                  ],
                },
                'POST /voice/rooms/7/invites.json': {
                  'invited_usernames': ['lee', 'kim'],
                },
                'GET /voice/rooms/7/memberships.json': {
                  'memberships': _membershipRows,
                },
                'POST /voice/rooms/7/memberships.json': const {},
                'PUT /voice/rooms/7/memberships/9.json': const {},
                'DELETE /voice/rooms/7/memberships/9.json': const {},
              },
            );
            final module = _EditorSessionModule(transport);
            final gate = Completer<void>();
            final heldSuggestions = action == 'suggestions completion';
            final heldAdd = action == 'add completion';
            final heldPath = heldSuggestions
                ? 'GET /voice/rooms/7/invites/suggestions.json'
                : 'POST /voice/rooms/7/memberships.json';
            if (heldSuggestions || heldAdd) {
              transport.responders[heldPath] = (_) async {
                await gate.future;
                return transport.responses[heldPath]!;
              };
              addTearDown(() {
                if (!gate.isCompleted) gate.complete();
              });
            }
            final plugins = PluginInstaller.install(PluginManifest([module]));
            addTearDown(plugins.close);
            const user = DiscourseUser(id: 1, username: 'sam');
            const replacement = DiscourseUser(
              id: 8,
              username: 'replacement',
              staff: true,
            );
            final auth = _EditorAuthenticator(rollback: rollback)
              ..keys[_siteUrl] = 'key';
            final shell = ShellController(
              instanceStore: FakeInstanceStore([
                instance('voice.example.com').copyWith(user: user),
              ]),
              api: FakeDiscourseApi(
                user: user,
                feeds: const {'/latest.json': []},
              )..accounts['replacement-key'] = replacement,
              authenticator: auth,
              drafts: FakeDraftStore(),
              trackers: FakeSiteTracker.reset(),
              plugins: plugins,
            );
            var disposed = false;
            addTearDown(() {
              if (!disposed) shell.dispose();
            });
            await shell.load();
            final controller = module.harness.controller;
            await controller.ensureLoaded(_siteUrl);
            await controller.join(
              siteUrl: _siteUrl,
              siteName: 'Voice',
              room: room,
            );
            await tester.pumpWidget(
              ShellScope(
                controller: shell,
                child: MaterialApp(
                  home: Scaffold(
                    body: PluginUiScope.own(
                      voicePluginId,
                      const VoiceRoomView(roomId: 7),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final inviting = action.endsWith('invite') || heldSuggestions;
            final trigger = tester.element(
              find.byTooltip(inviting ? 'Invite people' : 'Manage members'),
            );
            await tester.tap(
              find.byTooltip(inviting ? 'Invite people' : 'Manage members'),
            );
            await tester.pumpAndSettle();
            final field = find.byType(TextField);
            final modal = tester.element(field);
            if (action == 'typed invite' || action == 'add' || heldAdd) {
              await tester.enterText(field, 'lee');
            }
            if (heldAdd) {
              await tester.tap(find.byTooltip('Add member'));
              await tester.pump();
              expect(
                transport.writes.where(
                  (write) => write.path.contains('/memberships'),
                ),
                hasLength(1),
              );
            }
            await shell.connectCurrentInstance();
            await controller.ensureLoaded(_siteUrl, force: true);
            await tester.pumpAndSettle();
            expect(trigger.mounted, isFalse);
            expect(tester.element(field), same(modal));
            expect(auth.keys[_siteUrl], rollback ? 'key' : 'replacement-key');
            expect(controller.room(_siteUrl, 7)?.canManage, isTrue);
            switch (action) {
              case 'typed invite':
                await tester.tap(find.text('Send invite'));
              case 'suggested invite':
                await tester.tap(find.widgetWithText(DButton, 'Invite'));
              case 'add':
                await tester.tap(find.byTooltip('Add member'));
              case 'role':
                await tester.tap(
                  find.descendant(
                    of: find.widgetWithText(DItem, 'Lee Example'),
                    matching: find.byTooltip('Change role'),
                  ),
                );
                await tester.pumpAndSettle();
                await tester.tap(
                  find
                      .widgetWithText(
                        DDropdownMenuItem,
                        VoiceRole.participant.name,
                      )
                      .last,
                );
              case 'remove':
                await tester.tap(
                  find.descendant(
                    of: find.widgetWithText(DItem, 'Lee Example'),
                    matching: find.byTooltip('Remove member'),
                  ),
                );
              case 'suggestions completion':
              case 'add completion':
                gate.complete();
            }
            await tester.pumpAndSettle();
            expect(
              transport.writes.where(
                (write) =>
                    write.path.contains('/invites') ||
                    write.path.contains('/memberships'),
              ),
              heldAdd ? hasLength(1) : isEmpty,
            );
            if (heldSuggestions) {
              expect(find.text('kim'), findsNothing);
            }
            if (heldAdd) {
              expect(
                transport.reads.where(
                  (read) => read.path.contains('/memberships'),
                ),
                hasLength(1),
              );
              expect(tester.widget<TextField>(field).controller?.text, 'lee');
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(() async {
              disposed = true;
              shell.dispose();
              await shell.pluginTeardown;
            });
          },
        );
      }
    }
  });
}

final class _EditorSessionModule implements PluginModule {
  _EditorSessionModule(this.transport, {this.preferences});
  final RecordingPluginTransport transport;
  final VoicePreferences? preferences;
  late _Harness harness;

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: voicePluginId);

  @override
  void register(PluginRegistrar registrar) {
    if (preferences != null) registrar.addCapability(const VoicePlugin());
    registrar.addSession((bindings, _) {
      harness = _Harness(
        discourseApi: transport,
        requests: bindings.require(corePluginRequestPort),
        persistentPreferences: preferences,
      );
      final voice = VoiceShellService(
        controller: harness.controller,
        host: bindings.require(corePluginRouteNavigationPort),
        recordingEnabled: (_) => false,
      );
      return PluginSessionContribution(
        lifecycle: _EditorLifecycle(harness.controller),
        services: [
          PluginService<Object>(voiceControllerService, harness.controller),
          PluginService<Object>(voiceShellService, voice),
        ],
      );
    }, requires: const [corePluginRequestPort, corePluginRouteNavigationPort]);
  }
}

final class _EditorLifecycle extends PluginSessionLifecycle {
  _EditorLifecycle(this.controller);
  final VoiceController controller;
  @override
  void forget(String siteUrl) => controller.forget(siteUrl);
  @override
  Future<void> close() => controller.close();
}

final class _EditorAuthenticator extends FakeAuthenticator {
  _EditorAuthenticator({required this.rollback})
    : super(
        credentials: const UserApiCredentials(
          key: 'replacement-key',
          apiVersion: 4,
          push: false,
        ),
      );
  final bool rollback;
  @override
  Future<void> persistCredentials(
    String siteUrl,
    UserApiCredentials credentials,
  ) async {
    if (rollback) throw StateError('Keychain refused replacement credential');
    await super.persistCredentials(siteUrl, credentials);
  }
}

VoiceShellService _voiceShell(
  VoiceController controller, {
  PluginRouteSite? site,
  bool recordingEnabled = false,
  String? username,
}) => VoiceShellService(
  controller: controller,
  host: _RouteHost(site),
  recordingEnabled: (_) => recordingEnabled,
  currentUsername: (_) => username,
);

final class _RouteHost implements PluginRouteNavigationHost {
  @override
  String? get activeTabId => null;

  _RouteHost(this.currentSite)
    : sites = currentSite == null ? const [] : [currentSite];

  @override
  final List<PluginRouteSite> sites;

  @override
  PluginRouteSite? currentSite;

  @override
  ContentRoute? currentContent;
  VoidCallback? onPushContent;

  @override
  void pushContent(ContentRoute route) {
    currentContent = route;
    onPushContent?.call();
  }

  @override
  void replaceCurrentContent(ContentRoute route) => currentContent = route;

  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
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
  List<rtc.MediaDeviceInfo> availableDevices = const [];
  final List<String> audioInputs = [];
  final List<String> audioOutputs = [];
  final List<({bool enabled, String? deviceId})> cameraChanges = [];
  final List<({int participantId, double volume})> participantVolumes = [];

  @override
  VoiceMediaConnectionState get connectionState =>
      VoiceMediaConnectionState.connected;
  @override
  Object? get connectionFailure => null;
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
  Completer<void>? cameraGate;
  @override
  Future<void> setCameraEnabled(
    bool enabled, {
    String? deviceId,
    bool Function()? shouldContinue,
  }) async {
    if (enabled) await cameraGate?.future;
    if (enabled && shouldContinue?.call() == false) return;
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

  bool cameraEnabled = false;

  @override
  Future<bool> readCameraEnabled(String siteUrl, int userId) async =>
      cameraEnabled;

  @override
  Future<void> writeCameraEnabled(
    String siteUrl,
    int userId,
    bool enabled,
  ) async {
    cameraEnabled = enabled;
  }

  final double? participantVolume;
  Completer<void>? participantVolumeReadGate;
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
  ) async {
    await participantVolumeReadGate?.future;
    return participantVolume;
  }

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
