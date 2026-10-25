import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _old = TopicCategory(id: 1, name: 'Deleted root', color: '111111');
const _fresh = TopicCategory(id: 2, name: 'Fresh root', color: '222222');
const _later = TopicCategory(id: 3, name: 'Later root', color: '333333');
const _stale = TopicCategory(id: 4, name: 'Stale page', color: '444444');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'user refresh replaces roots and restarts exhausted pagination',
    () async {
      final api = _CategoryRefreshApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      shell.pushContent(ContentRoute.allCategories());
      await shell.loadMoreCategories(_site);
      expect(shell.categoryFeedFor(_site).nextPage, isNull);

      api.pages = {
        1: [_fresh],
        2: [_later],
      };
      await shell.refreshCurrentTab();
      expect(shell.categoryFeedFor(_site).categoryIds, [2]);
      expect(shell.categoryFeedFor(_site).nextPage, 2);
      expect(shell.categoryFor(1, siteUrl: _site), _old);
      await shell.loadMoreCategories(_site);
      expect(shell.categoryFeedFor(_site).categoryIds, [2, 3]);
      expect(shell.categoryFeedFor(_site).nextPage, 3);
      expect(api.categoryPagesRequested, [1, 2, 1, 2]);

      await shell.loadCategories(_site);
      expect(shell.categoryFeedFor(_site).categoryIds, [2, 3]);
      expect(api.categoryPagesRequested, [1, 2, 1, 2]);
    },
  );

  test('an empty refreshed directory has no roots or later page', () async {
    final api = _CategoryRefreshApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);
    api.pages = {};
    await shell.loadCategories(_site, force: true);
    expect(shell.categoryFeedFor(_site).categoryIds, isEmpty);
    expect(shell.categoryFeedFor(_site).nextPage, isNull);
    expect(shell.categoryFor(1, siteUrl: _site), _old);
    await shell.loadMoreCategories(_site);
    expect(api.categoryPagesRequested, [1, 1]);
  });

  for (final fails in [false, true]) {
    test('refresh fences an older page with failure=$fails', () async {
      final api = _CategoryRefreshApi();
      final shell = await _loadShell(api);
      final oldPage = Completer<CategoryLoadResult>();
      final refreshedPage = Completer<CategoryLoadResult>();
      addTearDown(() async {
        shell.dispose();
        if (!oldPage.isCompleted) {
          oldPage.complete(CategoryLoadResult(const []));
        }
        if (!refreshedPage.isCompleted) {
          refreshedPage.complete(CategoryLoadResult(const []));
        }
        await pumpEventQueue();
      });
      api.responses[2] = oldPage.future;
      final loadingOld = shell.loadMoreCategories(_site);
      await pumpEventQueue();
      api.responses[1] = refreshedPage.future;
      final refreshing = shell.loadCategories(_site, force: true);
      await pumpEventQueue();
      expect(shell.categoryFeedFor(_site).loading, isTrue);
      expect(shell.categoryFeedFor(_site).loadingMore, isFalse);
      await shell.loadMoreCategories(_site);
      expect(api.categoryPagesRequested, [1, 2, 1]);

      refreshedPage.complete(CategoryLoadResult(const [_fresh]));
      await refreshing;
      if (fails) {
        oldPage.completeError(StateError('Old page failed'));
      } else {
        oldPage.complete(CategoryLoadResult(const [_stale]));
      }
      await loadingOld;
      expect(shell.categoryFeedFor(_site).categoryIds, [2]);
      expect(shell.categoryFeedFor(_site).nextPage, 2);
      expect(shell.categoryFeedFor(_site).error, isNull);
      expect(shell.categoryFor(4, siteUrl: _site), isNull);
      api.responses.clear();
      api.pages = {
        1: [_fresh],
        2: [_later],
      };
      await shell.loadMoreCategories(_site);
      expect(shell.categoryFeedFor(_site).categoryIds, [2, 3]);
    });
  }

  test(
    'an incomplete same-snapshot retry preserves accumulated pages',
    () async {
      final api = _CategoryRefreshApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      api.complete = false;
      api.pages = {
        1: [_fresh],
        2: [_later],
      };
      await shell.loadCategories(_site, force: true);
      await shell.loadMoreCategories(_site);
      expect(shell.categoryFeedFor(_site).categoryIds, [2, 3]);
      api.complete = true;
      await shell.loadCategories(_site);
      expect(shell.categoryFeedFor(_site).categoryIds, [2, 3]);
      expect(shell.categoryFeedFor(_site).nextPage, 3);
    },
  );

  test('explicit refresh supersedes an ordinary first-page retry', () async {
    final api = _CategoryRefreshApi();
    final shell = await _loadShell(api);
    final oldResponse = Completer<CategoryLoadResult>();
    addTearDown(() async {
      shell.dispose();
      if (!oldResponse.isCompleted) {
        oldResponse.complete(CategoryLoadResult(const []));
      }
      await pumpEventQueue();
    });
    api.complete = false;
    await shell.loadCategories(_site, force: true);
    api.responses[1] = oldResponse.future;
    final oldLoad = shell.loadCategories(_site);
    await pumpEventQueue();
    api.responses.clear();
    api.pages = {
      1: [_fresh],
    };
    final refresh = shell.loadCategories(_site, force: true);
    await pumpEventQueue();
    expect(api.categoryPagesRequested, [1, 1, 1, 1]);
    oldResponse.complete(CategoryLoadResult(const [_stale]));
    await Future.wait([oldLoad, refresh]);
    expect(shell.categoryFeedFor(_site).categoryIds, [2]);
    expect(shell.categoryFor(4, siteUrl: _site), isNull);
  });

  test('refresh blocks paging while credentials are pending', () async {
    final api = _CategoryRefreshApi();
    final authenticator = _GatedAuthenticator()..keys[_site] = 'api-key';
    final shell = await _loadShell(api, authenticator: authenticator);
    final gate = Completer<String?>();
    addTearDown(() async {
      shell.dispose();
      if (!gate.isCompleted) gate.complete('api-key');
      await pumpEventQueue();
    });
    authenticator.gate = gate;
    final refresh = shell.loadCategories(_site, force: true);
    expect(shell.categoryFeedFor(_site).loading, isTrue);
    final more = shell.loadMoreCategories(_site);
    await pumpEventQueue();
    expect(api.categoryPagesRequested, [1]);
    gate.complete('api-key');
    await Future.wait([refresh, more]);
    expect(api.categoryPagesRequested, [1, 1]);
  });

  test('a refresh from a Store listener stops the old page merge', () async {
    final api = _CategoryRefreshApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);
    api.pages = {
      1: [_fresh],
      2: [_stale, _later],
    };
    Future<void>? refresh;
    final ref = shell.store.ref<TopicCategory>(_site, 4);
    void refreshOnCategory() {
      refresh ??= shell.loadCategories(_site, force: true);
    }

    ref.addListener(refreshOnCategory);
    addTearDown(() => ref.removeListener(refreshOnCategory));
    await shell.loadMoreCategories(_site);
    expect(refresh, isNotNull);
    await refresh;
    expect(shell.categoryFeedFor(_site).categoryIds, [2]);
    expect(shell.categoryFor(3, siteUrl: _site), isNull);
  });

  test(
    'failed refresh keeps cached roots and the next refresh replaces them',
    () async {
      final api = _CategoryRefreshApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      await shell.loadMoreCategories(_site);
      api.error = StateError('Refresh failed');
      await shell.loadCategories(_site, force: true);
      expect(shell.categoryFeedFor(_site).categoryIds, [1]);
      expect(shell.categoryFeedFor(_site).error, isNotNull);
      api.error = null;
      api.pages = {
        1: [_fresh],
      };
      await shell.loadCategories(_site, force: true);
      expect(shell.categoryFeedFor(_site).categoryIds, [2]);
      expect(shell.categoryFeedFor(_site).nextPage, 2);
      expect(shell.categoryFeedFor(_site).error, isNull);
    },
  );
}

