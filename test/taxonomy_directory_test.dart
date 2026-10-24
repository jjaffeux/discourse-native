import 'dart:async';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _directoryRoot = TopicCategory(id: 1, name: 'Directory', color: '111111');
const _child = TopicCategory(
  id: 10,
  name: 'Child',
  color: '222222',
  parentCategoryId: 20,
);
const _cyclicParent = TopicCategory(
  id: 20,
  name: 'Parent',
  color: '333333',
  parentCategoryId: 10,
);
const _orphan = TopicCategory(
  id: 11,
  name: 'Orphan',
  color: '444444',
  parentCategoryId: 99,
);
const _oldRoot = TopicCategory(id: 2, name: 'Old root', color: '555555');
const _newRoot = TopicCategory(id: 3, name: 'New root', color: '666666');
const _oldTop = SidebarTag(id: 1, name: 'Old top', slug: 'old-top');
const _newTop = SidebarTag(id: 2, name: 'New top', slug: 'new-top');
const _oldTag = SidebarTag(id: 3, name: 'Old tag', slug: 'old-tag');
const _newTag = SidebarTag(id: 4, name: 'New tag', slug: 'new-tag');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final allowUncategorized in [false, true]) {
    test(
      'editor category search forwards allowUncategorizedTopics=$allowUncategorized',
      () async {
        final api = _EditorCategorySearchApi(allowUncategorized);
        final shell = await _loadShell(api);
        addTearDown(shell.dispose);

        expect(
          shell.siteConfigFor(_site).allowUncategorizedTopics,
          allowUncategorized,
        );
        final categories = await shell.searchTopicCategoriesForEditor(
          siteUrl: _site,
          term: 'Directory',
        );

        expect(api.includeUncategorizedRequests, [allowUncategorized]);
        expect(api.categorySearchTerms, ['Directory']);
        expect(categories, [_directoryRoot]);
      },
    );
  }

  test('tag searches preserve remote precedence and numeric ranking', () async {
    final api = _TagSearchApi()
      ..directory = const [
        SidebarTag(id: 1, name: 'MATCH', slug: 'match', count: 999),
        SidebarTag(id: 2, name: 'Local', slug: 'local', count: 5),
      ]
      ..remote = const [
        TopicFilterLookupValue(name: 'match', description: '1000'),
        TopicFilterLookupValue(name: 'MATCH', description: '2'),
        TopicFilterLookupValue(name: 'Hex', description: '0x10'),
        TopicFilterLookupValue(name: 'Signed', description: '+5'),
        TopicFilterLookupValue(name: 'Zulu', description: 'invalid'),
        TopicFilterLookupValue(name: 'Alpha'),
        TopicFilterLookupValue(name: 'Empty', description: ''),
        TopicFilterLookupValue(name: 'Negative', description: '-3'),
      ];
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);
    await shell.loadTags(_site);

    final results = await shell.searchFilterTags(siteUrl: _site, term: '');
    expect(results.map((tag) => (tag.name, tag.description)), [
      ('Hex', '0x10'),
      ('Local', '5'),
      ('Signed', '+5'),
      ('MATCH', '2'),
      ('Alpha', null),
      ('Empty', ''),
      ('Zulu', 'invalid'),
      ('Negative', '-3'),
    ]);
    expect(identical(results[3], api.remote[1]), isTrue);
  });

  test(
    'tag searches keep all local results and literal query matching',
    () async {
      final api = _TagSearchApi()
        ..directory = [
          for (var i = 0; i < 2048; i++)
            SidebarTag(
              id: i + 1,
              name: 'Tag-${i.toString().padLeft(4, '0')}',
              slug: 'tag-$i',
              count: i % 3,
            ),
          const SidebarTag(id: 3000, name: ' Tag ', slug: 'spaced', count: 10),
          const SidebarTag(
            id: 3001,
            name: 'Tag-private',
            slug: 'private',
            pmOnly: true,
            count: 9999,
          ),
        ];
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      await shell.loadTags(_site);

      final results = await shell.searchFilterTags(siteUrl: _site, term: 'TAG');
      expect(results.length, 2049);
      expect(results.first.name, ' Tag ');
      expect(results.skip(1).map((tag) => tag.name), [
        for (final rank in [2, 1, 0])
          for (var i = rank; i < 2048; i += 3)
            'Tag-${i.toString().padLeft(4, '0')}',
      ]);
      expect(
        (await shell.searchFilterTags(
          siteUrl: _site,
          term: ' TAG ',
        )).map((tag) => tag.name),
        [' Tag '],
      );
      expect(
        await shell.searchFilterTags(
          siteUrl: _site,
          term: 'TAG',
          categoryId: 7,
        ),
        isEmpty,
      );
      expect(api.filterTagRequests.last.categoryId, 7);
    },
  );

  test(
    'tag searches follow equal and changed taxonomy source snapshots',
    () async {
      final api = _TagSearchApi()
        ..directory = const [
          SidebarTag(id: 1, name: 'Shared', slug: 'shared', count: 1),
          SidebarTag(id: 2, name: 'Before', slug: 'before', count: 2),
        ]
        ..top = const [SidebarTag(id: 3, name: 'Top', slug: 'top', count: 3)]
        ..defaults = const [
          SidebarTag(id: 4, name: 'Default', slug: 'default', count: 4),
        ];
      final shell = await _loadShell(
        api,
        user: const DiscourseUser(
          id: 7,
          username: 'reader',
          sidebarTags: [
            SidebarTag(id: 5, name: 'Shared', slug: 'personal', count: 5),
          ],
        ),
      );
      addTearDown(shell.dispose);
      await shell.loadCategories(_site);
      await shell.loadTags(_site);

      Future<List<(String, String?)>> search() async => [
        for (final tag in await shell.searchFilterTags(
          siteUrl: _site,
          term: '',
        ))
          (tag.name, tag.description),
      ];
      const initial = [
        ('Shared', '5'),
        ('Default', '4'),
        ('Top', '3'),
        ('Before', '2'),
      ];
      expect(await search(), initial);
      api.directory = List.of(api.directory);
      api.top = List.of(api.top);
      api.defaults = List.of(api.defaults);
      await shell.loadTags(_site, force: true);
      await shell.loadCategories(_site, force: true);
      expect(await search(), initial);

      api.directory = const [
        SidebarTag(id: 2, name: 'After', slug: 'after', count: 20),
        SidebarTag(id: 1, name: 'Shared', slug: 'shared', count: 10),
      ];
      api.top = const [
        SidebarTag(id: 3, name: 'New top', slug: 'top', count: 30),
      ];
      api.defaults = const [];
      await shell.loadTags(_site, force: true);
      await shell.loadCategories(_site, force: true);
      expect(await search(), [
        ('New top', '30'),
        ('After', '20'),
        ('Shared', '5'),
      ]);

      shell.applyAccountSessionInstance(
        shell
            .instanceFor(_site)!
            .copyWith(
              user: const DiscourseUser(
                id: 7,
                username: 'reader',
                sidebarTags: [
                  SidebarTag(
                    id: 5,
                    name: 'Personal',
                    slug: 'personal',
                    count: 40,
                  ),
                ],
              ),
            ),
        AccountSessionPhase.connecting,
      );
      expect(await search(), [
        ('Personal', '40'),
        ('New top', '30'),
        ('After', '20'),
        ('Shared', '10'),
      ]);
    },
  );

  test(
    'tag searches resolve current local sources after remote completion',
    () async {
      final api = _TagSearchApi()..directory = const [_oldTag];
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      await shell.loadTags(_site);
      expect(
        (await shell.searchFilterTags(
          siteUrl: _site,
          term: '',
        )).map((tag) => tag.name),
        ['Old tag'],
      );
      final response = Completer<List<TopicFilterLookupValue>>();
      api.lookupResponse = response;
      final pending = shell.searchFilterTags(siteUrl: _site, term: '');
      await pumpEventQueue();
      api.directory = const [_newTag];
      await shell.loadTags(_site, force: true);
      response.complete(const []);
      expect((await pending).map((tag) => tag.name), ['New tag']);

      final oldResponse = Completer<List<TopicFilterLookupValue>>();
      api.lookupResponse = oldResponse;
      final stale = shell.searchFilterTags(siteUrl: _site, term: '');
      await pumpEventQueue();
      final replacement = shell
          .instanceFor(_site)!
          .copyWith(user: const DiscourseUser(id: 8, username: 'replacement'));
      shell.lifecycle.invalidate(_site);
      shell.clearAccountSessionState(_site);
      shell.applyAccountSessionInstance(
        replacement,
        AccountSessionPhase.connecting,
      );
      api.lookupResponse = null;
      api.directory = const [_oldTag];
      await shell.loadTags(_site);
      oldResponse.complete(const [
        TopicFilterLookupValue(name: 'Stale remote'),
      ]);
      expect(await stale, isEmpty);
      expect(
        (await shell.searchFilterTags(
          siteUrl: _site,
          term: '',
        )).map((tag) => tag.name),
        ['Old tag'],
      );
    },
  );

  test(
    'overlapping topic loads share missing category lookup and resolve ancestry',
    () async {
      final api = _LookupApi();
      final shell = await _loadShell(api);
      addTearDown(() async {
        shell.dispose();
        api.releasePendingLookups();
        await pumpEventQueue();
      });
      await shell.loadCategories(_site);
      expect(shell.categoryFeedFor(_site).categoryIds, [1]);

      final first = shell.loadTopic(41, 'first');
      await api.lookupStarted(10);
      final second = shell.loadTopic(42, 'second');
      await api.firstTwoTopicsReturned.future;
      await pumpEventQueue();
      expect(api.categoryIdsRequested, [
        [10],
      ]);

      api.answer(10, [_child]);
      await api.lookupStarted(20);
      expect(api.categoryIdsRequested, [
        [10],
        [20],
      ]);
      api.answer(20, [_cyclicParent]);
      await Future.wait([first, second]);

      expect(shell.categoryFor(10, siteUrl: _site), _child);
      expect(shell.categoryFor(20, siteUrl: _site), _cyclicParent);
      expect(
        shell.topicCategoryPathLabel(_child, siteUrl: _site),
        'Parent › Child',
      );
      expect(api.categoryIdsRequested, [
        [10],
        [20],
      ]);

      final inaccessible = shell.loadTopic(43, 'third');
      await api.lookupStarted(11);
      api.answer(11, [_orphan]);
      await api.lookupStarted(99);
      api.answer(99, const []);
      await inaccessible;

      expect(shell.categoryFor(11, siteUrl: _site), _orphan);
      expect(shell.categoryFor(99, siteUrl: _site), isNull);
      expect(shell.topicCategoryPathLabel(_orphan, siteUrl: _site), 'Orphan');
      expect(api.categoryIdsRequested, [
        [10],
        [20],
        [11],
        [99],
      ]);
      expect(shell.categoryFeedFor(_site).categoryIds, [1]);
      expect(
        shell.filterCategoriesFor(_site).map((category) => category.id),
        unorderedEquals([1, 10, 20, 11]),
      );
    },
  );

  test(
    'old category and tag refreshes cannot publish into a new account',
    () async {
      final api = _RefreshingTaxonomyApi();
      final shell = await _loadShell(
        api,
        user: const DiscourseUser(id: 7, username: 'old-reader'),
      );
      addTearDown(() async {
        shell.dispose();
        api.releaseOldRefreshes();
        await pumpEventQueue();
      });
      await shell.loadCategories(_site);
      await shell.loadTags(_site);
      expect(shell.categoryFeedFor(_site).categoryIds, [2]);
      expect(shell.topicListFilterTagsFor(_site), [_oldTop, _oldTag]);

      api.holdOldRefreshes();
      final oldCategories = shell.loadCategories(_site, force: true);
      final oldTags = shell.loadTags(_site, force: true);
      await Future.wait([
        api.oldCategoryRequested.future,
        api.oldTagsRequested.future,
      ]);

      final replacement = shell
          .instanceFor(_site)!
          .copyWith(user: const DiscourseUser(id: 8, username: 'new-reader'));
      shell.lifecycle.invalidate(_site);
      shell.clearAccountSessionState(_site);
      shell.applyAccountSessionInstance(
        replacement,
        AccountSessionPhase.connecting,
      );

      api.answerNewAccount();
      await shell.loadCategories(_site);
      await shell.loadTags(_site);
      expect(shell.categoryFeedFor(_site).categoryIds, [3]);
      expect(shell.filterCategoriesFor(_site).map((category) => category.id), [
        3,
      ]);
      expect(shell.tagDirectoryFeedFor(_site).tags, [_newTag]);
      expect(shell.topicListFilterTagsFor(_site), [_newTop, _newTag]);

      api.releaseOldRefreshes();
      await Future.wait([oldCategories, oldTags]);
      expect(shell.currentInstance!.user!.id, 8);
      expect(shell.categoryFeedFor(_site).categoryIds, [3]);
      expect(shell.filterCategoriesFor(_site).map((category) => category.id), [
        3,
      ]);
      expect(shell.tagDirectoryFeedFor(_site).tags, [_newTag]);
      expect(shell.topicListFilterTagsFor(_site), [_newTop, _newTag]);
    },
  );
}

