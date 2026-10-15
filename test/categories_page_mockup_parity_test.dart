import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/category_directory.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/categories_page.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/search_words.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _capture = ValueKey('categories-capture');
const _site = 'https://meta.example';

void main() {
  setUpAll(() async {
    final systemFont = File('/System/Library/Fonts/SFNS.ttf');
    await (FontLoader('Category parity')..addFont(
          systemFont.existsSync()
              ? Future.value(ByteData.sublistView(systemFont.readAsBytesSync()))
              : rootBundle.load('assets/fonts/Lato-Regular.ttf'),
        ))
        .load();
  });

  for (final (platform, width) in [
    (TargetPlatform.iOS, 390.0),
    (TargetPlatform.macOS, 825.0),
  ]) {
    for (final dark in [false, true]) {
      for (final material in DAppearanceMaterial.values) {
        testWidgets(
          'categories reference on $platform, dark $dark, $material',
          (tester) async {
            final prior = debugDefaultTargetPlatformOverride;
            debugDefaultTargetPlatformOverride = platform;
            final shadows = debugDisableShadows;
            debugDisableShadows = false;
            try {
              await _mount(
                tester,
                width: width,
                dark: dark,
                material: material,
              );
              final first = tester.getRect(_card(1));
              expect(first.left, 16);
              expect(first.height, greaterThanOrEqualTo(100));
              expect(
                tester.getRect(find.byType(DPlaceCardMark).first).size,
                const Size(29, 29),
              );
              expect(
                find.text(
                  'Hydration, crumb and the long arguments about both.',
                ),
                findsOneWidget,
              );
              expect(find.text('Featured topic title'), findsNothing);
              final footer = find.descendant(
                of: _card(1),
                matching: find.text('8 topics'),
              );
              expect(footer, findsOneWidget);
              final second = tester.getRect(_card(2));
              if (platform == TargetPlatform.iOS) {
                expect(first.width, 358);
                expect(second.top - first.bottom, closeTo(10, .01));
              } else {
                expect(first.width, closeTo((width - 32 - 20) / 3, .01));
                expect(second.top, first.top);
                expect(second.left - first.right, closeTo(10, .01));
                expect(second.height, first.height);
              }
              expect(
                find.byKey(const ValueKey('categories-category-filter')),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              await _export(
                tester,
                '${platform.name}-${dark ? 'dark' : 'light'}-${material.name}',
              );
              if (platform == TargetPlatform.macOS) {
                final mouse = await tester.createGesture(
                  kind: PointerDeviceKind.mouse,
                );
                await mouse.addPointer(location: Offset.zero);
                await mouse.moveTo(first.center);
                await tester.pumpAndSettle();
                await _export(
                  tester,
                  'macOS-${dark ? 'dark' : 'light'}-${material.name}-hover',
                );
                await mouse.removePointer();
                final priorHighlight = FocusManager.instance.highlightStrategy;
                FocusManager.instance.highlightStrategy =
                    FocusHighlightStrategy.alwaysTraditional;
                try {
                  final detector = find
                      .descendant(
                        of: _card(1),
                        matching: find.byType(GestureDetector),
                      )
                      .last;
                  Focus.of(tester.element(detector)).requestFocus();
                  await tester.pumpAndSettle();
                  await _export(
                    tester,
                    'macOS-${dark ? 'dark' : 'light'}-${material.name}-focus',
                  );
                } finally {
                  FocusManager.instance.highlightStrategy = priorHighlight;
                }
              }
            } finally {
              debugDisableShadows = shadows;
              debugDefaultTargetPlatformOverride = prior;
            }
          },
        );
      }
    }
  }

  testWidgets(
    'category path shows one level and search spans the accessible hierarchy',
    (tester) async {
      final shell = await _mount(tester);
      expect(_card(12), findsNothing);
      expect(_card(13), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('categories-category-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('baking').last);
      await tester.pumpAndSettle();
      expect(_card(1), findsNothing);
      expect(_card(12), findsOneWidget);
      expect(_card(13), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('categories-subcategory-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('bread').last);
      await tester.pumpAndSettle();
      expect(_card(12), findsNothing);
      expect(_card(13), findsOneWidget);
      // Remount the same page with words, retaining the selected parent.
      await _mount(tester, shell: shell, words: 'starter');
      expect(_card(13), findsOneWidget);
      expect(_card(14), findsOneWidget);
      expect(_card(1), findsNothing);
      await _mount(tester, shell: shell, words: 'no matches at all');
      expect(find.byType(DPlaceCard), findsNothing);
      expect(find.text('Nothing here yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 700.0, 1100.0]) {
    testWidgets('large text, RTL and reduced motion at $width', (tester) async {
      final shadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        await _mount(tester, width: width, scale: 2, rtl: true, reduced: true);
        final rect = tester.getRect(_card(1));
        expect(rect.left, greaterThanOrEqualTo(16));
        expect(rect.right, lessThanOrEqualTo(width - 16));
        expect(rect.height, greaterThan(100));
        if (width == 320) {
          final path = tester.getRect(
            find.byKey(const ValueKey('categories-category-filter')),
          );
          final scope = tester.getRect(
            find.byType(DSelect<CategoryDirectoryScope>),
          );
          expect(path.top, greaterThan(scope.bottom));
          expect(path.left, greaterThanOrEqualTo(16));
          expect(path.right, lessThanOrEqualTo(width - 16));
        }
        expect(find.byType(IntrinsicHeight), findsNothing);
        expect(tester.takeException(), isNull);
        await _export(tester, 'large-rtl-${width.toInt()}');
      } finally {
        debugDisableShadows = shadows;
      }
    });
  }
}

Finder _card(int id) => find.byKey(ValueKey('category-row-$id'));

Future<ShellController> _mount(
  WidgetTester tester, {
  ShellController? shell,
  double width = 825,
  bool dark = false,
  double scale = 1,
  bool rtl = false,
  bool reduced = false,
  String words = '',
  DAppearanceMaterial material = DAppearanceMaterial.standard,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (shell == null) {
    const user = DiscourseUser(id: 7, username: 'reader');
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      categoryList: _categories(),
      trackingState: TopicTrackingState([
        for (var id = 1; id <= 13; id++)
          TrackedTopicState(
            topicId: 100 + id,
            categoryId: 1,
            highestPostNumber: 2,
            lastReadPostNumber: 1,
            notificationLevel: 2,
          ),
      ]),
    );
    shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.example').copyWith(user: user),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      ownsApi: false,
    );
    addTearDown(shell.dispose);
    await shell.load();
    await shell.loadCategories(_site);
    for (var i = 0; i < 20 && !shell.categoryFeedFor(_site).loaded; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  final theme = AppTheme.fromPalette(
    forumThemePresets
        .firstWhere((theme) => theme.id == 'dracula')
        .resolve(dark ? Brightness.dark : Brightness.light),
    fontFamily: 'Category parity',
    readingFontFamily: 'Category parity',
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: ContentSettingsScope(
        controller: shell.appSettings,
        child: ShellScope(
          controller: shell,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: DMaterialTheme.apply(theme, material),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 844),
                textScaler: TextScaler.linear(scale),
                disableAnimations: reduced,
              ),
              child: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Scaffold(
                  body: SearchWords(
                    query: words,
                    child: CategoriesPage(
                      siteUrl: _site,
                      feed: shell.categoryFeedFor(_site),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

List<TopicCategory> _categories() => [
  for (final (i, name, blurb, color, topics) in [
    (
      1,
      'baking',
      'Hydration, crumb and the long arguments about both.',
      'C99D27',
      8,
    ),
    (
      2,
      'wellness',
      'Sleep, habits, and the small things that hold.',
      'B776CF',
      3,
    ),
    (
      3,
      'photography',
      'Light, subjects, and the frame you nearly missed.',
      'D69738',
      4,
    ),
    (
      4,
      'plants',
      'What is thriving, what is not, and what you did about it.',
      '51BFA3',
      4,
    ),
    (
      5,
      'keyboards',
      'Switches, keycaps, and tier lists nobody asked for.',
      'D5AA2B',
      5,
    ),
    (6, 'cooking', 'Dinner, mostly, and how it went.', '4D93CA', 4),
    (
      7,
      'books',
      'What you are reading and what you would press on someone.',
      'D99436',
      4,
    ),
    (
      8,
      'hiking',
      'Routes, base weights, and the gear you never used.',
      '51BFA3',
      5,
    ),
    (
      9,
      'travel',
      'Where you went, what it cost, what you would do again.',
      'C99D27',
      2,
    ),
    (
      10,
      'pkm',
      'Questions about pkm, and the answers people found.',
      'D69738',
      3,
    ),
    (
      11,
      'remote-work',
      'Desks, hours, and keeping the two apart.',
      '51BFA3',
      2,
    ),
  ])
    TopicCategory(
      id: i,
      name: name,
      color: color,
      slug: name,
      topicCount: topics,
      styleType: 'icon',
      icon: [
        'layer-group',
        'heart',
        'code',
        'microphone',
        'flag',
        'link',
        'calendar',
        'bookmark',
        'layer-group',
        'code',
        'microphone',
      ][i - 1],
      descriptionExcerpt: blurb,
      featuredTopics: [
        CategoryFeaturedTopic(
          id: i * 100,
          title: 'Featured topic title',
          slug: 'featured',
          activityAt: DateTime.now().subtract(Duration(minutes: 22 + i * 4)),
        ),
      ],
    ),
  const TopicCategory(
    id: 12,
    name: 'bread',
    color: 'C99D27',
    parentCategoryId: 1,
  ),
  const TopicCategory(
    id: 13,
    name: 'sourdough starter',
    color: 'C99D27',
    parentCategoryId: 12,
  ),
  const TopicCategory(
    id: 14,
    name: 'plant starters',
    color: '51BFA3',
    parentCategoryId: 4,
  ),
];

Future<void> _export(WidgetTester tester, String name) async {
  final directory = Platform.environment['CATEGORIES_EXPORT_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
