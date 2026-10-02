import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
  canDeleteOthers: true,
  membership: ChatMembership(following: true),
);
const _message = ChatMessage(
  id: 7,
  channelId: 9,
  raw: 'A message to moderate',
  cooked: '<p>A message to moderate</p>',
  author: ChatMessageAuthor(id: 3, username: 'sam'),
);

enum _Operation { unchanged, failedReconnect, failedDisconnect, reconnect }

enum _Timing { beforeClick, afterClick, afterRepaint }

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          null,
        ),
  );
  for (final operation in _Operation.values) {
    for (final timing in _Timing.values) {
      testWidgets(
        'Native Chat Delete ${operation.name} ${timing.name} owns its menu',
        (tester) async {
          final fixture = await _openChannel(tester);
          final focus = find.byKey(const ValueKey('chat-message-actions-7'));
          await _openMenu(tester);
          final owner = tester.state(focus);
          final action = find.byKey(const ValueKey('chat-message-delete-7'));
          expect(action, findsOneWidget);
          expect(
            tester.widget(action),
            defaultTargetPlatform == TargetPlatform.macOS
                ? isA<DDropdownMenuItem>()
                : isA<DButton>(),
          );
          final lease = fixture.shell.chat.captureSession(_site);
          if (timing == _Timing.afterClick) {
            await tester.tap(action);
            // Both Native dismissal paths defer dispatch until a later frame.
            expect(fixture.api.requests, isEmpty);
          }
          await _transition(tester, fixture, operation);
          expect(lease.isCurrent, operation == _Operation.unchanged);
          expect(tester.state(focus), same(owner));
          if (timing == _Timing.afterRepaint) {
            await _pump(tester);
            if (operation != _Operation.reconnect) {
              expect(tester.state(focus), same(owner));
              expect(action, findsOneWidget);
            }
          }
          if (timing != _Timing.afterClick && action.evaluate().isNotEmpty) {
            await tester.tap(action);
          }
          await _pump(tester);
          if (operation == _Operation.unchanged) {
            _expectDelete(fixture.api.requests.single, 'old-key');
          } else {
            expect(fixture.api.requests, isEmpty);
            expect(fixture.shell.chat.message(_site, 7)!.isDeleted, isFalse);
            // A freshly opened menu is authorized for the restored/new user.
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await _pump(tester);
            expect(fixture.shell.openChatChannel(9), isTrue);
            await _pump(tester);
            await _openMenu(tester);
            await tester.tap(action);
            await _pump(tester);
            _expectDelete(
              fixture.api.requests.single,
              operation == _Operation.reconnect ? 'replacement-key' : 'old-key',
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
    }
  }
}

void _expectDelete(http.Request request, String key) {
  expect(request.method, 'DELETE');
  expect(request.url, Uri.parse('$_site/chat/api/channels/9/messages/7.json'));
  expect(request.headers['User-Api-Key'], key);
  expect(jsonDecode(request.body), <String, Object?>{});
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<void> _openMenu(WidgetTester tester) async {
  final row = find.byKey(const ValueKey('chat-message-actions-7'));
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(row));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-message-more-actions-7')));
    await gesture.removePointer();
  } else {
    await tester.longPress(row);
  }
  await _pump(tester);
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
        return http.Response('{}', 200);
      }),
    );
  }
  late final DiscourseApi transport;
  final requests = <http.Request>[];

  @override
  Future<void> deleteChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) => ChatApiClient(transport).deleteChatMessage(
    siteUrl: siteUrl,
    apiKey: apiKey,
    channelId: channelId,
    messageId: messageId,
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
