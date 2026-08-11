import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

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
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gif-category-0')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gif-picker-attribution')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('gif-category-0')));
    await tester.pump();
    await tester.pump();
    expect(api.gifSearchRequests.single.query, 'cats');
    expect(find.byKey(const ValueKey('gif-result-0')), findsOneWidget);
    expect(find.byTooltip('Choose Cat dance GIF'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gif-result-0')));
    await tester.pumpAndSettle();
    expect(selected, result);
  });
}
