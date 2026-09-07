import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/sidebar_section_store.dart';
import 'package:discourse_native/src/data/topic_sidebar_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';
const _parent = TopicCategory(id: 8, name: 'Design', color: '0088CC');
const _category = TopicCategory(
  id: 9,
  name: 'Interface',
  color: '0088CC',
  parentCategoryId: 8,
);
const _topic = Topic(
  id: 7,
  title: 'Ready topic',
  slug: 'ready-topic',
  categoryId: 9,
  tags: [TopicTag(name: 'smooth')],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a feed first appears with its category, parent, and tags', (
    tester,
  ) async {
    final api = _DelayedNavigationApi();
    final shell = await _shell(api);
    final loading = shell.loadFeed('latest');
    await tester.pumpWidget(
      _app(
        shell,
        ListenableBuilder(
          listenable: shell.topicFeeds,
          builder: (context, _) =>
              TopicListView(feed: shell.currentFeed ?? const TopicFeed()),
        ),
      ),
    );
    await tester.pump();

    expect(api.categoryLookups.single.ids, [9]);
    expect(find.text(_topic.title), findsNothing);
    expect(
      find.byKey(const ValueKey('topic-list-loading-skeleton')),
      findsOneWidget,
    );

    api.categoryLookups.single.response.complete([_category]);
    await tester.pump();
    expect(api.categoryLookups.last.ids, [8]);
    expect(find.text(_topic.title), findsNothing);

    api.categoryLookups.last.response.complete([_parent]);
    await tester.pump();
    await loading;
    expect(find.text(_topic.title), findsOneWidget);
    expect(find.text('Interface'), findsOneWidget);
    expect(find.text('Design'), findsOneWidget);
    expect(find.text('smooth'), findsOneWidget);
    final tagBounds = tester.getRect(find.text('smooth'));
    final titleBounds = tester.getRect(find.text(_topic.title));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getRect(find.text('smooth')), tagBounds);
    expect(tester.getRect(find.text(_topic.title)), titleBounds);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a topic joins a pending feed lookup before showing its posts', (
    tester,
  ) async {
    final api = _DelayedNavigationApi();
    final shell = await _shell(api);
    final feed = shell.loadFeed('latest');
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: _topic.slug, title: _topic.title),
    );
    final loading = shell.loadTopic(7, _topic.slug);
    await tester.pumpWidget(_app(shell, const TopicView()));
    await tester.pump();
    expect(api.categoryLookups, hasLength(1));
    expect(find.byType(CookedHtml), findsNothing);

    api.categoryLookups.single.response.complete([_category, _parent]);
    await tester.pump();
    await Future.wait([feed, loading]);
    expect(find.byType(CookedHtml), findsOneWidget);
    expect(api.categoryLookups, hasLength(1));
    expect(shell.categoryFor(9), _category);
    expect(shell.categoryFor(8), _parent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed category lookup still releases the topic', (
    tester,
  ) async {
    final api = _DelayedNavigationApi(includeFeed: false);
    final shell = await _shell(api);
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: _topic.slug, title: _topic.title),
    );
    final loading = shell.loadTopic(7, _topic.slug);
    await tester.pumpWidget(_app(shell, const TopicView()));
    await tester.pump();
    api.categoryLookups.single.response.completeError(StateError('offline'));
    await tester.pump();
    await loading;
    expect(find.byType(CookedHtml), findsOneWidget);
    expect(shell.currentTopicLoading, isFalse);
  });

  testWidgets(
    'taxonomy navigation waits for settings and restores its sections together',
    (tester) async {
      final configGate = Completer<void>();
      final api = _DelayedNavigationApi(
        includeFeed: false,
        configGate: configGate,
      );
      final shell = await _shell(api);
      final persistence = _DelayedSections();
      final store = SidebarSectionStore(persistence: persistence);
      Widget sidebar() =>
          SizedBox(width: 280, child: InstanceSidebar(sectionStore: store));
      await tester.pumpWidget(_app(shell, sidebar()));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('sidebar-loading-skeleton')),
        findsWidgets,
      );
      for (final pending in persistence.reads.values) {
        pending.complete(false);
      }
      await tester.pump();
      expect(find.text('Topics'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sidebar-loading-skeleton')),
        findsOneWidget,
      );

      api.navigation.complete(
        CategoryLoadResult(
          [_parent, _category],
          siteTopTags: const [
            SidebarTag(id: 1, name: 'smooth', slug: 'smooth'),
          ],
        ),
      );
      await tester.pump();
      expect(shell.categoryFeedFor(_site).loaded, isFalse);
      expect(find.text('Design'), findsNothing);

      configGate.complete();
      await tester.pump();
      await tester.pump();
      expect(persistence.reads.keys, containsAll(['categories', 'tags']));
      expect(find.text('Design'), findsNothing);
      for (final entry in persistence.reads.entries) {
        if (entry.key != 'tags' && !entry.value.isCompleted) {
          entry.value.complete(entry.key == 'categories');
        }
      }
      await tester.pump();
      expect(
        find.byKey(const ValueKey('sidebar-loading-skeleton')),
        findsOneWidget,
      );

      persistence.reads['tags']!.complete(false);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('sidebar-loading-skeleton')),
        findsNothing,
      );
      expect(
        find.text('Design'),
        findsNothing,
        reason: 'The saved collapsed section must never flash open.',
      );
      expect(find.text('smooth'), findsOneWidget);
      final tagBounds = tester.getRect(find.text('smooth'));
      final reads = persistence.readCount;

      await tester.pumpWidget(_app(shell, const SizedBox.shrink()));
      await tester.pumpWidget(_app(shell, sidebar()));
      expect(
        find.byKey(const ValueKey('sidebar-loading-skeleton')),
        findsNothing,
      );
      expect(find.text('Design'), findsNothing);
      expect(tester.getRect(find.text('smooth')), tagBounds);
      expect(persistence.readCount, reads);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a restored hidden topic sidebar never narrows the post stream', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _DelayedNavigationApi(includeFeed: false);
    final shell = await _shell(api);
    shell.store.putAll(_site, [_parent, _category]);
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: _topic.slug, title: _topic.title),
    );
    await shell.loadTopic(7, _topic.slug);
    final persistence = _DelayedTopicSidebar();
    final store = TopicSidebarStore(persistence: persistence);
    Widget reader() => TopicView(showSidebar: true, sidebarStore: store);

    await tester.pumpWidget(_app(shell, reader()));
    expect(find.byType(CookedHtml), findsNothing);
    expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
    persistence.read.complete(true);
    await tester.pump();
    expect(find.byType(CookedHtml), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
    final width = tester.getSize(find.byType(CookedHtml)).width;

    await tester.pumpWidget(_app(shell, const SizedBox.shrink()));
    await tester.pumpWidget(_app(shell, reader()));
    expect(find.byType(CookedHtml), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-loading-skeleton')), findsNothing);
    expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
    expect(tester.getSize(find.byType(CookedHtml)).width, width);
    expect(persistence.reads, 1);
  });
}

