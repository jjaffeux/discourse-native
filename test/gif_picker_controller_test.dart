import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker_controller.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://forum.example';
const _shortCategory = GifCategory(
  title: 'Go',
  imageUrl: 'https://cdn.example/go.webp',
  searchTerm: 'go',
);

void main() {
  group('search admission and ordering', () {
    testWidgets('requires at least three typed characters', (tester) async {
      final api = _ControllableGifsApi();
      final controller = _controller(
        api,
        searchDebounce: const Duration(milliseconds: 700),
      );
      addTearDown(controller.dispose);

      controller.updateQuery('go');
      await tester.pump(const Duration(milliseconds: 700));
      expect(controller.hasActiveSearch, isFalse);
      expect(api.requests, isEmpty);
    });

    testWidgets('dispatches an accepted query after exactly 700ms', (
      tester,
    ) async {
      final api = _ControllableGifsApi();
      final controller = _controller(
        api,
        searchDebounce: const Duration(milliseconds: 700),
      );
      addTearDown(controller.dispose);

      controller.updateQuery('cat');
      expect(controller.searchPending, isTrue);
      await tester.pump(const Duration(milliseconds: 699));
      expect(api.requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(api.requests.single.query, 'cat');
      api.responses.single.complete(GifSearchPage(results: const []));
      await tester.pump();
    });

    testWidgets('ignores an older page after a newer query starts', (
      tester,
    ) async {
      final api = _ControllableGifsApi();
      final controller = _controller(
        api,
        searchDebounce: const Duration(milliseconds: 700),
      );
      addTearDown(controller.dispose);

      controller.updateQuery('cat');
      await tester.pump(const Duration(milliseconds: 700));
      controller.updateQuery('dogs');
      await tester.pump(const Duration(milliseconds: 700));
      expect(api.requests.map((request) => request.query), ['cat', 'dogs']);

      api.responses[0].complete(GifSearchPage(results: const [_catResult]));
      await tester.pump();
      expect(controller.results, isEmpty);

      api.responses[1].complete(GifSearchPage(results: const [_dogResult]));
      await tester.pump();
      expect(controller.results, const [_dogResult]);
      expect(controller.searching, isFalse);
    });

    testWidgets('only starts the first-page retry requested by a listener', (
      tester,
    ) async {
      final api = _ControllableGifsApi();
      final credentials = _CountingCredentials();
      final controller = _controller(api, credentials: credentials);
      addTearDown(controller.dispose);

      void retryWhenSearching() {
        if (!controller.searching) return;
        controller.removeListener(retryWhenSearching);
        unawaited(controller.retry());
      }

      controller.addListener(retryWhenSearching);
      final loading = controller.selectCategory(_shortCategory);
      await tester.pump();

      expect(credentials.apiKeyCalls, 1);
      expect(api.requests, [(query: 'go', position: '0')]);
      expect(controller.searching, isTrue);

      api.responses.single.complete(GifSearchPage(results: const [_dogResult]));
      await tester.pump();
      await loading;
      expect(controller.results, const [_dogResult]);
      expect(controller.searching, isFalse);
    });

    for (final staleFinishesFirst in [true, false]) {
      for (final staleFails in [true, false]) {
        testWidgets('isolates overlapping first-page retries '
            '(stale finishes first: $staleFinishesFirst, fails: $staleFails)', (
          tester,
        ) async {
          final api = _ControllableGifsApi();
          final controller = _controller(api);
          addTearDown(controller.dispose);

          final initial = controller.selectCategory(_shortCategory);
          await tester.pump();
          api.responses[0].completeError(Exception('Initial failure'));
          await tester.pump();
          await initial;
          expect(controller.error, isNotNull);

          final older = controller.retry();
          await tester.pump();
          final newer = controller.retry();
          await tester.pump();
          expect(api.requests, List.filled(3, (query: 'go', position: '0')));

          void completeOlder() {
            if (staleFails) {
              api.responses[1].completeError(Exception('Stale failure'));
            } else {
              api.responses[1].complete(
                GifSearchPage(results: const [_catResult]),
              );
            }
          }

          if (staleFinishesFirst) {
            completeOlder();
            await tester.pump();
            await older;
            expect(controller.results, isEmpty);
            expect(controller.error, isNull);
            expect(controller.searching, isTrue);
          }

          api.responses[2].complete(
            GifSearchPage(
              results: const [_dogResult],
              nextPosition: 'new-cursor',
            ),
          );
          await tester.pump();
          await newer;

          if (!staleFinishesFirst) {
            completeOlder();
            await tester.pump();
            await older;
          }

          expect(controller.results, const [_dogResult]);
          expect(controller.error, isNull);
          expect(controller.searching, isFalse);
          expect(controller.canLoadMore, isTrue);

          final more = controller.loadMore();
          await tester.pump();
          expect(api.requests.last, (query: 'go', position: 'new-cursor'));
          api.responses.last.complete(GifSearchPage(results: const []));
          await tester.pump();
          await more;
          expect(controller.results, const [_dogResult]);
          expect(controller.canLoadMore, isFalse);
        });
      }
    }

    test('keeps a short category term as an active search', () async {
      const result = GifResult(
        title: 'Go',
        url: 'https://cdn.example/go-result.webp',
        width: 320,
        height: 180,
      );
      final api = FakeDiscourseApi(
        gifCategoriesBySite: const {
          _siteUrl: [_shortCategory],
        },
        gifSearchPages: {
          FakeDiscourseApi.gifSearchKey('go'): GifSearchPage(
            results: const [result],
          ),
        },
      );
      final controller = _controller(api);
      addTearDown(controller.dispose);

      await controller.loadCategories();
      expect(controller.showingCategories, isTrue);
      expect(controller.hasActiveSearch, isFalse);

      await controller.selectCategory(_shortCategory);

      expect(controller.query, 'go');
      expect(controller.hasActiveSearch, isTrue);
      expect(controller.showingCategories, isFalse);
      expect(controller.results, const [result]);
      expect(api.gifSearchRequests.single.query, 'go');
    });

    test('shows a short category search error instead of categories', () async {
      final controller = _controller(_FailingSearchApi());
      addTearDown(controller.dispose);

      await controller.loadCategories();
      expect(controller.showingCategories, isTrue);

      await controller.selectCategory(_shortCategory);

      expect(controller.hasActiveSearch, isTrue);
      expect(controller.showingCategories, isFalse);
      expect(controller.error, 'Too many GIF searches. Try again in a moment.');
    });
  });

  group('search pagination', () {
    for (final change in ['query', 'category']) {
      testWidgets('abandons load-more when a listener changes the $change', (
        tester,
      ) async {
        final api = _ControllableGifsApi();
        final credentials = _CountingCredentials();
        final controller = _controller(
          api,
          credentials: credentials,
          searchDebounce: const Duration(milliseconds: 700),
        );
        addTearDown(controller.dispose);

        controller.updateQuery('cats');
        await tester.pump(const Duration(milliseconds: 700));
        api.responses.single.complete(
          GifSearchPage(
            results: const [_catResult],
            nextPosition: 'cat-cursor',
          ),
        );
        await tester.pump();

        void changeSearchWhenLoadingMore() {
          if (!controller.loadingMore) return;
          controller.removeListener(changeSearchWhenLoadingMore);
          if (change == 'query') {
            controller.updateQuery('dogs');
          } else {
            unawaited(controller.selectCategory(_shortCategory));
          }
        }

        controller.addListener(changeSearchWhenLoadingMore);
        final loadingMore = controller.loadMore();
        await tester.pump();

        expect(credentials.apiKeyCalls, change == 'query' ? 1 : 2);
        expect(controller.results, isEmpty);
        expect(controller.loadingMore, isFalse);

        if (change == 'query') {
          expect(controller.searchPending, isTrue);
          await tester.pump(const Duration(milliseconds: 699));
          expect(api.requests, [(query: 'cats', position: '0')]);
          await tester.pump(const Duration(milliseconds: 1));
        }

        expect(api.requests, [
          (query: 'cats', position: '0'),
          (query: change == 'query' ? 'dogs' : 'go', position: '0'),
        ]);
        expect(controller.searchPending, isFalse);
        expect(controller.searching, isTrue);

        api.responses.last.complete(GifSearchPage(results: const [_dogResult]));
        await tester.pump();
        await loadingMore;
        expect(controller.results, const [_dogResult]);
        expect(controller.error, isNull);
        expect(controller.searching, isFalse);
      });
    }

    test(
      'deduplicates cursor pages and stops at the exact result cap',
      () async {
        const duplicate = GifResult(
          title: 'Duplicate',
          url: 'https://cdn.example/duplicate.webp',
          width: 320,
          height: 180,
        );
        const third = GifResult(
          title: 'Third',
          url: 'https://cdn.example/third.webp',
          width: 320,
          height: 180,
        );
        const beyondCap = GifResult(
          title: 'Beyond cap',
          url: 'https://cdn.example/beyond.webp',
          width: 320,
          height: 180,
        );
        final api = FakeDiscourseApi(
          gifSearchPages: {
            FakeDiscourseApi.gifSearchKey('cats'): GifSearchPage(
              results: const [_catResult, duplicate],
              nextPosition: 'cursor/24',
            ),
            FakeDiscourseApi.gifSearchKey(
              'cats',
              position: 'cursor/24',
            ): GifSearchPage(
              results: const [duplicate, third, beyondCap],
              nextPosition: 'cursor/48',
            ),
          },
        );
        final controller = _controller(api, maxResults: 3);
        addTearDown(controller.dispose);

        await controller.selectCategory(
          const GifCategory(
            title: 'Cats',
            imageUrl: 'https://cdn.example/cats.webp',
            searchTerm: 'cats',
          ),
        );
        expect(controller.results, const [_catResult, duplicate]);
        expect(controller.canLoadMore, isTrue);

        await controller.loadMore();

        expect(controller.results, const [_catResult, duplicate, third]);
        expect(controller.canLoadMore, isFalse);
        expect(api.gifSearchRequests.map((request) => request.position), [
          '0',
          'cursor/24',
        ]);
      },
    );

    test(
      'keeps results and cursor for retry after a load-more failure',
      () async {
        final api = _RetryingPaginationApi();
        final controller = _controller(api);
        addTearDown(controller.dispose);

        await controller.selectCategory(
          const GifCategory(
            title: 'Cats',
            imageUrl: 'https://cdn.example/cats.webp',
            searchTerm: 'cats',
          ),
        );
        expect(controller.results, const [_catResult]);

        await controller.loadMore();

        expect(controller.results, const [_catResult]);
        expect(
          controller.error,
          "Couldn't load GIFs. Check the connection and try again.",
        );
        expect(controller.canLoadMore, isTrue);

        await controller.retry();

        expect(controller.results, const [_catResult, _dogResult]);
        expect(controller.error, isNull);
        expect(controller.canLoadMore, isFalse);
        expect(api.loadMoreAttempts, 2);
      },
    );
  });

  group('request invalidation and disposal', () {
    test(
      'does not report missing credentials for an invalidated category lease',
      () async {
        final credentials = _GatedCredentials();
        final lifecycle = SiteLifecycle();
        final api = FakeDiscourseApi();
        final controller = _controller(
          api,
          credentials: credentials,
          lifecycle: lifecycle,
        );
        addTearDown(controller.dispose);

        final loading = controller.loadCategories();
        await credentials.started.future;
        lifecycle.invalidate(_siteUrl);
        credentials.result.complete('old-key');
        await loading;

        expect(controller.error, isNull);
        expect(api.gifCategoryRequests, isEmpty);
      },
    );

    test(
      'does not report missing credentials for an invalidated search lease',
      () async {
        final credentials = _GatedCredentials();
        final lifecycle = SiteLifecycle();
        final api = FakeDiscourseApi();
        final controller = _controller(
          api,
          credentials: credentials,
          lifecycle: lifecycle,
        );
        addTearDown(controller.dispose);

        final loading = controller.selectCategory(_shortCategory);
        await credentials.started.future;
        lifecycle.invalidate(_siteUrl);
        credentials.result.complete('old-key');
        await loading;

        expect(controller.hasActiveSearch, isTrue);
        expect(controller.error, isNull);
        expect(api.gifSearchRequests, isEmpty);
      },
    );

    test('stops API work when disposed during credential lookup', () async {
      final credentials = _GatedCredentials();
      final api = FakeDiscourseApi();
      final controller = _controller(api, credentials: credentials);

      final loading = controller.loadCategories();
      await credentials.started.future;
      controller.dispose();
      credentials.result.complete('stale-key');
      await loading;

      expect(credentials.clientIdCalls, 1);
      expect(api.gifCategoryRequests, isEmpty);
      expect(controller.error, isNull);
    });
  });
}

GifPickerController _controller(
  GifsApi api, {
  FakeApiCredentialReader? credentials,
  SiteLifecycle? lifecycle,
  Duration searchDebounce = Duration.zero,
  int? maxResults,
}) {
  final resolvedCredentials = credentials ?? FakeApiCredentialReader();
  resolvedCredentials.keys[_siteUrl] = 'key';
  return GifPickerController(
    siteUrl: _siteUrl,
    api: api,
    requests: FakePluginRequestHost(
      credentials: resolvedCredentials,
      lifecycle: lifecycle ?? SiteLifecycle(),
    ),
    fileDetail: 'webp',
    searchDebounce: searchDebounce,
    maxResults: maxResults,
  );
}

const _catResult = GifResult(
  title: 'Cat',
  url: 'https://cdn.example/cat.webp',
  width: 320,
  height: 180,
);
const _dogResult = GifResult(
  title: 'Dog',
  url: 'https://cdn.example/dog.webp',
  width: 320,
  height: 180,
);

final class _ControllableGifsApi implements GifsApi {
  final List<({String query, String position})> requests = [];
  final List<Completer<GifSearchPage>> responses = [];

  @override
  Future<List<GifCategory>> gifCategories({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => const [];

  @override
  Future<GifSearchPage> searchGifs({
    required String siteUrl,
    required String apiKey,
    required String query,
    required String fileDetail,
    String position = '0',
    String? clientId,
  }) {
    requests.add((query: query, position: position));
    final response = Completer<GifSearchPage>();
    responses.add(response);
    return response.future;
  }
}

final class _RetryingPaginationApi implements GifsApi {
  int loadMoreAttempts = 0;

  @override
  Future<List<GifCategory>> gifCategories({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => const [];

  @override
  Future<GifSearchPage> searchGifs({
    required String siteUrl,
    required String apiKey,
    required String query,
    required String fileDetail,
    String position = '0',
    String? clientId,
  }) async {
    if (position == '0') {
      return GifSearchPage(
        results: const [_catResult],
        nextPosition: 'cursor/24',
      );
    }
    loadMoreAttempts += 1;
    if (loadMoreAttempts == 1) {
      throw const SiteLookupException(
        SiteLookupFailure.unreachable,
        _siteUrl,
        statusCode: 502,
      );
    }
    return GifSearchPage(results: const [_dogResult]);
  }
}

final class _FailingSearchApi implements GifsApi {
  @override
  Future<List<GifCategory>> gifCategories({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => const [_shortCategory];

  @override
  Future<GifSearchPage> searchGifs({
    required String siteUrl,
    required String apiKey,
    required String query,
    required String fileDetail,
    String position = '0',
    String? clientId,
  }) async => throw const SiteLookupException(
    SiteLookupFailure.unreachable,
    _siteUrl,
    statusCode: 429,
  );
}

final class _GatedCredentials extends FakeApiCredentialReader {
  final Completer<void> started = Completer<void>();
  final Completer<String?> result = Completer<String?>();
  int clientIdCalls = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }

  @override
  Future<String> clientId() async {
    clientIdCalls++;
    return super.clientId();
  }
}

final class _CountingCredentials extends FakeApiCredentialReader {
  int apiKeyCalls = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    apiKeyCalls++;
    return super.apiKeyFor(siteUrl);
  }
}