Future<ShellController> _loadShell(
  _CategoryRefreshApi api, {
  FakeAuthenticator? authenticator,
}) async {
  const user = DiscourseUser(id: 7, username: 'reader');
  api.accounts['api-key'] = user;
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: api,
    authenticator:
        authenticator ?? (FakeAuthenticator()..keys[_site] = 'api-key'),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    ownsApi: false,
  );
  await shell.load();
  await pumpEventQueue();
  await shell.loadCategories(_site);
  return shell;
}

final class _GatedAuthenticator extends FakeAuthenticator {
  Completer<String?>? gate;

  @override
  Future<String?> apiKeyFor(String siteUrl) =>
      gate?.future ?? super.apiKeyFor(siteUrl);
}

final class _CategoryRefreshApi extends FakeDiscourseApi {
  _CategoryRefreshApi() : super(feeds: const {'/latest.json': []});

  Map<int, List<TopicCategory>> pages = {
    1: [_old],
  };
  final responses = <int, Future<CategoryLoadResult>>{};
  bool complete = true;
  Object? error;

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async {
    categoryRequests.add(siteUrl);
    categoryPagesRequested.add(page);
    if (error case final error?) throw error;
    final response = responses[page];
    if (response != null) return response;
    return CategoryLoadResult(pages[page] ?? const [], complete: complete);
  }
}
