import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_actions.dart';
import 'package:discourse_native/src/shell/topic_list_filter_bar.dart';
import 'package:discourse_native/src/shell/topic_list_navigation.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _config = SiteConfig(taggingEnabled: true, maxCategoryNesting: 4);
const _categories = [
  TopicCategory(id: 1, name: 'Product', slug: 'product', color: '563A93'),
  TopicCategory(
    id: 2,
    name: 'Design',
    slug: 'design',
    color: '3188CC',
    parentCategoryId: 1,
  ),
  TopicCategory(
    id: 3,
    name: 'Mobile',
    slug: 'mobile',
    color: 'DC8330',
    parentCategoryId: 2,
  ),
  TopicCategory(
    id: 4,
    name: 'iOS',
    slug: 'ios',
    color: '3BBF7B',
    parentCategoryId: 3,
  ),
];
const _titles = [
  'A clearer way to browse discussions',
  'Designing category navigation for mobile',
  'Share what you are building this week',
  'Small details that make a forum feel at home',
  'Keeping labels readable at larger text sizes',
  'What should we improve next?',
];

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['RESPONSIVE_FILTER_REVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final builder = ui.SceneBuilder();
    view.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      view.size.width.round(),
      view.size.height.round(),
    );
    scene.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<ShellController> _pump(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  String query = 'status:open',
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const user = DiscourseUser(id: 7, username: 'reader');
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user, config: _config),
    ]),
    api: FakeDiscourseApi(
      user: user,
      categoryList: _categories,
      siteConfigs: const {_site: _config},
      feeds: const {'/latest.json': [], '/filter.json': []},
      filterOptionsByPath: const {
        '/filter.json': [
          TopicFilterOption(name: 'category:', type: 'category'),
          TopicFilterOption(name: 'tag:', type: 'tag'),
          TopicFilterOption(name: 'status:open'),
        ],
      },
    ),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: true,
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await shell.loadCategories(_site);
  if (query.isNotEmpty) await shell.applyTopicListFilterQuery(query);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.forBrightness(
          Brightness.light,
          fontFamily: 'Open Sans',
        ).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 24, bottom: 34),
          ),
          child: DTouchTargets(child: child!),
        ),
        home: Scaffold(
          body: SafeArea(
            child: ListenableBuilder(
              listenable: shell,
              builder: (context, _) {
                final route = shell.topicListContent!;
                final query = shell.topicListFilterEditorQuery(route);
                return DPageSurface.headed(
                  title: const Text('Latest topics'),
                  controls: TopicListFilterBar(
                    inline: true,
                    wrap: true,
                    leading: TopicFeedMenu(
                      mode: shell.currentTopicListMode ?? TopicListMode.latest,
                      onSelected: shell.selectTopicListMode,
                    ),
                    trailing: TopicListFilterMenu(siteUrl: _site, query: query),
                    siteUrl: _site,
                    categories: _categories,
                    maxCategoryNesting: 4,
                    knownTags: const [],
                    selectedCategoryId: route.categoryId,
                    selectedTagName: route.tagName,
                    taggingEnabled: true,
                    filterQuery: query,
                    searchTags: (_) async => const [],
                    onCategorySelected: shell.selectTopicListCategory,
                    onTagSelected: shell.selectTopicListTag,
                  ),
                  bodyBuilder: (context, header) => ListView(
                    key: const ValueKey('responsive-filter-topics'),
                    children: [
                      header.spacer,
                      for (var i = 0; i < 24; i++)
                        DItem(
                          children: [
                            DItemContent(
                              children: [
                                DItemTitle(
                                  child: Text(_titles[i % _titles.length]),
                                ),
                                const DItemDescription(
                                  child: Text(
                                    'Product · Design   •   12 replies',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });

  setUpAll(() async {
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });

  testWidgets(
    'phone filter actions and active count survive header retraction',
    (tester) async {
      await _pump(tester);
      await _capture(tester, 'phone-expanded');
      final filters = find.byKey(const ValueKey('topic-list-filter'));
      final initialTop = tester.getTopLeft(filters).dy;
      await tester.drag(
        find.byKey(const ValueKey('responsive-filter-topics')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(filters).dy, lessThan(initialTop));
      expect(tester.getRect(filters).bottom, lessThan(200));
      expect(
        find.descendant(of: filters, matching: find.textContaining('1')),
        findsOneWidget,
      );
      await _capture(tester, 'phone-scrolled');
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'deep category paths retain reachable controls at 320 points and text $scale',
      (tester) async {
        await _pump(
          tester,
          width: 320,
          scale: scale,
          query: '=category:3 status:open',
        );
        await _capture(tester, 'phone-narrow-deep-$scale');
        for (var level = 0; level < 4; level++) {
          final key = level == 0
              ? 'topic-list-category-filter'
              : 'topic-list-subcategory-filter-$level';
          final segment = find.byKey(ValueKey(key));
          await tester.ensureVisible(segment);
          final rect = tester.getRect(segment);
          expect(rect.center.dx, inInclusiveRange(0, 320));
          expect(rect.height, greaterThan(0));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a tight list path keeps its editor while ancestors are removed',
    (tester) async {
      final shell = await _pump(
        tester,
        width: 430,
        query: 'category:3 status:open',
      );
      final bar = find.byKey(const ValueKey('topic-list-filter-bar'));
      expect(
        find.descendant(of: bar, matching: find.text('Product')),
        findsNothing,
      );
      expect(
        find.descendant(of: bar, matching: find.text('Mobile')),
        findsOneWidget,
      );
      await _capture(tester, 'phone-tight-deep');
      await tester.tap(
        find.byKey(const ValueKey('topic-list-subcategory-filter-3')),
      );
      await tester.pumpAndSettle();
      final editor = find.byKey(const ValueKey('topic-filter-input'));
      final state = tester.element(editor);
      await _capture(tester, 'phone-category-menu');
      await tester.tap(editor);
      await tester.pumpAndSettle();
      for (final expected in [2, 1, null]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.categoryId, expected);
        expect(tester.element(editor), same(state));
      }
      expect(tester.takeException(), isNull);
    },
  );
}
