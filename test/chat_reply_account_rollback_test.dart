import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/blank_png.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
final _user = DiscourseUser(
  id: 1,
  username: 'staff',
  staff: true,
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);
const _channel = ChatChannel(
  id: 9,
  title: 'Support',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
  threadingEnabled: false,
);
const _upload = ComposerUploadResult(
  id: 31,
  originalFilename: 'selected.png',
  shortUrl: 'upload://selected',
  url: '$_site/uploads/selected.png',
);

enum _Operation { unchanged, failedReconnect, failedDisconnect }

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final operation in _Operation.values) {
    testWidgets(
      'Native Reply ${operation.name} uses the current account draft ref',
      (tester) async {
        final previousFiles = FileSelectorPlatform.instance;
        FileSelectorPlatform.instance = _Files();
        try {
          final site = instance('meta.discourse.org').copyWith(user: _user);
          final store = _FailingStore([site]);
          final api = _ReplyApi();
          addTearDown(api.transport.close);
          await pumpShell(
            tester,
            defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
            instances: [site],
            store: store,
            api: api,
            authenticator: FakeAuthenticator()..keys[_site] = 'key',
          );
          final shell = ShellScope.read(tester.element(primaryMainContent));
          await shell.chat.loadChannels(_site);
          expect(shell.openChatChannel(9), isTrue);
          await tester.pumpAndSettle();
          final composer = find.byType(ChatComposer);
          final composerState = tester.state(composer);
          await tester.enterText(_field, 'Previous account draft');
          await _tap(tester, find.byKey(const ValueKey('chat-composer-add')));
          await _tap(
            tester,
            find.byKey(const ValueKey('chat-composer-upload')),
          );
          expect(
            tester
                .widget<ComposerUploadQueue>(find.byType(ComposerUploadQueue))
                .composer
                .completedUploads
                .single
                .id,
            31,
          );
          await _reply(tester, 7);
          expect(find.text('Replying to @sam'), findsOneWidget);
          final lease = shell.chat.captureSession(_site);
          final rollsBack = operation != _Operation.unchanged;
          if (rollsBack) {
            store.failSignedOut = true;
            if (operation == _Operation.failedDisconnect) {
              expect(
                await tester.runAsync(() => shell.disconnectInstance(_site)),
                isFalse,
              );
            } else {
              await tester.runAsync(shell.connectCurrentInstance);
            }
            expect(shell.currentInstance?.user?.id, 1);
            expect(lease.isCurrent, isFalse);
            await shell.chat.loadChannels(_site);
            await shell.chat.openChannel(_site, 9, force: true);
            await _pump(tester);
            expect(tester.state(composer), same(composerState));
            expect(shell.chat.canSendMessage(_site, 9), isTrue);
            expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
            expect(find.byType(ComposerUploadQueue), findsNothing);
            expect(find.text('Replying to @sam'), findsNothing);
          }
          await _reply(tester, 8);
          final showedReply = find
              .text('Replying to @other')
              .evaluate()
              .isNotEmpty;
          await tester.enterText(_field, 'New reply');
          await _pump(tester);
          await _edit(tester, 11);
          expect(
            tester.widget<TextField>(_field).controller!.text,
            'Message 11',
          );
          await tester.enterText(_field, 'Independent edit');
          // Revalidation in this session must preserve a current edit. Cancel
          // then restores the reply and document from the current draft ref.
          await shell.chat.openChannel(_site, 9, force: true);
          await _pump(tester);
          expect(
            tester.widget<TextField>(_field).controller!.text,
            'Independent edit',
          );
          await _tap(
            tester,
            find.byKey(const ValueKey('chat-composer-edit-cancel')),
          );
          expect(
            tester.widget<TextField>(_field).controller!.text,
            'New reply',
          );

          await _tap(tester, find.byKey(const ValueKey('chat-composer-send')));
          final request = api.requests.single;
          expect(request.method, 'POST');
          expect(request.url, Uri.parse('$_site/chat/9.json'));
          expect(request.headers['User-Api-Key'], 'key');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['message'], 'New reply');
          expect(body['in_reply_to_id'], 8);
          expect(showedReply, isTrue);
          expect(body['thread_id'], isNull);
          expect(body['upload_ids'], rollsBack ? isNull : [31]);
          expect(find.text('Replying to @other'), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          FileSelectorPlatform.instance = previousFiles;
        }
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  }
}

Finder get _field => find
    .descendant(of: find.byType(ChatComposer), matching: find.byType(TextField))
    .first;

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _pump(tester);
}

