import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart'
    show PluginTestRequestHost, RecordingPluginLiveChannels;
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_callkit.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics.dart';
import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_preferences.dart';
import 'package:discourse_native/src/plugins/voice/voice_shell_service.dart';
import 'package:discourse_plugin_api/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'support/voice_fake_chat_conversations.dart';

const _siteUrl = 'https://voice.example.com';
const _site = PluginRouteSite(url: _siteUrl, title: 'Voice', isConnected: true);
const _room = {
  'id': 9,
  'name': 'sam + kim',
  'slug': 'call-1a2b',
  'ephemeral': true,
  'room_type': 'conference',
  'expected_transport': 'mesh',
  'active_participants': [
    {'id': 1, 'username': 'sam', 'role': 'participant'},
  ],
};

void main() {
  group('outgoing call ownership', () {
    for (final retirement in ['replacement', 'forget', 're-add', 'close']) {
      test('discards a held room response after $retirement', () async {
        final harness = _Harness();
        addTearDown(harness.controller.close);
        final response = Completer<Map<String, dynamic>>();
        final started = Completer<void>();
        harness.transport.responders['POST /voice/calls.json'] = (_) {
          started.complete();
          return response.future;
        };

        final calling = harness.controller.callUser(_siteUrl, 'kim');
        await started.future;
        await harness.retire(retirement);
        response.complete(_room);

        expect(await calling, isNull);
        expect(harness.controller.room(_siteUrl, 9), isNull);
        expect(harness.tracker.subscriberCount('/voice/rooms/9'), 0);
        harness.expectNoJoin();
      });
    }

    for (final retirement in ['replacement', 'forget']) {
      test(
        'does not create a call after credentials and $retirement',
        () async {
          final harness = _Harness();
          addTearDown(harness.controller.close);
          final gate = Completer<void>();
          harness.requests.credentialsGate = gate;
          final calling = harness.controller.callUser(_siteUrl, 'kim');
          await harness.requests.credentialsStarted.future;

          await harness.retire(retirement);
          gate.complete();

          expect(await calling, isNull);
          expect(harness.transport.requests, isEmpty);
          expect(harness.media.localUserIds, isEmpty);
        },
      );
    }

    for (final retirement in ['replacement', 'forget', 're-add']) {
      testWidgets('does not navigate after a held POST and $retirement', (
        tester,
      ) async {
        final harness = _Harness(privacyWarningEnabled: false);
        addTearDown(harness.controller.dispose);
        final context = await _mount(tester);
        final response = Completer<Map<String, dynamic>>();
        harness.transport.responders['POST /voice/calls.json'] = (_) =>
            response.future;

        final calling = harness.shell.callUser(
          context,
          siteUrl: _siteUrl,
          username: 'kim',
        );
        await tester.pump();
        expect(harness.transport.writes.single.path, '/voice/calls.json');
        await harness.retire(retirement);
        response.complete(_room);
        await tester.pumpAndSettle();
        await calling;

        expect(harness.host.navigation, isEmpty);
        harness.expectNoJoin();
      });
    }

    for (final boundary in ['privacy read', 'privacy dialog']) {
      for (final retirement in ['replacement', 're-add']) {
        testWidgets('stops at $boundary after $retirement', (tester) async {
          final harness = _Harness();
          addTearDown(harness.controller.dispose);
          final context = await _mount(tester);
          final gate = Completer<void>();
          if (boundary == 'privacy read') harness.preferences.readGate = gate;

          final calling = harness.shell.callUser(
            context,
            siteUrl: _siteUrl,
            username: 'kim',
          );
          await tester.pumpAndSettle();
          expect(harness.preferences.privacyReads, 1);
          expect(harness.host.navigation, ['push voice-room-9']);
          if (boundary == 'privacy dialog') {
            expect(find.text('Before you join this room'), findsOneWidget);
            await tester.tap(find.text("Don't show this again"));
            await tester.pump();
          }

          await harness.retire(retirement);
          if (boundary == 'privacy read') {
            gate.complete();
          } else {
            await tester.tap(find.text('Join room'));
          }
          await tester.pumpAndSettle();
          // Dismiss an incorrectly opened stale warning so a failing test
          // releases the process-wide dialog guard for the next case.
          final staleWarning = tester.any(
            find.text('Before you join this room'),
          );
          if (staleWarning) {
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
          }
          await calling;

          expect(staleWarning, isFalse);
          expect(harness.host.navigation, ['push voice-room-9']);
          harness.expectNoJoin();
        });
      }
    }

    for (final callback in [
      'select',
      'push',
      'replace',
      'content',
      'privacy',
    ]) {
      testWidgets('rechecks ownership after the $callback callback', (
        tester,
      ) async {
        final harness = _Harness(privacyWarningEnabled: false);
        addTearDown(harness.controller.dispose);
        final context = await _mount(tester);
        switch (callback) {
          case 'select':
            harness.host.currentSite = null;
            harness.host.onSelect = harness.replaceAccount;
          case 'push':
            harness.host.onPush = harness.replaceAccount;
          case 'replace':
            harness.host.currentContent = const ContentRoute(
              id: 'voice-room-9',
              title: 'Existing call',
              icon: DIcons.microphoneLines,
            );
            harness.host.onReplace = harness.replaceAccount;
          case 'content':
            harness.host.onReadContent = harness.replaceAccount;
          case 'privacy':
            harness.onPrivacyFlag = harness.replaceAccount;
        }

        final calling = harness.shell.callUser(
          context,
          siteUrl: _siteUrl,
          username: 'kim',
        );
        await tester.pumpAndSettle();
        await calling;

        expect(harness.host.navigation, switch (callback) {
          'select' => ['select 0'],
          'replace' => ['replace voice-room-9'],
          'content' => <String>[],
          _ => ['push voice-room-9'],
        });
        expect(harness.preferences.privacyReads, 0);
        harness.expectNoJoin();
      });
    }

    testWidgets('a current confirmation acknowledges and joins as its owner', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.controller.dispose);
      final context = await _mount(tester);

      final calling = harness.shell.callUser(
        context,
        siteUrl: _siteUrl,
        username: 'kim',
      );
      await tester.pumpAndSettle();
      expect(find.text('Before you join this room'), findsOneWidget);
      await tester.tap(find.text("Don't show this again"));
      await tester.pump();
      await tester.tap(find.text('Join room'));
      await tester.pumpAndSettle();
      await calling;

      expect(harness.host.navigation, ['push voice-room-9']);
      expect(harness.preferences.privacyWrites, [true]);
      expect(harness.media.localUserIds, [1]);
      expect(harness.media.sessions.single.connected, isTrue);
      expect(harness.controller.call?.status, VoiceCallStatus.connected);
      expect(harness.controller.call?.room.id, 9);
      expect(harness.tracker.subscriberCount('/voice/rooms/9'), 1);
      expect(
        harness.transport.requests.map(
          (request) => '${request.method} ${request.path}',
        ),
        [
          'POST /voice/calls.json',
          'POST /voice/rooms/9/join.json',
          'POST /voice/rooms/9/state.json',
        ],
      );
      expect(harness.transport.writes.map((request) => request.apiKey), [
        'original-key',
        'original-key',
        'original-key',
      ]);
      expect(harness.transport.writes[1].body, {
        'skip_status': null,
        'invited_by': null,
        'participant_session_id': null,
      });
      harness.controller.dispose();
      await tester.pump();
    });

    testWidgets('a current server refusal propagates without navigation', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.controller.dispose);
      final context = await _mount(tester);
      const refusal = WriteException(
        WriteFailure.forbidden,
        statusCode: 403,
        errors: ['Sorry, you cannot call that user.'],
      );
      harness.transport.failures['POST /voice/calls.json'] = refusal;

      await expectLater(
        harness.shell.callUser(context, siteUrl: _siteUrl, username: 'kim'),
        throwsA(same(refusal)),
      );

      expect(harness.host.navigation, isEmpty);
      expect(harness.preferences.privacyReads, 0);
      harness.expectNoJoin();
    });
  });
}

