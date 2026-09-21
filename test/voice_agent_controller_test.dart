import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart'
    show PluginTestRequestHost, RecordingPluginLiveChannels;
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_plugin_api/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/voice_fake_chat_conversations.dart';
import 'voice_controller_test.dart'
    show FakeVoicePreferences, FakeVoiceSystemCall;

const site = 'https://voice.example.com';
const roomPayload = <String, dynamic>{
  'id': 7,
  'name': 'Lounge',
  'slug': 'lounge',
  'public': true,
  'expected_transport': 'livekit',
  'active_participants': [
    {'id': 42, 'username': 'human'},
  ],
};

class AgentHarness {
  AgentHarness() {
    controller = VoiceController(
      api: VoiceApi(transport),
      requests: requests,
      chatConversations: FakeChatConversationCapability(),
      trackerFor: (_) => channels,
      userIdFor: (_) => 42,
      onCallSiteChanged: () {},
      systemCall: FakeVoiceSystemCall(),
      preferences: FakeVoicePreferences(),
    );
  }

  final requests = GatedAgentRequests();
  final channels = RecordingPluginLiveChannels();
  final transport = RecordingPluginTransport(
    responses: {
      'GET /voice/rooms.json': {
        'rooms': [roomPayload],
      },
      'GET /site.json': {'voice_livekit_agent_bot_id': -2},
      'GET /voice/agents.json': {
        'agents': [
          {'name': 'assistant'},
        ],
      },
      'GET /voice/agents.json?refresh=true': {'agents': <Object>[]},
      'POST /voice/rooms/7/invite_agent.json': {'dispatch_id': 'AD_test'},
    },
  );
  late final VoiceController controller;

  Future<void> load() async {
    await controller.ensureLoaded(site);
    await controller.refreshAgentPermission(site);
  }

  Future<void> close() => controller.close();
}

class GatedAgentRequests implements PluginRequestHost {
  final delegate = PluginTestRequestHost(apiKeys: {site: 'key'});
  Completer<void>? gate;
  Completer<void>? started;

  @override
  PluginSiteLease capture(String siteUrl) => delegate.capture(siteUrl);

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async {
    started?.complete();
    started = null;
    await gate?.future;
    return delegate.credentialsFor(siteUrl);
  }

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) =>
      delegate.writeCredentialFor(siteUrl);
}