Future<ShellController> _loadShell(
  FakeDiscourseApi api, {
  DiscourseUser user = const DiscourseUser(id: 7, username: 'reader'),
}) async {
  api.accounts['api-key'] = user;
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    ownsApi: false,
  );
  await shell.load();
  await pumpEventQueue();
  return shell;
}

final class _EditorCategorySearchApi extends FakeDiscourseApi {
  _EditorCategorySearchApi(bool allowUncategorized)
    : super(
        feeds: const {'/latest.json': []},
        siteConfigs: {
          _site: SiteConfig(allowUncategorizedTopics: allowUncategorized),
        },
        categorySearches: const {
          'Directory': [_directoryRoot],
        },
      );

  final includeUncategorizedRequests = <bool>[];

  @override
  Future<List<TopicCategory>> searchCategories({
    required String siteUrl,
    required String term,
    required String apiKey,
    bool includeUncategorized = true,
    bool includeAncestors = false,
    String? clientId,
  }) {
    includeUncategorizedRequests.add(includeUncategorized);
    return super.searchCategories(
      siteUrl: siteUrl,
      term: term,
      apiKey: apiKey,
      includeUncategorized: includeUncategorized,
      includeAncestors: includeAncestors,
      clientId: clientId,
    );
  }
}

final class _LookupApi extends FakeDiscourseApi {
  _LookupApi()
    : super(
        feeds: const {'/latest.json': []},
        categoryList: const [_directoryRoot],
        topics: {
          41: topicPayload(id: 41, title: 'First', categoryId: 10),
          42: topicPayload(id: 42, title: 'Second', categoryId: 10),
          43: topicPayload(id: 43, title: 'Third', categoryId: 11),
        },
      );