Future<BuildContext> _mount(WidgetTester tester) async {
  late BuildContext callContext;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          callContext = context;
          return const Scaffold();
        },
      ),
    ),
  );
  return callContext;
}

final class _Harness {
  _Harness({bool privacyWarningEnabled = true}) {
    controller = VoiceController(
      api: VoiceApi(transport),
      chatConversations: FakeChatConversationCapability(),
      requests: requests,
      trackerFor: (_) => tracker,
      userIdFor: (_) => userId,
      onCallSiteChanged: () {},
      mediaFactory: media,
      systemCall: _SystemCall(),
      preferences: preferences,
      heartbeatInterval: const Duration(days: 1),
    );
    shell = VoiceShellService(
      controller: controller,
      host: host,
      recordingEnabled: (_) => false,
      meshPrivacyWarningEnabled: (_) {
        onPrivacyFlag?.call();
        return privacyWarningEnabled;
      },
    );
  }

  final requests = _Requests();
  final tracker = RecordingPluginLiveChannels();
  final media = _MediaFactory();
  final preferences = _Preferences();
  final host = _RouteHost();
  final transport = RecordingPluginTransport(
    responses: const {
      'GET /voice/rooms.json': {'rooms': <Object?>[]},
      'POST /voice/calls.json': _room,
      'POST /voice/rooms/9/join.json': {
        'transport': 'mesh',
        'room': _room,
        'ice': {'servers': <Object?>[]},
      },
      'POST /voice/rooms/9/state.json': {},
      'DELETE /voice/rooms/9/leave.json': {},
    },
  );
  late final VoiceController controller;
  late final VoiceShellService shell;
  int userId = 1;
  VoidCallback? onPrivacyFlag;

