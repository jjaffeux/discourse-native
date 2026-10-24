import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart'
    show PluginSiteLease, WriteException, WriteFailure;
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_direct_message_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_new_direct_message_session.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/start_chatting_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sender does not consume another recipient slot', () async {
    final (editor, _, api) = await _fixture(maximum: 2);
    expect(editor.startGroup(editor.revision), isTrue);
    const self = ChatDirectMessageUser(
      identifier: 'u-7',
      matchQuality: 1,
      enabled: true,
      username: 'reader',
    );
    await editor.select(self, editor.revision);
    await editor.select(startChattingPeople.first, editor.revision);
    expect(editor.membersCount, 1);
    await editor.select(startChattingPeople[1], editor.revision);
    expect(editor.members, [self, ...startChattingPeople.take(2)]);
    expect(editor.membersCount, 2);
    expect(editor.error, isNull);
    expect(await editor.createGroup('Within the limit'), isNotNull);
    expect(api.directMessageChannelRequests.single.usernames, [
      'reader',
      'maya',
      'theo',
    ]);
  });

  for (final self in [
    const ChatDirectMessageUser(
      identifier: 'u-7',
      matchQuality: 1,
      enabled: true,
      username: 'renamed-reader',
    ),
    const ChatDirectMessageUser(
      identifier: 'u-reader',
      matchQuality: 1,
      enabled: true,
      username: 'READER',
    ),
  ]) {
    test('sender-only group recognizes ${self.identifier}', () async {
      final (editor, _, api) = await _fixture(maximum: 2);
      expect(editor.startGroup(editor.revision), isTrue);
      await editor.select(self, editor.revision);
      expect(editor.members, [self]);
      expect(editor.membersCount, 0);
      expect(await editor.createGroup('Just me'), isNotNull);
      expect(api.directMessageChannelRequests.single.usernames, [
        self.username,
      ]);
    });
  }

  test(
    'canonical recipient ID overrides the captured sender username',
    () async {
      final (editor, _, api) = await _fixture(maximum: 2);
      const namesake = ChatDirectMessageUser(
        identifier: 'u-8',
        matchQuality: 1,
        enabled: true,
        username: 'reader',
      );
      expect(editor.startGroup(editor.revision), isTrue);
      await editor.select(namesake, editor.revision);
      expect(editor.membersCount, 1);
      await editor.select(startChattingPeople.first, editor.revision);
      expect(editor.membersCount, 2);
      expect(editor.canAddMember(startChattingPeople[1]), isFalse);
      await editor.select(startChattingPeople[1], editor.revision);
      expect(editor.members, [namesake, startChattingPeople.first]);
      expect(await editor.createGroup('Distinct account'), isNotNull);
      expect(api.directMessageChannelRequests.single.usernames, [
        'reader',
        'maya',
      ]);
    },
  );

  test('ordinary recipients still enforce the other-user limit', () async {
    final (editor, _, api) = await _fixture(maximum: 2);
    expect(editor.startGroup(editor.revision), isTrue);
    for (final person in startChattingPeople.take(2)) {
      await editor.select(person, editor.revision);
    }
    expect(editor.membersCount, 2);
    expect(editor.canAddMember(startChattingPeople.first), isTrue);
    await editor.select(startChattingPeople.first, editor.revision);
    expect(editor.members, startChattingPeople.take(2));
    expect(editor.canAddMember(startChattingPeople.last), isFalse);
    await editor.select(startChattingPeople.last, editor.revision);
    expect(editor.members, startChattingPeople.take(2));
    expect(editor.error, 'A group chat can include up to 2 people.');
    expect(await editor.createGroup('Within the limit'), isNotNull);
    expect(api.directMessageChannelRequests.single.usernames, ['maya', 'theo']);
  });

  test('explicit recipients count distinct normalized usernames', () async {
    final (editor, _, api) = await _fixture(maximum: 2);
    const duplicate = ChatDirectMessageUser(
      identifier: 'u-maya',
      matchQuality: 1,
      enabled: true,
      username: 'MAYA',
    );
    expect(editor.startGroup(editor.revision), isTrue);
    await editor.select(startChattingPeople.first, editor.revision);
    await editor.select(startChattingPeople[1], editor.revision);
    expect(editor.canAddMember(duplicate), isTrue);
    await editor.select(duplicate, editor.revision);
    expect(editor.membersCount, 2);
    expect(editor.canAddMember(startChattingPeople.last), isFalse);
    expect(await editor.createGroup('Distinct recipients'), isNotNull);
    expect(api.directMessageChannelRequests.single.usernames, [
      'maya',
      'theo',
      'MAYA',
    ]);
  });

  test('retained count stays bound to the sender after replacement', () async {
    final (editor, shell, api) = await _fixture(maximum: 2);
    const self = ChatDirectMessageUser(
      identifier: 'u-7',
      matchQuality: 1,
      enabled: true,
      username: 'reader',
    );
    expect(editor.startGroup(editor.revision), isTrue);
    await editor.select(self, editor.revision);
    api.accounts['api-key'] = DiscourseUser(
      id: 2,
      username: 'maya',
      plugins: startChattingUser.plugins,
    );
    await shell.connectCurrentInstance();
    expect(shell.currentUserFor(startChattingSite)?.username, 'maya');
    expect(editor.members, [self]);
    expect(editor.membersCount, 0);
    expect(await editor.createGroup('Retired'), isNull);
    expect(api.directMessageChannelRequests, isEmpty);
    expect(
      editor.error,
      'Your connection changed. Reopen the action and try again.',
    );
  });

  test('group server refusal retains recipients and permits retry', () async {
    final api = _RefusingApi();
    final (editor, _, _) = await _fixture(maximum: 2, api: api);
    expect(editor.startGroup(editor.revision), isTrue);
    await editor.select(startChattingPeople.first, editor.revision);
    expect(await editor.createGroup('Refused'), isNull);
    expect(editor.opening, isFalse);
    expect(editor.members, [startChattingPeople.first]);
    expect(editor.error, 'The server rejected these recipients.');
    api.refuse = false;
    expect(await editor.createGroup('Retry'), isNotNull);
    expect(api.directMessageChannelRequests, hasLength(2));
    expect(api.directMessageChannelRequests.last.usernames, ['maya']);
  });

  test(
    'typing rejects retained rows before debounce and ignores old answers',
    () async {
      final (editor, _, api) = await _fixture();
      final recent = editor.results.first;
      final oldRevision = editor.revision;
      api.pendingSearches['maya'] = Completer();
      editor.changeQuery(' maya ');
      expect(editor.searchText, ' maya ');
      expect(editor.searching, isTrue);
      expect(editor.results, isEmpty);
      expect(await editor.select(recent, oldRevision), isNull);
      expect(editor.startGroup(oldRevision), isFalse);
      expect(api.chatDirectMessageSearchRequests, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(api.chatDirectMessageSearchRequests.single.term, 'maya');
      expect(api.chatDirectMessageSearchRequests.single.includeGroups, isTrue);
      expect(
        api.chatDirectMessageSearchRequests.single.includeDirectMessageChannels,
        isTrue,
      );
      expect(
        api.chatDirectMessageSearchRequests.single.includeCategoryChannels,
        isTrue,
      );
      editor.changeQuery('theo');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(editor.results.single, startChattingPeople[1]);
      api.pendingSearches['maya']!.complete(
        ChatDirectMessageSearchResults([startChattingPeople.first]),
      );
      await pumpEventQueue();
      expect(editor.results.single, startChattingPeople[1]);
      expect(api.directMessageChannelRequests, isEmpty);
    },
  );

  test(
    'direct to group retains recipients across queries and enforces expanded counts',
    () async {
      final (editor, _, api) = await _fixture(maximum: 3);
      await editor.select(startChattingGroup, editor.revision);
      expect(editor.composingGroup, isTrue);
      expect(editor.members, [startChattingGroup]);
      expect(editor.membersCount, 3);
      final selected = editor.members;
      expect(() => selected.clear(), throwsUnsupportedError);
      editor.changeQuery('maya');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(editor.members, selected);
      expect(
        api.chatDirectMessageSearchRequests.single.includeDirectMessageChannels,
        isFalse,
      );
      expect(
        api.chatDirectMessageSearchRequests.single.includeCategoryChannels,
        isFalse,
      );
      await editor.select(startChattingPeople.first, editor.revision);
      expect(editor.members, [startChattingGroup]);
      expect(editor.error, isNotNull);
      editor.removeMember(startChattingGroup);
      await editor.select(startChattingPeople.first, editor.revision);
      expect(editor.members, [startChattingPeople.first]);
      expect(editor.searchText, isEmpty);
      expect(editor.results, isEmpty);
      await editor.select(startChattingPeople.first, editor.revision);
      expect(editor.members, hasLength(1));
      expect(editor.cancelGroup(), isTrue);
      expect(editor.composingGroup, isFalse);
      expect(editor.members, isEmpty);
      expect(editor.results.whereType<ChatDirectMessageChannel>(), isNotEmpty);
      expect(selected, [startChattingGroup]);
    },
  );

  test(
    'group opening snapshots recipients and navigation failure retains published creation',
    () async {
      final (editor, shell, api) = await _fixture();
      expect(editor.startGroup(editor.revision), isTrue);
      await editor.select(startChattingPeople.first, editor.revision);
      api.creationGate = Completer();
      final pending = editor.createGroup('Design review');
      await pumpEventQueue();
      expect(editor.opening, isTrue);
      editor.changeQuery('theo');
      editor.removeMember(startChattingPeople.first);
      expect(editor.cancelGroup(), isFalse);
      expect(await editor.createGroup('duplicate'), isNull);
      expect(editor.members, [startChattingPeople.first]);
      final request = api.directMessageChannelRequests.single;
      expect(request.usernames, ['maya']);
      expect(request.name, 'Design review');
      expect(request.upsert, isFalse);
      api.creationGate!.complete();
      final destination = (await pending)!;
      expect(destination.requiresCurrentRoute, isTrue);
      final channel = shell.chat.channel(
        startChattingSite,
        destination.channelId!,
      );
      expect(channel, isNotNull);
      editor.navigationFailed(destination);
      expect(editor.opening, isFalse);
      expect(editor.error, 'This conversation is no longer available.');
      expect(editor.members, [startChattingPeople.first]);
      expect(
        shell.chat.channel(startChattingSite, destination.channelId!),
        same(channel),
      );
      api.creationGate = Completer();
      final retry = editor.createGroup('Retry');
      editor.navigationFailed(destination);
      expect(editor.opening, isTrue);
      api.creationGate!.complete();
      expect(await retry, isNotNull);
    },
  );

  test('failed direct opening keeps results available for retry', () async {
    final (editor, _, api) = await _fixture();
    editor.changeQuery('maya');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    api.failCreation = true;
    expect(await editor.select(editor.results.single, editor.revision), isNull);
    expect(editor.opening, isFalse);
    expect(editor.error, 'Could not start this chat.');
    expect(editor.results.single, startChattingPeople.first);
    api.failCreation = false;
    final destination = await editor.select(
      editor.results.single,
      editor.revision,
    );
    expect(destination, isNotNull);
    expect(api.directMessageChannelRequests, hasLength(2));
  });

  test(
    'retirement rejects pending search and every editing transition',
    () async {
      final (editor, shell, api) = await _fixture();
      final recent = editor.results.first;
      api.pendingSearches['maya'] = Completer();
      editor.changeQuery('maya');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await shell.disconnectInstance(startChattingSite);
      final retiredRevision = editor.revision;
      api.pendingSearches['maya']!.complete(
        ChatDirectMessageSearchResults([startChattingPeople.first]),
      );
      await pumpEventQueue();
      expect(editor.searching, isFalse);
      expect(editor.opening, isFalse);
      expect(editor.results, isEmpty);
      expect(
        editor.error,
        'Your connection changed. Reopen the action and try again.',
      );
      editor.changeQuery('theo');
      expect(editor.startGroup(retiredRevision), isFalse);
      expect(editor.cancelGroup(), isFalse);
      expect(await editor.select(recent, retiredRevision), isNull);
      expect(await editor.createGroup('retired'), isNull);
      expect(editor.revision, retiredRevision);
      expect(api.directMessageChannelRequests, isEmpty);
    },
  );

  test(
    'disposing during creation leaves publication to the directory',
    () async {
      final (_, shell, api) = await _fixture();
      final editor = ChatNewDirectMessageSession(
        chat: shell.chat,
        siteUrl: startChattingSite,
        lease: shell.chat.captureSession(startChattingSite),
      );
      editor.startGroup(editor.revision);
      await editor.select(startChattingPeople.first, editor.revision);
      expect(shell.chat.channel(startChattingSite, 59), isNull);
      api.creationGate = Completer();
      final pending = editor.createGroup('Created after dismissal');
      await pumpEventQueue();
      var notifications = 0;
      editor.addListener(() => notifications++);
      editor.dispose();
      api.creationGate!.complete();
      expect(await pending, isNull);
      expect(notifications, 0);
      expect(shell.chat.channel(startChattingSite, 59), isNotNull);
    },
  );

  test('retirement during opening notification prevents dispatch', () async {
    final (_, shell, api) = await _fixture();
    final lease = _MutableLease();
    final editor = ChatNewDirectMessageSession(
      chat: shell.chat,
      siteUrl: startChattingSite,
      lease: lease,
    );
    addTearDown(editor.dispose);
    editor.addListener(() {
      if (editor.opening) lease.isCurrent = false;
    });
    expect(
      await editor.select(startChattingPeople.first, editor.revision),
      isNull,
    );
    expect(editor.opening, isFalse);
    expect(api.directMessageChannelRequests, isEmpty);
  });

  for (final maximum in [0, 1]) {
    for (final staff in [false, true]) {
      test(
        'staff=$staff preserves group admission at maximum $maximum',
        () async {
          final (editor, _, api) = await _fixture(
            maximum: maximum,
            staff: staff,
          );
          expect(editor.canUseGroupChat, staff);
          await editor.select(startChattingGroup, editor.revision);
          expect(editor.composingGroup, staff);
          expect(editor.membersCount, staff ? 3 : 0);
          if (staff) {
            await editor.select(startChattingPeople.first, editor.revision);
            expect(editor.membersCount, 4);
            final destination = await editor.createGroup('Staff chat');
            expect(destination, isNotNull);
            final request = api.directMessageChannelRequests.single;
            expect(request.usernames, ['maya']);
            expect(request.groups, ['design']);
          } else {
            expect(api.directMessageChannelRequests, isEmpty);
          }
        },
      );
    }
  }
}

