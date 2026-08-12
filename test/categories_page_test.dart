import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/categories_page.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const Size _viewport = Size(1200, 900);

Future<ShellController> _loadCategories(FakeDiscourseApi api) async {
  final site = instance('meta.discourse.org', title: 'Discourse Meta');
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  addTearDown(controller.dispose);

  await controller.load();
  await controller.loadCategories(site.url);
  for (
    var attempt = 0;
    attempt < 20 && !controller.categoryFeedFor(site.url).loaded;
    attempt++
  ) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(controller.categoryFeedFor(site.url).loaded, isTrue);

  final categories = controller.categorySidebarSectionFor(site.url);
  expect(categories, isNotNull);
  controller.selectDestination(
    categories!.destinations.singleWhere(
      (destination) => destination.id == 'all-categories',
    ),
  );
  return controller;
}

Future<void> _pumpPage(
  WidgetTester tester,
  ShellController controller, {
  double width = 1100,
}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: _viewport.height,
              child: const MainContent(layout: ShellLayout.expanded),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _card(int categoryId) =>
    find.byKey(ValueKey('category-card-$categoryId'));

Finder _featuredTopic(int topicId) =>
    find.byKey(ValueKey('category-featured-topic-$topicId'));

DIconData _topicIcon(WidgetTester tester, int topicId) => tester
    .widget<DIcon>(
      find.descendant(
        of: _featuredTopic(topicId),
        matching: find.byType(DIcon),
      ),
    )
    .icon;

void main() {
  testWidgets(
    'keeps root server order, featured topic order, and muted cards',
    (tester) async {
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': []},
        categoryList: const [
          TopicCategory(
            id: 30,
            name: 'Alerts',
            color: 'F15A24',
            slug: 'alerts',
            featuredTopics: [
              CategoryFeaturedTopic(
                id: 101,
                title: 'Pinned and closed',
                slug: 'pinned-and-closed',
                pinned: true,
                closed: true,
              ),
              CategoryFeaturedTopic(
                id: 102,
                title: 'Closed topic',
                slug: 'closed-topic',
                closed: true,
              ),
              CategoryFeaturedTopic(
                id: 103,
                title: 'Ordinary topic',
                slug: 'ordinary-topic',
              ),
            ],
          ),
          TopicCategory(
            id: 31,
            name: 'Alerts child',
            color: 'DD4411',
            slug: 'child',
            parentCategoryId: 30,
          ),
          TopicCategory(
            id: 10,
            name: 'Muted',
            color: '999999',
            slug: 'muted',
            notificationLevel: 0,
            featuredTopics: [
              CategoryFeaturedTopic(
                id: 104,
                title: 'Hidden muted topic',
                slug: 'hidden-muted-topic',
              ),
            ],
          ),
          TopicCategory(
            id: 20,
            name: 'Product',
            color: '10AFA0',
            slug: 'product',
          ),
        ],
      );
      final controller = await _loadCategories(api);
      await _pumpPage(tester, controller);

      expect(find.byType(CategoriesPage), findsOneWidget);
      expect(_card(30), findsOneWidget);
      expect(_card(31), findsNothing);
      expect(_card(10), findsOneWidget);
      expect(_card(20), findsOneWidget);

      final alerts = tester.getTopLeft(_card(30));
      final muted = tester.getTopLeft(_card(10));
      final product = tester.getTopLeft(_card(20));
      expect(alerts.dy, muted.dy);
      expect(muted.dy, product.dy);
      expect(alerts.dx, lessThan(muted.dx));
      expect(muted.dx, lessThan(product.dx));
      expect(
        tester.getBottomRight(_card(30)).dy,
        tester.getBottomRight(_card(10)).dy,
      );
      expect(
        tester.getBottomRight(_card(10)).dy,
        tester.getBottomRight(_card(20)).dy,
      );

      expect(_featuredTopic(101), findsOneWidget);
      expect(_featuredTopic(102), findsOneWidget);
      expect(_featuredTopic(103), findsOneWidget);
      expect(_featuredTopic(104), findsNothing);
      expect(
        tester.getTopLeft(_featuredTopic(101)).dy,
        lessThan(tester.getTopLeft(_featuredTopic(102)).dy),
      );
      expect(
        tester.getTopLeft(_featuredTopic(102)).dy,
        lessThan(tester.getTopLeft(_featuredTopic(103)).dy),
      );
      expect(_topicIcon(tester, 101), DIcons.thumbtack);
      expect(_topicIcon(tester, 102), DIcons.lock);
      expect(_topicIcon(tester, 103), DIcons.farFileLines);
    },
  );

  testWidgets('opens a native category feed and Back restores the grid', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/c/alerts/30.json': []},
      categoryList: const [
        TopicCategory(id: 30, name: 'Alerts', color: 'F15A24', slug: 'alerts'),
      ],
    );
    final controller = await _loadCategories(api);
    await _pumpPage(tester, controller);

    await tester.tap(
      find.descendant(of: _card(30), matching: find.text('Alerts')),
    );
    await tester.pumpAndSettle();

    expect(controller.currentContent?.id, 'category-30');
    expect(controller.currentContent?.feedPath, '/c/alerts/30.json');
    expect(api.feedPaths.last, '/c/alerts/30.json');
    expect(find.byType(CategoriesPage), findsNothing);

    expect(controller.handleBack(canReturnToSidebar: false), isTrue);
    await tester.pumpAndSettle();

    expect(controller.currentContent?.id, 'all-categories');
    expect(find.byType(CategoriesPage), findsOneWidget);
    expect(_card(30), findsOneWidget);
  });

  testWidgets('opens a featured topic at its first unread post and returns', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      categoryList: const [
        TopicCategory(
          id: 30,
          name: 'Alerts',
          color: 'F15A24',
          slug: 'alerts',
          featuredTopics: [
            CategoryFeaturedTopic(
              id: 101,
              title: 'Partly read topic',
              slug: 'partly-read-topic',
              lastReadPostNumber: 3,
              highestPostNumber: 8,
            ),
          ],
        ),
      ],
      topics: {
        101: topicPayload(
          id: 101,
          title: 'Partly read topic',
          posts: const [
            Post(
              id: 1004,
              postNumber: 4,
              username: 'sam',
              cooked: '<p>Fourth post</p>',
            ),
          ],
        ),
      },
    );
    final controller = await _loadCategories(api);
    await _pumpPage(tester, controller);

    await tester.tap(_featuredTopic(101));
    await tester.pumpAndSettle();

    expect(controller.currentContent?.topicId, 101);
    expect(controller.currentContent?.postNumber, 4);
    expect(api.topicsOpened.last, 101);
    expect(api.topicPostNumbersOpened.last, 4);
    expect(find.byType(CategoriesPage), findsNothing);

    expect(controller.handleBack(canReturnToSidebar: false), isTrue);
    await tester.pumpAndSettle();

    expect(controller.currentContent?.id, 'all-categories');
    expect(find.byType(CategoriesPage), findsOneWidget);
    expect(_featuredTopic(101), findsOneWidget);
  });

  testWidgets('a featured topic is a 44 pixel named keyboard target', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      categoryList: const [
        TopicCategory(
          id: 30,
          name: 'Alerts',
          color: 'F15A24',
          slug: 'alerts',
          featuredTopics: [
            CategoryFeaturedTopic(
              id: 101,
              title: 'Ordinary topic',
              slug: 'ordinary-topic',
            ),
          ],
        ),
      ],
      topics: {
        101: topicPayload(
          id: 101,
          title: 'Ordinary topic',
          posts: const [
            Post(
              id: 1001,
              postNumber: 1,
              username: 'sam',
              cooked: '<p>First post</p>',
            ),
          ],
        ),
      },
    );
    final controller = await _loadCategories(api);
    final semantics = tester.ensureSemantics();
    try {
      await _pumpPage(tester, controller);

      final topic = _featuredTopic(101);
      expect(tester.getSize(topic).height, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(topic),
        isSemantics(
          label: 'Ordinary topic',
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      final focusChild = find
          .descendant(of: topic, matching: find.byType(MouseRegion))
          .first;
      final focus = Focus.of(tester.element(focusChild));
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(focus.hasPrimaryFocus, isTrue);
      expect(
        tester.getSemantics(topic),
        isSemantics(isFocusable: true, isFocused: true),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.currentContent?.topicId, 101);
      expect(api.topicsOpened, [101]);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('adapts category cards from three columns to two and one', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      categoryList: const [
        TopicCategory(id: 1, name: 'One', color: '111111'),
        TopicCategory(id: 2, name: 'Two', color: '222222'),
        TopicCategory(id: 3, name: 'Three', color: '333333'),
      ],
    );
    final controller = await _loadCategories(api);

    await _pumpPage(tester, controller, width: 1100);
    expect(tester.getTopLeft(_card(1)).dy, tester.getTopLeft(_card(2)).dy);
    expect(tester.getTopLeft(_card(2)).dy, tester.getTopLeft(_card(3)).dy);

    await _pumpPage(tester, controller, width: 700);
    expect(tester.getTopLeft(_card(1)).dy, tester.getTopLeft(_card(2)).dy);
    expect(
      tester.getTopLeft(_card(3)).dy,
      greaterThan(tester.getTopLeft(_card(2)).dy),
    );

    await _pumpPage(tester, controller, width: 500);
    expect(
      tester.getTopLeft(_card(2)).dy,
      greaterThan(tester.getTopLeft(_card(1)).dy),
    );
    expect(
      tester.getTopLeft(_card(3)).dy,
      greaterThan(tester.getTopLeft(_card(2)).dy),
    );
  });

  test('keeps paging after a short page until an empty response', () async {
    final firstPage = [
      for (var id = 1; id <= 20; id++)
        TopicCategory(id: id, name: 'Category $id', color: '0088CC'),
    ];
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      categoryPages: {
        1: firstPage,
        2: const [TopicCategory(id: 21, name: 'Category 21', color: '0088CC')],
        3: const [],
      },
    );
    final controller = await _loadCategories(api);
    final siteUrl = controller.currentInstance!.url;

    expect(controller.categoryFeedFor(siteUrl).categoryIds, [
      for (var id = 1; id <= 20; id++) id,
    ]);

    await controller.loadMoreCategories(siteUrl);

    expect(controller.categoryFeedFor(siteUrl).categoryIds, [
      for (var id = 1; id <= 21; id++) id,
    ]);
    expect(controller.categoryFeedFor(siteUrl).nextPage, 3);
    expect(api.categoryPagesRequested, [1, 2]);

    await controller.loadMoreCategories(siteUrl);

    expect(controller.categoryFeedFor(siteUrl).categoryIds, [
      for (var id = 1; id <= 21; id++) id,
    ]);
    expect(controller.categoryFeedFor(siteUrl).hasMore, isFalse);
    expect(api.categoryPagesRequested, [1, 2, 3]);
  });

  testWidgets('fills a tall viewport until the server returns no categories', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      categoryPages: const {
        1: [TopicCategory(id: 1, name: 'One', color: '111111')],
        2: [TopicCategory(id: 2, name: 'Two', color: '222222')],
        3: [],
      },
    );
    final controller = await _loadCategories(api);

    await _pumpPage(tester, controller);

    expect(api.categoryPagesRequested, [1, 2, 3]);
    expect(_card(1), findsOneWidget);
    expect(_card(2), findsOneWidget);
    expect(
      controller.categoryFeedFor(controller.currentInstance!.url).hasMore,
      isFalse,
    );
  });

  testWidgets('stops automatic paging once cards overflow the viewport', (
    tester,
  ) async {
    final secondPage = [
      for (var id = 2; id <= 51; id++)
        TopicCategory(id: id, name: 'Category $id', color: '0088CC'),
    ];
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      categoryPages: {
        1: const [TopicCategory(id: 1, name: 'Category 1', color: '0088CC')],
        2: secondPage,
        3: const [
          TopicCategory(id: 52, name: 'Not loaded yet', color: '0088CC'),
        ],
      },
    );
    final controller = await _loadCategories(api);

    await _pumpPage(tester, controller);

    expect(api.categoryPagesRequested, [1, 2]);
    expect(_card(51), findsOneWidget);
    expect(_card(52), findsNothing);
    expect(
      controller.categoryFeedFor(controller.currentInstance!.url).nextPage,
      3,
    );
  });
}