  void replaceAccount() {
    requests.host.forget(_siteUrl);
    requests.host.apiKeys[_siteUrl] = 'replacement-key';
    userId = 2;
  }

  Future<void> retire(String retirement) async {
    switch (retirement) {
      case 'replacement':
        replaceAccount();
      case 'forget':
        controller.forget(_siteUrl);
      case 're-add':
        controller.forget(_siteUrl);
        requests.host.forget(_siteUrl);
        // Re-adding the same URL and credentials must still create a new owner.
        await controller.ensureLoaded(_siteUrl);
      case 'close':
        await controller.close();
    }
  }

  void expectNoJoin() {
    expect(controller.call, isNull);
    expect(media.localUserIds, isEmpty);
    expect(preferences.privacyWrites, isEmpty);
    expect(
      transport.writes.map(
        (request) => (
          siteUrl: request.siteUrl,
          method: request.method,
          path: request.path,
          apiKey: request.apiKey,
          clientId: request.clientId,
        ),
      ),
      [
        (
          siteUrl: _siteUrl,
          method: 'POST',
          path: '/voice/calls.json',
          apiKey: 'original-key',
          clientId: 'test-client',
        ),
      ],
    );
    expect(transport.writes.single.body, {'username': 'kim'});
  }
}

final class _Requests implements PluginRequestHost {
  final host = PluginTestRequestHost(apiKeys: const {_siteUrl: 'original-key'});
  final credentialsStarted = Completer<void>();
  Completer<void>? credentialsGate;

  @override
  PluginSiteLease capture(String siteUrl) => host.capture(siteUrl);

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async {
    if (!credentialsStarted.isCompleted) credentialsStarted.complete();
    await credentialsGate?.future;
    return host.credentialsFor(siteUrl);
  }

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) =>
      host.writeCredentialFor(siteUrl);
}

final class _RouteHost implements PluginRouteNavigationHost {
  @override
  final sites = const [_site];
  @override
  PluginRouteSite? currentSite = _site;
  ContentRoute? _content;
  VoidCallback? onSelect;
  VoidCallback? onPush;
  VoidCallback? onReplace;
  VoidCallback? onReadContent;
  final navigation = <String>[];

