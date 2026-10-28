import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/emoji_preferences.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_callkit.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_reaction_widgets.dart';
import 'package:discourse_native/src/plugins/voice/voice_reactions.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/media_pipeline.dart';
import 'support/voice_fake_chat_conversations.dart';
import 'voice_controller_test.dart'
    show FakeVoiceMediaFactory, FakeVoicePreferences;

const _site = 'https://voice.example.com';
final _emoji = PluginEmojiHost(
  preferences: _Preferences(),
  siteConfigFor: (_) => const SiteConfig.unknown(),
  loadCatalog: (_, {refresh = false}) async => SiteEmojiCatalog.empty,
  loadSearchAliases: (_, {refresh = false}) async => null,
  resolveUrl: (site, name) => '$site/$name.png',
);

final class _Preferences implements EmojiPreferenceStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Finder _button(String label) => find.byWidgetPredicate(
  (widget) => widget is DButton && widget.tooltip == label,
);

void main() {
  setUp(() {
    installTestMediaPipeline(
      client: MockClient((_) async => http.Response('', 404)),
    );
  });

  testWidgets(
    'picker sends the configured custom emoji and holds during cooldown',
    (tester) async {
      final transport = RecordingPluginTransport(
        responses: {'POST /live/rooms/7/reaction.json': {}},
      );
      final api = VoiceApi(transport, namespaceFor: (_) => VoiceNamespace.live);
      final session = VoiceReactionSession(
        siteUrl: _site,
        roomId: 7,
        userId: 1,
        username: 'sam',
        isCurrent: () => true,
        load: () async => const VoiceReactionSettings(
          emojis: ['heart', 'custom_party', 'clap:t3'],
        ),
        send: (emoji) => api.reaction(
          siteUrl: _site,
          roomId: 7,
          apiKey: 'key',
          emoji: emoji,
          participantSessionId: 'joined-session',
        ),
      );
      addTearDown(session.dispose);
      await session.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Center(
              child: VoiceReactionButton(session: session, emoji: _emoji),
            ),
          ),
        ),
      );
      await tester.tap(_button('Add reaction'));
      await tester.pumpAndSettle();
      await tester.tap(_button('custom_party'));
      await tester.pumpAndSettle();
      expect(transport.writes.single.body, {
        'emoji': 'custom_party',
        'participant_session_id': 'joined-session',
      });
      transport.failures['POST /live/rooms/7/reaction.json'] =
          const WriteException(
            WriteFailure.rateLimited,
            statusCode: 429,
            retryAfter: Duration(seconds: 8),
          );
      await tester.tap(_button('Add reaction'));
      await tester.pumpAndSettle();
      await tester.tap(_button('clap:t3'));
      await tester.pumpAndSettle();
      expect(tester.widget<DButton>(_button('Add reaction')).onPressed, isNull);
      expect(session.reactions.map((reaction) => reaction.emoji), [
        'custom_party',
      ]);
      await tester.pump(const Duration(seconds: 8));
      expect(
        tester.widget<DButton>(_button('Add reaction')).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('only the active room stage mounts the call reaction feed', (
    tester,
  ) async {
    final room =
        jsonDecode(File('test/fixtures/voice/room.json').readAsStringSync())
            as Map<String, dynamic>;
    final transport = RecordingPluginTransport(
      responses: {
        'GET /voice/rooms.json': {
          'rooms': [room],
        },
        'POST /voice/rooms/7/join.json':
            jsonDecode(
                  File('test/fixtures/voice/join_mesh.json').readAsStringSync(),
                )
                as Map<String, dynamic>,
        'GET /site.json': {
          'voice_reaction_emojis': ['heart'],
        },
        'POST /voice/rooms/7/state.json': {},
        'POST /voice/rooms/7/heartbeat.json': {},
        'DELETE /voice/rooms/7/leave.json': {},
      },
    );
    final module = _StageModule(transport);
    final plugins = PluginInstaller.install(PluginManifest([module]));
    final session = plugins.openSession(const PluginHostBindings.empty());
    addTearDown(session.close);
    final controller = module.controller;
    await controller.ensureLoaded(_site);
    await controller.join(
      siteUrl: _site,
      siteName: 'Example',
      room: VoiceRoom.fromJson(room),
    );

    Widget stage(int roomId) => PluginScope(
      session: session,
      registry: plugins.registry,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PluginUiScope.own(
            voicePluginId,
            VoiceReactionStage(
              controller: controller,
              siteUrl: _site,
              roomId: roomId,
              child: const Text('Stage'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(stage(8));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceReactionOverlay), findsNothing);
    await tester.pumpWidget(stage(7));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceReactionOverlay), findsOneWidget);
    controller.callReactions!.receive({
      'user_id': 2,
      'username': 'alex',
      'emoji': 'heart',
    });
    await tester.pump();
    expect(find.text('alex'), findsOneWidget);
    await tester.pumpWidget(stage(8));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceReactionOverlay), findsNothing);
    expect(find.text('alex'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.close();
    await session.close();
    await tester.pump();
  });
}

final class _StageModule implements PluginModule {
  _StageModule(this.transport);
  final RecordingPluginTransport transport;
  late VoiceController controller;

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: voicePluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession((bindings, _) {
      controller = VoiceController(
        api: VoiceApi(transport, namespaceFor: (_) => VoiceNamespace.voice),
        chatConversations: FakeChatConversationCapability(),
        requests: PluginTestRequestHost(apiKeys: {_site: 'key'}),
        trackerFor: (_) => null,
        userIdFor: (_) => 1,
        onCallSiteChanged: () {},
        mediaFactory: FakeVoiceMediaFactory(),
        systemCall: _SystemCall(),
        preferences: FakeVoicePreferences(),
        heartbeatInterval: const Duration(days: 1),
      );
      return PluginSessionContribution(
        lifecycle: _Lifecycle(controller),
        services: [PluginService<Object>(voiceEmojiHostService, _emoji)],
      );
    });
  }
}

final class _Lifecycle extends PluginSessionLifecycle {
  _Lifecycle(this.controller);
  final VoiceController controller;
  @override
  Future<void> close() => controller.close();
}

final class _SystemCall implements VoiceSystemCall {
  @override
  Stream<VoiceSystemCallAction> get actions => _SystemActions();
  @override
  Future<void> start({
    required String roomName,
    required String siteName,
  }) async {}
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