  final firstTwoTopicsReturned = Completer<void>();
  final _lookupResponses = <int, Completer<List<TopicCategory>>>{};
  final _lookupStarted = <int, Completer<void>>{};
  int _topicsReturned = 0;

  Future<void> lookupStarted(int id) =>
      _lookupStarted.putIfAbsent(id, Completer<void>.new).future;

  void answer(int id, List<TopicCategory> categories) =>
      _lookupResponses[id]!.complete(categories);

  void releasePendingLookups() {
    if (!firstTwoTopicsReturned.isCompleted) firstTwoTopicsReturned.complete();
    for (final started in _lookupStarted.values) {
      if (!started.isCompleted) started.complete();
    }
    for (final response in _lookupResponses.values) {
      if (!response.isCompleted) response.complete(const []);
    }
  }

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) async {
    final result = await super.topic(
      siteUrl: siteUrl,
      slug: slug,
      id: id,
      postNumber: postNumber,
      summary: summary,
      apiKey: apiKey,
      clientId: clientId,
      abortTrigger: abortTrigger,
    );
    _topicsReturned++;
    if (_topicsReturned == 2) firstTwoTopicsReturned.complete();
    return result;
  }

  @override
  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) {
    final requested = ids.toList(growable: false);
    categoryIdsRequested.add(requested);
    for (final id in requested) {
      final started = _lookupStarted.putIfAbsent(id, Completer<void>.new);
      if (!started.isCompleted) started.complete();
    }
    if (requested.length != 1) {
      return Future.error(TestFailure('Unexpected category batch: $requested'));
    }
    return _lookupResponses
        .putIfAbsent(requested.single, Completer<List<TopicCategory>>.new)
        .future;
  }
}

