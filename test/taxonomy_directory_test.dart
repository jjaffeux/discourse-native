import 'dart:async';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
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
