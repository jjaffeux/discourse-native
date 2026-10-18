import 'package:discourse_native/src/models/badge_route.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native list paths retain the URL bound', () {
    const forum = DiscourseInstance(
      url: 'https://forum.example',
      title: 'Forum',
    );
    const prefix = '/latest.json?search=';
    final words = 'x' * (ListLink.maximumUrlLength - prefix.length);
    ContentRoute? decode(String query) => ContentRouteCodec.fromUrl(
      '${forum.url}/latest?search=$query',
      instance: forum,
      config: forum.config,
      defaultTopPeriod: TopPeriod.all,
    );

    expect(decode(words)?.feedPath?.length, ListLink.maximumUrlLength);
    expect(decode('${words}x'), isNull);
  });

  test('legacy taxonomy queries retain list behavior under custom keys', () {
    for (final query in ['category=42', 'tags[]=design']) {
      final route = ContentRoute.fromJson({
        'id': 'custom-feed',
        'title': 'Saved feed',
        'icon': DIcons.list.name,
        'feed_path': '/latest.json?$query',
      });
      expect(route.destination, isA<FeedDestination>());
      expect(route.isTopicList, isTrue);
      expect(route.isTopicListFilter, isTrue);
      expect(route.id, 'custom-feed');
      expect(
        ContentRoute.fromJson(route.toJson()).destination,
        isA<FeedDestination>(),
      );
    }
  });

  test('group and badge keys remain canonical across typed saves', () {
    for (final destination in [
      GroupDestination(GroupRoute.detail('team')),
      BadgeDestination(BadgeRoute.detail(5)),
    ]) {
      final route = ContentRoute(
        destination: destination,
        title: 'Saved',
        icon: DIcons.star,
      );
      final restored = ContentRoute.fromJson(route.toJson());
      expect(restored.destination.runtimeType, destination.runtimeType);
      expect(restored.id, destination.key);
      expect(restored.groupRoute, route.groupRoute);
      expect(restored.badgeRoute, route.badgeRoute);
      expect(
        () => ContentRoute.fromJson({...route.toJson(), 'id': 'mismatched'}),
        throwsFormatException,
      );
    }
  });

  test(
    'typed extensions retain display and identity matching legacy aliases',
    () {
      for (final key in ['new-tab', 'filter', 'themes', 'users']) {
        final route = ContentRoute(
          destination: ExtensionDestination(key),
          title: 'Plugin title',
          icon: DIcons.star,
        );
        final restored = ContentRoute.fromJson(route.toJson());
        expect(restored.destination, isA<ExtensionDestination>());
        expect(restored.id, key);
        expect(restored.title, route.title);
        expect(restored.icon, route.icon);
      }
    },
  );

  test('legacy topic payload retains its saved key and optional slug', () {
    final route = ContentRoute.fromJson({
      'id': 'restored-topic-42-at-7',
      'title': 'Saved topic',
      'icon': DIcons.comments.name,
      'topic_id': 42,
      'post_number': 7,
      'feed_path': '/latest.json?status=open',
    });

    expect(route.destination, isA<TopicDestination>());
    expect(route.id, 'restored-topic-42-at-7');
    expect(route.topicId, 42);
    expect(route.slug, isNull);
    expect(route.postNumber, 7);
    expect(route.feedPath, '/latest.json?status=open');
    final restored = ContentRoute.fromJson(route.toJson());
    expect(restored.id, 'restored-topic-42-at-7');
    expect(restored.topicId, 42);
    expect(restored.postNumber, 7);
    expect(restored.feedPath, '/latest.json?status=open');
  });

  test('legacy opaque plugin routes preserve identity and source', () {
    final route = ContentRoute.fromJson({
      'id': 'plugin-room-4',
      'title': 'Plugin room',
      'icon': DIcons.microphoneLines.name,
      'feed_path': '/plugin/room/4.json?sort=recent',
    });

    expect(route.destination, isA<ExtensionDestination>());
    expect(route.isTopicList, isFalse);
    expect(route.id, 'plugin-room-4');
    expect(route.feedPath, '/plugin/room/4.json?sort=recent');
    final restored = ContentRoute.fromJson(route.toJson());
    expect(restored.destination, isA<ExtensionDestination>());
    expect(restored.id, 'plugin-room-4');
    expect(restored.feedPath, '/plugin/room/4.json?sort=recent');
  });

  test('restored placement flags do not become destination state', () {
    final route = ContentRoute.fromJson({
      'id': 'users',
      'title': 'Users',
      'icon': DIcons.users.name,
      'open_in_secondary_panel': true,
      'open_in_new_tab': true,
    });

    expect(route.destination, isA<PageDestination>());
    expect(route.id, 'users');
    expect(route.toJson(), isNot(contains('open_in_secondary_panel')));
    expect(route.toJson(), isNot(contains('open_in_new_tab')));
    expect(
      route,
      const ContentRoute(
        destination: PageDestination(CorePage.users),
        title: 'Users',
        icon: DIcons.users,
      ),
    );
  });

  test('runtime destination types own message and feed modes', () {
    const opaqueMessage = ContentRoute(
      destination: ExtensionDestination('messages-unread'),
      title: 'Extension',
      icon: DIcons.inbox,
    );
    const opaqueFeed = ContentRoute(
      destination: ExtensionDestination('latest'),
      title: 'Extension',
      icon: DIcons.list,
    );
    const messages = ContentRoute(
      destination: MessagesDestination(
        mode: MessageListMode.archive,
        legacyKey: 'custom-archive',
      ),
      title: 'Archive',
      icon: DIcons.inbox,
    );
    const feed = ContentRoute(
      destination: FeedDestination(
        key: 'custom-unread',
        mode: TopicListMode.unread,
      ),
      title: 'Unread',
      icon: DIcons.list,
    );

    expect(opaqueMessage.isMessages, isFalse);
    expect(TopicListMode.fromRoute(opaqueFeed), isNull);
    expect(messages.isMessages, isTrue);
    expect(messages.messageListMode, MessageListMode.archive);
    expect(messages.isTopicList, isTrue);
    expect(TopicListMode.fromRoute(feed), TopicListMode.unread);
    expect(feed.isTopicList, isTrue);
  });

  test(
    'persistence retains explicit kinds and modes independently of keys',
    () {
      const feed = ContentRoute(
        destination: FeedDestination(
          key: 'custom-feed',
          sourcePath: '/custom-feed.json?status=open',
          mode: TopicListMode.unread,
        ),
        title: 'Unread',
        icon: DIcons.list,
      );
      const messages = ContentRoute(
        destination: MessagesDestination(
          mode: MessageListMode.archive,
          legacyKey: 'custom-archive',
        ),
        title: 'Archive',
        icon: DIcons.inbox,
      );
      const extension = ContentRoute(
        destination: ExtensionDestination('latest', sourcePath: '/latest.json'),
        title: 'Extension',
        icon: DIcons.comment,
      );

      final restoredFeed = ContentRoute.fromJson(feed.toJson());
      expect(restoredFeed.destination, isA<FeedDestination>());
      expect(restoredFeed.id, 'custom-feed');
      expect(restoredFeed.feedPath, '/custom-feed.json?status=open');
      expect(TopicListMode.fromRoute(restoredFeed), TopicListMode.unread);

      final restoredMessages = ContentRoute.fromJson(messages.toJson());
      expect(restoredMessages.isMessages, isTrue);
      expect(restoredMessages.id, 'custom-archive');
      expect(restoredMessages.messageListMode, MessageListMode.archive);

      final restoredExtension = ContentRoute.fromJson(extension.toJson());
      expect(restoredExtension.destination, isA<ExtensionDestination>());
      expect(restoredExtension.id, 'latest');
      expect(restoredExtension.feedPath, '/latest.json');
      expect(TopicListMode.fromRoute(restoredExtension), isNull);
    },
  );

  test('restored directory tabs adopt updated default icons', () {
    for (final (page, oldIcon, newIcon) in [
      (CorePage.users, DIcons.user, DIcons.users),
      (CorePage.activity, DIcons.list, DIcons.barsStaggered),
    ]) {
      final id = page.key;
      final saved = ContentRoute(
        destination: PageDestination(page),
        title: id,
        icon: oldIcon,
      ).toJson();
      expect(ContentRoute.fromJson(saved).icon, newIcon);
      final custom = ContentRoute(
        destination: PageDestination(page),
        title: id,
        icon: DIcons.star,
      );
      expect(ContentRoute.fromJson(custom.toJson()).icon, DIcons.star);
    }
  });

  test('forum About is distinct from application About and persists', () {
    final route = ContentRoute.forumAbout();
    expect(route.isForumAbout, isTrue);
    expect(route.tabTitle, 'About this forum');
    expect(ContentRoute.fromJson(route.toJson()).isForumAbout, isTrue);
    expect(ContentRoute.appearance().isForumAbout, isFalse);
  });

  test('start page uses house and upgrades saved new tabs', () {
    final route = ContentRoute.newTab();
    expect(route.tabTitle, 'Start page');
    expect(route.icon, DIcons.house);
    expect(ContentRoute.fromJson(route.toJson()), route);

    final restored = ContentRoute.fromJson({
      ...route.toJson(),
      'title': 'New tab',
      'icon': DIcons.house.name,
    });
    expect(restored.tabTitle, 'Start page');
    expect(restored.icon, DIcons.house);
  });

  test(
    'tab titles describe topic modes, including restored and filtered tabs',
    () {
      final route = ContentRoute.topicList(TopicListMode.topYearly);
      expect(route.tabTitle, 'Top - year');
      expect(ContentRoute.fromJson(route.toJson()).tabTitle, 'Top - year');
      expect(
        ContentRoute.filteredTopicList(
          TopicListMode.topMonthly,
          categoryId: 42,
          tags: const ['design'],
        ).tabTitle,
        'Top - month',
      );
      expect(ContentRoute.topicList(TopicListMode.latest).tabTitle, 'Latest');
      expect(ContentRoute.topicList(TopicListMode.unread).tabTitle, 'Unread');
      expect(ContentRoute.topicFilter('status:open').tabTitle, 'Topics');
      expect(
        ContentRoute.topic(
          topicId: 42,
          slug: 'design',
          title: 'Design',
        ).tabTitle,
        'Design',
      );
    },
  );

  group('topic list sorting', () {
    test('preserves filters and mode, resets pagination, and round trips', () {
      for (final mode in TopicListMode.values) {
        final source = ContentRoute.filteredTopicList(
          mode,
          categoryId: 42,
          tags: const ['design', 'mobile'],
        );
        final paged = ContentRoute.fromJson({
          ...source.toJson(),
          'feed_path': '${source.feedPath}&page=3&status=open',
        });
        final sorted = paged.withTopicListSort('posts', ascending: true);
        expect(sorted.id, isNot(source.id));
        expect(sorted.topicListOrder, 'posts');
        expect(sorted.topicListAscending, isTrue);
        expect(TopicListMode.fromRoute(sorted), mode);
        expect(sorted.categoryId, 42);
        expect(sorted.tagNames, ['design', 'mobile']);
        final query = Uri.parse(sorted.feedPath!).queryParameters;
        expect(query['page'], isNull);
        expect(query['status'], 'open');
        expect(ContentRoute.fromJson(sorted.toJson()), sorted);

        final cleared = sorted.withTopicListSort(null);
        expect(cleared.topicListOrder, isNull);
        expect(cleared.topicListAscending, isFalse);
        expect(TopicListMode.fromRoute(cleared), mode);
        expect(cleared.categoryId, 42);
        expect(cleared.tagNames, ['design', 'mobile']);
      }
    });

    test(
      'clears the last sort parameter and retains sorting across filters',
      () {
        final sorted = ContentRoute.topicList(
          TopicListMode.latest,
        ).withTopicListSort('activity');
        expect(sorted.withTopicListSort(null).feedPath, '/latest.json');
        final filtered = ContentRoute.filteredTopicList(
          TopicListMode.topWeekly,
          categoryId: 42,
        ).withTopicListQueryFrom(sorted);
        expect(filtered.topicListOrder, 'activity');
        expect(TopicListMode.fromRoute(filtered), TopicListMode.topWeekly);
        expect(filtered.categoryId, 42);
      },
    );

    test('names a list given its parameters as switching to it does', () {
      final sorted = ContentRoute.topicList(
        TopicListMode.latest,
      ).withTopicListSort('views');
      for (final mode in TopicListMode.values) {
        final switched = ContentRoute.topicList(
          mode,
        ).withTopicListQueryFrom(sorted);
        final given = ContentRoute.filteredTopicList(
          mode,
          query: const {
            'order': ['views'],
          },
        );
        expect(given.id, switched.id);
        expect(given.feedPath, switched.feedPath);
        expect(TopicListMode.fromRoute(given), mode);
      }
      expect(
        ContentRoute.filteredTopicList(TopicListMode.unread).id,
        ContentRoute.topicList(TopicListMode.unread).id,
      );
    });

    test('does not invent ordering for unsupported sources or columns', () {
      for (final source in [
        ContentRoute.messages(),
        ContentRoute.topicFilter('status:open order:views'),
        ContentRoute.topic(topicId: 1, slug: 'topic', title: 'Topic'),
      ]) {
        expect(source.canSortTopicList, isFalse);
        expect(source.withTopicListSort('posts'), same(source));
      }
      final latest = ContentRoute.topicList(TopicListMode.latest);
      expect(latest.withTopicListSort('last-poster'), same(latest));
    });
  });

  test(
    'advanced filters round trip with taxonomy and compile one API query',
    () {
      final route = ContentRoute.topicFilter(
        'status:open',
        categoryId: 42,
        tags: const ['ux', 'bug'],
      );
      final restored = ContentRoute.fromJson(route.toJson());
      expect(restored, route);
      expect(restored.isTopicList, isTrue);
      expect(restored.topicFilterQuery, 'status:open');
      expect(restored.categoryId, 42);
      expect(restored.tagNames, ['ux', 'bug']);
      expect(Uri.parse(restored.topicFilterRequestPath).queryParameters, {
        'q': 'status:open category:42 tag:ux+bug',
      });
      expect(
        ContentRoute.fromJson({
          ...route.toJson(),
          'id': 'filter',
        }).isAdvancedTopicFilter,
        isTrue,
      );
    },
  );

  group('visible list word filters persist', () {
    test('word replacement drops endpoint q copied by taxonomy navigation', () {
      final carried = ContentRoute.filteredTopicList(
        TopicListMode.latest,
        categoryId: 12,
      ).withTopicListQueryFrom(ContentRoute.searchList('旧' * 2048));
      final words = '新' * 2048;
      final replaced = carried.withTopicListSearch(words);

      expect(
        Uri.parse(replaced.feedPath!).queryParameters.containsKey('q'),
        isFalse,
      );
      expect(replaced.topicListSearch, words);
      expect(replaced.categoryId, 12);
      expect(ContentRoute.fromJson(replaced.toJson()), replaced);
    });

    test('Unicode search bounds survive encoding and scoped round trips', () {
      final query = '中' * 2048;
      final group = '团' * ContentRoute.maximumMessageGroupNameLength;
      for (final route in [
        ContentRoute.topicList(TopicListMode.latest).withTopicListSearch(query),
        ContentRoute.list(
          ListLink.parse('/c/support/12?status=open&tags[]=ux&tags[]=mobile')!,
        ).withTopicListSearch(query).withTopicListSort('posts'),
        ContentRoute.filteredTopicList(
          TopicListMode.unread,
          categoryId: 12,
          tags: const ['design', 'mobile'],
        ).withTopicListSearch(query),
        ContentRoute.topicFilter(query, categoryId: 12, tags: const ['design']),
        ContentRoute.searchList(query),
        ContentRoute.messages(groupName: group).withTopicListSearch(query),
        ContentRoute.searchList(
          '$query in:personal group_messages:$group',
          groupName: group,
          messageMode: MessageListMode.inbox,
        ),
      ]) {
        final restored = ContentRoute.fromJson(route.toJson());
        expect(restored, route);
        expect(restored.feedPath, route.feedPath);
        expect(restored.messageGroupName, route.messageGroupName);
        expect(
          Uri.parse(restored.feedPath!).queryParametersAll,
          Uri.parse(route.feedPath!).queryParametersAll,
        );
      }
    });

    test('restores list word filters beside their scope', () {
      for (final source in [
        ContentRoute.topicList(TopicListMode.latest),
        ContentRoute.topicList(TopicListMode.newTopics),
        ContentRoute.topicList(TopicListMode.topWeekly),
        ContentRoute.list(ListLink.parse('/c/ux/42?status=open')!),
        ContentRoute.list(ListLink.parse('/tag/design?assigned=nobody')!),
        ContentRoute.filteredTopicList(
          TopicListMode.unread,
          categoryId: 42,
          tags: const ['design', 'mobile'],
        ),
      ]) {
        final legacy = source.withTopicListSearch('café & layout');
        final saved = {
          ...legacy.toJson(),
          'feed_path': '${legacy.feedPath}&page=3&custom[]=one&custom[]=two',
        };
        final restored = ContentRoute.fromJson(saved);
        final expectedQuery = {
          ...Uri.parse(saved['feed_path']! as String).queryParametersAll,
        };

        expect(restored.id, legacy.id);
        expect(restored.title, legacy.title);
        expect(restored.isTopicList, isTrue);
        expect(restored.categoryId, legacy.categoryId);
        expect(restored.tagNames, legacy.tagNames);
        expect(
          TopicListMode.fromRoute(restored),
          TopicListMode.fromRoute(legacy),
        );
        expect(restored.topicListSearch, 'café & layout');
        expect(Uri.parse(restored.feedPath!).queryParametersAll, expectedQuery);
        expect(ContentRoute.fromJson(restored.toJson()), restored);
      }
    });

    test('retains a sole word query for the shared field', () {
      final legacy = ContentRoute.topicList(
        TopicListMode.latest,
      ).withTopicListSearch('layout');
      expect(
        ContentRoute.fromJson(legacy.toJson()).feedPath,
        '/latest.json?search=layout',
      );
    });

    test(
      'preserves unrelated search parameters on topic and plugin routes',
      () {
        for (final source in const [
          ContentRoute(
            destination: TopicDestination(
              topicId: 42,
              retainedFeedPath: '/latest.json?search=layout',
            ),
            title: 'Topic',
            icon: DIcons.comments,
          ),
          ContentRoute(
            destination: ExtensionDestination(
              'plugin-custom',
              sourcePath: '/plugin-custom.json?search=layout',
            ),
            title: 'Plugin',
            icon: DIcons.magnifyingGlass,
          ),
        ]) {
          final restored = ContentRoute.fromJson(source.toJson());
          expect(restored.feedPath, source.feedPath);
          expect(restored.id, source.id);
        }
      },
    );

    test('retains back and forward word filters and tab anchors', () {
      final past = ContentRoute.topicList(
        TopicListMode.latest,
      ).withTopicListSearch('layout');
      final future = ContentRoute.topicList(
        TopicListMode.unread,
      ).withTopicListSearch('design');
      final tab = ForumTab(
        id: 'saved-tab',
        rootDestinationId: 'latest',
        contentStack: [
          past,
          ContentRoute.topic(topicId: 42, slug: 'design', title: 'Design'),
        ],
        forwardStack: [future],
        anchors: {
          past.id: const ForumTabAnchor(kind: 'feed', itemId: 17),
          future.id: const ForumTabAnchor(kind: 'feed', itemId: 19),
        },
      );
      final restored = ForumTab.tryFromJson(tab.toJson())!;
      expect(restored.contentStack.first.feedPath, past.feedPath);
      expect(restored.forwardStack.single.feedPath, future.feedPath);
      expect(restored.currentContent.topicId, 42);
      expect(restored.anchors[past.id]?.itemId, 17);
      expect(restored.anchors[future.id]?.itemId, 19);
    });
  });

  test('restored routes reject feed components that cannot be decoded', () {
    final saved = ContentRoute.topicList(TopicListMode.topYearly).toJson();
    for (final path in [
      '/tag/%FF.json',
      '/top.json?period=%C3',
      '/latest.json?tags[]=%ED%A0%80',
    ]) {
      expect(
        () => ContentRoute.fromJson({...saved, 'feed_path': path}),
        throwsFormatException,
        reason: path,
      );
    }
  });

  group('ContentRoute category identity', () {
    test('restores slug-only category lists with distinct query filters', () {
      final open = ContentRoute.list(
        ListLink.parse('/c/todo?status=open&assigned=nobody')!,
      );
      final closed = ContentRoute.list(
        ListLink.parse('/c/todo?status=closed&assigned=nobody')!,
      );
      final restored = ContentRoute.fromJson(open.toJson());

      expect(restored.id, open.id);
      expect(restored.id, isNot(closed.id));
      expect(restored.feedPath, '/c/todo.json?status=open&assigned=nobody');
      expect(restored.isTopicList, isTrue);
      expect(restored.isTopicListFilter, isTrue);
      expect(restored.title, 'Todo');
    });

    test('resolves the root category while retaining the feed identity', () {
      final route = ContentRoute.list(
        ListLink.parse('/c/todo?status=open&assigned=nobody')!,
      );
      final resolved = route.resolveCategoryLink(const [
        TopicCategory(
          id: 9,
          name: 'Nested Todo',
          slug: 'todo',
          color: '112233',
          parentCategoryId: 3,
        ),
        TopicCategory(id: 5, name: 'Todo', slug: 'todo', color: '112233'),
      ]);

      expect(resolved.id, route.id);
      expect(resolved, isNot(route));
      expect(resolved.categoryId, 5);
      expect(resolved.feedPath, '/c/todo/5.json?status=open&assigned=nobody');
      expect(ContentRoute.fromJson(resolved.toJson()).categoryId, 5);
    });

    test('resolves encoded category slugs and leaves unknown slugs alone', () {
      final route = ContentRoute.list(ListLink.parse('/c/caf%C3%A9')!);
      expect(route.resolveCategoryLink(const []), same(route));
      final resolved = route.resolveCategoryLink(const [
        TopicCategory(id: 5, name: 'Café', slug: 'caf%C3%A9', color: '112233'),
      ]);

      expect(resolved.categoryId, 5);
      expect(resolved.feedPath, '/c/caf%C3%A9/5.json');
    });

    test('dropdown changes retain filters but replace selections and page', () {
      final source = ContentRoute.list(
        ListLink.parse(
          '/c/todo/5?status=open&assigned=nobody&category=5&tags[]=old'
          '&page=3&period=daily&subset=topics&custom[]=one&custom[]=two',
        )!,
      );
      final route = ContentRoute.filteredTopicList(
        TopicListMode.topWeekly,
        categoryId: 6,
        tags: const ['urgent'],
      ).withTopicListQueryFrom(source);

      expect(TopicListMode.fromRoute(route), TopicListMode.topWeekly);
      expect(Uri.parse(route.feedPath!).queryParametersAll, {
        'status': ['open'],
        'assigned': ['nobody'],
        'custom[]': ['one', 'two'],
        'period': ['weekly'],
        'category': ['6'],
        'tags[]': ['urgent'],
        'match_all_tags': ['true'],
      });
    });

    test('reads top-level and nested category feed paths', () {
      expect(ContentRoute.list(ListLink.parse('/c/support/5')!).categoryId, 5);
      expect(
        ContentRoute.list(ListLink.parse('/c/parent/support/12')!).categoryId,
        12,
      );
    });

    test('does not identify tag or ordinary feed routes as categories', () {
      expect(
        ContentRoute.list(ListLink.parse('/tag/support/5')!).categoryId,
        isNull,
      );
      expect(ContentRoute.topicList(TopicListMode.latest).categoryId, isNull);
    });

    test('reads a category from a combined category and tag route', () {
      const withoutTagId = ContentRoute(
        destination: FeedDestination(
          key: 'filtered',
          sourcePath: '/tags/c/discourse-native/12/ux.json',
        ),
        title: 'Native',
        icon: DIcons.folder,
      );
      const withTagId = ContentRoute(
        destination: FeedDestination(
          key: 'filtered',
          sourcePath: '/tags/c/meta/discourse-native/12/ux/41.json',
        ),
        title: 'Native',
        icon: DIcons.folder,
      );
      const idOnlyCategory = ContentRoute(
        destination: FeedDestination(
          key: 'filtered',
          sourcePath: '/tags/c/12/ux.json',
        ),
        title: 'Native',
        icon: DIcons.folder,
      );

      expect(withoutTagId.categoryId, 12);
      expect(withTagId.categoryId, 12);
      expect(idOnlyCategory.categoryId, 12);
    });
  });

  group('ContentRoute tag identity', () {
    test('reads slug-only, identified, and category-scoped tag routes', () {
      expect(ContentRoute.list(ListLink.parse('/tag/ux')!).tagName, 'ux');
      expect(ContentRoute.list(ListLink.parse('/tag/ux/41')!).tagName, 'ux');
      expect(
        const ContentRoute(
          destination: FeedDestination(
            key: 'filtered',
            sourcePath: '/tags/c/discourse-native/12/design-feedback.json',
          ),
          title: 'Native',
          icon: DIcons.folder,
        ).tagName,
        'design-feedback',
      );
      expect(
        const ContentRoute(
          destination: FeedDestination(
            key: 'filtered',
            sourcePath: '/tags/c/discourse-native/12/design-feedback/41.json',
          ),
          title: 'Native',
          icon: DIcons.folder,
        ).tagName,
        'design-feedback',
      );
    });

    test('reads the id an identified tag list names its tag by', () {
      final identified = ContentRoute.list(ListLink.parse('/tag/7-tag/7')!);
      expect(identified.tagId, 7);
      expect(identified.tagName, '7-tag');
      expect(ContentRoute.list(ListLink.parse('/tag/ux')!).tagId, isNull);
      expect(ContentRoute.list(ListLink.parse('/c/support/5')!).tagId, isNull);
      expect(
        ContentRoute.filteredTopicList(
          TopicListMode.newActivity,
          tags: const ['中文'],
        ).tagId,
        isNull,
      );
    });

    test('filtered modes round trip category, multiple tags, and period', () {
      for (final mode in TopicListMode.values) {
        final route = ContentRoute.filteredTopicList(
          mode,
          categoryId: 22,
          tags: const ['community', 'design-feedback'],
        );
        final restored = ContentRoute.fromJson(route.toJson());
        expect(TopicListMode.fromRoute(restored), mode);
        expect(restored.categoryId, 22);
        expect(restored.tagNames, ['community', 'design-feedback']);
        expect(restored.isTopicList, isTrue);
        final uri = Uri.parse(restored.feedPath!);
        expect(uri.queryParametersAll['tags[]'], [
          'community',
          'design-feedback',
        ]);
        expect(uri.queryParameters['match_all_tags'], 'true');
        if (mode.topPeriod case final period?) {
          expect(uri.queryParameters['period'], period.queryValue);
        }
      }
    });

    test('does not identify category or ordinary feeds as tags', () {
      expect(
        ContentRoute.list(ListLink.parse('/c/support/5')!).tagName,
        isNull,
      );
      expect(ContentRoute.topicList(TopicListMode.latest).tagName, isNull);
      expect(ContentRoute.list(ListLink.parse('/tag/41')!).tagName, isNull);
    });

    test('recognizes discovery modes, category, and tag lists as filters', () {
      expect(
        ContentRoute.topicList(TopicListMode.latest).isTopicListFilter,
        isTrue,
      );
      expect(
        ContentRoute.topicList(TopicListMode.topWeekly).isTopicListFilter,
        isTrue,
      );
      expect(
        ContentRoute.list(ListLink.parse('/c/support/5')!).isTopicListFilter,
        isTrue,
      );
      expect(
        ContentRoute.list(ListLink.parse('/tag/ux')!).isTopicListFilter,
        isTrue,
      );
    });
  });
}
