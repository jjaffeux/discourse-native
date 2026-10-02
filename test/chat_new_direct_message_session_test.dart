import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_direct_message_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/start_chatting_fixture.dart';

enum _Operation { unchanged, replacement, failedReconnect, failedDisconnect }

enum _Action { user, group }

final _replacement = DiscourseUser(
  id: 8,
  username: 'replacement',
  plugins: startChattingUser.plugins,
);
final _search = find.byKey(const ValueKey('chat-new-direct-message-search'));
final _createGroup = find.byKey(
  const ValueKey('chat-create-group-direct-message'),
);
Finder _user(String name) =>
    find.byKey(ValueKey('chat-new-direct-message-user-$name'));
Finder _form() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_ChatNewDirectMessageDialog',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final operation in _Operation.values) {
    for (final action in _Action.values) {
      testWidgets(
        'Start chatting ${action.name} ${operation == _Operation.unchanged ? 'uses its original session' : 'rejects ${operation.name} session replacement'}',
        (tester) async {
          final fixture = await _fixture(operation);
          addTearDown(fixture.shell.dispose);
          _size(tester);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(StartChattingFixture(shell: fixture.shell));
          await tester.tap(find.byKey(const ValueKey('open-start-chatting')));
          await tester.pumpAndSettle();
          if (action == _Action.group) {
            await tester.tap(
              find.byKey(const ValueKey('chat-new-group-direct-message')),
            );
            await tester.pumpAndSettle();
          }
          await _query(tester, 'maya');
          if (action == _Action.group) {
            await tester.tap(_user('maya'));
            await tester.pumpAndSettle();
            await _query(tester, 'theo');
            await tester.tap(_user('theo'));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('chat-new-group-member-u-2')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('chat-new-group-member-u-3')),
              findsOneWidget,
            );
          }
          final state = tester.state(_form());
          final oldSelection = action == _Action.user
              ? _item(tester, 'u-2').onSelected!
              : null;
          final oldSave = action == _Action.group
              ? tester.widget<DButton>(_createGroup).onPressed!
              : null;
          final lease = fixture.shell.chat.captureSession(startChattingSite);
          if (operation != _Operation.unchanged) {
            if (operation == _Operation.failedDisconnect) {
              fixture.store.failSignedOut = true;
              expect(
                await fixture.shell.disconnectInstance(startChattingSite),
                isFalse,
              );
            } else {
              await fixture.shell.connectCurrentInstance();
            }
            expect(lease.isCurrent, isFalse);
            expect(
              fixture.shell.currentInstance?.user?.id,
              operation == _Operation.replacement
                  ? _replacement.id
                  : startChattingUser.id,
            );
            expect(
              fixture.auth.keys[startChattingSite],
              operation == _Operation.replacement
                  ? 'replacement-key'
                  : 'fixture-key',
            );
            // Fresh authorized channels must not make the old modal's recipients
            // belong to this newly acquired account session.
            await fixture.shell.chat.loadChannels(startChattingSite);
            await tester.pumpAndSettle();
            expect(tester.state(_form()), same(state));
          }
          await tester.tap(
            action == _Action.user ? _user('maya') : _createGroup,
          );
          await tester.pumpAndSettle();
          if (operation == _Operation.unchanged) {
            expect(fixture.api.creationKeys, ['fixture-key']);
            expect(
              fixture.api.directMessageChannelRequests.single.usernames,
              action == _Action.user ? ['maya'] : ['maya', 'theo'],
            );
            expect(_form(), findsNothing);
          } else {
            oldSelection?.call('u-2');
            oldSave?.call();
            await tester.pumpAndSettle();
            expect(fixture.api.creationKeys, isEmpty);
            expect(fixture.api.directMessageChannelRequests, isEmpty);
            expect(_form(), findsOneWidget);
            expect(
              tester.widget<DCommandInput<String>>(_search).enabled,
              isFalse,
            );
            expect(
              find.text(
                'Your connection changed. Reopen the action and try again.',
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.macOS,
          TargetPlatform.iOS,
        }),
      );
    }
  }

  for (final pending in ['search', 'creation']) {
    testWidgets(
      'Start chatting retires a pending $pending after replacement',
      (tester) async {
        final fixture = await _fixture(_Operation.replacement);
        addTearDown(fixture.shell.dispose);
        _size(tester);
        await tester.pumpWidget(StartChattingFixture(shell: fixture.shell));
        await tester.tap(find.byKey(const ValueKey('open-start-chatting')));
        await tester.pumpAndSettle();
        if (pending == 'search') {
          fixture.api.pendingSearches['maya'] = Completer();
          await tester.enterText(_search, 'maya');
          await tester.pump(const Duration(milliseconds: 350));
        } else {
          await _query(tester, 'maya');
          fixture.api.creationGate = Completer<void>();
          await tester.tap(_user('maya'));
          await tester.pumpAndSettle();
          expect(fixture.api.creationKeys, ['fixture-key']);
        }
        final state = tester.state(_form());
        await fixture.shell.connectCurrentInstance();
        await fixture.shell.chat.loadChannels(startChattingSite);
        await tester.pumpAndSettle();
        final route = fixture.shell.currentContent?.id;
        if (pending == 'search') {
          fixture.api.pendingSearches['maya']!.complete(
            ChatDirectMessageSearchResults([startChattingPeople.first]),
          );
        } else {
          fixture.api.creationGate!.complete();
        }
        await tester.pumpAndSettle();
        expect(tester.state(_form()), same(state));
        expect(find.text('Searching…'), findsNothing);
        expect(find.text('Opening conversation…'), findsNothing);
        expect(
          find.text(
            'Your connection changed. Reopen the action and try again.',
          ),
          findsOneWidget,
        );
        expect(fixture.shell.currentContent?.id, route);
        final searchCount = fixture.api.chatDirectMessageSearchRequests.length;
        tester
            .widget<DCommand<String>>(find.byType(DCommand<String>))
            .onQueryChanged!('theo');
        await tester.pump(const Duration(milliseconds: 350));
        expect(fixture.api.chatDirectMessageSearchRequests.length, searchCount);
        if (pending == 'search') {
          expect(_user('maya'), findsNothing);
          expect(fixture.api.creationKeys, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      }),
    );
  }
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = defaultTargetPlatform == TargetPlatform.iOS
      ? const Size(390, 844)
      : const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

DCommandItem<String> _item(WidgetTester tester, String value) => tester
    .widget<DCommandList<String>>(
      find.byKey(const ValueKey('chat-new-direct-message-results')),
    )
    .children
    .whereType<DCommandGroup<String>>()
    .expand((group) => group.items)
    .singleWhere((item) => item.value == value);

Future<void> _query(WidgetTester tester, String query) async {
  await tester.enterText(_search, query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<({ShellController shell, _Api api, _Authenticator auth, _Store store})>
_fixture(_Operation operation) async {
  final api = _Api();
  api.accounts['fixture-key'] = startChattingUser;
  api.accounts['replacement-key'] = _replacement;
  final auth = _Authenticator(
    failPersistence: operation == _Operation.failedReconnect,
  )..keys[startChattingSite] = 'fixture-key';
  final store = _Store([
    instance('chat-review.invalid').copyWith(
      user: startChattingUser,
      config: SiteConfig(
        plugins: PluginData.none.withValue(
          chatSettingsDataKey,
          const ChatSettings(maximumDirectMessageUsers: 10),
        ),
      ),
    ),
  ]);
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: store,
    api: api,
    authenticator: auth,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  await shell.load();
  await shell.chat.loadChannels(startChattingSite);
  return (shell: shell, api: api, auth: auth, store: store);
}

class _Api extends StartChattingApi {
  final creationKeys = <String>[];
  @override
  Future<ChatChannel> createChatDirectMessageChannel({
    required String siteUrl,
    required String apiKey,
    required List<String> usernames,
    List<String> groups = const [],
    String? name,
    bool upsert = false,
    String? clientId,
  }) {
    creationKeys.add(apiKey);
    return super.createChatDirectMessageChannel(
      siteUrl: siteUrl,
      apiKey: apiKey,
      usernames: usernames,
      groups: groups,
      name: name,
      upsert: upsert,
      clientId: clientId,
    );
  }
}

class _Authenticator extends FakeAuthenticator {
  _Authenticator({required this.failPersistence})
    : super(
        credentials: const UserApiCredentials(
          key: 'replacement-key',
          apiVersion: 4,
          push: false,
        ),
      );
  final bool failPersistence;
  @override
  Future<void> persistCredentials(
    String siteUrl,
    UserApiCredentials credentials,
  ) async {
    if (failPersistence) throw StateError('Keychain write failed');
    await super.persistCredentials(siteUrl, credentials);
  }
}

class _Store extends FakeInstanceStore {
  _Store(super.instances);
  bool failSignedOut = false;
  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut &&
        instances.any(
          (site) => site.url == startChattingSite && site.user == null,
        )) {
      return Future.error(StateError('Account snapshot storage unavailable'));
    }
    return super.save(instances);
  }
}
