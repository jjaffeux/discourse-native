import 'dart:async';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker_controller.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_api.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_settings.dart';
import 'package:discourse_native/src/shell/image_decode.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/blank_png.dart';
import 'support/fake_image_http_client.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _errorMessage = "Couldn't load GIFs. Check the connection and try again.";
const _result = GifResult(
  title: 'Cat dance',
  url: 'https://media.klipy.example/cat-dance.webp',
  width: 240,
  height: 180,
);

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets('$platform picker shows loading throughout held requests', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _HeldGifsApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: Scaffold(
            body: Builder(
              builder: (context) => DButton(
                label: const Text('Open held GIF picker'),
                onPressed: () => unawaited(
                  showGifPicker(
                    context: context,
                    siteUrl: _siteUrl,
                    api: api,
                    requests: FakePluginRequestHost(
                      credentials: FakeAuthenticator()
                        ..keys[_siteUrl] = 'api-key',
                      lifecycle: SiteLifecycle(),
                    ),
                    settings: const GifsSettings(enabled: true),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open held GIF picker'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final loading = find.byKey(const ValueKey('gif-picker-loading'));
      expect(loading, findsOneWidget);
      expect(
        tester.widget<DSkeletonRegion>(loading).semanticsLabel,
        'Loading categories…',
      );
      expect(tester.getSize(loading).height, greaterThan(200));
      expect(find.byType(DSkeleton), findsWidgets);
      expect(find.byKey(const ValueKey('gif-category-0')), findsNothing);
      if (platform == TargetPlatform.android) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getSize(loading).height, greaterThan(100));
        expect(tester.getBottomLeft(loading).dy, lessThanOrEqualTo(564));
      }

      api.categoryResponse.complete(const [_category]);
      await tester.pump();
      await tester.pump();
      expect(loading, findsNothing);
      expect(find.byKey(const ValueKey('gif-category-0')), findsOneWidget);
      final search = find.byKey(const ValueKey('gif-picker-search'));
      await tester.enterText(search, 'ca');
      await tester.pump();
      expect(find.byKey(const ValueKey('gif-category-0')), findsOneWidget);
      expect(loading, findsNothing);

      await tester.enterText(search, 'cats');
      await tester.pump();
      expect(loading, findsOneWidget);
      expect(
        tester.widget<DSkeletonRegion>(loading).semanticsLabel,
        'Searching…',
      );
      expect(api.searches, isEmpty);
      await tester.pump(const Duration(milliseconds: 700));
      expect(api.searches.single.query, 'cats');
      expect(loading, findsOneWidget);
      api.searches.single.response.complete(
        GifSearchPage(results: const [_result]),
      );
      await tester.pump();
      await tester.pump();
      expect(loading, findsNothing);
      expect(find.byKey(const ValueKey('gif-result-0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gif-picker-clear')));
      await tester.pump();
      expect(find.byKey(const ValueKey('gif-category-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gif-category-0')));
      await tester.pump();
      expect(api.searches.last.query, _category.searchTerm);
      expect(loading, findsOneWidget);
      api.searches.last.response.complete(
        GifSearchPage(results: _firstPage, nextPosition: 'next'),
      );
      await tester.pump();
      await tester.pump();
      expect(loading, findsNothing);
      final grid = find.byKey(const ValueKey('gif-picker-results'));
      await tester.drag(grid, const Offset(0, -5000));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(api.searches.last.position, 'next');
      final paging = find.byKey(const ValueKey('gif-picker-page-loading'));
      expect(paging, findsOneWidget);
      expect(tester.getSize(paging).height, greaterThan(0));
      expect(find.byTooltip(RegExp('Choose Cat [0-9]+ GIF')), findsWidgets);
      expect(
        tester.widget<GifPicker>(find.byType(GifPicker)).controller.results,
        _firstPage,
      );
      expect(find.byKey(const ValueKey('gif-picker-load-more')), findsNothing);
      api.searches.last.response.complete(GifSearchPage(results: const []));
      await tester.pump();
      await tester.pump();
      expect(paging, findsNothing);
      expect(find.byTooltip(RegExp('Choose Cat [0-9]+ GIF')), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('gif-picker-close')));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('only a reopened picker can search with a replacement account', (
    tester,
  ) async {
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'old-key';
    final lifecycle = SiteLifecycle();
    final requests = FakePluginRequestHost(
      credentials: credentials,
      lifecycle: lifecycle,
    );
    final api = _AccountGifsApi();
    GifResult? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                selected = await showGifPicker(
                  context: context,
                  siteUrl: _siteUrl,
                  api: api,
                  requests: requests,
                  settings: const GifsSettings(enabled: true),
                );
              },
              child: const Text('Open GIF picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open GIF picker'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('gif-picker-search'));
    await tester.enterText(search, 'private query');
    await tester.pump(const Duration(milliseconds: 699));
    lifecycle.invalidate(_siteUrl);
    credentials.keys[_siteUrl] = 'new-key';
    await tester.pump(const Duration(milliseconds: 1));
    expect(api.requests, [(query: null, apiKey: 'old-key')]);

    await tester.tap(find.byKey(const ValueKey('gif-picker-close')));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('Open GIF picker'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gif-category-0')), findsOneWidget);
    await tester.enterText(search, 'cats');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(api.requests, [
      (query: null, apiKey: 'old-key'),
      (query: null, apiKey: 'new-key'),
      (query: 'cats', apiKey: 'new-key'),
    ]);
    await tester.tap(find.byKey(const ValueKey('gif-result-0')));
    await tester.pumpAndSettle();
    expect(selected, _result);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile picker fits above the keyboard and caps the query', (
    tester,
  ) async {
    const siteUrl = 'https://meta.discourse.org';
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeDiscourseApi();
    final credentials = FakeAuthenticator()..keys[siteUrl] = 'api-key';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => unawaited(
                showGifPicker(
                  context: context,
                  siteUrl: siteUrl,
                  api: api,
                  requests: FakePluginRequestHost(
                    credentials: credentials,
                    lifecycle: SiteLifecycle(),
                  ),
                  settings: const GifsSettings(enabled: true),
                ),
              ),
              child: const Text('Open GIF picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open GIF picker'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('gif-picker-search'));
    expect(search, findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byType(DSheetContent)).dy,
      lessThanOrEqualTo(844 - 280),
    );
    expect(tester.takeException(), isNull);

    await tester.enterText(search, List.filled(120, 'a').join());
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: search, matching: find.byType(TextField)),
          )
          .controller!
          .text,
      hasLength(100),
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('category search chooses a result and keeps Klipy attribution', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    try {
      const siteUrl = 'https://meta.discourse.org';
      const category = GifCategory(
        title: 'Cats',
        imageUrl: 'https://media.klipy.example/cats-category.webp',
        searchTerm: 'cats',
      );
      const result = GifResult(
        title: 'Cat dance',
        url: 'https://media.klipy.example/cat-dance.webp',
        width: 240,
        height: 180,
      );
      final api = FakeDiscourseApi(
        gifCategoriesBySite: const {
          siteUrl: [category],
        },
        gifSearchPages: {
          FakeDiscourseApi.gifSearchKey('cats'): GifSearchPage(
            results: const [result],
          ),
        },
      );
      final credentials = FakeAuthenticator()..keys[siteUrl] = 'api-key';
      final lifecycle = SiteLifecycle();
      GifResult? selected;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  selected = await showGifPicker(
                    context: context,
                    siteUrl: siteUrl,
                    api: api,
                    requests: FakePluginRequestHost(
                      credentials: credentials,
                      lifecycle: lifecycle,
                    ),
                    settings: const GifsSettings(enabled: true),
                  );
                },
                child: const Text('Open categories'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open categories'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('gif-category-0')), findsOneWidget);
      expect(find.byTooltip('Search Cats GIFs'), findsOneWidget);
      final categoryAction = find.bySemanticsLabel(RegExp('Search Cats GIFs'));
      expect(categoryAction, findsOneWidget);
      expect(
        tester.getSemantics(categoryAction),
        isSemantics(label: 'Search Cats GIFs', isButton: true),
      );
      final categoryTarget = find.descendant(
        of: find.byKey(const ValueKey('gif-category-0')),
        matching: find.byType(InkWell),
      );
      expect(categoryTarget, findsOneWidget);
      expect(
        tester.getSemantics(categoryTarget),
        isSemantics(
          label: 'Cats',
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(tester.getSemantics(categoryAction).tooltip, isEmpty);
      expect(
        find.byKey(const ValueKey('gif-picker-attribution')),
        findsOneWidget,
      );
      _expectCoverNetworkImage(
        tester,
        within: find.byKey(const ValueKey('gif-category-0')),
        url: category.imageUrl,
      );
      final attribution = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('gif-picker-attribution')),
          matching: find.byType(Image),
        ),
      );
      final attributionProvider = attribution.image as ResizeImage;
      expect(attributionProvider.height, 60);
      expect(attributionProvider.allowUpscaling, isFalse);

      await tester.tap(find.byKey(const ValueKey('gif-category-0')));
      await tester.pump();
      await tester.pump();
      expect(api.gifSearchRequests.single.query, 'cats');
      expect(find.byKey(const ValueKey('gif-result-0')), findsOneWidget);
      expect(find.byTooltip('Choose Cat dance GIF'), findsOneWidget);
      final resultAction = find.bySemanticsLabel(
        RegExp('Choose Cat dance GIF'),
      );
      expect(resultAction, findsOneWidget);
      expect(
        tester.getSemantics(resultAction),
        isSemantics(label: 'Choose Cat dance GIF', isButton: true),
      );
      final resultTarget = find.descendant(
        of: find.byKey(const ValueKey('gif-result-0')),
        matching: find.byType(InkWell),
      );
      expect(resultTarget, findsOneWidget);
      expect(
        tester.getSemantics(resultTarget),
        isSemantics(
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(tester.getSemantics(resultAction).tooltip, isEmpty);
      _expectCoverNetworkImage(
        tester,
        within: find.byKey(const ValueKey('gif-result-0')),
        url: result.url,
      );

      await tester.tap(find.byKey(const ValueKey('gif-result-0')));
      await tester.pumpAndSettle();
      expect(selected, result);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('cover tiles decode wide artwork tall enough to fill them', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    PaintingBinding.instance.imageCache.clear();
    addTearDown(PaintingBinding.instance.imageCache.clear);
    const category = GifCategory(
      title: 'Cats',
      imageUrl: 'https://media.klipy.example/cats.webp',
      searchTerm: 'cats',
    );
    final controller = _controller(
      FakeDiscourseApi(
        gifCategoriesBySite: const {
          _siteUrl: [category],
        },
        gifSearchPages: {
          FakeDiscourseApi.gifSearchKey('cats'): GifSearchPage(
            results: const [_result],
          ),
        },
      ),
    );
    addTearDown(controller.dispose);
    final client = FakeImageHttpClient(blankPng(width: 1600, height: 900));
    debugNetworkImageHttpClientProvider = () => client;
    try {
      await _pumpPicker(tester, controller);
      await controller.loadCategories();
      await tester.pump();
      // A 4:3 category tile, then a square result tile.
      await _expectCoverDecode(
        tester,
        within: find.byKey(const ValueKey('gif-category-0')),
      );
      await controller.selectCategory(category);
      await tester.pump();
      await _expectCoverDecode(
        tester,
        within: find.byKey(const ValueKey('gif-result-0')),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });

  testWidgets('initial failure is announced without losing retry', (
    tester,
  ) async {
    final controller = _controller(
      FakeDiscourseApi(gifFailure: SiteLookupFailure.unreachable),
    );
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await _pumpPicker(tester, controller);

      await controller.loadCategories();
      await tester.pump();

      final error = find.bySemanticsLabel(_errorMessage);
      expect(error, findsOneWidget);
      expect(
        tester.getSemantics(error),
        isSemantics(label: _errorMessage, isLiveRegion: true),
      );
      final retry = find.byKey(const ValueKey('gif-picker-retry'));
      expect(retry, findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(of: retry, matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNotNull,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('pagination failure announces error and preserves results', (
    tester,
  ) async {
    final api = _PaginationFailureApi();
    final controller = _controller(api);
    addTearDown(controller.dispose);
    await controller.selectCategory(
      const GifCategory(
        title: 'Cats',
        imageUrl: 'https://media.klipy.example/cats.webp',
        searchTerm: 'cats',
      ),
    );

    final semantics = tester.ensureSemantics();
    try {
      await _pumpPicker(tester, controller);
      expect(find.byKey(const ValueKey('gif-result-0')), findsOneWidget);

      final grid = find.byKey(const ValueKey('gif-picker-results'));
      await tester.drag(grid, const Offset(0, -3000));
      await tester.pumpAndSettle();

      expect(api.laterPageRequests, 1);
      expect(controller.results, _firstPage);
      expect(find.byKey(const ValueKey('gif-result-39')), findsOneWidget);
      final error = find.bySemanticsLabel(_errorMessage);
      expect(error, findsOneWidget);
      expect(
        tester.getSemantics(error),
        isSemantics(label: _errorMessage, isLiveRegion: true),
      );
      final announcement = tester.getSemantics(error).id;

      // Scrolling and bouncing at the end of the grid leave the failed page
      // for an explicit retry, so the live region is not announced again.
      final wiggle = await tester.startGesture(tester.getCenter(grid));
      for (final dy in const [60.0, -120.0, 60.0, -120.0, 90.0, -150.0]) {
        await wiggle.moveBy(Offset(0, dy));
        await tester.pump();
      }
      await wiggle.up();
      await tester.pumpAndSettle();
      await tester.drag(grid, const Offset(0, -3000));
      await tester.pumpAndSettle();

      expect(api.laterPageRequests, 1);
      expect(tester.getSemantics(error).id, announcement);

      final retry = find.widgetWithText(FilledButton, 'Try again');
      expect(retry, findsOneWidget);
      expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(api.laterPageRequests, 2);
      expect(controller.results, _firstPage);
      expect(find.bySemanticsLabel(_errorMessage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gif-picker-load-more')));
      await tester.pumpAndSettle();

      expect(api.laterPageRequests, 3);
    } finally {
      semantics.dispose();
    }
  });
}

GifPickerController _controller(GifsApi api) => GifPickerController(
  siteUrl: _siteUrl,
  api: api,
  requests: FakePluginRequestHost(
    credentials: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    lifecycle: SiteLifecycle(),
  ),
  fileDetail: 'webp',
  searchDebounce: Duration.zero,
);

Future<void> _pumpPicker(WidgetTester tester, GifPickerController controller) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: SizedBox(
            width: 620,
            height: 500,
            child: GifPicker(
              controller: controller,
              siteUrl: _siteUrl,
              onPicked: (_) {},
            ),
          ),
        ),
      ),
    );

final List<GifResult> _firstPage = List.unmodifiable([
  for (var index = 0; index < 40; index++)
    GifResult(
      title: 'Cat $index',
      url: 'https://media.klipy.example/cat-$index.webp',
      width: 240,
      height: 180,
    ),
]);

const _category = GifCategory(
  title: 'Hello',
  imageUrl: 'https://media.klipy.example/hello.webp',
  searchTerm: 'hi',
);

final class _HeldGifsApi extends FakeDiscourseApi {
  final categoryResponse = Completer<List<GifCategory>>();
  final searches =
      <({String query, String position, Completer<GifSearchPage> response})>[];

  @override
  Future<List<GifCategory>> gifCategories({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) => categoryResponse.future;

  @override
  Future<GifSearchPage> searchGifs({
    required String siteUrl,
    required String apiKey,
    required String query,
    required String fileDetail,
    String position = '0',
    String? clientId,
  }) {
    final response = Completer<GifSearchPage>();
    searches.add((query: query, position: position, response: response));
    return response.future;
  }
}

final class _PaginationFailureApi extends FakeDiscourseApi {
  int laterPageRequests = 0;

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
      return GifSearchPage(results: _firstPage, nextPosition: 'next');
    }
    laterPageRequests += 1;
    // A failure lands on a later frame, as a network one does, so a
    // re-request visibly replaces the error rather than restoring it unseen.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
  }
}

final class _AccountGifsApi implements GifsApi {
  final List<({String? query, String apiKey})> requests = [];

  @override
  Future<List<GifCategory>> gifCategories({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    requests.add((query: null, apiKey: apiKey));
    return const [
      GifCategory(
        title: 'Cats',
        imageUrl: 'https://media.klipy.example/cats.webp',
        searchTerm: 'cats',
      ),
    ];
  }

  @override
  Future<GifSearchPage> searchGifs({
    required String siteUrl,
    required String apiKey,
    required String query,
    required String fileDetail,
    String position = '0',
    String? clientId,
  }) async {
    requests.add((query: query, apiKey: apiKey));
    return GifSearchPage(results: const [_result]);
  }
}

void _expectCoverNetworkImage(
  WidgetTester tester, {
  required Finder within,
  required String url,
}) {
  final imageFinder = find.descendant(of: within, matching: find.byType(Image));
  final image = tester.widget<Image>(imageFinder);

  expect(image.fit, BoxFit.cover);
  expect(
    image.image,
    imageForCover(
      tester.element(imageFinder),
      NetworkImage(url),
      logicalSize: tester.getSize(imageFinder),
    ),
  );
}

/// Waits for the artwork [within] a tile to decode, and expects it to cover
/// the tile's physical height at the test's 2x density.
Future<void> _expectCoverDecode(
  WidgetTester tester, {
  required Finder within,
}) async {
  final raw = find.descendant(of: within, matching: find.byType(RawImage));
  ui.Image? decoded;
  for (var attempt = 0; attempt < 100 && decoded == null; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (raw.evaluate().isNotEmpty) decoded = tester.widget<RawImage>(raw).image;
  }

  // The tile is squarer than the source, so a fit would leave it short.
  final tile = tester.getSize(raw);
  expect(tile.width / tile.height, lessThan(16 / 9));
  expect(tester.widget<RawImage>(raw).fit, BoxFit.cover);
  expect(decoded!.height, greaterThanOrEqualTo(tile.height * 2));
  expect(decoded.width / decoded.height, closeTo(16 / 9, 0.01));
}
