import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_reactors.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
DiscourseUser _user(int id, String username) => DiscourseUser(
  id: id,
  username: username,
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);
final _original = _user(1, 'reader');
final _replacement = _user(2, 'replacement');
const _channel = ChatChannel(
  id: 9,
  title: 'Support',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
);
const _message = ChatMessage(
  id: 7,
  channelId: 9,
  raw: 'A message with reactions',
  cooked: '<p>A message with reactions</p>',
  author: ChatMessageAuthor(id: 3, username: 'sam'),
  reactions: [ChatReaction(emoji: 'clap', count: 1)],
);

enum _Operation { unchanged, failedReconnect, failedDisconnect, reconnect }

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final operation in _Operation.values) {
    testWidgets(
      'Native Chat reaction pill owns its rendered session after '
      '${operation.name} before repaint',
      (tester) async {
        final fixture = await _openChannel(tester);
        final shell = fixture.shell;
        final pill = find.byType(ReactionPill);
        final state = tester.state(pill);
        final lease = shell.chat.captureSession(_site);
        await _transition(tester, fixture, operation);
        expect(tester.state(pill), same(state));
        expect(lease.isCurrent, operation == _Operation.unchanged);
        // The old rendered control still exists until the next frame. The same
        // channel/message are already available to the replacement account.
        await tester.tap(find.byKey(const ValueKey('chat-reaction-clap')));
        await _pump(tester);
        final writes = fixture.api.requests.where((r) => r.method == 'PUT');
        if (operation == _Operation.unchanged) {
          expect(writes, hasLength(1));
          _expectReaction(writes.single, 'old-key', 'add');
        } else {
          expect(writes, isEmpty);
        }
        // Newly rendered controls may act for the current account.
        if (operation != _Operation.unchanged) {
          expect(shell.openChatChannel(9), isTrue);
          await _pump(tester);
        }
        await tester.tap(find.byKey(const ValueKey('chat-reaction-clap')));
        await _pump(tester);
        final currentWrites = fixture.api.requests.where(
          (r) => r.method == 'PUT',
        );
        expect(
          currentWrites,
          hasLength(operation == _Operation.unchanged ? 2 : 1),
        );
        _expectReaction(
          currentWrites.last,
          operation == _Operation.reconnect ? 'replacement-key' : 'old-key',
          operation == _Operation.unchanged ? 'remove' : 'add',
        );
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );

    testWidgets(
      'Native Chat reaction gesture retires across ${operation.name} repaint',
      (tester) async {
        final fixture = await _openChannel(tester);
        final pill = find.byType(ReactionPill);
        final state = tester.state(pill);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('chat-reaction-clap'))),
        );
        await _transition(tester, fixture, operation);
        await _pump(tester);
        await gesture.up();
        await _pump(tester);
        final writes = fixture.api.requests.where((r) => r.method == 'PUT');
        if (operation == _Operation.unchanged) {
          expect(tester.state(pill), same(state));
          expect(writes, hasLength(1));
          _expectReaction(writes.single, 'old-key', 'add');
        } else {
          expect(state.mounted, isFalse);
          expect(writes, isEmpty);
          expect(fixture.shell.openChatChannel(9), isTrue);
          await _pump(tester);
          await tester.tap(find.byKey(const ValueKey('chat-reaction-clap')));
          await _pump(tester);
          _expectReaction(
            fixture.api.requests.where((r) => r.method == 'PUT').single,
            operation == _Operation.reconnect ? 'replacement-key' : 'old-key',
            'add',
          );
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );

    testWidgets(
      'Native Chat reactor sheet owns its opening session after '
      '${operation.name}',
      (tester) async {
        final fixture = await _openChannel(tester);
        fixture.api.failReactors = true;
        await tester.longPress(
          find.byKey(const ValueKey('chat-reaction-clap')),
        );
        await _pump(tester);
        expect(find.byType(DSheetContent), findsOneWidget);
        expect(
          find.byKey(const ValueKey('reactor-list-retry')),
          findsOneWidget,
        );
        final sheet = tester.element(find.byType(DSheetContent));
        expect(fixture.api.requests, hasLength(1));
        expect(fixture.api.requests.single.method, 'GET');
        fixture.api.failReactors = false;
        await _transition(tester, fixture, operation);
        expect(sheet.mounted, isTrue);
        await tester.tap(find.byKey(const ValueKey('reactor-list-retry')));
        await _pump(tester);
        if (operation == _Operation.unchanged) {
          expect(fixture.api.requests, hasLength(2));
          expect(fixture.api.requests.last.headers['User-Api-Key'], 'old-key');
          expect(find.text('Sam Reactor'), findsOneWidget);
        } else {
          expect(fixture.api.requests, hasLength(1));
          expect(
            find.byKey(const ValueKey('reactor-list-retry')),
            findsNothing,
          );
          expect(find.text('Sam Reactor'), findsNothing);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _pump(tester);
        expect(fixture.shell.openChatChannel(9), isTrue);
        await _pump(tester);
        await tester.longPress(
          find.byKey(const ValueKey('chat-reaction-clap')),
        );
        await _pump(tester);
        expect(find.text('Sam Reactor'), findsOneWidget);
        expect(
          fixture.api.requests.last.headers['User-Api-Key'],
          operation == _Operation.reconnect ? 'replacement-key' : 'old-key',
        );
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}

void _expectReaction(http.Request request, String key, String action) {
  expect(request.method, 'PUT');
  expect(request.url, Uri.parse('$_site/chat/9/react/7.json'));
  expect(request.headers['User-Api-Key'], key);
  expect(jsonDecode(request.body), {'emoji': 'clap', 'react_action': action});
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<({ShellController shell, _Api api, _Store store})> _openChannel(
  WidgetTester tester,
) async {
  final site = instance('meta.discourse.org').copyWith(user: _original);
  final store = _Store([site]);
  final api = _Api();
  addTearDown(api.transport.close);
  await pumpShell(
    tester,
    defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
    instances: [site],
    store: store,
    api: api,
    authenticator: _Authenticator()..keys[_site] = 'old-key',
  );
  final shell = ShellScope.read(tester.element(primaryMainContent));
  await shell.chat.loadChannels(_site);
  expect(shell.openChatChannel(9), isTrue);
  await tester.pumpAndSettle();
  expect(find.byType(ReactionPill), findsOneWidget);
  return (shell: shell, api: api, store: store);
}

Future<void> _transition(
  WidgetTester tester,
  ({ShellController shell, _Api api, _Store store}) fixture,
  _Operation operation,
) async {
  if (operation == _Operation.unchanged) return;
  fixture.store.failSignedOut = operation != _Operation.reconnect;
  if (operation == _Operation.failedDisconnect) {
    expect(
      await tester.runAsync(() => fixture.shell.disconnectInstance(_site)),
      isFalse,
    );
  } else {
    await tester.runAsync(fixture.shell.connectCurrentInstance);
  }
  expect(
    fixture.shell.currentInstance?.user?.id,
    operation == _Operation.reconnect ? 2 : 1,
  );
  await fixture.shell.chat.loadChannels(_site);
  await fixture.shell.chat.openChannel(_site, 9, force: true);
  expect(fixture.shell.chat.message(_site, 7), isNotNull);
}

class _Api extends FakeDiscourseApi {
  _Api()
    : super(
        user: _original,
        feeds: const {'/latest.json': []},
        chatChannelsBySite: const {
          _site: ChatChannels(public: [_channel], direct: []),
        },
        chatChannelsById: const {9: _channel},
        chatMessagesByKey: const {
          '9': (
            messages: [_message],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
        },
      ) {
    accounts['replacement-key'] = _replacement;
    transport = DiscourseApi(
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          if (failReactors) return http.Response('{}', 500);
          return http.Response(
            jsonEncode({
              'users': [
                {
                  'id': 3,
                  'username': 'sam',
                  'name': 'Sam Reactor',
                  'reaction': 'clap',
                },
              ],
              'total_rows': 1,
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
  }
  late final DiscourseApi transport;
  final requests = <http.Request>[];
  bool failReactors = false;

  @override
  Future<void> setChatMessageReaction({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required String emoji,
    required ChatReactionAction action,
    String? clientId,
  }) => ChatApiClient(transport).setChatMessageReaction(
    siteUrl: siteUrl,
    apiKey: apiKey,
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
    action: action,
    clientId: clientId,
  );

  @override
  Future<ChatMessageReactors> chatMessageReactors({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? reaction,
    int limit = ChatMessageReactors.maximumPageSize,
    String? clientId,
  }) => ChatApiClient(transport).chatMessageReactors(
    siteUrl: siteUrl,
    apiKey: apiKey,
    channelId: channelId,
    messageId: messageId,
    reaction: reaction,
    limit: limit,
    clientId: clientId,
  );
}

class _Authenticator extends FakeAuthenticator {
  _Authenticator()
    : super(
        credentials: const UserApiCredentials(
          key: 'replacement-key',
          apiVersion: 4,
          push: false,
        ),
      );
}

class _Store extends FakeInstanceStore {
  _Store(super.instances);
  bool failSignedOut = false;
  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut && instances.any((site) => site.user == null)) {
      return Future.error(StateError('Account snapshot unavailable'));
    }
    return super.save(instances);
  }
}
