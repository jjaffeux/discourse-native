import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:discourse_native/src/data/recent_destinations_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/global_search_filters.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final forums = [
    instance('one.example', title: 'One'),
    instance('two.example', title: 'Two'),
  ];

  late ShellController controller;
  late FakeForumTabStore forumTabs;

  for (final source in [
    ContentRoute.topicList(TopicListMode.latest),
    ContentRoute.messages(groupName: 'team', mode: MessageListMode.archive),
  ]) {
    test(
      'a Unicode search on ${source.id} survives a workspace restart',
      () async {
        final persistence = MemoryForumTabPersistence();
        final tabs = ForumTabStore(persistence: persistence);
        final first = ShellController(
          instanceStore: FakeInstanceStore(forums),
          api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: tabs,
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(first.dispose);
        await first.load();
        first.pushContent(source);
        final query = '中' * 230;
        first.applySearchToList(query, const []);
        final applied = first.currentContent!;
        final tabId = first.activeTabId;
        expect(applied.topicListSearch, query);
        await tabs.save([
          first.currentWorkspace!,
        ], selectedSiteUrl: forums.first.url);

        final restored = ShellController(
          instanceStore: FakeInstanceStore(forums),
          api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: ForumTabStore(persistence: persistence),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(restored.dispose);
        await restored.load();

        expect(restored.activeTabId, tabId);
        expect(restored.currentContent?.feedPath, applied.feedPath);
        expect(restored.currentContent?.topicListSearch, query);
        expect(restored.currentContent?.isMessages, source.isMessages);
        expect(
          restored.currentContent?.messageGroupName,
          source.messageGroupName,
        );
        expect(
          restored.currentContent?.messageListMode,
          source.messageListMode,
        );
      },
    );
  }

  group('ShellController tabs', () {
    setUp(() async {
      forumTabs = FakeForumTabStore();
      controller = ShellController(
        instanceStore: FakeInstanceStore(forums),
        api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        forumTabs: forumTabs,
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();
    });

    test(
      'plain words replace a prior endpoint search without retaining q',
      () async {
        final shell = controller;
        final previousQuery = '旧' * 2048;
        final words = '新' * 2048;
        for (final source in [
          ContentRoute.searchList(previousQuery),
          ContentRoute.topicFilter(previousQuery),
          ContentRoute.searchList(
            previousQuery,
            groupName: 'team',
            messageMode: MessageListMode.unread,
          ),
        ]) {
          shell.pushContent(source);
          shell.applySearchToList(words, const []);
          final route = shell.currentContent!;

          expect(Uri.parse(route.feedPath!).queryParameters, {'search': words});
          expect(route.topicListSearch, words);
          expect(route.isMessages, source.isMessages);
          expect(route.messageGroupName, source.messageGroupName);
          if (source.isMessages) {
            expect(route.messageListMode, MessageListMode.unread);
          }
          expect(ContentRoute.fromJson(route.toJson()), route);
        }
      },
    );

    test('taxonomy replacements discard the previous endpoint query', () async {
      final shell = controller;
      final words = '新' * 2030;
      for (final source in [
        ContentRoute.searchList('旧' * 2048),
        ContentRoute.topicFilter('旧' * 2048),
      ]) {
        for (final condition in const [
          GlobalSearchCondition(
            filterId: 'category',
            operator: 'any',
            value: ['12'],
          ),
          GlobalSearchCondition(
            filterId: 'tags',
            operator: 'any',
            value: ['design'],
          ),
        ]) {
          shell.pushContent(source);
          shell.applySearchToList(words, [condition]);
          final route = shell.currentContent!;
          expect(
            Uri.parse(route.feedPath!).queryParameters.containsKey('q'),
            isFalse,
          );
          expect(route.topicListSearch, words);
          expect(route.isSearchList, isFalse);
          expect(route.isAdvancedTopicFilter, isFalse);
          if (condition.filterId == 'category') {
            expect(route.categoryId, 12);
          } else {
            expect(route.tagNames, ['design']);
          }
          expect(ContentRoute.fromJson(route.toJson()), route);
        }
      }
    });

    test('edited search conditions replace the prior taxonomy scope', () async {
      final shell = controller;
      final source = ContentRoute.filteredTopicList(
        TopicListMode.topWeekly,
        categoryId: 12,
        tags: const ['design', 'mobile'],
      ).withTopicListSort('posts');
      shell.pushContent(source);
      shell.applySearchToList('new words', const []);
      final route = shell.currentContent!;

      expect(route.categoryId, isNull);
      expect(route.tagNames, isEmpty);
      expect(route.topicListSearch, 'new words');
      expect(TopicListMode.fromRoute(route), TopicListMode.topWeekly);
      expect(route.topicListOrder, 'posts');
      expect(ContentRoute.fromJson(route.toJson()), route);
    });

    test('repeated message searches preserve their mailbox identity', () {
      for (final group in [null, 'team']) {
        for (final mode in MessageListMode.values) {
          if (group != null && !mode.supportsGroup) continue;
          final source = ContentRoute.messages(groupName: group, mode: mode);
          controller.pushContent(source);
          for (final words in ['first', 'second', '']) {
            controller.applySearchToList(words, const []);
            final route = controller.currentContent!;
            expect(route.isMessages, isTrue);
            expect(route.messageGroupName, group);
            expect(route.messageListMode, mode);
            expect(route.topicListSearch, words);
            expect(ContentRoute.fromJson(route.toJson()), route);
          }
        }
      }
    });

    test('clearing only search words preserves the current list scope', () {
      for (final source in [
        ContentRoute.list(ListLink.parse('/c/design/12?order=posts')!),
        ContentRoute.filteredTopicList(
          TopicListMode.topWeekly,
          categoryId: 12,
          tags: const ['design', 'mobile'],
        ).withTopicListSort('posts'),
        ContentRoute.messages(groupName: 'team', mode: MessageListMode.archive),
      ]) {
        controller.pushContent(source.withTopicListSearch('words'));
        controller.clearSearchWords();
        final route = controller.currentContent!;
        if (!source.isMessages) expect(route.feedPath, source.feedPath);
        expect(route.categoryId, source.categoryId);
        expect(route.tagNames, source.tagNames);
        expect(route.topicListOrder, source.topicListOrder);
        expect(route.isMessages, source.isMessages);
        expect(route.messageGroupName, source.messageGroupName);
        expect(route.messageListMode, source.messageListMode);
        expect(route.topicListSearch, isEmpty);
        expect(ContentRoute.fromJson(route.toJson()), route);
      }
    });

    test(
      'external core feeds cannot consume the search expansion budget',
      () async {
        final shell = controller;
        final before = shell.currentContent;
        expect(shell.openCorePageUrl('/latest?extra=${'中' * 2000}'), isFalse);
        expect(shell.currentContent, before);
      },
    );

    test(
      'bounded tag searches and replacement words retain external filters',
      () async {
        final shell = controller;
        final extra = 'x' * 1900;
        expect(
          shell.openCorePageUrl('/top?period=weekly&extra=$extra'),
          isTrue,
        );
        final tags = [
          for (var index = 0; index < 30; index++) '${'中' * 64}$index',
        ];
        final conditions = [
          const GlobalSearchCondition(
            filterId: 'category',
            operator: 'any',
            value: ['12'],
          ),
          GlobalSearchCondition(filterId: 'tags', operator: 'all', value: tags),
        ];
        const capabilities = GlobalSearchCapabilities();
        final words = '新' * 20;
        for (final condition in conditions) {
          expect(
            validateGlobalSearchCondition(condition, capabilities),
            isNull,
          );
        }
        expect(
          globalSearchTerm(
            GlobalSearchRequest(
              scope: GlobalSearchScope.forum,
              query: words,
              capabilities: capabilities,
              conditions: conditions,
            ),
          ).length,
          lessThanOrEqualTo(2048),
        );

        shell.applySearchToList(words, conditions);
        final filtered = shell.currentContent!;
        expect(filtered.categoryId, 12);
        expect(filtered.tagNames, tags);
        expect(filtered.topicListSearch, words);
        expect(TopicListMode.fromRoute(filtered), TopicListMode.topWeekly);
        expect(Uri.parse(filtered.feedPath!).queryParameters['extra'], extra);
        expect(ContentRoute.fromJson(filtered.toJson()), filtered);

        shell.applySearchToList('新' * 2048, const []);
        final replaced = shell.currentContent!;
        expect(replaced.categoryId, isNull);
        expect(replaced.tagNames, isEmpty);
        expect(replaced.topicListSearch, '新' * 2048);
        expect(Uri.parse(replaced.feedPath!).queryParameters['extra'], extra);
        expect(ContentRoute.fromJson(replaced.toJson()), replaced);
      },
    );

    group('creation', () {
      for (final inPanel in [false, true]) {
        test(
          'opening a same-key destination retains its distinct source ${inPanel ? 'in another panel' : 'in a new tab'}',
          () {
            controller.desktopTopicTabs = true;
            final source = controller.activeTab!;
            const route = ContentRoute(
              destination: ExtensionDestination('latest'),
              title: 'Plugin page',
              icon: DIcons.list,
            );
            if (inPanel) {
              controller.openContentInPanel(route, panel: ForumPanel.secondary);
            } else {
              controller.openContentInNewTab(route, source: source);
            }

            expect(controller.activeTab!.contentStack, [
              source.currentContent,
              route,
            ]);
          },
        );
      }

      test('closing a reader retains its distinct same-key source', () {
        controller.desktopTopicTabs = true;
        const source = ContentRoute(
          destination: ExtensionDestination('latest'),
          title: 'Plugin page',
          icon: DIcons.list,
        );
        controller.openContentInPanel(source, panel: ForumPanel.secondary);
        final readerId = controller.activeTabId;
        controller.pushContent(_topic(42, 'A topic'));

        controller.closeTopic();

        expect(controller.activeTabId, readerId);
        expect(controller.currentContent, source);
      });

      for (final stacked in [false, true]) {
        test(
          'restored feed hydrates its explicit mode ${stacked ? 'above a same-key Start page' : 'independently of its key'}',
          () async {
            const route = ContentRoute(
              destination: FeedDestination(
                key: 'new-tab',
                mode: TopicListMode.unread,
              ),
              title: 'Unread',
              icon: DIcons.list,
            );
            final api = FakeDiscourseApi(feeds: const {'/unread.json': []});
            final restored = ShellController(
              instanceStore: FakeInstanceStore(forums),
              api: api,
              authenticator: FakeAuthenticator(),
              drafts: FakeDraftStore(),
              forumTabs: FakeForumTabStore([
                ForumWorkspace(
                  siteUrl: forums.first.url,
                  accountIdentity: 'anonymous',
                  tabs: [
                    ForumTab(
                      id: 'custom',
                      rootDestinationId: 'latest',
                      contentStack: [if (stacked) ContentRoute.newTab(), route],
                    ),
                  ],
                  activeTabId: 'custom',
                ),
              ]),
              trackers: FakeSiteTracker.reset(),
            );
            addTearDown(restored.dispose);
            await restored.load();
            await pumpEventQueue();
            expect(api.feedPaths, contains('/unread.json'));
            expect(restored.currentFeedId, route.id);
            expect(restored.currentFeed, isNotNull);
          },
        );
      }

      test(
        'hydration refreshes display without changing restored topic identity',
        () async {
          final route = ContentRoute.fromJson({
            'id': 'saved-reader-42',
            'title': 'Saved title',
            'icon': DIcons.comments.name,
            'topic_id': 42,
            'slug': 'saved-topic',
            'feed_path': '/legacy.json?search=kept',
          });
          final location = ForumTabLocation(
            rootDestinationId: 'latest',
            contentStack: [route],
          );
          final tab = ForumTab(
            id: 'saved-reader',
            rootDestinationId: 'latest',
            contentStack: [route],
            backHistory: [location],
            forwardHistory: [location],
            anchors: const {
              'saved-reader-42': ForumTabAnchor(kind: 'topic', itemId: 1),
            },
          );
          final saved = FakeForumTabStore([
            ForumWorkspace(
              siteUrl: forums.first.url,
              accountIdentity: 'anonymous',
              tabs: [tab],
              activeTabId: tab.id,
            ),
          ]);
          final restored = ShellController(
            instanceStore: FakeInstanceStore(forums),
            api: FakeDiscourseApi(
              topics: {42: topicPayload(id: 42, title: 'Fresh title')},
            ),
            authenticator: FakeAuthenticator(),
            drafts: FakeDraftStore(),
            forumTabs: saved,
            trackers: FakeSiteTracker.reset(),
          );
          addTearDown(restored.dispose);
          await restored.load();
          await pumpEventQueue();

          expect(restored.currentContent!.title, 'Fresh title');
          for (final entry in [
            restored.activeTab!.location,
            ...restored.activeTab!.backHistory,
            ...restored.activeTab!.forwardHistory,
          ]) {
            expect(entry.contentStack.single.id, route.id);
            expect(entry.contentStack.single.feedPath, route.feedPath);
            expect(entry.contentStack.single.title, 'Fresh title');
          }
          expect(restored.activeTab!.backHistory, hasLength(1));
          expect(restored.activeTab!.forwardHistory, hasLength(1));
          expect(restored.activeTab!.anchors[route.id]?.itemId, 1);
          restored.openCurrentTopicPost(2);
          expect(restored.currentContent!.id, route.id);
          expect(restored.currentContent!.feedPath, route.feedPath);
          expect(restored.currentContent!.postNumber, 2);
        },
      );

      test(
        'desktop panels seed Start pages without changing active content',
        () {
          final main = controller.activeTab!;
          controller.desktopTopicTabs = true;

          final start = controller.selectedTabIn(ForumPanel.secondary)!;
          expect(start.currentContent.isNewTab, isTrue);
          expect(controller.activeTab, main);
          controller.desktopTopicTabs = false;
          controller.desktopTopicTabs = true;
          expect(controller.tabsForCurrentForum, hasLength(2));
          expect(controller.selectedTabIn(ForumPanel.secondary), start);

          controller.selectInstance(1);
          expect(controller.activeTab!.panel, ForumPanel.main);
          expect(controller.currentContent!.isNewTab, isFalse);
          expect(
            controller
                .selectedTabIn(ForumPanel.secondary)
                ?.currentContent
                .isNewTab,
            isTrue,
          );
        },
      );

      for (final panel in ForumPanel.values) {
        test(
          'restoring a full $panel workspace fills its empty panel',
          () async {
            final tabs = [
              for (var index = 0; index < ForumWorkspace.maximumTabs; index++)
                ForumTab(
                  id: 'restored-$index',
                  panel: panel,
                  rootDestinationId: 'latest',
                  contentStack: [_topic(index + 1, 'Saved topic $index')],
                ),
            ];
            final saved = ForumWorkspace(
              siteUrl: forums.first.url,
              accountIdentity: 'anonymous',
              tabs: tabs,
              activeTabId: tabs.first.id,
            );
            final store = FakeForumTabStore([saved]);
            final restored = ShellController(
              instanceStore: FakeInstanceStore(forums),
              api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
              authenticator: FakeAuthenticator(),
              drafts: FakeDraftStore(),
              forumTabs: store,
              trackers: FakeSiteTracker.reset(),
            )..desktopTopicTabs = true;
            addTearDown(restored.dispose);
            await restored.load();

            final other = panel == ForumPanel.main
                ? ForumPanel.secondary
                : ForumPanel.main;
            expect(restored.currentWorkspace!.tabsIn(panel), tabs);
            expect(restored.activeTab, tabs.first);
            final start = restored.selectedTabIn(other)!;
            expect(start.currentContent.isNewTab, isTrue);
            expect(restored.canCreateTab, isFalse);
            expect(
              ForumWorkspace.tryFromJson(restored.currentWorkspace!.toJson()),
              restored.currentWorkspace,
            );
            restored.selectTab(start.id);
            restored.pushContent(_topic(99, 'Opened from Start page'));
            expect(restored.activeTab!.panel, other);
            expect(restored.currentContent!.topicId, 99);
            expect(
              ForumWorkspace.tryFromJson(restored.currentWorkspace!.toJson()),
              restored.currentWorkspace,
            );
          },
        );
      }

      test(
        'Start page visits survive a restart, including background tabs',
        () async {
          final persistence = MemoryRecentDestinationsPersistence();
          final firstStore = RecentDestinationsStore(persistence: persistence);
          final first = ShellController(
            instanceStore: FakeInstanceStore(forums),
            api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
            authenticator: FakeAuthenticator(),
            drafts: FakeDraftStore(),
            forumTabs: forumTabs,
            recentDestinations: firstStore,
            trackers: FakeSiteTracker.reset(),
          );
          addTearDown(first.dispose);
          await first.load();
          first.openTopicUrl('/t/visited-topic/42');
          first.openListUrl('/c/support/12', title: 'Support');
          expect(
            first.openContentInNewTab(
              const ContentRoute(
                destination: ExtensionDestination('chat-c-7'),
                title: 'General',
                icon: DIcons.comments,
              ),
              select: false,
            ),
            TabOpenResult.opened,
          );
          for (final tab in first.tabsForCurrentForum.toList()) {
            first.closeTab(tab.id);
          }
          await firstStore.save();

          final restored = ShellController(
            instanceStore: FakeInstanceStore(forums),
            api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
            authenticator: FakeAuthenticator(),
            drafts: FakeDraftStore(),
            forumTabs: forumTabs,
            recentDestinations: RecentDestinationsStore(
              persistence: persistence,
            ),
            trackers: FakeSiteTracker.reset(),
          );
          addTearDown(restored.dispose);
          await restored.load();

          expect(restored.recentTopicsFor(forums.first.url).single.topicId, 42);
          expect(
            restored.recentCategoriesFor(forums.first.url).single.title,
            'Support',
          );
          expect(
            restored.recentChannelsFor(forums.first.url).single.title,
            'General',
          );
          expect(restored.recentTopicsFor(forums.last.url), isEmpty);
        },
      );

      for (final rail in [forums, <DiscourseInstance>[]]) {
        test(
          rail.isEmpty
              ? 'an empty rail keeps every Start page visit'
              : 'a restart drops Start page visits of forums off the rail',
          () async {
            final persistence = MemoryRecentDestinationsPersistence();
            await (RecentDestinationsStore(persistence: persistence)
                  ..remember(
                    forums.first.url,
                    'anonymous',
                    ContentRoute.topic(
                      topicId: 41,
                      slug: 'kept',
                      title: 'Kept',
                    ),
                  )
                  ..remember(
                    'https://removed.example',
                    'user:reader',
                    ContentRoute.topic(
                      topicId: 42,
                      slug: 'contract-renewal',
                      title: 'Contract renewal',
                    ),
                  ))
                .save();

            final restored = ShellController(
              instanceStore: FakeInstanceStore(rail),
              api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
              authenticator: FakeAuthenticator(),
              drafts: FakeDraftStore(),
              forumTabs: forumTabs,
              recentDestinations: RecentDestinationsStore(
                persistence: persistence,
              ),
              trackers: FakeSiteTracker.reset(),
            );
            addTearDown(restored.dispose);
            await restored.load();

            final reloaded = RecentDestinationsStore(persistence: persistence);
            await reloaded.load();
            expect(
              reloaded.topicsFor(forums.first.url, 'anonymous').single.topicId,
              41,
            );
            expect(
              reloaded.hasVisits('https://removed.example', 'user:reader'),
              rail.isEmpty,
            );
            expect(
              persistence.value,
              rail.isEmpty
                  ? contains('Contract renewal')
                  : isNot(contains('Contract renewal')),
            );
          },
        );
      }

      test(
        'restored tab history seeds visits from before persistence',
        () async {
          controller.openTopicUrl('/t/older-topic/41');
          controller.openTopicUrl('/t/newer-topic/42');
          await Future<void>.delayed(Duration.zero);

          final restored = ShellController(
            instanceStore: FakeInstanceStore(forums),
            api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
            authenticator: FakeAuthenticator(),
            drafts: FakeDraftStore(),
            forumTabs: forumTabs,
            recentDestinations: RecentDestinationsStore.memory(),
            trackers: FakeSiteTracker.reset(),
          );
          addTearDown(restored.dispose);
          await restored.load();

          expect(
            restored
                .recentTopicsFor(forums.first.url)
                .map((route) => route.topicId),
            [42, 41],
          );
        },
      );

      test('recent destinations keep five distinct visits per forum', () {
        for (var id = 1; id <= 6; id++) {
          controller.openTopicUrl('/t/topic-$id/$id');
        }
        expect(
          controller
              .recentTopicsFor(forums.first.url)
              .map((route) => route.topicId),
          [6, 5, 4, 3, 2],
        );

        controller.openTopicUrl('/t/topic-3/3');
        expect(
          controller
              .recentTopicsFor(forums.first.url)
              .map((route) => route.topicId),
          [3, 6, 5, 4, 2],
        );

        controller.openListUrl('/c/support/12', title: 'Support');
        expect(
          controller.recentCategoriesFor(forums.first.url).single.title,
          'Support',
        );
        controller.selectDestination(
          const SidebarDestination(
            id: 'chat-c-9',
            label: 'General',
            icon: DIcons.comment,
          ),
        );
        expect(
          controller.recentChannelsFor(forums.first.url).single.id,
          'chat-c-9',
        );
        controller.selectInstance(1);
        expect(controller.recentTopicsFor(forums.last.url), isEmpty);
        expect(controller.recentCategoriesFor(forums.last.url), isEmpty);
      });

      test('opens a topic in the background with its requested post', () async {
        controller.openTopicUrl('/t/another-topic/42/3');
        final original = controller.activeTab;

        expect(
          controller.openLinkInNewTab('/t/another-topic/42/8'),
          TabOpenResult.opened,
        );

        expect(controller.activeTab, original);
        expect(controller.tabsForCurrentForum, hasLength(2));
        final opened = controller.tabsForCurrentForum.last;
        expect(opened.currentContent.topicId, 42);
        expect(opened.currentContent.postNumber, 8);

        controller.selectTab(opened.id);
        await Future<void>.delayed(Duration.zero);
        expect(controller.currentContent?.topicId, 42);
        expect(controller.currentContent?.postNumber, 8);
      });

      test(
        'opens another forum’s link without switching the current forum',
        () {
          final original = controller.activeTab;

          expect(
            controller.openLinkInNewTab('https://two.example/tag/flutter'),
            TabOpenResult.opened,
          );

          expect(controller.currentInstance?.url, forums.first.url);
          expect(controller.activeTab, original);
          expect(controller.tabsForCurrentForum, hasLength(1));

          controller.selectInstance(1);
          expect(controller.tabsForCurrentForum, hasLength(2));
          expect(
            controller.tabsForCurrentForum.last.currentContent.feedPath,
            '/tag/flutter.json',
          );
        },
      );

      test(
        'opens category and group links without changing the active tab',
        () {
          final original = controller.activeTab;

          expect(
            controller.openLinkInNewTab('/c/support/12', title: 'Support'),
            TabOpenResult.opened,
          );
          expect(
            controller.tabsForCurrentForum.last.currentContent.title,
            'Support',
          );
          expect(
            controller.tabsForCurrentForum.last.currentContent.feedPath,
            '/c/support/12.json',
          );
          expect(controller.openLinkInNewTab('/g/staff'), TabOpenResult.opened);
          expect(
            controller
                .tabsForCurrentForum
                .last
                .currentContent
                .groupRoute
                ?.groupName,
            'staff',
          );
          expect(controller.activeTab, original);
        },
      );

      test('opens the native About page in a background tab', () {
        final original = controller.activeTab;
        expect(controller.openLinkInNewTab('/about'), TabOpenResult.opened);
        expect(
          controller.tabsForCurrentForum.last.currentContent.id,
          'forum-about',
        );
        expect(controller.activeTab, original);
      });

      test('declines unsupported links without creating empty tabs', () {
        final original = controller.activeTab;
        for (final url in [
          'https://other.example/t/topic/42',
          'https://name:password@one.example/t/topic/42',
          '/c/support/12/l/top',
        ]) {
          expect(controller.openLinkInNewTab(url), TabOpenResult.unsupported);
        }
        expect(controller.tabsForCurrentForum, hasLength(1));
        expect(controller.activeTab, original);
      });

      test('adds and activates a fresh new-tab page', () {
        final originalTabId = controller.activeTabId;

        expect(originalTabId, isNotNull);
        expect(controller.tabsForCurrentForum, hasLength(1));

        controller.createTab();

        expect(controller.tabsForCurrentForum, hasLength(2));
        expect(controller.activeTabId, isNot(originalTabId));
        _expectNewTabRoot(controller);
      });

      test('stops at the bounded eager workspace capacity', () {
        for (var count = 1; count < ForumWorkspace.maximumTabs; count++) {
          expect(
            controller.canCreateTab,
            isTrue,
            reason: 'A workspace with $count tabs should still accept another.',
          );
          controller.createTab();
          expect(controller.tabsForCurrentForum, hasLength(count + 1));
        }
        final active = controller.activeTabId;

        expect(
          controller.tabsForCurrentForum,
          hasLength(ForumWorkspace.maximumTabs),
        );
        expect(controller.canCreateTab, isFalse);

        controller.createTab();
        var switched = false;
        controller.switchSidebarPanel(() => switched = true);
        expect(switched, isFalse);
        expect(
          controller.tabsForCurrentForum,
          hasLength(ForumWorkspace.maximumTabs),
        );
        expect(controller.activeTabId, active);
        final content = controller.currentContent;
        expect(
          controller.openLinkInNewTab('/t/full-workspace/42'),
          TabOpenResult.limitReached,
        );
        expect(controller.activeTabId, active);
        expect(controller.currentContent, content);
      });
    });

    group('forum-scoped navigation', () {
      test('list selections retain 50 topics in each direction', () {
        for (var id = 1; id <= 60; id++) {
          controller.openTopicFromList(
            Topic(id: id, slug: 'topic-$id', title: 'Topic $id'),
          );
        }
        expect(controller.contentStack, hasLength(2));
        for (var id = 59; id >= 10; id--) {
          expect(controller.handleBack(canReturnToSidebar: false), isTrue);
          expect(controller.currentContent?.topicId, id);
          expect(controller.topicListContent?.id, 'latest');
        }
        expect(controller.canPopContent, isFalse);
        expect(controller.handleBack(canReturnToSidebar: false), isFalse);
        for (var id = 11; id <= 60; id++) {
          expect(controller.handleForward(), isTrue);
          expect(controller.currentContent?.topicId, id);
        }
        expect(controller.canForwardContent, isFalse);
      });

      test(
        'sidebar destination visits restore their navigation context',
        () async {
          controller.openTopicFromList(
            const Topic(id: 101, slug: 'first', title: 'First'),
          );
          controller.selectDestination(_destination(forums[0], 'categories'));
          controller.selectDestination(_destination(forums[0], 'latest'));
          await controller.selectTopicListMode(TopicListMode.topYearly);

          expect(controller.handleBack(canReturnToSidebar: false), isTrue);
          expect(controller.currentTopicListMode, TopicListMode.latest);
          expect(controller.handleBack(canReturnToSidebar: false), isTrue);
          expect(controller.destinationId, 'categories');
          expect(controller.currentContent?.id, 'categories');
          expect(controller.handleBack(canReturnToSidebar: false), isTrue);
          expect(controller.destinationId, 'latest');
          expect(controller.currentContent?.topicId, 101);
          expect(controller.handleForward(), isTrue);
          expect(controller.destinationId, 'categories');
          expect(controller.handleForward(), isTrue);
          expect(controller.currentTopicListMode, TopicListMode.latest);
          expect(controller.handleForward(), isTrue);
          expect(controller.currentTopicListMode, TopicListMode.topYearly);
        },
      );

      test('reselecting a destination refreshes without losing Forward', () {
        controller.selectDestination(_destination(forums[0], 'categories'));
        controller.handleBack(canReturnToSidebar: false);
        final tab = controller.activeTab;
        controller.selectDestination(_destination(forums[0], 'latest'));
        expect(controller.activeTab, tab);
        expect(controller.handleForward(), isTrue);
        expect(controller.currentContent?.id, 'categories');
      });

      test('replacing a reader after Back clears Forward', () {
        for (var id = 1; id <= 3; id++) {
          controller.openTopicFromList(
            Topic(id: id, slug: 'topic-$id', title: 'Topic $id'),
          );
        }
        controller.handleBack(canReturnToSidebar: false);
        controller.openTopicFromList(
          const Topic(id: 4, slug: 'fourth', title: 'Fourth'),
        );
        expect(controller.canForwardContent, isFalse);
        controller.handleBack(canReturnToSidebar: false);
        expect(controller.currentContent?.topicId, 2);
      });

      test(
        'closing a reader retains its current list after history expires',
        () async {
          for (var id = 1; id <= 60; id++) {
            controller.openTopicFromList(
              Topic(id: id, slug: 'topic-$id', title: 'Topic $id'),
            );
          }
          await controller.selectTopicListMode(
            TopicListMode.topYearly,
            keepTopicOpen: true,
          );
          controller.closeTopicListReader();
          expect(controller.currentContent?.isTopic, isFalse);
          expect(controller.currentTopicListMode, TopicListMode.topYearly);
          controller.handleBack(canReturnToSidebar: false);
          expect(controller.currentContent?.topicId, 60);
          expect(controller.currentTopicListMode, TopicListMode.topYearly);
        },
      );

      test('bounds content history while preserving its root', () {
        for (var id = 1; id <= ForumTab.maximumContentRoutes + 5; id++) {
          controller.pushContent(_topic(id, 'Topic $id'));
        }

        expect(
          controller.contentStack,
          hasLength(ForumTab.maximumContentRoutes),
        );
        expect(controller.contentStack.first.id, 'latest');
        expect(controller.contentStack[1].topicId, 7);
        expect(controller.contentStack.last.topicId, 69);
      });

      test('moves backward and forward through content history', () {
        controller.pushContent(_topic(101, 'First topic'));
        controller.pushContent(_topic(202, 'Second topic'));

        expect(controller.canForwardContent, isFalse);
        expect(controller.handleBack(canReturnToSidebar: false), isTrue);
        expect(_routeIds(controller), ['latest', 'topic-101']);
        expect(controller.canForwardContent, isTrue);

        expect(controller.handleForward(), isTrue);
        expect(_routeIds(controller), ['latest', 'topic-101', 'topic-202']);
        expect(controller.canForwardContent, isFalse);
      });

      test('a new push after Back clears forward history', () {
        controller.pushContent(_topic(101, 'First topic'));
        controller.pushContent(_topic(202, 'Second topic'));
        controller.handleBack(canReturnToSidebar: false);

        expect(controller.canForwardContent, isTrue);

        controller.pushContent(_topic(303, 'Replacement topic'));

        expect(_routeIds(controller), ['latest', 'topic-101', 'topic-303']);
        expect(controller.canForwardContent, isFalse);
        expect(controller.handleForward(), isFalse);
      });

      test('Forward is a no-op without forward history', () {
        final content = controller.currentContent;
        final stack = controller.contentStack;

        expect(controller.canForwardContent, isFalse);
        expect(controller.handleForward(), isFalse);
        expect(controller.currentContent, same(content));
        expect(controller.contentStack, same(stack));
      });

      test('hydrates a restored route when moving Forward', () async {
        final latest = ContentRoute.fromDestination(
          _destination(forums.first, 'latest'),
        );
        final futureTopic = _topic(202, 'Restored future topic');
        final restoredTabs = FakeForumTabStore([
          ForumWorkspace(
            siteUrl: forums.first.url,
            accountIdentity: 'anonymous',
            tabs: [
              ForumTab(
                id: 'restored-history',
                rootDestinationId: 'latest',
                contentStack: [latest],
                forwardStack: [futureTopic],
              ),
            ],
            activeTabId: 'restored-history',
          ),
        ]);
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          topics: {202: topicPayload(id: 202, title: 'Restored future topic')},
        );
        final restored = ShellController(
          instanceStore: FakeInstanceStore(forums),
          api: api,
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: restoredTabs,
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(restored.dispose);
        await restored.load();

        expect(api.topicsOpened, isEmpty);

        expect(restored.handleForward(), isTrue);
        await Future<void>.delayed(Duration.zero);

        expect(api.topicsOpened, [202]);
      });

      test('keeps forward history isolated per tab', () {
        final firstTabId = controller.activeTabId!;
        controller.pushContent(_topic(101, 'First topic'));
        controller.pushContent(_topic(202, 'Second topic'));
        controller.handleBack(canReturnToSidebar: false);

        expect(controller.canForwardContent, isTrue);

        controller.createTab();
        final secondTabId = controller.activeTabId!;

        expect(controller.canForwardContent, isFalse);
        expect(controller.handleForward(), isFalse);

        controller.selectTab(firstTabId);

        expect(controller.canForwardContent, isTrue);
        expect(controller.handleForward(), isTrue);
        expect(controller.currentContent?.topicId, 202);

        controller.selectTab(secondTabId);

        expect(controller.canForwardContent, isFalse);
        _expectNewTabRoot(controller);
      });

      test('keeps independent active content stacks per forum', () {
        final firstForumTabId = controller.activeTabId;
        controller.pushContent(_topic(101, 'First forum topic'));

        controller.selectInstance(1);
        final secondForumTabId = controller.activeTabId;
        controller.pushContent(_topic(202, 'Second forum topic'));

        expect(secondForumTabId, isNotNull);
        expect(_routeIds(controller), ['latest', 'topic-202']);

        controller.selectInstance(0);

        expect(controller.activeTabId, firstForumTabId);
        expect(_routeIds(controller), ['latest', 'topic-101']);

        controller.selectInstance(1);

        expect(controller.activeTabId, secondForumTabId);
        expect(_routeIds(controller), ['latest', 'topic-202']);
      });

      test("restores each forum's last active tab", () {
        final firstForumInitialTabId = controller.activeTabId;
        controller.createTab();
        final firstForumLastTabId = controller.activeTabId;
        controller.selectDestination(_destination(forums[0], 'categories'));

        controller.selectInstance(1);
        controller.createTab();
        controller.createTab();
        final secondForumLastTabId = controller.activeTabId;
        controller.selectDestination(_destination(forums[1], 'categories'));

        expect(controller.tabsForCurrentForum, hasLength(3));
        expect(controller.currentContent?.id, 'categories');

        controller.selectInstance(0);

        expect(controller.tabsForCurrentForum, hasLength(2));
        expect(controller.activeTabId, firstForumLastTabId);
        expect(controller.activeTabId, isNot(firstForumInitialTabId));
        expect(controller.currentContent?.id, 'categories');

        controller.selectInstance(1);

        expect(controller.tabsForCurrentForum, hasLength(3));
        expect(controller.activeTabId, secondForumLastTabId);
        expect(controller.currentContent?.id, 'categories');
      });
    });

    group('tab lifecycle', () {
      test('restorable tabs retain all their search words', () {
        final site = forums.first.url;
        final id = controller.activeTabId!;
        controller.pushContent(_topic(101, 'Visited topic'));
        controller.search.setPageWords(site, id, 'topic-101', 'first words');
        controller.search.setPageWords(site, id, 'topic-202', 'second words');
        controller.search.setStartPageQuery(site, id, 'start query');

        controller.closeTab(id);
        expect(
          controller.search.wordsFor(site, id, 'topic-101'),
          'first words',
        );
        expect(controller.reopenClosedTab(id), isTrue);
        expect(controller.activeTabId, id);
        expect(
          controller.search.wordsFor(site, id, 'topic-101'),
          'first words',
        );
        expect(
          controller.search.wordsFor(site, id, 'topic-202'),
          'second words',
        );
        expect(controller.search.startPageQueryFor(site, id), 'start query');
      });

      test('discarded Start tabs retire their search state', () {
        final site = forums.first.url;
        final id = controller.activeTabId!;
        controller.pushContent(_topic(101, 'Visited topic'));
        controller.search.setPageWords(site, id, 'topic-101', 'retired words');
        controller.search.setStartPageQuery(site, id, 'retired query');
        controller.pushContent(ContentRoute.newTab());

        controller.closeTab(id);

        expect(controller.reopenClosedTab(id), isFalse);
        expect(controller.search.wordsFor(site, id, 'topic-101'), isEmpty);
        expect(controller.search.startPageQueryFor(site, id), isEmpty);
      });

      test('closed-tab eviction retires only unreachable search owners', () {
        final firstSite = forums.first.url;
        final secondSite = forums.last.url;
        final oldest = controller.activeTabId!;
        controller.pushContent(_topic(101, 'Oldest topic'));
        controller.search.setPageWords(
          firstSite,
          oldest,
          'topic-101',
          'oldest',
        );
        controller.closeTab(oldest);

        controller.selectInstance(1);
        final live = controller.activeTabId!;
        controller.search.setPageWords(secondSite, live, 'latest', 'live');
        controller.createTab();
        final restorable = controller.activeTabId!;
        controller.pushContent(_topic(202, 'Restorable topic'));
        controller.search.setPageWords(
          secondSite,
          restorable,
          'topic-202',
          'saved',
        );
        controller.closeTab(restorable);

        controller.selectInstance(0);
        for (var index = 0; index < ForumWorkspace.maximumTabs - 2; index++) {
          controller.pushContent(_topic(300 + index, 'Another topic'));
          controller.closeTab(controller.activeTabId!);
        }
        expect(
          controller.search.wordsFor(firstSite, oldest, 'topic-101'),
          'oldest',
        );

        controller.selectInstance(1);
        controller.createTab();
        controller.pushContent(_topic(999, 'Newly closed topic'));
        controller.closeTab(controller.activeTabId!);

        expect(
          controller.search.wordsFor(firstSite, oldest, 'topic-101'),
          isEmpty,
        );
        expect(controller.search.wordsFor(secondSite, live, 'latest'), 'live');
        expect(
          controller.search.wordsFor(secondSite, restorable, 'topic-202'),
          'saved',
        );
        expect(controller.reopenClosedTab(restorable), isTrue);
        expect(
          controller.search.wordsFor(secondSite, restorable, 'topic-202'),
          'saved',
        );
        controller.selectInstance(0);
        expect(controller.reopenClosedTab(oldest), isFalse);
      });

      test('bulk close retires Start and evicted content search state', () {
        final firstSite = forums.first.url;
        final closed = <String>[];
        for (var index = 0; index < ForumWorkspace.maximumTabs; index++) {
          final id = controller.activeTabId!;
          closed.add(id);
          controller.pushContent(_topic(100 + index, 'Closed topic'));
          controller.search.setPageWords(
            firstSite,
            id,
            'topic-${100 + index}',
            'saved',
          );
          controller.closeTab(id);
        }
        controller.selectInstance(1);
        final site = forums.last.url;
        final kept = controller.activeTabId!;
        controller.pushContent(_topic(1000, 'Kept topic'));
        controller.search.setPageWords(site, kept, 'topic-1000', 'kept');
        controller.createTab();
        final start = controller.activeTabId!;
        controller.pushContent(_topic(2001, 'Visited topic'));
        controller.search.setPageWords(site, start, 'topic-2001', 'discarded');
        controller.pushContent(ContentRoute.newTab());
        final restorable = <String>[];
        for (final topicId in [2002, 2003]) {
          controller.createTab();
          final id = controller.activeTabId!;
          restorable.add(id);
          controller.pushContent(_topic(topicId, 'Restorable topic'));
          controller.search.setPageWords(site, id, 'topic-$topicId', 'recent');
        }

        controller.closeOtherTabs(kept);

        for (var index = 0; index < 2; index++) {
          expect(
            controller.search.wordsFor(
              firstSite,
              closed[index],
              'topic-${100 + index}',
            ),
            isEmpty,
          );
        }
        expect(controller.search.wordsFor(site, start, 'topic-2001'), isEmpty);
        expect(controller.search.wordsFor(site, kept, 'topic-1000'), 'kept');
        for (var index = 0; index < restorable.length; index++) {
          expect(
            controller.search.wordsFor(
              site,
              restorable[index],
              'topic-${2002 + index}',
            ),
            'recent',
          );
          expect(controller.reopenClosedTab(restorable[index]), isTrue);
        }
        expect(controller.reopenClosedTab(start), isFalse);
      });

      test('desktop topic tabs select the next topic after closing', () {
        controller.desktopTopicTabs = true;
        final listTabId = controller.activeTabId!;
        final topicTabIds = <String>[];
        for (final topicId in [101, 202, 303, 404]) {
          controller.openLinkInNewTab('/t/topic/$topicId');
          topicTabIds.add(controller.tabsForCurrentForum.last.id);
        }

        controller.selectTab(topicTabIds[1]);
        controller.closeTab(topicTabIds[1]);
        expect(controller.activeTabId, topicTabIds[2]);

        controller.selectTab(topicTabIds[3]);
        controller.closeTab(topicTabIds[3]);
        expect(controller.activeTabId, topicTabIds[2]);

        controller.closeTab(topicTabIds[2]);
        expect(controller.activeTabId, topicTabIds[0]);

        controller.closeTab(topicTabIds[0]);
        expect(controller.activeTabId, listTabId);
      });

      test(
        'selects the nearest surviving neighbour after an active tab closes',
        () {
          final firstTabId = controller.activeTabId!;
          controller.createTab();
          final middleTabId = controller.activeTabId!;
          controller.createTab();
          final lastTabId = controller.activeTabId!;

          controller.selectTab(middleTabId);
          controller.closeTab(middleTabId);

          expect(controller.tabsForCurrentForum, hasLength(2));
          expect(controller.activeTabId, lastTabId);

          controller.closeTab(lastTabId);

          expect(controller.tabsForCurrentForum, hasLength(1));
          expect(controller.activeTabId, firstTabId);
        },
      );

      test('replaces the final closed tab with a fresh new-tab page', () {
        final closedTabId = controller.activeTabId!;

        controller.closeTab(closedTabId);

        expect(controller.tabsForCurrentForum, hasLength(1));
        expect(controller.activeTabId, isNotNull);
        expect(controller.activeTabId, isNot(closedTabId));
        _expectNewTabRoot(controller);
      });

      test('ignores a closed Start page even after visiting content', () {
        controller.pushContent(_topic(101, 'Visited topic'));
        controller.pushContent(ContentRoute.newTab());
        final closedTabId = controller.activeTabId!;

        controller.closeTab(closedTabId);

        expect(controller.currentWorkspace?.tabById(closedTabId), isNull);
        _expectNewTabRoot(controller);
        expect(controller.recentlyClosedTabsForCurrentForum, isEmpty);
        expect(controller.reopenClosedTab(closedTabId), isFalse);
        expect(controller.reopenClosedTab(), isFalse);
      });

      test('closing Start pages preserves earlier closed content tabs', () {
        final contentTab = controller.activeTab!;
        controller.closeTab(contentTab.id);

        for (var index = 0; index <= ForumWorkspace.maximumTabs; index++) {
          _expectNewTabRoot(controller);
          controller.closeTab(controller.activeTabId!);
        }

        expect(controller.recentlyClosedTabsForCurrentForum, [contentTab]);
        expect(controller.reopenClosedTab(), isTrue);
        expect(controller.activeTab, contentTab);
        expect(controller.reopenClosedTab(), isFalse);
      });

      test('closing the last tab in a panel opens a Start page there', () {
        controller.desktopTopicTabs = true;
        final mainId = controller.activeTabId!;
        controller.selectTab(
          controller.selectedTabIn(ForumPanel.secondary)!.id,
        );
        final secondaryId = controller.activeTabId!;

        controller.closeTab(mainId);
        final newMain = controller.selectedTabIn(ForumPanel.main);
        expect(newMain, isNotNull);
        expect(newMain!.id, isNot(mainId));
        expect(newMain.currentContent.isNewTab, isTrue);
        expect(controller.activeTabId, secondaryId);

        controller.closeTab(secondaryId);
        final newSecondary = controller.selectedTabIn(ForumPanel.secondary);
        expect(newSecondary, isNotNull);
        expect(newSecondary!.id, isNot(secondaryId));
        expect(newSecondary.currentContent.isNewTab, isTrue);
        expect(controller.activeTabId, newSecondary.id);
      });

      test('moving the only main tab leaves a Start page behind', () {
        controller.desktopTopicTabs = true;
        final movedId = controller.activeTabId!;

        controller.moveTabToPanel(movedId, ForumPanel.secondary);

        expect(controller.selectedTabIn(ForumPanel.secondary)?.id, movedId);
        expect(controller.activeTabId, movedId);
        final main = controller.selectedTabIn(ForumPanel.main);
        expect(main, isNotNull);
        expect(main!.id, isNot(movedId));
        expect(main.currentContent.title, 'Start page');
        expect(main.currentContent.icon, DIcons.house);
      });

      test('closing other tabs keeps a Start page in the emptied panel', () {
        controller.desktopTopicTabs = true;
        final mainId = controller.activeTabId!;
        controller.selectTab(
          controller.selectedTabIn(ForumPanel.secondary)!.id,
        );
        final secondaryId = controller.activeTabId!;

        controller.closeOtherTabs(mainId);

        expect(controller.activeTabId, mainId);
        expect(controller.currentWorkspace?.tabById(secondaryId), isNull);
        expect(
          controller.selectedTabIn(ForumPanel.secondary)?.currentContent.title,
          'Start page',
        );
      });

      test('preserves the active tab and persists reordered tabs', () {
        final firstTabId = controller.activeTabId!;
        controller.createTab();
        final secondTabId = controller.activeTabId!;
        controller.createTab();
        final thirdTabId = controller.activeTabId!;
        final savesBeforeMove = forumTabs.saveCount;

        controller.moveTab(firstTabId, 2);

        expect(controller.tabsForCurrentForum.map((tab) => tab.id), [
          secondTabId,
          thirdTabId,
          firstTabId,
        ]);
        expect(controller.activeTabId, thirdTabId);
        expect(forumTabs.saveCount, savesBeforeMove + 1);
        expect(forumTabs.workspaces.single.tabs.map((tab) => tab.id), [
          secondTabId,
          thirdTabId,
          firstTabId,
        ]);
      });

      test('keeps and activates the requested tab when closing others', () {
        final firstTabId = controller.activeTabId!;
        controller.pushContent(_topic(303, 'Kept topic'));
        controller.createTab();
        controller.createTab();

        controller.closeOtherTabs(firstTabId);

        expect(controller.tabsForCurrentForum.map((tab) => tab.id), [
          firstTabId,
        ]);
        expect(controller.activeTabId, firstTabId);
        expect(_routeIds(controller), ['latest', 'topic-303']);
      });

      test('lists and reopens a requested tab closed by close others', () {
        final firstTabId = controller.activeTabId!;
        controller.createTab();
        final secondTabId = controller.activeTabId!;
        controller.createTab();
        final thirdTabId = controller.activeTabId!;
        controller.pushContent(_topic(303, 'Third tab topic'));
        controller.createTab();
        final startTabId = controller.activeTabId!;

        controller.closeOtherTabs(secondTabId);

        expect(
          controller.recentlyClosedTabsForCurrentForum.map((tab) => tab.id),
          [firstTabId, thirdTabId],
        );
        expect(controller.reopenClosedTab(startTabId), isFalse);
        expect(controller.reopenClosedTab(thirdTabId), isTrue);
        expect(controller.tabsForCurrentForum.map((tab) => tab.id), [
          secondTabId,
          thirdTabId,
        ]);
        expect(controller.activeTabId, thirdTabId);
        expect(controller.currentContent?.topicId, 303);
        expect(
          controller.recentlyClosedTabsForCurrentForum.map((tab) => tab.id),
          [firstTabId],
        );
        expect(controller.reopenClosedTab('missing'), isFalse);

        expect(controller.reopenClosedTab(), isTrue);
        expect(controller.tabsForCurrentForum.map((tab) => tab.id), [
          firstTabId,
          secondTabId,
          thirdTabId,
        ]);
        expect(controller.activeTabId, firstTabId);

        expect(controller.reopenClosedTab(), isFalse);
      });
    });

    group('per-tab state', () {
      test('limits ordinary destination changes to the active tab', () {
        final firstTabId = controller.activeTabId!;
        controller.pushContent(_topic(303, 'First tab topic'));

        controller.createTab();
        final secondTabId = controller.activeTabId!;
        controller.selectDestination(_destination(forums[0], 'categories'));

        expect(_routeIds(controller), ['categories']);

        controller.selectTab(firstTabId);

        expect(_routeIds(controller), ['latest', 'topic-303']);

        controller.selectTab(secondTabId);

        expect(_routeIds(controller), ['categories']);
      });

      test('restores feed rows independently', () {
        final firstTabId = controller.activeTabId!;
        controller.saveFeedScrollRow('latest', 12);

        controller.createTab();
        final secondTabId = controller.activeTabId!;
        expect(controller.feedScrollRow('latest'), 0);
        controller.saveFeedScrollRow('latest', 3);

        controller.selectTab(firstTabId);
        expect(controller.feedScrollRow('latest'), 12);

        controller.selectTab(secondTabId);
        expect(controller.feedScrollRow('latest'), 3);
      });

      test(
        'panels retain independent feed rows while either has focus',
        () async {
          controller.desktopTopicTabs = true;
          final firstListId = controller.activeTabId!;
          controller.saveFeedScrollRow('latest', 12);
          controller.openLinkInNewTab(
            '/t/reader/303',
            panel: ForumPanel.secondary,
          );
          final readerId = controller.tabsForCurrentForum.last.id;
          controller.selectTab(readerId);
          controller.saveFeedScrollRow('latest', 18, tabId: firstListId);
          expect(controller.activeTabId, readerId);
          expect(controller.activeTab!.anchors['latest'], isNull);

          controller.createTab(panel: ForumPanel.main);
          final secondListId = controller.activeTabId!;
          controller.selectDestination(
            const SidebarDestination(
              id: 'latest',
              label: 'Topics',
              icon: DIcons.layerGroup,
            ),
          );
          expect(controller.selectedTabIn(ForumPanel.secondary)?.id, readerId);
          expect(controller.feedScrollRow('latest'), 0);
          controller.saveFeedScrollRow('latest', 3);
          controller.selectTab(firstListId);
          expect(controller.feedScrollRow('latest'), 18);
          controller.selectTab(secondListId);
          expect(controller.feedScrollRow('latest'), 3);

          controller.flushAnchorPersist();
          await Future<void>.delayed(Duration.zero);
          final saved = forumTabs.workspaces.firstWhere(
            (workspace) => workspace.siteUrl == forums.first.url,
          );
          expect(saved.tabById(firstListId)!.anchors['latest']?.itemId, 18);
          expect(saved.tabById(secondListId)!.anchors['latest']?.itemId, 3);
          expect(saved.tabById(readerId)!.anchors['latest'], isNull);
        },
      );

      test('moving a list to secondary preserves its reading position', () {
        controller.desktopTopicTabs = true;
        final listId = controller.activeTabId!;
        controller.saveFeedScrollRow('latest', 12);
        controller.moveTabToPanel(listId, ForumPanel.secondary);
        expect(controller.feedScrollRow('latest'), 12);
        controller.saveFeedScrollRow('latest', 3);
        controller.createTab(panel: ForumPanel.main);
        controller.saveFeedScrollRow('latest', 8);
        controller.selectTab(listId);
        expect(controller.feedScrollRow('latest'), 3);
      });

      test('restores topic posts independently', () {
        final firstTabId = controller.activeTabId!;
        controller.pushContent(_topic(303, 'Shared topic'));
        controller.saveTopicScrollPost(303, 18);

        controller.createTab();
        final secondTabId = controller.activeTabId!;
        controller.pushContent(_topic(303, 'Shared topic'));
        expect(controller.topicScrollPostNumber(303), isNull);
        controller.saveTopicScrollPost(303, 4);

        controller.selectTab(firstTabId);
        expect(controller.topicScrollPostNumber(303), 18);

        controller.selectTab(secondTabId);
        expect(controller.topicScrollPostNumber(303), 4);
      });
    });

    group('anchor persistence', () {
      test('coalesces rapid saves into one trailing write', () async {
        final anchorTabs = FakeForumTabStore();
        final scrolling = ShellController(
          instanceStore: FakeInstanceStore(forums),
          api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: anchorTabs,
          trackers: FakeSiteTracker.reset(),
          // Zero still defers to the next event-loop turn, so a synchronous
          // scroll burst shares one window without slowing the test down.
          anchorPersistDebounce: Duration.zero,
        );
        addTearDown(scrolling.dispose);
        await scrolling.load();
        scrolling.pushContent(_topic(303, 'Scrolled topic'));
        final savesBeforeScroll = anchorTabs.saveCount;

        scrolling.saveFeedScrollRow('latest', 4);
        scrolling.saveTopicScrollPost(303, 2);
        scrolling.saveTopicScrollPost(303, 9);
        scrolling.saveTopicScrollPost(303, 27, viewportOffset: -12);

        expect(scrolling.topicScrollPostNumber(303), 27);
        expect(anchorTabs.saveCount, savesBeforeScroll);

        await Future<void>.delayed(Duration.zero);

        expect(anchorTabs.saveCount, savesBeforeScroll + 1);
        final anchors = anchorTabs.workspaces.single.activeTab.anchors;
        expect(anchors['latest']?.itemId, 4);
        expect(anchors['topic-303']?.itemId, 27);
        expect(anchors['topic-303']?.offset, -12);

        await Future<void>.delayed(Duration.zero);
        expect(anchorTabs.saveCount, savesBeforeScroll + 1);
      });

      test('flushes a pending write on disposal', () async {
        final anchorTabs = FakeForumTabStore();
        final closing = ShellController(
          instanceStore: FakeInstanceStore(forums),
          api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: anchorTabs,
          trackers: FakeSiteTracker.reset(),
        );
        await closing.load();
        closing.pushContent(_topic(606, 'Closed topic'));
        final savesBeforeScroll = anchorTabs.saveCount;
        closing.saveTopicScrollPost(606, 21);
        expect(anchorTabs.saveCount, savesBeforeScroll);

        closing.dispose();

        expect(anchorTabs.saveCount, savesBeforeScroll + 1);
        expect(
          anchorTabs.workspaces.single.activeTab.anchors['topic-606']?.itemId,
          21,
        );
      });

      test('flushes a pending write on backgrounding', () async {
        controller.pushContent(_topic(707, 'Background topic'));
        final savesBeforeScroll = forumTabs.saveCount;
        controller.saveTopicScrollPost(707, 12);
        expect(forumTabs.saveCount, savesBeforeScroll);

        controller.setForeground(false);

        expect(forumTabs.saveCount, savesBeforeScroll + 1);
        expect(
          forumTabs.workspaces.single.activeTab.anchors['topic-707']?.itemId,
          12,
        );
      });
    });

    group('workspace persistence', () {
      test(
        'restores a Start page when a saved workspace has no main tab',
        () async {
          final secondary = ForumTab(
            id: 'secondary-only',
            rootDestinationId: 'latest',
            panel: ForumPanel.secondary,
            contentStack: [
              ContentRoute.fromDestination(
                _destination(forums.first, 'latest'),
              ),
            ],
          );
          final saved = FakeForumTabStore([
            ForumWorkspace(
              siteUrl: forums.first.url,
              accountIdentity: 'anonymous',
              tabs: [secondary],
              activeTabId: secondary.id,
            ),
          ]);
          final restored = ShellController(
            instanceStore: FakeInstanceStore(forums),
            api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
            authenticator: FakeAuthenticator(),
            drafts: FakeDraftStore(),
            forumTabs: saved,
            trackers: FakeSiteTracker.reset(),
          );
          addTearDown(restored.dispose);
          await restored.load();

          expect(restored.activeTabId, secondary.id);
          expect(
            restored.selectedTabIn(ForumPanel.secondary)?.id,
            secondary.id,
          );
          expect(
            restored.selectedTabIn(ForumPanel.main)?.currentContent.title,
            'Start page',
          );
        },
      );

      test(
        'restores tab order, active stack, and anchors after restart',
        () async {
          final firstTabId = controller.activeTabId!;
          controller.saveFeedScrollRow('latest', 8);
          controller.pushContent(_topic(404, 'Persisted topic'));
          controller.saveTopicScrollPost(404, 16);
          controller.createTab();
          final activeTabId = controller.activeTabId!;
          controller.selectDestination(_destination(forums[0], 'categories'));
          await Future<void>.delayed(Duration.zero);

          controller = ShellController(
            instanceStore: FakeInstanceStore(forums),
            api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
            authenticator: FakeAuthenticator(),
            drafts: FakeDraftStore(),
            forumTabs: forumTabs,
            trackers: FakeSiteTracker.reset(),
          );
          addTearDown(controller.dispose);
          await controller.load();

          expect(controller.tabsForCurrentForum.map((tab) => tab.id), [
            firstTabId,
            activeTabId,
          ]);
          expect(controller.activeTabId, activeTabId);
          expect(_routeIds(controller), ['categories']);

          controller.selectTab(firstTabId);
          expect(_routeIds(controller), ['latest', 'topic-404']);
          expect(controller.feedScrollRow('latest'), 8);
          expect(controller.topicScrollPostNumber(404), 16);
        },
      );

      test('flushes a tab selection awaiting paint on disposal', () async {
        final closingTabs = FakeForumTabStore();
        final closing = ShellController(
          instanceStore: FakeInstanceStore(forums),
          api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: closingTabs,
          trackers: FakeSiteTracker.reset(),
        );
        await closing.load();
        final firstTabId = closing.activeTabId!;
        closing.createTab();
        final savesBeforeSelection = closingTabs.saveCount;

        // A listener makes selection use the paint-first path. No frame is pumped
        // before disposal, matching a window closed immediately after the click.
        closing.addListener(() {});
        closing.selectTab(firstTabId);
        expect(closingTabs.saveCount, savesBeforeSelection);

        closing.dispose();

        expect(closingTabs.saveCount, savesBeforeSelection + 1);
        expect(closingTabs.workspaces.single.activeTabId, firstTabId);
      });
    });

    group('disabled mode', () {
      test('ignores tab lifecycle commands', () async {
        final disabledTabs = FakeForumTabStore();
        final disabled = ShellController(
          instanceStore: FakeInstanceStore(forums),
          api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: disabledTabs,
          forumTabsEnabled: false,
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(disabled.dispose);
        await disabled.load();

        final tabId = disabled.activeTabId!;
        disabled.pushContent(_topic(505, 'Kept topic'));
        final saveCount = disabledTabs.saveCount;

        disabled.createTab();
        disabled.selectTab(tabId);
        disabled.closeTab(tabId);
        disabled.moveTab(tabId, 3);
        disabled.closeOtherTabs(tabId);

        expect(disabled.tabsForCurrentForum, hasLength(1));
        expect(disabled.activeTabId, tabId);
        expect(_routeIds(disabled), ['latest', 'topic-505']);
        expect(disabledTabs.saveCount, saveCount);
      });

      test('migrates to the prior active tab', () async {
        final latest = ContentRoute.fromDestination(
          _destination(forums.first, 'latest'),
        );
        final categories = ContentRoute.fromDestination(
          _destination(forums.first, 'categories'),
        );
        final inactive = ForumTab(
          id: 'inactive-tab',
          rootDestinationId: 'latest',
          contentStack: [latest],
        );
        final active = ForumTab(
          id: 'active-tab',
          rootDestinationId: 'latest',
          contentStack: [latest, categories],
          anchors: const {'latest': ForumTabAnchor(kind: 'feed', itemId: 27)},
        );
        final disabledTabs = FakeForumTabStore([
          ForumWorkspace(
            siteUrl: forums.first.url,
            accountIdentity: 'anonymous',
            tabs: [inactive, active],
            activeTabId: active.id,
          ),
        ]);
        final disabled = ShellController(
          instanceStore: FakeInstanceStore(forums),
          api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: disabledTabs,
          forumTabsEnabled: false,
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(disabled.dispose);

        await disabled.load();

        expect(disabled.tabsForCurrentForum, [same(active)]);
        expect(disabled.activeTabId, active.id);
        expect(disabled.contentStack, active.contentStack);
        expect(disabled.activeTab?.anchors, active.anchors);
        expect(disabledTabs.saveCount, 1);
        expect(disabledTabs.workspaces.single.tabs, [same(active)]);
      });
    });
  });

  testWidgets('a quit request persists an anchor still inside its debounce', (
    tester,
  ) async {
    final forumTabs = _GatedForumTabStore();
    addTearDown(() {
      if (!forumTabs.release.isCompleted) forumTabs.release.complete();
    });
    await pumpShell(tester, desktop, forumTabs: forumTabs);
    final shell = tester.widget<ShellScope>(find.byType(ShellScope)).notifier!;
    shell.pushContent(_topic(909, 'Quit topic'));
    await tester.pumpAndSettle();
    final siteUrl = shell.currentInstance!.url;
    final savesBeforeScroll = forumTabs.saveCount;

    forumTabs.gated = true;
    shell.saveTopicScrollPost(909, 33, viewportOffset: -8);
    AppExitResponse? response;
    unawaited(
      tester.binding.handleRequestAppExit().then((value) => response = value),
    );
    await tester.pump();

    expect(forumTabs.saveCount, savesBeforeScroll + 1);
    final anchor = forumTabs.workspaces
        .singleWhere((workspace) => workspace.siteUrl == siteUrl)
        .activeTab
        .anchors['topic-909'];
    expect(anchor?.itemId, 33);
    expect(anchor?.offset, -8);
    // The answer waits for the write to land, not merely to start.
    expect(response, isNull);

    forumTabs.release.complete();
    await tester.pump();
    expect(response, AppExitResponse.exit);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _GatedForumTabStore extends FakeForumTabStore {
  final release = Completer<void>();
  bool gated = false;

  @override
  Future<void> save(
    Iterable<ForumWorkspace> workspaces, {
    String? selectedSiteUrl,
  }) async {
    await super.save(workspaces, selectedSiteUrl: selectedSiteUrl);
    if (gated) await release.future;
  }
}

ContentRoute _topic(int id, String title) =>
    ContentRoute.topic(topicId: id, slug: 'topic-$id', title: title);

SidebarDestination _destination(DiscourseInstance forum, String id) =>
    id == 'categories'
    ? const SidebarDestination(
        id: 'categories',
        label: 'Categories',
        icon: DIcons.filter,
      )
    : forum.sections
          .expand(
            (section) => [...section.destinations, ...section.moreDestinations],
          )
          .singleWhere((destination) => destination.id == id);

List<String> _routeIds(ShellController controller) => [
  for (final route in controller.contentStack) route.id,
];

void _expectNewTabRoot(ShellController controller) {
  expect(controller.destinationId, 'new-tab');
  expect(_routeIds(controller), ['new-tab']);
  expect(controller.currentContent?.title, 'Start page');
  expect(controller.currentContent?.icon, DIcons.house);
}