Future<void> _reply(WidgetTester tester, int id) async {
  final tile = find.byWidgetPredicate(
    (widget) => widget is ChatMessageTile && widget.messageId == id,
  );
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    try {
      await tester.ensureVisible(tile);
      await _pump(tester);
      await pointer.moveTo(tester.getCenter(tile));
      await tester.pump();
      await pointer.moveBy(const Offset(1, 0));
      await tester.pump();
      final reply = find.descendant(
        of: tile,
        matching: find.byTooltip('Reply'),
      );
      if (reply.evaluate().isEmpty) {
        await tester.tap(
          find.descendant(
            of: tile,
            matching: find.byTooltip('More message actions'),
          ),
        );
        await _pump(tester);
        await tester.tap(find.text('Reply'));
      } else {
        await tester.tap(reply);
      }
      await _pump(tester);
    } finally {
      await pointer.removePointer();
    }
  } else {
    await tester.longPress(tile);
    await _pump(tester);
    await _tap(tester, find.text('Reply').last);
  }
}

Future<void> _edit(WidgetTester tester, int id) async {
  final tile = find.byWidgetPredicate(
    (widget) => widget is ChatMessageTile && widget.messageId == id,
  );
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    try {
      await tester.ensureVisible(tile);
      await _pump(tester);
      await pointer.moveTo(tester.getCenter(tile));
      await tester.pump();
      await pointer.moveBy(const Offset(1, 0));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: tile,
          matching: find.byTooltip('More message actions'),
        ),
      );
      await _pump(tester);
      await tester.tap(find.text('Edit'));
      await _pump(tester);
    } finally {
      await pointer.removePointer();
    }
  } else {
    await tester.longPress(tile);
    await _pump(tester);
    await _tap(tester, find.text('Edit').last);
  }
}

class _Files extends FileSelectorPlatform {
  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => [
    XFile.fromData(blankPng(width: 20, height: 20), path: 'selected.png'),
  ];
}

class _ReplyApi extends FakeDiscourseApi {
  _ReplyApi()
    : super(
        user: _user,
        feeds: const {'/latest.json': []},
        composerUploadResult: _upload,
        chatChannelsBySite: const {
          _site: ChatChannels(public: [_channel], direct: []),
        },
        chatChannelsById: const {9: _channel},
        chatMessagesByKey: {
          '9': (
            messages: [
              for (final (id, username) in [
                (7, 'sam'),
                (8, 'other'),
                (11, 'staff'),
              ])
                ChatMessage(
                  id: id,
                  channelId: 9,
                  raw: 'Message $id',
                  cooked: '<p>Message $id</p>',
                  author: ChatMessageAuthor(
                    id: username == 'staff' ? 1 : id,
                    username: username,
                  ),
                  createdAt: DateTime.utc(2026, 8, 11, 0, 0, id),
                ),
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
        return http.Response('{}', 200);
      }),
    );
  }
  late final DiscourseApi transport;
  final requests = <http.Request>[];

  @override
  Future<int?> sendChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required String message,
    List<int> uploadIds = const [],
    int? threadId,
    int? inReplyToId,
    String? stagedId,
    DateTime? clientCreatedAt,
    int? contextTopicId,
    List<int> contextPostIds = const [],
    String? clientId,
  }) => ChatApiClient(transport).sendChatMessage(
    siteUrl: siteUrl,
    apiKey: apiKey,
    channelId: channelId,
    message: message,
    uploadIds: uploadIds,
    threadId: threadId,
    inReplyToId: inReplyToId,
    stagedId: stagedId,
    clientCreatedAt: clientCreatedAt,
    contextTopicId: contextTopicId,
    contextPostIds: contextPostIds,
    clientId: clientId,
  );
}

class _FailingStore extends FakeInstanceStore {
  _FailingStore(super.instances);
  bool failSignedOut = false;
  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut && instances.any((site) => site.user == null)) {
      return Future.error(StateError('Account snapshot unavailable'));
    }
    return super.save(instances);
  }
}
