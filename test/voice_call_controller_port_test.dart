import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_call_controller_port.dart';
import 'package:discourse_native/src/plugins/voice/voice_call_port.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_shell_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/voice_fake_chat_conversations.dart';
import 'voice_controller_test.dart'
    show
        FakeVoiceMediaFactory,
        FakeVoicePreferences,
        FakeVoiceSystemCall,
        fixture;

void main() {
  test(
    'presents a server reconnect refusal and clears it after recovery',
    () async {
      const site = 'https://voice.example.com';
      final transport = RecordingPluginTransport(
        responses: {
          'GET /voice/rooms.json': fixture('directory'),
          'POST /voice/rooms/7/join.json': fixture('join_livekit'),
          'POST /voice/rooms/7/state.json': <String, dynamic>{},
          'POST /voice/rooms/7/heartbeat.json': <String, dynamic>{},
          'DELETE /voice/rooms/7/leave.json': <String, dynamic>{},
        },
      );
      final mediaFactory = FakeVoiceMediaFactory();
      final channels = RecordingPluginLiveChannels();
      final controller = VoiceController(
        api: VoiceApi(transport),
        requests: PluginTestRequestHost(apiKeys: const {site: 'key'}),
        chatConversations: FakeChatConversationCapability(),
        trackerFor: (_) => channels,
        userIdFor: (_) => 1,
        onCallSiteChanged: () {},
        mediaFactory: mediaFactory,
        systemCall: FakeVoiceSystemCall(),
        preferences: FakeVoicePreferences(),
        heartbeatInterval: const Duration(days: 1),
      );
      final port = VoiceCallControllerPort(
        controller: controller,
        shell: VoiceShellService(
          controller: controller,
          host: _RouteHost(),
          recordingEnabled: (_) => false,
        ),
      );
      addTearDown(() async {
        await port.close();
        await controller.close();
      });
      await controller.ensureLoaded(site);
      await controller.join(
        siteUrl: site,
        siteName: 'meta',
        room: controller.room(site, 7)!,
      );
      final media = mediaFactory.sessions.single;
      media.connectionFailure = const WriteException(
        WriteFailure.validation,
        statusCode: 422,
        errors: ['This room is full.'],
      );
      media.connectionState = VoiceMediaConnectionState.failed;
      media.notifyListeners();
      expect(port.state.call?.status, VoiceCallPresentationStatus.failed);
      expect(port.state.call?.failureMessage, 'This room is full.');

      media.connectionFailure = null;
      media.connectionState = VoiceMediaConnectionState.reconnecting;
      media.notifyListeners();
      expect(port.state.call?.status, VoiceCallPresentationStatus.reconnecting);
      expect(port.state.call?.failureMessage, isNull);
      media.connectionState = VoiceMediaConnectionState.connected;
      media.notifyListeners();
      expect(port.state.call?.status, VoiceCallPresentationStatus.connected);
      expect(port.state.call?.failureMessage, isNull);
    },
  );

  test('translates a dependency read failure into unavailable state', () {
    final runtime = _Runtime()..readFailure = StateError('missing runtime');
    final port = _port(runtime);
    addTearDown(port.close);

    expect(
      port.state,
      isA<VoiceCallPortState>()
          .having((state) => state.supported, 'supported', isTrue)
          .having((state) => state.call, 'call', isNull)
          .having(
            (state) => state.failureMessage,
            'failureMessage',
            'Voice calling is unavailable.',
          ),
    );
  });

  for (final failureCase in const [
    (
      action: VoiceCallAction.openRoom,
      message: "Couldn't open the voice room.",
    ),
    (
      action: VoiceCallAction.toggleMuted,
      message: "Couldn't update the microphone.",
    ),
    (action: VoiceCallAction.leave, message: "Couldn't leave the voice room."),
  ]) {
    test('translates ${failureCase.action.name} dependency failures', () async {
      final runtime = _Runtime(
        onAction: (_) => throw StateError('dependency rejected'),
      );
      final port = _port(runtime);
      addTearDown(port.close);

      port.dispatch(failureCase.action);
      await pumpEventQueue();

      expect(runtime.actions, [failureCase.action]);
      expect(port.state.call, same(runtime.state.call));
      expect(port.state.failureMessage, failureCase.message);
    });
  }

  test('close awaits actions and ignores their late completion', () async {
    final actionCompletion = Completer<void>();
    final runtime = _Runtime(onAction: (_) => actionCompletion.future);
    final port = _port(runtime);
    var notifications = 0;
    port.addListener(() => notifications++);
    port.dispatch(VoiceCallAction.toggleMuted);

    var closed = false;
    final closing = port.close().then((_) => closed = true);
    await pumpEventQueue();
    expect(closed, isFalse);

    runtime.replaceState(_state(roomName: 'Ignored runtime'));
    actionCompletion.complete();
    await closing;

    expect(notifications, 0);
    expect(port.state.call?.roomName, 'Planning');
    port.dispatch(VoiceCallAction.leave);
    expect(runtime.actions, [VoiceCallAction.toggleMuted]);
  });
}

VoiceCallControllerPort _port(_Runtime runtime) =>
    VoiceCallControllerPort.controlled(
      runtime: runtime,
      readState: runtime.readState,
      performAction: runtime.performAction,
    );

final class _Runtime extends ChangeNotifier {
  _Runtime({this.onAction});

  final FutureOr<void> Function(VoiceCallAction action)? onAction;
  final List<VoiceCallAction> actions = [];
  VoiceCallPortState state = _state();
  Object? readFailure;

  VoiceCallPortState readState() {
    if (readFailure case final failure?) throw failure;
    return state;
  }

  FutureOr<void> performAction(VoiceCallAction action) {
    actions.add(action);
    return onAction?.call(action);
  }

  void replaceState(VoiceCallPortState value) {
    state = value;
    notifyListeners();
  }
}

VoiceCallPortState _state({String roomName = 'Planning'}) => VoiceCallPortState(
  supported: true,
  call: VoiceCallPresentation(
    roomName: roomName,
    siteName: 'meta',
    participantCount: 2,
    status: VoiceCallPresentationStatus.connected,
    muted: false,
  ),
);

final class _RouteHost extends Fake implements PluginRouteNavigationHost {
  @override
  String? get activeTabId => null;
}