final class _RefreshingTaxonomyApi extends FakeDiscourseApi {
  _RefreshingTaxonomyApi()
    : super(
        feeds: const {'/latest.json': []},
        categoryList: const [_oldRoot],
        categorySiteTopTags: const [_oldTop],
        tagList: const [_oldTag],
      );

  final oldCategoryGate = Completer<CategoryLoadResult>();
  final oldTagGate = Completer<List<SidebarTag>>();
  final oldCategoryRequested = Completer<void>();
  final oldTagsRequested = Completer<void>();
  Future<CategoryLoadResult>? categoryResponse;
  Future<List<SidebarTag>>? tagResponse;

  void holdOldRefreshes() {
    categoryResponse = oldCategoryGate.future;
    tagResponse = oldTagGate.future;
  }

  void answerNewAccount() {
    categoryResponse = Future.value(
      CategoryLoadResult(const [_newRoot], siteTopTags: const [_newTop]),
    );
    tagResponse = Future.value(const [_newTag]);
  }

  void releaseOldRefreshes() {
    if (!oldCategoryRequested.isCompleted) oldCategoryRequested.complete();
    if (!oldTagsRequested.isCompleted) oldTagsRequested.complete();
    if (!oldCategoryGate.isCompleted) {
      oldCategoryGate.complete(
        CategoryLoadResult(const [_oldRoot], siteTopTags: const [_oldTop]),
      );
    }
    if (!oldTagGate.isCompleted) oldTagGate.complete(const [_oldTag]);
  }

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) {
    final response = categoryResponse;
    if (response == null) {
      return super.loadCategories(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        page: page,
      );
    }
    categoryRequests.add(siteUrl);
    categoryPagesRequested.add(page);
    if (identical(response, oldCategoryGate.future) &&
        !oldCategoryRequested.isCompleted) {
      oldCategoryRequested.complete();
    }
    return response;
  }

  @override
  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final response = tagResponse;
    if (response == null) {
      return super.tags(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);
    }
    tagRequests.add(siteUrl);
    if (identical(response, oldTagGate.future) &&
        !oldTagsRequested.isCompleted) {
      oldTagsRequested.complete();
    }
    return response;
  }
}

final class _TagSearchApi extends FakeDiscourseApi {
  _TagSearchApi() : super(feeds: const {'/latest.json': []});

  List<SidebarTag> directory = const [];
  List<SidebarTag> top = const [];
  List<SidebarTag> defaults = const [];
  List<TopicFilterLookupValue> remote = const [];
  Completer<List<TopicFilterLookupValue>>? lookupResponse;

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async => CategoryLoadResult(
    const [_directoryRoot],
    siteTopTags: top,
    anonymousDefaultTags: defaults,
  );

  @override
  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => directory;

  @override
  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
    int? categoryId,
    int limit = 5,
    String? apiKey,
    String? clientId,
  }) async {
    filterTagRequests.add((
      siteUrl: siteUrl,
      term: term,
      categoryId: categoryId,
    ));
    return lookupResponse == null ? remote : await lookupResponse!.future;
  }
}
