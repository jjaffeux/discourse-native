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
  testWidgets(
    'requires three characters, debounces 700ms, and ignores a stale page',
    (tester) async {
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

      controller.updateQuery('cat');
      expect(controller.searchPending, isTrue);
      await tester.pump(const Duration(milliseconds: 699));
      expect(api.requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(api.requests.single.query, 'cat');

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
    },
  );

  test(
    'a short category term remains an active search after loading',
    () async {
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
    },
  );

  test('deduplicates cursor pages and stops at the exact result cap', () async {
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
  });

  test('load-more failure keeps results and cursor for a retry', () async {
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
    expect(controller.error, isNotNull);
    expect(controller.canLoadMore, isTrue);

    await controller.retry();

    expect(controller.results, const [_catResult, _dogResult]);
    expect(controller.error, isNull);
    expect(controller.canLoadMore, isFalse);
    expect(api.loadMoreAttempts, 2);
  });

  test(
    'a short category search exposes its search error, not categories',
    () async {
      final controller = _controller(_FailingSearchApi());
      addTearDown(controller.dispose);

      await controller.loadCategories();
      expect(controller.showingCategories, isTrue);

      await controller.selectCategory(_shortCategory);

      expect(controller.hasActiveSearch, isTrue);
      expect(controller.showingCategories, isFalse);
      expect(controller.error, 'Too many GIF searches. Try again in a moment.');
    },
  );

  test(
    'an invalidated category lease does not claim credentials are missing',
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
    'an invalidated search lease does not claim credentials are missing',
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

  test('dispose during credential lookup stops API work', () async {
    final credentials = _GatedCredentials();
    final api = FakeDiscourseApi();
    final controller = _controller(api, credentials: credentials);

    final loading = controller.loadCategories();
    await credentials.started.future;
    controller.dispose();
    credentials.result.complete('stale-key');
    await loading;

    // The host returns one atomic credential snapshot, so it may complete
    // both private-store reads even though the picker was disposed midway.
    expect(credentials.clientIdCalls, 1);
    expect(api.gifCategoryRequests, isEmpty);
    expect(controller.error, isNull);
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
