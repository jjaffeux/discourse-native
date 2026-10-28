import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_room_editor.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_ui_evidence.dart';
import 'support/voice_fake_chat_conversations.dart';
import 'voice_controller_test.dart'
    show FakeVoiceMediaFactory, FakeVoicePreferences, FakeVoiceSystemCall;

const _site = 'https://voice.example.com';
Map<String, dynamic> _room({bool canDelete = true, bool ephemeral = false}) => {
  'id': 7,
  'name': 'Lounge',
  'slug': 'lounge',
  'public': true,
  'can_manage': true,
  'can_delete': canDelete,
  'ephemeral': ephemeral,
  'room_type': 'open',
  'active_participants': [
    {'id': 1, 'username': 'sam', 'role': 'participant'},
  ],
};

void main() {
  late RecordingPluginTransport transport;
  late RecordingPluginLiveChannels live;
  late VoiceController controller;
  late FakeVoiceMediaFactory media;
  setUp(() {
    transport = RecordingPluginTransport(
      responses: {
        'GET /live/rooms.json': {
          'rooms': [_room()],
        },
        'POST /live/rooms/7/join.json': {
          'room': _room(),
          'transport': 'mesh',
          'participant_session_id': 'call-session',
          'ice': {'servers': <Object>[]},
        },
        'POST /live/rooms/7/state.json': {},
        'DELETE /live/rooms/7.json': {},
        'DELETE /live/rooms/7/leave.json': {},
      },
    );
    live = RecordingPluginLiveChannels();
    media = FakeVoiceMediaFactory();
    controller = VoiceController(
      api: VoiceApi(transport, namespaceFor: (_) => VoiceNamespace.live),
      chatConversations: FakeChatConversationCapability(),
      requests: PluginTestRequestHost(apiKeys: {_site: 'key'}),
      trackerFor: (_) => live,
      userIdFor: (_) => 1,
      onCallSiteChanged: () {},
      mediaFactory: media,
      systemCall: FakeVoiceSystemCall(),
      preferences: FakeVoicePreferences(),
      heartbeatInterval: const Duration(days: 1),
    );
  });
  tearDown(() => controller.close());

  test(
    'deleting an occupied room removes it and ends the local call',
    () async {
      await controller.ensureLoaded(_site);
      await controller.join(
        siteUrl: _site,
        siteName: 'Voice',
        room: controller.room(_site, 7)!,
      );
      expect(controller.call, isNotNull);
      expect(await controller.deleteRoom(siteUrl: _site, roomId: 7), isTrue);
      expect(controller.room(_site, 7), isNull);
      expect(controller.directory(_site)!.rooms, isEmpty);
      expect(controller.call, isNull);
      expect(
        transport.writes
            .where((request) => request.path == '/live/rooms/7.json')
            .single
            .method,
        'DELETE',
      );
      expect(
        transport.writes.where(
          (request) => request.path.endsWith('/leave.json'),
        ),
        isEmpty,
      );
    },
  );

  for (final denied in ['moderator', 'temporary']) {
    test(
      'does not delete a $denied room without server delete permission',
      () async {
        transport.responses['GET /live/rooms.json'] = {
          'rooms': [
            _room(
              canDelete: denied != 'moderator',
              ephemeral: denied == 'temporary',
            ),
          ],
        };
        await controller.ensureLoaded(_site);
        expect(await controller.deleteRoom(siteUrl: _site, roomId: 7), isFalse);
        expect(controller.room(_site, 7), isNotNull);
        expect(transport.writes, isEmpty);
      },
    );
  }

  test('failed deletion retains the room and exposes an error', () async {
    transport.failures['DELETE /live/rooms/7.json'] = const WriteException(
      WriteFailure.forbidden,
      statusCode: 403,
    );
    await controller.ensureLoaded(_site);
    expect(await controller.deleteRoom(siteUrl: _site, roomId: 7), isFalse);
    expect(controller.room(_site, 7), isNotNull);
    expect(controller.errorFor(_site), isNotEmpty);
  });

  test('late deletion cannot remove a replacement account room', () async {
    final response = Completer<Map<String, dynamic>>();
    transport.responders['DELETE /live/rooms/7.json'] = (_) => response.future;
    await controller.ensureLoaded(_site);
    final deletion = controller.deleteRoom(siteUrl: _site, roomId: 7);
    await pumpEventQueue();
    controller.forget(_site);
    await controller.ensureLoaded(_site);
    response.complete({});
    expect(await deletion, isFalse);
    expect(controller.room(_site, 7), isNotNull);
    expect(controller.errorFor(_site), isNull);
  });

  test(
    'a directory read started before deletion cannot resurrect the room',
    () async {
      await controller.ensureLoaded(_site);
      final response = Completer<Map<String, dynamic>>();
      transport.responders['GET /live/rooms.json'] = (_) => response.future;
      final refresh = controller.ensureLoaded(_site, force: true);
      await pumpEventQueue();
      expect(await controller.deleteRoom(siteUrl: _site, roomId: 7), isTrue);
      response.complete({
        'rooms': [_room()],
      });
      await refresh;
      expect(controller.room(_site, 7), isNull);
      expect(controller.directory(_site)!.rooms, isEmpty);
    },
  );

  testWidgets('delete action confirms and cancel keeps the room', (
    tester,
  ) async {
    await controller.ensureLoaded(_site);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        builder: (context, child) => nativeUiEvidenceBuilder(context, child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => DButton(
              label: const Text('Edit'),
              onPressed: () => showVoiceRoomEditor(
                context,
                siteUrl: _site,
                room: controller.room(_site, 7),
                controller: controller,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete room'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Delete this room? Everyone in the call will be disconnected. This cannot be undone.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(controller.room(_site, 7), isNotNull);
    expect(transport.writes, isEmpty);
    await tester.tap(find.text('Delete room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete room').last);
    await tester.pumpAndSettle();
    expect(controller.room(_site, 7), isNull);
    expect(find.text('Edit voice room'), findsNothing);
  });
}
