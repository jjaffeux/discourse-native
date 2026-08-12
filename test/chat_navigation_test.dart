import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/open_link.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const String _site = 'https://meta.discourse.org';
const String _otherSite = 'https://other.example';
const DiscourseUser _user = DiscourseUser(
  id: 7,
  username: 'reader',
  name: 'Reader',
);

ChatChannel _channel(int id, {String title = 'Support'}) => ChatChannel(
  id: id,
  title: title,
  kind: ChatChannelKind.category,
  membership: const ChatMembership(following: true),
  tracking: const ChatTracking(),
  threadingEnabled: true,
);

ChatThread _thread(int channelId, int threadId) => ChatThread(
  id: threadId,
  channelId: channelId,
  status: 'open',
  replyCount: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShellController shell;
  late FakeDiscourseApi api;

  setUp(() async {
    api = FakeDiscourseApi(
      user: _user,
      chatNotificationList: const [
        DiscourseNotification(
          id: 51,
          kind: NotificationKind.chatWatchedThread,
          actor: 'sam',
          title: 'Support thread',
          path: '/chat/c/-/9/t/3/44',
        ),
      ],
      feeds: const {'/latest.json': []},
      chatChannelsBySite: {
        _site: ChatChannels(public: [_channel(9)], direct: const []),
        _otherSite: ChatChannels(
          public: [_channel(12, title: 'Other support')],
          direct: const [],
        ),
      },
      chatThreadsByKey: {
        FakeDiscourseApi.chatThreadKey(9, 3): _thread(9, 3),
        FakeDiscourseApi.chatThreadKey(9, 4): _thread(9, 4),
        FakeDiscourseApi.chatThreadKey(12, 7): _thread(12, 7),
      },
    );
    final authenticator = FakeAuthenticator()
      ..keys[_site] = 'meta-key'
      ..keys[_otherSite] = 'other-key';
    shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: _user),
        instance('other.example').copyWith(user: _user),
      ]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      ownsApi: false,
    );
    addTearDown(shell.dispose);
    await shell.load();
  });

  test(
    'opens a thread route and hands its message to the mounted view',
    () async {
      expect(await shell.openChatUrl('$_site/chat/c/-/9/t/3/44'), isTrue);

      expect(shell.destinationId, 'chat-c-9');
      expect(shell.contentStack.map((route) => route.id), [
        'chat-c-9',
        'chat-c-9-t-3',
      ]);
      expect(shell.currentContent?.title, 'Thread');
      expect(shell.currentContent?.subtitle, 'Support');
      expect(shell.chatNavigation.value?.siteUrl, _site);
      expect(
        shell.chatNavigation.value?.route,
        ChatRoute.thread(channelId: 9, threadId: 3),
      );
      expect(shell.chatNavigation.value?.messageId, 44);
    },
  );

  test(
    'retargets the same route without adding a duplicate stack entry',
    () async {
      await shell.openChatUrl('$_site/chat/c/-/9/t/3/44');
      final stack = shell.contentStack;

      expect(await shell.openChatUrl('$_site/chat/c/-/9/t/3/45'), isTrue);

      expect(shell.contentStack, same(stack));
      expect(shell.chatNavigation.value?.messageId, 45);
    },
  );

  test('same-route Chat links reactivate compact content', () async {
    expect(await shell.openChatUrl('$_site/chat/c/-/9/t/3/44'), isTrue);
    shell.selectInstance(0);
    expect(shell.mobilePane, MobilePane.sidebar);

    expect(await shell.openChatUrl('$_site/chat/c/-/9/t/3/45'), isTrue);

    expect(shell.mobilePane, MobilePane.content);
    expect(shell.currentContent?.id, 'chat-c-9-t-3');
    expect(shell.chatNavigation.value?.messageId, 45);
  });

  test(
    'a superseded native Chat open cannot overwrite the latest intent',
    () async {
      final channelGate = Completer<void>();
      final gatedApi = FakeDiscourseApi(
        user: _user,
        feeds: const {'/latest.json': []},
        chatChannelGate: channelGate,
        chatChannelsBySite: {
          _site: ChatChannels(public: [_channel(9)]),
        },
      );
      final gated = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(user: _user),
        ]),
        api: gatedApi,
        authenticator: FakeAuthenticator()..keys[_site] = 'meta-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        ownsApi: false,
      );
      addTearDown(gated.dispose);
      await gated.load();

      final first = gated.openChatUrl('$_site/chat/c/-/9/44');
      expect(
        await gated.openChatUrl('https://unknown.example/chat/c/-/9'),
        isFalse,
      );
      channelGate.complete();

      expect(await first, isFalse);
      expect(gated.currentContent?.id, 'latest');
      expect(gated.chatNavigation.value, isNull);
    },
  );

  test('a different thread replaces the previous thread history', () async {
    await shell.openChatUrl('$_site/chat/c/-/9/t/3');
    await shell.openChatUrl('$_site/chat/c/-/9/t/4');

    expect(shell.contentStack.map((route) => route.id), [
      'chat-c-9',
      'chat-c-9-t-4',
    ]);
    expect(shell.handleBack(), isTrue);
    expect(shell.currentContent?.id, 'chat-c-9');
  });

  test('cross-site Chat links switch only after access is confirmed', () async {
    expect(await shell.openChatUrl('$_otherSite/chat/c/-/12/88'), isTrue);

    expect(shell.currentInstance?.url, _otherSite);
    expect(shell.currentContent?.id, 'chat-c-12');
    expect(shell.chatNavigation.value?.messageId, 88);
  });

  test(
    'unknown sites and channels retain browser fallback semantics',
    () async {
      expect(
        await shell.openChatUrl('https://unknown.example/chat/c/-/9'),
        isFalse,
      );
      expect(await shell.openChatUrl('$_otherSite/chat/c/-/99'), isFalse);

      expect(shell.currentInstance?.url, _site);
      expect(shell.currentContent?.id, 'latest');
      expect(shell.chatNavigation.value, isNull);
    },
  );

  test('an inaccessible thread retains browser fallback semantics', () async {
    expect(await shell.openChatUrl('$_site/chat/c/-/9/t/99/44'), isFalse);

    expect(shell.currentInstance?.url, _site);
    expect(shell.currentContent?.id, 'latest');
    expect(shell.chatNavigation.value, isNull);
  });

  test('a persisted thread route restores and hydrates its channel', () async {
    final restoredApi = FakeDiscourseApi(
      user: _user,
      feeds: const {'/latest.json': []},
      chatChannelsBySite: {
        _site: ChatChannels(public: [_channel(9)], direct: const []),
      },
    );
    final restored = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: _user),
      ]),
      api: restoredApi,
      authenticator: FakeAuthenticator()..keys[_site] = 'meta-key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore([
        ForumWorkspace(
          siteUrl: _site,
          accountIdentity: 'user:reader',
          tabs: [
            ForumTab(
              id: 'persisted-tab',
              rootDestinationId: 'chat-c-9',
              contentStack: const [
                ContentRoute(
                  id: 'chat-c-9',
                  title: 'Support',
                  icon: DIcons.comment,
                ),
                ContentRoute(
                  id: 'chat-c-9-t-3',
                  title: 'Thread',
                  icon: DIcons.comments,
                ),
              ],
            ),
          ],
          activeTabId: 'persisted-tab',
        ),
      ]),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      ownsApi: false,
    );
    addTearDown(restored.dispose);

    await restored.load();
    for (
      var attempt = 0;
      attempt < 20 && restored.chat.channel(_site, 9) == null;
      attempt++
    ) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(restored.currentContent?.id, 'chat-c-9-t-3');
    expect(restoredApi.chatChannelsRequested, contains(_site));
    expect(restored.chat.channel(_site, 9)?.title, 'Support');
  });

  testWidgets('generic openLink dispatches Chat before browser fallback', (
    tester,
  ) async {
    bool? opened;
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                opened = await openLink(context, '/chat/c/-/9/t/3/44');
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
    expect(shell.currentContent?.id, 'chat-c-9-t-3');
    expect(shell.chatNavigation.value?.messageId, 44);
  });

  testWidgets('a Chat notification opens natively before browser fallback', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          home: Scaffold(
            body: ChatNotificationsSection(
              siteUrl: _site,
              onOpened: () => opened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NotificationRow));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
    expect(api.markedRead, [51]);
    expect(shell.currentContent?.id, 'chat-c-9-t-3');
    expect(shell.chatNavigation.value?.messageId, 44);
  });

  test('imperative thread opening selects its owning site', () async {
    await shell.chat.loadChannels(_otherSite);

    shell.openChatThread(
      siteUrl: _otherSite,
      channelId: 12,
      threadId: 7,
      messageId: 91,
      focusComposer: true,
    );

    expect(shell.currentInstance?.url, _otherSite);
    expect(shell.contentStack.map((route) => route.id), [
      'chat-c-12',
      'chat-c-12-t-7',
    ]);
    expect(shell.chatNavigation.value?.messageId, 91);
    expect(shell.chatNavigation.value?.focusComposer, isTrue);
  });
}