  @override
  ContentRoute? get currentContent {
    onReadContent?.call();
    return _content;
  }

  set currentContent(ContentRoute? content) => _content = content;

  @override
  void pushContent(ContentRoute route) {
    navigation.add('push ${route.id}');
    _content = route;
    onPush?.call();
  }

  @override
  void replaceCurrentContent(ContentRoute route) {
    navigation.add('replace ${route.id}');
    _content = route;
    onReplace?.call();
  }

  @override
  void selectInstance(int index) {
    navigation.add('select $index');
    currentSite = sites[index];
    onSelect?.call();
  }

  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) {}
}

final class _Preferences implements VoicePreferences {
  Completer<void>? readGate;
  int privacyReads = 0;
  final privacyWrites = <bool>[];

  @override
  Future<bool> readMeshPrivacyAcknowledged() async {
    privacyReads++;
    await readGate?.future;
    return false;
  }

  @override
  Future<void> writeMeshPrivacyAcknowledged(bool acknowledged) async {
    privacyWrites.add(acknowledged);
  }

  @override
  Future<VoiceDevicePreferences> readDevices() async =>
      const VoiceDevicePreferences();
  @override
  Future<bool?> readAutoStatusEnabled() async => null;
  @override
  Future<double?> readParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
  ) async => null;
  @override
  Future<void> writeAutoStatusEnabled(bool enabled) async {}
  @override
  Future<void> writeDevice(
    VoiceDevicePreference preference,
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

final class _MediaFactory implements VoiceMediaFactory {
  final localUserIds = <int>[];
  final sessions = <_MediaSession>[];

  @override
  VoiceMediaSession create({
    required VoiceJoinResponse join,
    required int localUserId,
    required VoiceSignalSender sendSignal,
    required VoiceLiveKitCredentialRefresher refreshLiveKitCredentials,
    VoiceDiagnosticsRecorder diagnostics = const NoopVoiceDiagnosticsRecorder(),
    String correlationId = 'uncorrelated',
  }) {
    localUserIds.add(localUserId);
    final media = _MediaSession();
    sessions.add(media);
    return media;
  }
}

final class _MediaSession extends ChangeNotifier implements VoiceMediaSession {
  bool connected = false;
  @override
  VoiceTransport get transport => VoiceTransport.mesh;
  @override
  VoiceMediaConnectionState get connectionState =>
      VoiceMediaConnectionState.connected;
  @override
  Object? get localVideoTrack => null;
  @override
  bool get screenSharing => false;
  @override
  Set<int> get speakingParticipantIds => const {};
  @override
  Object? videoTrackFor(int participantId) => null;
  @override
  Future<void> connect() async {
    connected = true;
  }

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
  Future<void> setDeafened(bool deafened) async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> setParticipantVolume(int participantId, double volume) async {}
  @override
  Future<void> setScreenShareEnabled(bool enabled) async {}
  @override
  Future<void> syncParticipants(List<VoiceParticipant> participants) async {}
  @override
  Future<void> dispose() async {
    super.dispose();
  }
}

final class _SystemCall implements VoiceSystemCall {
  final _actions = StreamController<VoiceSystemCallAction>.broadcast();

  @override
  Stream<VoiceSystemCallAction> get actions => _actions.stream;
  @override
  Future<void> start({
    required String roomName,
    required String siteName,
  }) async {}
  @override
  Future<void> connected() async {}
  @override
  Future<void> failed() async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> end() async {}
  @override
  Future<bool> reportIncomingCall({
    required String callerName,
    required String roomName,
    required String handle,
  }) async => false;
  @override
  Future<void> answerIncomingCall() async {}
  @override
  Future<void> declineIncomingCall() async {}
  @override
  Future<void> endIncomingCall(VoiceIncomingCallEndReason reason) async {}
  @override
  Future<void> dispose() => _actions.close();
}
