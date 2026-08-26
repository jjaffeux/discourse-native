import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker_controller.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_api.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
                  credentials: credentials,
                  lifecycle: SiteLifecycle(),
                  config: const SiteConfig(gifsEnabled: true),
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
    final inset = tester.widget<AnimatedPadding>(
      find.byKey(const ValueKey('shell-sheet-keyboard-inset')),
    );
    expect(inset.padding, const EdgeInsets.only(bottom: 280));
    expect(tester.takeException(), isNull);

    await tester.enterText(search, List.filled(120, 'a').join());
    await tester.pump();
    expect(tester.widget<TextField>(search).controller!.text, hasLength(100));

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
                    credentials: credentials,
                    lifecycle: lifecycle,
                    config: const SiteConfig(gifsEnabled: true),
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
        isSemantics(
          label: 'Search Cats GIFs\nCats',
          isButton: true,
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
      _expectBoundedNetworkImage(
        tester,
        within: find.byKey(const ValueKey('gif-category-0')),
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
        isSemantics(
          label: 'Choose Cat dance GIF',
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(tester.getSemantics(resultAction).tooltip, isEmpty);
      _expectBoundedNetworkImage(
        tester,
        within: find.byKey(const ValueKey('gif-result-0')),
      );

      await tester.tap(find.byKey(const ValueKey('gif-result-0')));
      await tester.pumpAndSettle();
      expect(selected, result);
    } finally {
      semantics.dispose();
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
      expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('pagination failure announces error and preserves results', (
    tester,
  ) async {
    final controller = _controller(_PaginationFailureApi());
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

      await controller.loadMore();
      await tester.pump();

      expect(find.byKey(const ValueKey('gif-result-0')), findsOneWidget);
      final error = find.bySemanticsLabel(_errorMessage);
      expect(error, findsOneWidget);
      expect(
        tester.getSemantics(error),
        isSemantics(label: _errorMessage, isLiveRegion: true),
      );
      final retry = find.widgetWithText(TextButton, 'Try again');
      expect(retry, findsOneWidget);
      expect(tester.widget<TextButton>(retry).onPressed, isNotNull);
    } finally {
      semantics.dispose();
    }
  });
}

GifPickerController _controller(GifsApi api) => GifPickerController(
  siteUrl: _siteUrl,
  api: api,
  credentials: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
  lifecycle: SiteLifecycle(),
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

final class _PaginationFailureApi extends FakeDiscourseApi {
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
      return GifSearchPage(results: const [_result], nextPosition: 'next');
    }
    throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
  }
}

void _expectBoundedNetworkImage(WidgetTester tester, {required Finder within}) {
  final imageFinder = find.descendant(of: within, matching: find.byType(Image));
  final image = tester.widget<Image>(imageFinder);
  final provider = image.image as ResizeImage;
  final layoutSize = tester.getSize(imageFinder);

  expect(provider.imageProvider, isA<NetworkImage>());
  expect(provider.width, (layoutSize.width * 2).ceil());
  expect(provider.height, (layoutSize.height * 2).ceil());
  expect(provider.policy, ResizeImagePolicy.fit);
  expect(provider.allowUpscaling, isFalse);
}
