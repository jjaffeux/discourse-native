import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_blocks.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_blocks_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_contract.dart';
import 'package:discourse_native/src/plugins/chat/chat_pin.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_chat_message.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/native_ui_evidence.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _channel = ChatChannel(
  id: 9,
  title: 'Support',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
);
final _wire = <String, dynamic>{
  'id': 7,
  'chat_channel_id': 9,
  'cooked': '<p>Change the category?</p>',
  'user': {'id': -1201, 'username': 'helper'},
  'ai_llm_name': 'Model A',
  'blocks': [
    {
      'type': 'confirmation',
      'title': 'Move topic',
      'show_description': false,
      'cooked_question': '<p>Apply this change?</p>',
      'changes': [
        {
          'label': 'Category',
          'before': 'General',
          'after': 'Support',
          'after_color': '0088cc',
        },
      ],
      'parameters': [
        {'label': 'topic_id', 'value': '42'},
      ],
      'elements': [
        {
          'type': 'button',
          'action_id': 'approve-7',
          'text': {'text': 'Approve'},
          'style': 'primary',
        },
      ],
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('JetBrains Mono')
          ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf')))
        .load();
  });
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        ),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          null,
        ),
  );

  test(
    'blocks and optional metadata survive local projections and full records clear them',
    () {
      final codec = ChatMessageCodec([const AiChatMessageContribution()]);
      final original = codec.decode(_wire, _site);
      expect(original.blocks.single, isA<ChatConfirmationBlock>());
      expect(
        original.plugins.get(const AiChatMessageContribution().key)?.model,
        'Model A',
      );
      final projected = original
          .withPinned(true)
          .withReactions([])
          .withBookmark(null)
          .withThreadPreview(null)
          .withUserFlagStatus(0)
          .withFirstOfResults(true)
          .withPersonalizedStateOf(original, currentUserId: 1);
      expect(projected.blocks, original.blocks);
      expect(projected.plugins, original.plugins);
      final replaced = codec.decode({
        ..._wire,
        'blocks': null,
        'ai_llm_name': null,
      }, _site);
      expect(replaced.blocks, isEmpty);
      expect(replaced.plugins.isEmpty, isTrue);
      final omitted = Map<String, dynamic>.of(_wire)
        ..remove('blocks')
        ..remove('ai_llm_name');
      expect(codec.decode(omitted, _site).plugins.isEmpty, isTrue);
      expect(codec.decode(omitted, _site).blocks, isEmpty);
      expect(original, codec.decode(_wire, _site));
      expect(original.hashCode, codec.decode(_wire, _site).hashCode);
      expect(ChatMessage.fromJson(_wire, _site).plugins.isEmpty, isTrue);
      final pin = ChatPin.fromJson(
        {'id': 3, 'message': _wire},
        _site,
        decodeMessage: codec.decode,
      );
      expect(pin.message.plugins, original.plugins);
    },
  );

  test(
    'bot identity fallback only claims validated authors and preserves group flair',
    () {
      expect(
        ChatMessageAuthor.fromJson(const {
          'id': 0,
          'username': 'system',
        }, _site).isBot,
        isTrue,
      );
      expect(
        ChatMessageAuthor.fromJson(const {'username': 'unknown'}, _site).isBot,
        isFalse,
      );
      expect(ChatMessageAuthor.fromJson(null, _site).isBot, isFalse);
      expect(
        ChatMessageAuthor.fromJson(const {
          'id': -1201,
          'username': 'helper',
          'flair_group_id': 42,
          'flair_name': 'AI',
          'flair_url': 'discourse-ai',
        }, _site).flair?.url,
        'discourse-ai',
      );
    },
  );

  test(
    'unknown blocks and malformed elements leave ordinary message content readable',
    () {
      final message = ChatMessage.fromJson({
        ..._wire,
        'blocks': const <Object?>[
          {'type': 'future-block', 'elements': <Object?>[]},
          {
            'type': 'actions',
            'elements': [
              null,
              {'type': 'button'},
              {'type': 'future'},
            ],
          },
        ],
      }, _site);
      expect(message.cooked, '<p>Change the category?</p>');
      expect(message.blocks.single.elements, isEmpty);
    },
  );

  test(
    'transport sends only the selected server action and decodes installed metadata in pages',
    () async {
      final requests = <http.Request>[];
      final transport = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              request.method == 'POST'
                  ? <String, Object?>{
                      'interaction': {'id': 1},
                    }
                  : <String, Object?>{
                      'messages': [_wire],
                      'meta': <String, Object?>{},
                    },
            ),
            200,
          );
        }),
      );
      addTearDown(transport.close);
      final codec = ChatMessageCodec([const AiChatMessageContribution()]);
      final api = ChatApiClient(transport, decodeMessage: codec.decode);
      await api.createChatMessageInteraction(
        siteUrl: _site,
        apiKey: 'key',
        clientId: 'client',
        channelId: 9,
        messageId: 7,
        actionId: 'approve-7',
      );
      expect(
        requests.single.url.path,
        '/chat/api/channels/9/messages/7/interactions',
      );
      expect(jsonDecode(requests.single.body), {'action_id': 'approve-7'});
      final page = await api.chatMessages(
        siteUrl: _site,
        apiKey: 'key',
        channelId: 9,
      );
      expect(
        page.messages.single.plugins
            .get(const AiChatMessageContribution().key)
            ?.model,
        'Model A',
      );
    },
  );

  test(
    'interactions suppress overlapping clicks and disown account-replaced failures',
    () async {
      final api = _InteractionApi();
      final lifecycle = SiteLifecycle();
      final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
      final store = Store()
        ..put(_site, _channel)
        ..put(_site, ChatMessage.fromJson(_wire, _site));
      final chat = ChatController(
        api: api,
        requests: FakePluginRequestHost(
          credentials: credentials,
          lifecycle: lifecycle,
        ),
        store: store,
        currentUserFor: (_) => const DiscourseUser(id: 1, username: 'reader'),
      );
      addTearDown(chat.dispose);
      final first = chat.interactWithMessage(_site, 7, 'approve-7');
      expect(chat.messageInteractionPending(_site, 7), isTrue);
      final duplicate = await chat.interactWithMessage(_site, 7, 'approve-7');
      expect(duplicate, isNotNull);
      await Future<void>.delayed(Duration.zero);
      expect(api.calls, 1);
      expect(
        chat.message(_site, 7)!.blocks.single,
        isA<ChatConfirmationBlock>(),
      );
      lifecycle.invalidate(_site);
      api.pending.completeError(const WriteException(WriteFailure.forbidden));
      expect(await first, isNull);
      expect(chat.messageInteractionPending(_site, 7), isFalse);
      expect(api.calls, 1);
    },
  );

  for (final failed in [false, true]) {
    test(
      'a ${failed ? 'failed' : 'successful'} interaction keeps server state authoritative without replay',
      () async {
        final api = _InteractionApi();
        final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
        final store = Store()
          ..put(_site, _channel)
          ..put(_site, ChatMessage.fromJson(_wire, _site));
        final chat = ChatController(
          api: api,
          requests: FakePluginRequestHost(credentials: credentials),
          store: store,
          currentUserFor: (_) => const DiscourseUser(id: 1, username: 'reader'),
        );
        addTearDown(chat.dispose);
        expect(await chat.interactWithMessage(_site, 7, 'unknown'), isNotNull);
        expect(api.calls, 0);
        final result = chat.interactWithMessage(_site, 7, 'approve-7');
        await Future<void>.delayed(Duration.zero);
        if (failed) {
          api.pending.completeError(
            const WriteException(WriteFailure.forbidden),
          );
        } else {
          api.pending.complete();
        }
        expect(await result, failed ? isNotNull : isNull);
        expect(chat.messageInteractionPending(_site, 7), isFalse);
        expect(api.calls, 1);
        expect(
          (chat.message(_site, 7)!.blocks.single as ChatConfirmationBlock)
              .cookedStatus,
          isNull,
        );
      },
    );
  }

  for (final size in [phone, desktop]) {
    testWidgets(
      'confirmation ${size.width} renders changes and server status replaces its actions',
      (tester) async {
        await prepareNativeUiEvidence(tester);
        const user = DiscourseUser(id: 1, username: 'reader');
        final site = instance('meta.discourse.org').copyWith(user: user);
        final codec = ChatMessageCodec([const AiChatMessageContribution()]);
        final message = codec.decode(_wire, _site);
        final api = _InteractionApi(
          user: user,
          chatChannelsBySite: const {
            _site: ChatChannels(public: [_channel], direct: []),
          },
          chatMessagesByKey: {
            '9': (
              messages: [message],
              canLoadMorePast: false,
              canLoadMoreFuture: false,
              targetMessageId: null,
            ),
          },
        );
        await pumpShell(
          tester,
          size,
          instances: [site],
          api: api,
          authenticator: FakeAuthenticator.signedIn([site], site: api),
        );
        final shell = ShellScope.read(
          tester.element(find.byType(MainContent).first),
        );
        await shell.chat.loadChannels(_site);
        expect(shell.openChatChannel(9), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(ChatMessageBlocks), findsOneWidget);
        expect(find.text('Move topic'), findsOneWidget);
        expect(find.text('Model A'), findsOneWidget);
        expect(find.text('General'), findsOneWidget);
        expect(find.text('Approve'), findsOneWidget);
        final output = Platform.environment['NATIVE_UI_EVIDENCE_DIR'];
        if (output != null) {
          RenderObject? object = tester.renderObject(
            find.byType(ChatMessageBlocks),
          );
          while (object != null && object is! RenderRepaintBoundary) {
            object = object.parent;
          }
          if (object case final RenderRepaintBoundary boundary) {
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory(output)..createSync(recursive: true);
              await File(
                '${directory.path}/chat-confirmation-${size.width.toInt()}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
        expect(
          tester
              .widgetList<GroupFlairBadge>(find.byType(GroupFlairBadge))
              .any((badge) => badge.url == 'robot'),
          isTrue,
        );

        expect(renderedText('Change the category?'), findsNothing);
        expect(
          shell.chat.canInteractWithBlock(_site, message, 'approve-7'),
          isTrue,
        );
        await tester.tap(find.text('Approve'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(api.calls, 1);
        expect(api.chatReactionsSet, isEmpty);
        final action = find.ancestor(
          of: find.text('Approve'),
          matching: find.byType(DButton),
        );
        expect(tester.widget<DButton>(action).loading, isTrue);
        api.pending.complete();
        await tester.pumpAndSettle();

        final resolved = codec.decode({
          ..._wire,
          'blocks': [
            {
              ...(_wire['blocks'] as List).single as Map<String, dynamic>,
              'cooked_status': '<p>Approved by reader</p>',
            },
          ],
        }, _site);
        shell.chatRecords.put(_site, resolved);
        await tester.pumpAndSettle();
        expect(find.text('Approve'), findsNothing);
        expect(renderedText('Approved by reader'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _InteractionApi extends FakeDiscourseApi {
  _InteractionApi({
    super.user,
    super.chatChannelsBySite,
    super.chatMessagesByKey,
  });
  int calls = 0;
  final pending = Completer<void>();
  @override
  Future<void> createChatMessageInteraction({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required String actionId,
    String? clientId,
  }) {
    calls++;
    return pending.future;
  }
}
