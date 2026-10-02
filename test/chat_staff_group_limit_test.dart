import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/start_chatting_fixture.dart';

final _search = find.byKey(const ValueKey('chat-new-direct-message-search'));
final _newGroup = find.byKey(const ValueKey('chat-new-group-direct-message'));
final _createGroup = find.byKey(
  const ValueKey('chat-create-group-direct-message'),
);
Finder _user(String name) =>
    find.byKey(ValueKey('chat-new-direct-message-user-$name'));
final _design = find.byKey(
  const ValueKey('chat-new-direct-message-group-design'),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final maximum in [0, 1]) {
    for (final useGroup in [false, true]) {
      testWidgets(
        'staff can create a ${useGroup ? 'visible-group' : 'two-user'} DM at a configured limit of $maximum',
        (tester) async {
          final (shell, api) = await _fixture(staff: true, maximum: maximum);
          addTearDown(shell.dispose);
          addTearDown(api.transport.close);
          await _open(tester, shell);
          expect(_newGroup, findsOneWidget);
          if (useGroup) {
            await _query(tester, 'design');
            await tester.tap(_design);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('chat-new-group-member-g-8')),
              findsOneWidget,
            );
          } else {
            await tester.tap(_newGroup);
            await tester.pumpAndSettle();
            for (final name in ['maya', 'theo']) {
              await _query(tester, name);
              await tester.tap(_user(name));
              await tester.pumpAndSettle();
            }
            expect(
              find.byKey(const ValueKey('chat-new-group-member-u-2')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('chat-new-group-member-u-3')),
              findsOneWidget,
            );
          }
          expect(tester.widget<DButton>(_createGroup).onPressed, isNotNull);
          expect(
            find.text('${useGroup ? 3 : 2} of $maximum people selected'),
            findsNothing,
          );
          await tester.runAsync(() async {
            await tester.tap(_createGroup);
            await pumpEventQueue();
          });
          await tester.pumpAndSettle();
          expect(api.writes, hasLength(1));
          final request = api.writes.single;
          expect(request.method, 'POST');
          expect(request.url.path, '/chat/api/direct-message-channels.json');
          expect(request.headers['User-Api-Key'], 'fixture-key');
          expect(
            jsonDecode(request.body),
            useGroup
                ? {
                    'target_groups': ['design'],
                    'upsert': false,
                  }
                : {
                    'target_usernames': ['maya', 'theo'],
                    'upsert': false,
                  },
          );
          expect(shell.currentContent?.id, 'chat-c-59');
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.macOS,
          TargetPlatform.iOS,
        }),
      );
    }
    testWidgets(
      'nonstaff cannot start a group at a configured limit of $maximum',
      (tester) async {
        final (shell, api) = await _fixture(staff: false, maximum: maximum);
        addTearDown(shell.dispose);
        addTearDown(api.transport.close);
        await _open(tester, shell);
        expect(_newGroup, findsNothing);
        await _query(tester, 'design');
        expect(api.chatDirectMessageSearchRequests.last.includeGroups, isFalse);
        expect(_design, findsNothing);
        expect(api.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets(
    'nonstaff still cannot add people above its group member limit',
    (tester) async {
      final (shell, api) = await _fixture(staff: false, maximum: 2);
      addTearDown(shell.dispose);
      addTearDown(api.transport.close);
      await _open(tester, shell);
      await _query(tester, 'design');
      await tester.tap(_design);
      await tester.pumpAndSettle();
      expect(
        find.text('A group chat can include up to 2 people.'),
        findsOneWidget,
      );
      expect(_createGroup, findsNothing);
      await tester.enterText(_search, '');
      await tester.pumpAndSettle();
      await tester.tap(_newGroup);
      await tester.pumpAndSettle();
      for (final name in ['maya', 'theo']) {
        await _query(tester, name);
        await tester.tap(_user(name));
        await tester.pumpAndSettle();
      }
      await _query(tester, 'lena');
      await tester.tap(_user('lena'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-new-group-member-u-4')),
        findsNothing,
      );
      expect(find.text('2 of 2 people selected'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(_createGroup);
        await pumpEventQueue();
      });
      await tester.pumpAndSettle();
      expect(jsonDecode(api.writes.single.body), {
        'target_usernames': ['maya', 'theo'],
        'upsert': false,
      });
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
  );
}

Future<void> _open(WidgetTester tester, ShellController shell) async {
  tester.view.physicalSize = defaultTargetPlatform == TargetPlatform.iOS
      ? const Size(390, 844)
      : const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StartChattingFixture(shell: shell));
  await tester.tap(find.byKey(const ValueKey('open-start-chatting')));
  await tester.pumpAndSettle();
}

Future<void> _query(WidgetTester tester, String query) async {
  await tester.enterText(_search, query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<(ShellController, _WireApi)> _fixture({
  required bool staff,
  required int maximum,
}) async {
  final user = DiscourseUser(
    id: 7,
    username: 'reader',
    staff: staff,
    plugins: startChattingUser.plugins,
  );
  final api = _WireApi()..accounts['fixture-key'] = user;
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('chat-review.invalid').copyWith(
        user: user,
        config: SiteConfig(
          plugins: PluginData.none.withValue(
            chatSettingsDataKey,
            ChatSettings(maximumDirectMessageUsers: maximum),
          ),
        ),
      ),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[startChattingSite] = 'fixture-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  await shell.load();
  await shell.chat.loadChannels(startChattingSite);
  return (shell, api);
}

class _WireApi extends StartChattingApi {
  _WireApi() {
    transport = DiscourseApi(
      client: MockClient((request) async {
        writes.add(request);
        return http.Response(
          jsonEncode({
            'channel': {
              'id': 59,
              'title': 'Created group',
              'chatable_type': 'DirectMessage',
              'chatable': {'group': true, 'users': <Object?>[]},
              'current_user_membership': {'following': true},
            },
          }),
          200,
        );
      }),
    );
  }
  late final DiscourseApi transport;
  final writes = <http.Request>[];
  @override
  Future<ChatChannel> createChatDirectMessageChannel({
    required String siteUrl,
    required String apiKey,
    required List<String> usernames,
    List<String> groups = const [],
    String? name,
    bool upsert = false,
    String? clientId,
  }) => ChatApiClient(transport).createChatDirectMessageChannel(
    siteUrl: siteUrl,
    apiKey: apiKey,
    usernames: usernames,
    groups: groups,
    name: name,
    upsert: upsert,
    clientId: clientId,
  );
}
