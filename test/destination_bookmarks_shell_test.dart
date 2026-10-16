import 'dart:async';

import 'package:discourse_native/src/data/destination_bookmarks_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/destination_bookmark.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://forum.example';
const _page = ContentRoute(
  id: 'preferences',
  title: 'Preferences',
  icon: DIcons.gear,
);
const _category = ContentRoute(
  id: 'category-12',
  title: 'Support',
  icon: DIcons.folder,
  feedPath: '/c/support/12.json',
);
const _chat = ContentRoute(
  id: 'chat-c-9',
  title: 'Travel',
  icon: DIcons.comment,
);
const _channel = ChatChannel(
  id: 9,
  title: 'Travel',
  kind: ChatChannelKind.category,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'page and category reopen the exact typed root and hydrate in every panel',
    () async {
      final shell = await _shell();
      addTearDown(shell.dispose);
      shell.desktopTopicTabs = true;
      for (final route in [_page, _category, ContentRoute.allCategories()]) {
        expect(
          (await shell.destinationBookmarkAction(route)!.invoke()).saved,
          isTrue,
        );
        final saved = shell.destinationBookmarksFor(_site).first;
        for (final panel in [null, ForumPanel.main, ForumPanel.secondary]) {
          expect(
            await shell.openDestinationBookmark(_site, saved, panel: panel),
            isTrue,
          );
          expect(shell.currentContent, route);
          expect(shell.activeTab!.rootDestinationId, route.id);
        }
        expect(
          await shell.openDestinationBookmark(_site, saved, newTab: true),
          isTrue,
        );
        expect(shell.tabsForCurrentForum.last.currentContent, route);
        expect(shell.tabsForCurrentForum.last.rootDestinationId, route.id);
      }
      await pumpEventQueue();
      expect(shell.categoryFeedFor(_site).loaded, isTrue);
    },
  );

  test(
    'whole channel opens through plugin ownership without a thread or message anchor',
    () async {
      final shell = await _shell(
        api: FakeDiscourseApi(
          user: const DiscourseUser(username: 'reader'),
          chatChannelsBySite: const {
            _site: ChatChannels(public: [_channel]),
          },
        ),
      );
      addTearDown(shell.dispose);
      expect(
        (await shell.destinationBookmarkAction(_chat)!.invoke()).saved,
        isTrue,
      );
      final saved = shell.destinationBookmarksFor(_site).single;
      expect(await shell.openDestinationBookmark(_site, saved), isTrue);
      expect(shell.currentContent?.id, 'chat-c-9');
      expect(shell.currentContent?.postNumber, isNull);
      expect(shell.currentContent?.topicId, isNull);
    },
  );

  test(
    'disabled chat keeps its local bookmark but does not navigate',
    () async {
      final shell = await _shell(withPlugins: false);
      addTearDown(shell.dispose);
      await shell.destinationBookmarkAction(_chat)!.invoke();
      final before = shell.currentContent;
      expect(
        await shell.openDestinationBookmark(
          _site,
          shell.destinationBookmarksFor(_site).single,
        ),
        isFalse,
      );
      expect(shell.currentContent, before);
      expect(shell.destinationBookmarksFor(_site), hasLength(1));
    },
  );

  test('foreign URL resolution keeps forum ownership and label', () async {
    final shell = await _shell();
    addTearDown(shell.dispose);
    const url = 'https://other.example/c/support/12';
    final site = shell.destinationBookmarkSiteForUrl(url);
    final route = shell.destinationBookmarkRouteForUrl(
      url,
      title: 'Other support',
    )!;
    expect(site, 'https://other.example');
    await shell.destinationBookmarkAction(route, siteUrl: site)!.invoke();
    expect(shell.destinationBookmarksFor(_site), isEmpty);
    expect(
      shell.destinationBookmarksFor(site!).single.route.title,
      'Other support',
    );
    final sourceSite = shell.currentInstance!.url;
    expect(
      await shell.openDestinationRoute(route, siteUrl: site, newTab: true),
      TabOpenResult.opened,
    );
    expect(shell.currentInstance!.url, sourceSite);
    expect(shell.workspaceFor(site)!.tabs.last.currentContent, route);
    expect(
      await shell.openDestinationRoute(route, siteUrl: site),
      TabOpenResult.opened,
    );
    expect(shell.currentInstance!.url, site);
    expect(shell.currentContent, route);
    expect(
      shell
          .destinationBookmarkRouteForUrl(
            '$_site/chat/c/travel/9',
            title: 'Travel',
          )
          ?.title,
      'Travel',
    );
    expect(
      shell.destinationBookmarkRouteForUrl('$_site/chat/c/travel/9/123'),
      isNull,
    );
  });

  test(
    'captured actions and rows cannot cross a sign-out; saved owner is retained',
    () async {
      final store = DestinationBookmarksStore.memory();
      final shell = await _shell(store: store);
      addTearDown(shell.dispose);
      await shell.destinationBookmarkAction(_page)!.invoke();
      final saved = shell.destinationBookmarksFor(_site).single;
      final stale = shell.destinationBookmarkAction(_category)!;
      final account = shell.currentAccountIdentity!;
      expect(await shell.disconnectInstance(_site), isTrue);
      expect(shell.destinationBookmarksFor(_site), isEmpty);
      expect((await stale.invoke()).saved, isFalse);
      expect(await shell.openDestinationBookmark(_site, saved), isFalse);
      expect(store.entriesFor(_site, account).single.route, _page);
      expect(shell.destinationBookmarkAction(_category), isNull);
    },
  );

  test(
    'durable forum removal clears every local account, preserving other forums',
    () async {
      final store = DestinationBookmarksStore.memory();
      final shell = await _shell(store: store);
      addTearDown(shell.dispose);
      await shell.destinationBookmarkAction(_page)!.invoke();
      final account = shell.currentAccountIdentity!;
      await shell.disconnectInstance(_site);
      await store.set(
        _site,
        'user:another-reader',
        DestinationBookmark.fromRoute(_category)!,
        bookmarked: true,
      );
      await shell
          .destinationBookmarkAction(_chat, siteUrl: 'https://other.example')!
          .invoke();
      expect(await shell.removeInstance(shell.currentInstance!), isTrue);
      await store.flush();
      expect(store.entriesFor(_site, account), isEmpty);
      expect(store.entriesFor(_site, 'user:another-reader'), isEmpty);
      expect(
        shell.destinationBookmarksFor('https://other.example'),
        hasLength(1),
      );
    },
  );

  test(
    'pending whole-chat navigation stands down after account rotation',
    () async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        user: const DiscourseUser(username: 'reader'),
        chatChannelGate: gate,
        chatChannelsBySite: const {
          _site: ChatChannels(public: [_channel]),
        },
      );
      final shell = await _shell(api: api);
      addTearDown(shell.dispose);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await shell.destinationBookmarkAction(_chat)!.invoke();
      final opening = shell.openDestinationBookmark(
        _site,
        shell.destinationBookmarksFor(_site).single,
      );
      await pumpEventQueue();
      await shell.disconnectInstance(_site);
      final after = shell.currentContent;
      gate.complete();
      await opening;
      await pumpEventQueue();
      expect(shell.currentContent, after);
      expect(shell.currentContent?.id, isNot('chat-c-9'));
      expect(
        shell.pluginSession.require(chatControllerService).channel(_site, 9),
        isNull,
      );
    },
  );
}

Future<ShellController> _shell({
  FakeDiscourseApi? api,
  DestinationBookmarksStore? store,
  bool withPlugins = true,
}) async {
  const user = DiscourseUser(username: 'reader');
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('forum.example').copyWith(user: user),
      instance(
        'other.example',
      ).copyWith(user: const DiscourseUser(username: 'other')),
    ]),
    api: api ?? FakeDiscourseApi(user: user),
    authenticator: FakeAuthenticator()
      ..keys[_site] = 'key'
      ..keys['https://other.example'] = 'other-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    destinationBookmarks: store,
    plugins: withPlugins ? installedPlugins : null,
  );
  await shell.load();
  await pumpEventQueue();
  return shell;
}
