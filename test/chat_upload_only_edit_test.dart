import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

const _site = 'https://chat.example';
const _user = DiscourseUser(id: 7, username: 'reader');

void main() {
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    for (final (initialRaw, updatedRaw, removeUpload) in [
      ('caption', '', false),
      ('', 'new caption', false),
      ('caption', 'updated caption', false),
      ('', '', false),
      ('caption', 'caption', false),
      ('caption', '', true),
    ]) {
      testWidgets(
        '${platform.name} inline Edit "$initialRaw" → "$updatedRaw", remove upload $removeUpload',
        (tester) async {
          final api = _EditHttpApi(initialRaw);
          final shell = await _shell(api);
          addTearDown(shell.dispose);
          addTearDown(api.transport.close);
          await tester.pumpWidget(_View(shell, platform));
          await tester.pumpAndSettle();

          await _openEdit(tester, platform);
          expect(
            tester.widget<TextField>(_field()).controller!.text,
            initialRaw,
          );
          expect(find.byTooltip('Remove upload'), findsOneWidget);

          await tester.enterText(_field(), updatedRaw);
          if (removeUpload) {
            await tester.tap(find.byTooltip('Remove upload'));
          }
          await tester.pump();
          final save = find.byKey(const ValueKey('chat-composer-send'));
          if (removeUpload) {
            expect(tester.widget<DButton>(save).onPressed, isNull);
            expect(api.requests, isEmpty);
            expect(shell.chat.message(_site, 12)?.raw, initialRaw);
            expect(shell.chat.message(_site, 12)?.uploads.single.id, 31);
            expect(tester.takeException(), isNull);
            return;
          }
          expect(tester.widget<DButton>(save).onPressed, isNotNull);
          await tester.tap(save);
          await tester.pumpAndSettle();

          if (initialRaw == updatedRaw) {
            expect(api.requests, isEmpty);
          } else {
            expect(api.requests, hasLength(1));
            final request = api.requests.single;
            expect(request.method, 'PUT');
            expect(request.url.path, '/chat/api/channels/9/messages/12.json');
            expect(request.headers['user-api-key'], 'key');
            expect(jsonDecode(request.body), {
              'message': updatedRaw,
              'upload_ids': [31],
            });
          }
          expect(shell.chat.message(_site, 12)?.raw, updatedRaw);
          expect(shell.chat.message(_site, 12)?.uploads.single.id, 31);
          expect(
            find.byKey(const ValueKey('chat-composer-edit-cancel')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Finder _field() => find.descendant(
  of: find.byKey(const ValueKey('chat-composer')),
  matching: find.byType(TextField),
);

Future<void> _openEdit(WidgetTester tester, TargetPlatform platform) async {
  if (platform == TargetPlatform.macOS) {
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(
      tester.getCenter(find.byKey(ChatMessageTile.actionsKey(12))),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('More message actions'));
  } else {
    await tester.longPress(find.byType(ChatMessageTile));
  }
  await tester.pumpAndSettle();
  final edit = find.text('Edit');
  expect(edit, findsOneWidget);
  await tester.tap(edit);
  await tester.pumpAndSettle();
}

Future<ShellController> _shell(_EditHttpApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      const DiscourseInstance(
        url: _site,
        title: 'Chat',
        apiVersion: 4,
        user: _user,
      ),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  await shell.load();
  shell.chatRecords.put(
    _site,
    const ChatChannel(
      id: 9,
      title: 'design',
      kind: ChatChannelKind.category,
      membership: ChatMembership(following: true),
    ),
  );
  return shell;
}

final class _View extends StatelessWidget {
  const _View(this.shell, this.platform);

  final ShellController shell;
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: shell,
    child: PluginUiScope.own(
      chatPluginId,
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        builder: (_, child) => DToaster(child: child!),
        home: const Scaffold(body: ChatChannelView(channelId: 9)),
      ),
    ),
  );
}

final class _EditHttpApi extends FakeDiscourseApi {
  _EditHttpApi(String raw)
    : super(
        user: _user,
        chatMessagesByKey: {
          FakeDiscourseApi.chatMessagesKey(9): (
            messages: [
              ChatMessage.fromJson({
                'id': 12,
                'chat_channel_id': 9,
                'message': raw,
                'cooked': raw.isEmpty ? '' : '<p>$raw</p>',
                'user': const {'id': 7, 'username': 'reader'},
                'created_at': '2026-10-02T10:00:00Z',
                'uploads': const [
                  {
                    'id': 31,
                    'url': '/uploads/design.txt',
                    'original_filename': 'design.txt',
                    'extension': 'txt',
                  },
                ],
              }, _site),
            ],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
        },
      ) {
    transport = DiscourseApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'success': 'OK'}), 200);
      }),
    );
  }

  final requests = <http.Request>[];
  late final DiscourseApi transport;

  @override
  Future<void> editChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required String message,
    List<int> uploadIds = const [],
    String? clientId,
  }) => ChatApiClient(transport).editChatMessage(
    siteUrl: siteUrl,
    apiKey: apiKey,
    channelId: channelId,
    messageId: messageId,
    message: message,
    uploadIds: uploadIds,
    clientId: clientId,
  );
}
