import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_callkit.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics.dart';
import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_plugin.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_shell_service.dart';
import 'package:discourse_native/src/plugins/voice/voice_user_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import '../../support/voice_fake_chat_conversations.dart';

const registry = PluginRegistry([VoicePlugin()]);
const site = 'https://voice.example';

void main() {
  test("Voice reads the site's call permission off the user card", () {
    expect(
      registry
          .readUserCard(const {'voice_can_call': true}, site)
          .get(voiceUserCardKey)
          ?.canCall,
      isTrue,
    );
    expect(
      registry
          .readUserCard(const {'voice_can_call': false}, site)
          .get(voiceUserCardKey)
          ?.canCall,
      isFalse,
    );
  });

  test('a card without the field says nothing about calling', () {
    expect(
      registry
          .readUserCard(const {'username': 'kim'}, site)
          .get(voiceUserCardKey),
      isNull,
    );
  });

  for (final warnAboutMesh in [false, true]) {
    testWidgets('dismisses the card and opens and joins a delayed call once '
        '${warnAboutMesh ? 'with' : 'without'} the mesh warning', (
      tester,
    ) async {
      final harness = _CallHarness(warnAboutMesh: warnAboutMesh);
      addTearDown(harness.close);
      await harness.openCard(tester);
      final repeatCall = tester
          .widget<DButton>(find.byKey(_callButtonKey))
          .onPressed!;

      await tester.tap(find.byKey(_callButtonKey));
      repeatCall();
      await harness.finishDismissal(tester);

      expect(harness.host.opened, isEmpty);
      expect(harness.transport.writes.single.body, {'username': 'kim'});

      harness.creation.complete({'room': _callRoom});
      await tester.pumpAndSettle();
      if (warnAboutMesh) {
        expect(find.text('Before you join this room'), findsOneWidget);
        expect(harness.requestRoutes, ['POST /voice/calls.json']);
        expect(harness.media.sessions, isEmpty);
        await tester.tap(find.text('Join room'));
        await tester.pumpAndSettle();
      }

      expect(harness.host.opened.map((route) => route.id), ['voice-room-9']);
      expect(harness.requestRoutes, [
        'POST /voice/calls.json',
        'POST /voice/rooms/9/join.json',
        'POST /voice/rooms/9/state.json',
      ]);
      expect(harness.controller.call?.room.id, 9);
      expect(harness.controller.call?.status, VoiceCallStatus.connected);
      expect(harness.media.sessions.single.connectCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      final closing = harness.close();
      await tester.pump();
      await closing;
      expect(harness.media.sessions.single.disposeCount, 1);
      expect(harness.requestRoutes.last, 'DELETE /voice/rooms/9/leave.json');
      expect(tester.takeException(), isNull);
    });
  }

  for (final (label, error, message) in [
    (
      'server refusal',
      const WriteException(
        WriteFailure.forbidden,
        errors: ["Kim can't receive calls."],
      ),
      "Kim can't receive calls.",
    ),
    (
      'unexpected failure',
      StateError('room creation failed'),
      "Couldn't start the call.",
    ),
  ]) {
    testWidgets('shows a delayed $label after the card is disposed', (
      tester,
    ) async {
      final harness = _CallHarness();
      addTearDown(harness.close);
      await harness.openCard(tester);
      await tester.tap(find.byKey(_callButtonKey));
      await harness.finishDismissal(tester);

      harness.creation.completeError(error);
      await tester.pumpAndSettle();

      expect(harness.messengerKey.currentState?.mounted, isTrue);
      expect(find.widgetWithText(SnackBar, message), findsOneWidget);
      expect(harness.host.opened, isEmpty);
      expect(harness.media.sessions, isEmpty);
      expect(harness.requestRoutes, ['POST /voice/calls.json']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final fail in [false, true]) {
    testWidgets(
      'ignores delayed call ${fail ? 'failure' : 'success'} after host teardown',
      (tester) async {
        final harness = _CallHarness();
        addTearDown(harness.close);
        await harness.openCard(tester);
        await tester.tap(find.byKey(_callButtonKey));
        await harness.finishDismissal(tester);
        final navigator = harness.navigatorKey.currentState!;
        final messenger = harness.messengerKey.currentState!;
        await tester.pumpWidget(const SizedBox.shrink());
        expect(navigator.mounted, isFalse);
        expect(messenger.mounted, isFalse);

        if (fail) {
          harness.creation.completeError(
            const WriteException(WriteFailure.unreachable),
          );
        } else {
          harness.creation.complete({'room': _callRoom});
        }
        await tester.pumpAndSettle();

        expect(harness.host.opened, isEmpty);
        expect(harness.media.sessions, isEmpty);
        expect(harness.requestRoutes, ['POST /voice/calls.json']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

const _callButtonKey = ValueKey<String>('user-card-call-kim');
const _callRoom = {
  'id': 9,
  'name': 'Call with Kim',
  'slug': 'call-kim',
  'ephemeral': true,
  'room_type': 'call',
  'expected_transport': 'mesh',
  'active_participants': <Object>[],
};

final class _CallHarness {
  _CallHarness({bool warnAboutMesh = false}) {
    transport = RecordingPluginTransport(
      responders: {'POST /voice/calls.json': (_) => creation.future},
      responses: const {
        'POST /voice/rooms/9/join.json': {
          'room': _callRoom,
          'transport': 'mesh',
          'ice': {'servers': <Object>[]},
        },
        'POST /voice/rooms/9/state.json': {},
        'DELETE /voice/rooms/9/leave.json': {},
      },
    );
    controller = VoiceController(
      api: VoiceApi(transport),
      chatConversations: FakeChatConversationCapability(),
      requests: PluginTestRequestHost(apiKeys: const {site: 'key'}),
      trackerFor: (_) => null,
      userIdFor: (_) => 1,
      onCallSiteChanged: () {},
      mediaFactory: media,
      systemCall: _SystemCall(),
    );
    final shell = VoiceShellService(
      controller: controller,
      host: host,
      recordingEnabled: (_) => false,
      meshPrivacyWarningEnabled: (_) => warnAboutMesh,
    );
    plugins = PluginInstaller.install(PluginManifest([_CallModule(shell)]));
    session = plugins.openSession(const PluginHostBindings.empty());
  }

  final creation = Completer<Map<String, dynamic>>();
  final host = _RouteHost();
  final media = _MediaFactory();
  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final RecordingPluginTransport transport;
  late final VoiceController controller;
  late final InstalledPlugins plugins;
  late final PluginSession session;
  late BuildContext cardContext;
  int dismissals = 0;
  bool _closed = false;

  Iterable<String> get requestRoutes =>
      transport.requests.map((request) => '${request.method} ${request.path}');

  Future<void> openCard(WidgetTester tester) async {
    await tester.pumpWidget(
      PluginScope(
        session: session,
        registry: plugins.registry,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: messengerKey,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  showGeneralDialog<void>(
                    context: context,
                    barrierDismissible: true,
                    barrierLabel: 'Dismiss',
                    transitionDuration: const Duration(milliseconds: 140),
                    pageBuilder: (context, _, _) => Center(
                      child: Material(
                        child: SizedBox(
                          width: 320,
                          child: PluginUiScope.own(
                            voicePluginId,
                            VoiceUserCardCallButton(
                              siteUrl: site,
                              user: const UserCard(username: 'kim'),
                              close: () {
                                dismissals++;
                                unawaited(Navigator.of(context).maybePop());
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open card'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open card'));
    await tester.pumpAndSettle();
    cardContext = tester.element(find.byType(VoiceUserCardCallButton));
  }

  Future<void> finishDismissal(WidgetTester tester) async {
    await tester.pump();
    expect(dismissals, 1);
    expect(requestRoutes, ['POST /voice/calls.json']);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 140),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 1),
    );
    expect(creation.isCompleted, isFalse);
    expect(cardContext.mounted, isFalse);
    expect(find.byType(VoiceUserCardCallButton), findsNothing);
    expect(navigatorKey.currentState!.canPop(), isFalse);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!creation.isCompleted) creation.complete({'room': _callRoom});
    await controller.close();
    await session.close();
    await plugins.close();
  }
}

final class _CallModule implements PluginModule {
  const _CallModule(this.shell);

  final VoiceShellService shell;

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: voicePluginId);

  @override
  void register(PluginRegistrar registrar) => registrar.addSession(
    (_, _) => PluginSessionContribution(
      lifecycle: _CallLifecycle(),
      services: [PluginService(voiceShellService, shell)],
    ),
  );
}

final class _CallLifecycle extends PluginSessionLifecycle {}

final class _RouteHost implements PluginRouteNavigationHost {
  final List<ContentRoute> opened = [];

  @override
  final sites = const [
    PluginRouteSite(url: site, title: 'Voice', isConnected: true),
  ];

  @override
  PluginRouteSite get currentSite => sites.single;

  @override
  ContentRoute? get currentContent => opened.lastOrNull;

  @override
  void pushContent(ContentRoute route) => opened.add(route);

  @override
  void replaceCurrentContent(ContentRoute route) => opened.last = route;

  @override
  void selectInstance(int index) => throw StateError('Unexpected site switch');

  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) => throw StateError('Unexpected topic navigation');
}

final class _MediaFactory implements VoiceMediaFactory {
  final List<_MediaSession> sessions = [];

  @override
  VoiceMediaSession create({
    required VoiceJoinResponse join,
    required int localUserId,
    required VoiceSignalSender sendSignal,
    required VoiceLiveKitCredentialRefresher refreshLiveKitCredentials,
    VoiceDiagnosticsRecorder diagnostics = const NoopVoiceDiagnosticsRecorder(),
    String correlationId = 'uncorrelated',
  }) {
    final session = _MediaSession();
    sessions.add(session);
    return session;
  }
}

final class _MediaSession extends ChangeNotifier implements VoiceMediaSession {
  int connectCount = 0;
  int disposeCount = 0;

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
  Future<void> setMuted(bool enabled) async {}
  @override
  Future<void> setParticipantVolume(int participantId, double volume) async {}
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

final class _SystemCall implements VoiceSystemCall {
  @override
  Stream<VoiceSystemCallAction> get actions => _SystemActions();
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
  Future<void> connected() async {}
  @override
  Future<void> dispose() async {}
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

final class _SystemActions extends Stream<VoiceSystemCallAction> {
  @override
  StreamSubscription<VoiceSystemCallAction> listen(
    void Function(VoiceSystemCallAction)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _SystemSubscription();
}

final class _SystemSubscription extends Fake
    implements StreamSubscription<VoiceSystemCallAction> {
  @override
  Future<void> cancel() => SynchronousFuture<void>(null);
}