Future<ShellController> _shell(_DelayedNavigationApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.example')]),
    api: api,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() {
    shell.dispose();
    if (!api.navigation.isCompleted) {
      api.navigation.complete(CategoryLoadResult([]));
    }
  });
  await shell.load();
  return shell;
}

Widget _app(ShellController shell, Widget body) => ShellScope(
  controller: shell,
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: body),
  ),
);

final class _CategoryLookup {
  _CategoryLookup(Iterable<int> ids) : ids = ids.toList();
  final List<int> ids;
  final response = Completer<List<TopicCategory>>();
}

final class _DelayedNavigationApi extends FakeDiscourseApi {
  _DelayedNavigationApi({bool includeFeed = true, Completer<void>? configGate})
    : super(
        feeds: {
          '/latest.json': includeFeed ? [_topic] : [],
        },
        siteConfigs: {_site: const SiteConfig()},
        siteConfigGate: configGate,
        topics: {
          7: topicPayload(
            id: 7,
            title: _topic.title,
            categoryId: 9,
            tags: _topic.tags,
            posts: const [
              Post(
                id: 70,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>Ready content</p>',
              ),
            ],
          ),
        },
      );
  final navigation = Completer<CategoryLoadResult>();
  final List<_CategoryLookup> categoryLookups = [];

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) => navigation.future;

  @override
  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) {
    final lookup = _CategoryLookup(ids);
    categoryLookups.add(lookup);
    return lookup.response.future;
  }
}

final class _DelayedSections implements SidebarSectionPersistence {
  final Map<String, Completer<bool?>> reads = {};
  int readCount = 0;

  @override
  Future<bool?> readCollapsed({
    required String siteUrl,
    required String sectionId,
  }) {
    readCount++;
    return reads.putIfAbsent(sectionId, Completer<bool?>.new).future;
  }

  @override
  Future<bool> writeCollapsed({
    required String siteUrl,
    required String sectionId,
    required bool collapsed,
  }) async => true;
}

final class _DelayedTopicSidebar implements TopicSidebarPersistence {
  final read = Completer<bool?>();
  int reads = 0;

  @override
  Future<bool?> readCollapsed({required String siteUrl}) {
    reads++;
    return read.future;
  }

  @override
  Future<bool> writeCollapsed({
    required String siteUrl,
    required bool collapsed,
  }) async => true;
}