Future<(ChatNewDirectMessageSession, ShellController, StartChattingApi)>
_fixture({int maximum = 10, bool staff = false, StartChattingApi? api}) async {
  api ??= StartChattingApi();
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('chat-review.invalid').copyWith(
        user: DiscourseUser(
          id: 7,
          username: 'reader',
          staff: staff,
          plugins: startChattingUser.plugins,
        ),
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
  final editor = ChatNewDirectMessageSession(
    chat: shell.chat,
    siteUrl: startChattingSite,
    lease: shell.chat.captureSession(startChattingSite),
  );
  addTearDown(() async {
    editor.dispose();
    shell.dispose();
    await shell.pluginTeardown;
  });
  return (editor, shell, api);
}

final class _RefusingApi extends StartChattingApi {
  bool refuse = true;

  @override
  Future<ChatChannel> createChatDirectMessageChannel({
    required String siteUrl,
    required String apiKey,
    required List<String> usernames,
    List<String> groups = const [],
    String? name,
    bool upsert = false,
    String? clientId,
  }) async {
    final channel = await super.createChatDirectMessageChannel(
      siteUrl: siteUrl,
      apiKey: apiKey,
      usernames: usernames,
      groups: groups,
      name: name,
      upsert: upsert,
      clientId: clientId,
    );
    if (refuse) {
      throw const WriteException(
        WriteFailure.validation,
        errors: ['The server rejected these recipients.'],
      );
    }
    return channel;
  }
}

final class _MutableLease implements PluginSiteLease {
  @override
  bool isCurrent = true;

  @override
  bool commit(void Function() mutation) {
    if (!isCurrent) return false;
    mutation();
    return true;
  }
}