void main() {
  test(
    'bot roster arriving before POST success still settles the invitation',
    () async {
      final h = AgentHarness();
      addTearDown(h.close);
      await h.load();
      final invitation = h.controller.agentInvitation(site, 7);
      addTearDown(invitation.dispose);
      final gate = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      h.transport.responders['POST /voice/rooms/7/invite_agent.json'] = (_) {
        started.complete();
        return gate.future;
      };
      final pending = invitation.submit('assistant');
      await started.future;
      h.channels.deliver('/voice/rooms/7', {
        'type': 'participants',
        'participants': [
          {'id': 42, 'username': 'human'},
          {'id': -2, 'username': 'bot'},
        ],
      });
      expect(h.controller.canInviteAgent(site, 7), isFalse);
      gate.complete({'dispatch_id': 'AD_test'});
      await pending;
      expect(invitation.sent, isTrue);
      expect(invitation.sending, isFalse);
      expect(invitation.error, isNull);
      final duplicate = h.controller.agentInvitation(site, 7);
      addTearDown(duplicate.dispose);
      await duplicate.submit('assistant');
      expect(h.transport.writes.length, 1);
    },
  );

  test('permission is account-owned and a failed refresh revokes it', () async {
    final h = AgentHarness();
    addTearDown(h.close);
    await h.controller.ensureLoaded(site);
    expect(h.controller.canInviteAgent(site, 7), isFalse);
    await h.controller.refreshAgentPermission(site);
    expect(h.controller.canInviteAgent(site, 7), isTrue);
    h.requests.delegate.forget(site);
    expect(h.controller.canInviteAgent(site, 7), isFalse);
    await h.controller.refreshAgentPermission(site);
    expect(h.controller.canInviteAgent(site, 7), isTrue);
    h.transport.failures['GET /site.json'] = StateError('offline');
    await h.controller.refreshAgentPermission(site);
    expect(h.controller.canInviteAgent(site, 7), isFalse);
  });

  test('new permission response wins over a stale grant', () async {
    final h = AgentHarness();
    addTearDown(h.close);
    await h.controller.ensureLoaded(site);
    final gate = Completer<Map<String, dynamic>>();
    final started = Completer<void>();
    h.transport.responders['GET /site.json'] = (_) {
      started.complete();
      return gate.future;
    };
    final old = h.controller.refreshAgentPermission(site);
    await started.future;
    h.transport.responders.remove('GET /site.json');
    h.transport.responses['GET /site.json'] = {};
    await h.controller.refreshAgentPermission(site);
    gate.complete({'voice_livekit_agent_bot_id': -2});
    await old;
    expect(h.controller.canInviteAgent(site, 7), isFalse);
  });

  test(
    'forgetting account during permission read discards its response',
    () async {
      final h = AgentHarness();
      addTearDown(h.close);
      await h.load();
      final gate = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      h.transport.responders['GET /site.json'] = (_) {
        started.complete();
        return gate.future;
      };
      final pending = h.controller.refreshAgentPermission(site);
      await started.future;
      h.controller.forget(site);
      gate.complete({'voice_livekit_agent_bot_id': -2});
      await pending;
      expect(h.controller.canInviteAgent(site, 7), isFalse);
    },
  );

  for (final operation in ['catalogue', 'invitation']) {
    for (final retirement in [
      'account',
      'room',
      'surface',
      'permission',
      'disposed',
    ]) {
      test(
        '$retirement retirement during credentials prevents $operation request',
        () async {
          final h = AgentHarness();
          addTearDown(h.close);
          await h.load();
          var visible = true;
          final invitation = h.controller.agentInvitation(
            site,
            7,
            ifCurrent: () => visible,
          );
          final gate = Completer<void>();
          final started = Completer<void>();
          h.requests.gate = gate;
          h.requests.started = started;
          final pending = operation == 'catalogue'
              ? invitation.refresh()
              : invitation.submit('assistant');
          await started.future;
          switch (retirement) {
            case 'account':
              h.requests.delegate.forget(site);
            case 'room':
              h.channels.deliver('/voice/rooms/index', {
                'type': 'destroyed',
                'room': roomPayload,
              });
            case 'surface':
              visible = false;
            case 'permission':
              h.requests.gate = null;
              h.transport.responses['GET /site.json'] = {};
              await h.controller.refreshAgentPermission(site);
            case 'disposed':
              invitation.dispose();
          }
          final previous = h.transport.requests.length;
          gate.complete();
          await pending;
          expect(h.transport.requests.length, previous);
          expect(invitation.sent, isFalse);
          if (retirement != 'disposed') invitation.dispose();
        },
      );
    }
  }

  test(
    'two choosers cannot dispatch concurrently and successful writes are trimmed',
    () async {
      final h = AgentHarness();
      addTearDown(h.close);
      await h.load();
      final first = h.controller.agentInvitation(site, 7);
      final second = h.controller.agentInvitation(site, 7);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final gate = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      h.transport.responders['POST /voice/rooms/7/invite_agent.json'] = (_) {
        started.complete();
        return gate.future;
      };
      final pending = first.submit(' assistant ');
      await started.future;
      await second.submit('support');
      gate.complete({'dispatch_id': 'AD_test'});
      await pending;
      expect(h.transport.writes.map((request) => request.body), [
        {'agent_name': 'assistant'},
      ]);
      expect(first.sent, isTrue);
      expect(second.sent, isFalse);
    },
  );

  for (final operation in ['catalogue', 'invitation']) {
    test('late $operation response cannot update a replaced account', () async {
      final h = AgentHarness();
      addTearDown(h.close);
      await h.load();
      final invitation = h.controller.agentInvitation(site, 7);
      addTearDown(invitation.dispose);
      final gate = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      final path = operation == 'catalogue'
          ? 'GET /voice/agents.json?refresh=true'
          : 'POST /voice/rooms/7/invite_agent.json';
      h.transport.responders[path] = (_) {
        started.complete();
        return gate.future;
      };
      final pending = operation == 'catalogue'
          ? invitation.refresh()
          : invitation.submit('assistant');
      await started.future;
      h.requests.delegate.forget(site);
      gate.complete({
        'dispatch_id': 'AD_test',
        'agents': [
          {'name': 'stale'},
        ],
      });
      await pending;
      expect(invitation.sent, isFalse);
      expect(invitation.names, isEmpty);
    });
  }
}
