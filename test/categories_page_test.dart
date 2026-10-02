import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/category_directory.dart';
import 'package:discourse_native/src/models/category_sidebar.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/app_text_scale.dart';
import 'package:discourse_native/src/shell/categories_page.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/skeleton_expectations.dart';

const Size _viewport = Size(1200, 900);

Future<ShellController> _loadCategories(
  FakeDiscourseApi api, {
  bool connected = false,
  bool waitForCategories = true,
}) async {
  final site = instance('meta.discourse.org', title: 'Discourse Meta').copyWith(
    user: connected ? const DiscourseUser(id: 7, username: 'joffreyj') : null,
  );
  final authenticator = FakeAuthenticator();
  if (connected) authenticator.keys[site.url] = 'test-key';
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  addTearDown(controller.dispose);

  await controller.load();
  if (waitForCategories) {
    await controller.loadCategories(site.url);
    for (
      var attempt = 0;
      attempt < 20 && !controller.categoryFeedFor(site.url).loaded;
      attempt++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.categoryFeedFor(site.url).loaded, isTrue);
  } else {
    unawaited(controller.loadCategories(site.url));
  }

  final categories =
      controller.categorySidebarSectionFor(site.url) ??
      buildCategorySidebarSection(categories: const [], connected: connected);
  controller.selectDestination(
    categories.destinations.singleWhere(
      (destination) => destination.id == 'all-categories',
    ),
  );
  return controller;
}

Future<void> _pumpPage(
  WidgetTester tester,
  ShellController controller, {
  double width = 1100,
  Size size = _viewport,
  ShellLayout layout = ShellLayout.expanded,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ContentSettingsScope(
      controller: controller.appSettings,
      child: ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => AppTextScaleRegion(
            controller: controller.appSettings,
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: size.height,
                child: MainContent(layout: layout),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _PendingCategoriesApi extends FakeDiscourseApi {
  _PendingCategoriesApi() : super(feeds: const {'/latest.json': []});

  Completer<CategoryLoadResult> categoriesGate =
      Completer<CategoryLoadResult>();

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) => page == 1
      ? categoriesGate.future
      : super.loadCategories(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          page: page,
        );
}

Finder _row(int categoryId) => find.byKey(ValueKey('category-row-$categoryId'));

Finder _featuredTopic(int topicId) =>
    find.byKey(ValueKey('category-featured-topic-$topicId'));

Future<void> _selectScope(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DSelect<CategoryDirectoryScope>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('loading', () {
    for (final (size, platform, layout) in [
      (const Size(390, 844), TargetPlatform.iOS, ShellLayout.compact),
      (const Size(1440, 1200), TargetPlatform.macOS, ShellLayout.expanded),
    ]) {
      testWidgets('category skeleton fills the page at $size on $platform', (
        tester,
      ) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = platform;
        final semantics = tester.ensureSemantics();
        try {
          final api = _PendingCategoriesApi();
          final controller = await _loadCategories(
            api,
            waitForCategories: false,
          );
          await controller.appSettings.setLimitContentSize(true);

          await _pumpPage(
            tester,
            controller,
            size: size,
            width: size.width,
            layout: layout,
            settle: false,
          );

          expect(
            controller.categoryFeedFor(controller.currentInstance!.url).loading,
            isTrue,
          );
          expectSkeletonFillsViewport(
            tester,
            label: 'Loading categories',
            bottom: size.height - 24,
          );
          expect(find.bySemanticsLabel('Loading categories'), findsOneWidget);
          final region = tester.getRect(find.byType(DSkeletonRegion));
          if (platform == TargetPlatform.macOS) {
            expect(
              region.width,
              lessThanOrEqualTo(ContentReadingLane.maxWidth),
            );
            expect(region.center.dx, closeTo(size.width / 2, 1));
          }

          api.categoriesGate.complete(
            CategoryLoadResult(const [
              TopicCategory(id: 30, name: 'Support', color: '0088CC'),
            ]),
          );
          await tester.pumpAndSettle();

          expect(find.byType(DSkeletonRegion), findsNothing);
          expect(_row(30), findsOneWidget);

          api.categoriesGate = Completer<CategoryLoadResult>();
          final refresh = controller.loadCategories(
            controller.currentInstance!.url,
            force: true,
          );
          await tester.pump();
          expect(find.byType(DSkeletonRegion), findsNothing);
          expect(_row(30), findsOneWidget);

          api.categoriesGate.complete(
            CategoryLoadResult(const [
              TopicCategory(id: 30, name: 'Support', color: '0088CC'),
            ]),
          );
          await refresh;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      });
    }

    testWidgets(
      'category skeleton becomes the empty state and returns on refresh',
      (tester) async {
        final api = _PendingCategoriesApi();
        final controller = await _loadCategories(api, waitForCategories: false);
        await _pumpPage(tester, controller, settle: false);
        expect(find.byType(DSkeletonRegion), findsOneWidget);

        api.categoriesGate.complete(CategoryLoadResult(const []));
        await tester.pumpAndSettle();
        expect(find.byType(DSkeletonRegion), findsNothing);
        expect(find.text('No categories yet'), findsOneWidget);

        api.categoriesGate = Completer<CategoryLoadResult>();
        final refresh = controller.loadCategories(
          controller.currentInstance!.url,
          force: true,
        );
        await tester.pump();
        expect(find.byType(DSkeletonRegion), findsOneWidget);
        expect(find.text('No categories yet'), findsNothing);

        api.categoriesGate.complete(CategoryLoadResult(const []));
        await refresh;
        await tester.pumpAndSettle();
        expect(find.byType(DSkeletonRegion), findsNothing);
        expect(find.text('No categories yet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'category skeleton becomes the error state and returns on retry',
      (tester) async {
        final api = _PendingCategoriesApi();
        final controller = await _loadCategories(api, waitForCategories: false);
        await _pumpPage(tester, controller, settle: false);
        expect(find.byType(DSkeletonRegion), findsOneWidget);

        api.categoriesGate.completeError(StateError('Offline'));
        await tester.pumpAndSettle();
        expect(find.byType(DSkeletonRegion), findsNothing);
        expect(find.text('Try again'), findsOneWidget);

        api.categoriesGate = Completer<CategoryLoadResult>();
        await tester.tap(find.text('Try again'));
        await tester.pump();
        expect(find.byType(DSkeletonRegion), findsOneWidget);
        expect(find.text('Try again'), findsNothing);

        api.categoriesGate.complete(
          CategoryLoadResult(const [
            TopicCategory(id: 30, name: 'Support', color: '0088CC'),
          ]),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DSkeletonRegion), findsNothing);
        expect(_row(30), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('category directory', () {
    testWidgets(
      'shows full-width activity rows in server order and keeps private and muted categories',
      (tester) async {
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          categoryList: [
            TopicCategory(
              id: 30,
              name: 'Alerts',
              color: 'F15A24',
              slug: 'alerts',
              readRestricted: true,
              featuredTopics: [
                CategoryFeaturedTopic(
                  id: 101,
                  title: 'Old pinned topic',
                  slug: 'old',
                  pinned: true,
                  activityAt: DateTime(2020),
                ),
                CategoryFeaturedTopic(
                  id: 102,
                  title: 'Latest topic',
                  slug: 'latest',
                  activityAt: DateTime.now().subtract(const Duration(hours: 2)),
                ),
              ],
            ),
            const TopicCategory(
              id: 31,
              name: 'Child',
              color: 'DD4411',
              slug: 'child',
              parentCategoryId: 30,
            ),
            const TopicCategory(
              id: 10,
              name: 'Muted',
              color: '999999',
              slug: 'muted',
              topicCount: 9,
              descriptionExcerpt: '<p>Quiet &amp; calm</p>',
              notificationLevel: CategoryNotificationLevel.muted,
              featuredTopics: [
                CategoryFeaturedTopic(
                  id: 104,
                  title: 'Hidden muted topic',
                  slug: 'hidden',
                ),
              ],
            ),
            const TopicCategory(
              id: 20,
              name: 'Product',
              color: '10AFA0',
              slug: 'product',
              topicCount: 2,
            ),
          ],
        );
        final controller = await _loadCategories(api);
        await _pumpPage(tester, controller);
        expect(_row(31), findsNothing);
        expect(
          find.byKey(const ValueKey('category-subcategory-31')),
          findsOneWidget,
        );
        for (final id in [10, 20]) {
          expect(
            tester.getTopLeft(_row(id)).dx,
            tester.getTopLeft(_row(30)).dx,
          );
          expect(
            tester.getSize(_row(id)).width,
            tester.getSize(_row(30)).width,
          );
        }
        expect(
          tester.getTopLeft(_row(30)).dy,
          lessThan(tester.getTopLeft(_row(10)).dy),
        );
        expect(
          tester.getTopLeft(_row(10)).dy,
          lessThan(tester.getTopLeft(_row(20)).dy),
        );
        expect(_featuredTopic(102), findsOneWidget);
        expect(_featuredTopic(101), findsNothing);
        expect(_featuredTopic(104), findsNothing);
        expect(find.text('2h'), findsOneWidget);
        expect(find.text('9 topics'), findsOneWidget);
        expect(find.text('Quiet & calm'), findsOneWidget);
        expect(find.byType(DAvatar), findsNWidgets(3));
        expect(find.text('0 topics'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(CategoriesPage),
            matching: find.byType(DCard),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'opens category and subcategory feeds and Back restores the directory',
      (tester) async {
        final api = FakeDiscourseApi(
          feeds: const {
            '/latest.json': [],
            '/c/alerts/30.json': [],
            '/c/alerts/child/31.json': [],
          },
          categoryList: const [
            TopicCategory(
              id: 30,
              name: 'Alerts',
              color: 'F15A24',
              slug: 'alerts',
            ),
            TopicCategory(
              id: 31,
              name: 'Child',
              color: 'DD4411',
              slug: 'child',
              parentCategoryId: 30,
            ),
          ],
        );
        final controller = await _loadCategories(api);
        await _pumpPage(tester, controller);
        await tester.tap(find.text('Alerts'));
        await tester.pumpAndSettle();
        expect(controller.currentContent?.feedPath, '/c/alerts/30.json');
        expect(controller.handleBack(canReturnToSidebar: false), isTrue);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('category-subcategory-31')));
        await tester.pumpAndSettle();
        expect(controller.currentContent?.feedPath, '/c/alerts/child/31.json');
        expect(controller.handleBack(canReturnToSidebar: false), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(CategoriesPage), findsOneWidget);
      },
    );

    testWidgets(
      'latest topic is a keyboard action and opens at its first unread post',
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
        final semantics = tester.ensureSemantics();
        try {
          await _pumpPage(tester, controller, width: 390);
          expect(
            tester.getSemantics(_featuredTopic(101)).getSemanticsData().label,
            contains('Partly read topic'),
          );
          final target = find
              .descendant(
                of: _featuredTopic(101),
                matching: find.byType(MouseRegion),
              )
              .last;
          Focus.of(tester.element(target)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(controller.currentContent?.topicId, 101);
          expect(controller.currentContent?.postNumber, 4);
          expect(api.topicPostNumbersOpened.last, 4);
          expect(controller.handleBack(canReturnToSidebar: false), isTrue);
          await tester.pumpAndSettle();
          expect(_featuredTopic(101), findsOneWidget);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('category context menu opens its actual route in a new tab', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': [], '/c/alerts/30.json': []},
        categoryList: const [
          TopicCategory(
            id: 30,
            name: 'Alerts',
            color: 'F15A24',
            slug: 'alerts',
          ),
        ],
      );
      final controller = await _loadCategories(api);
      await _pumpPage(tester, controller);
      await tester.tap(_row(30), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Open in new main tab'), findsOneWidget);
      await tester.tap(find.text('Open in new main tab'));
      await tester.pumpAndSettle();
      expect(
        controller.tabsForCurrentForum.any(
          (tab) => tab.contentStack.any((route) => route.categoryId == 30),
        ),
        isTrue,
      );
    });

    testWidgets(
      'With topics uses server totals and retains descendants and read-only categories',
      (tester) async {
        final controller = await _loadCategories(
          FakeDiscourseApi(
            feeds: const {'/latest.json': []},
            categoryList: const [
              TopicCategory(id: 1, name: 'Empty', color: '111111'),
              TopicCategory(
                id: 2,
                name: 'Read only',
                color: '222222',
                permission: 2,
                topicCount: 12,
              ),
              TopicCategory(id: 3, name: 'Parent', color: '333333'),
              TopicCategory(
                id: 4,
                name: 'Child',
                color: '444444',
                parentCategoryId: 3,
                topicCount: 5,
              ),
            ],
          ),
        );
        await _pumpPage(tester, controller);
        await _selectScope(tester, 'With topics');
        expect(_row(1), findsNothing);
        expect(_row(2), findsOneWidget);
        expect(_row(3), findsOneWidget);
        expect(find.text('5 topics'), findsOneWidget);
        await _selectScope(tester, 'All categories');
        expect(_row(1), findsOneWidget);
        await tester.tap(find.byType(DSelect<CategoryDirectoryScope>));
        await tester.pumpAndSettle();
        final select = tester.widget<DSelect<CategoryDirectoryScope>>(
          find.byType(DSelect<CategoryDirectoryScope>),
        );
        expect(
          select.entries
              .whereType<DSelectOption<CategoryDirectoryScope>>()
              .singleWhere(
                (option) => option.value == CategoryDirectoryScope.unread,
              )
              .enabled,
          isFalse,
        );
      },
    );

    testWidgets(
      'Unread waits for the tracking snapshot before trusting live arrivals',
      (tester) async {
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          categoryList: const [
            TopicCategory(id: 1, name: 'General', color: '111111'),
          ],
          trackingStateGate: gate,
          trackingState: TopicTrackingState(const [
            TrackedTopicState(
              topicId: 10,
              categoryId: 1,
              highestPostNumber: 4,
              lastReadPostNumber: 1,
              notificationLevel: 2,
            ),
          ]),
        );
        final controller = await _loadCategories(api, connected: true);
        await _pumpPage(tester, controller);
        FakeSiteTracker.built.single.deliverTopicTracking(const {
          'topic_id': 10,
          'message_type': 'unread',
          'payload': {'highest_post_number': 4, 'category_id': 1},
        });
        await tester.pumpAndSettle();
        expect(
          controller.categoryUnreadTopicCountsFor('https://meta.discourse.org'),
          isNull,
        );
        await _selectScope(tester, 'Unread');
        expect(find.text('No categories with unread topics'), findsNothing);
        expect(_row(1), findsNothing);
        gate.complete();
        await tester.pumpAndSettle();
        expect(_row(1), findsOneWidget);
      },
    );

    testWidgets(
      'Unread follows live tracking and ignores muted and new-only topics',
      (tester) async {
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          categoryList: const [
            TopicCategory(id: 1, name: 'Unread parent', color: '111111'),
            TopicCategory(
              id: 2,
              name: 'Child',
              color: '222222',
              parentCategoryId: 1,
            ),
            TopicCategory(
              id: 3,
              name: 'Muted',
              color: '333333',
              notificationLevel: CategoryNotificationLevel.muted,
            ),
            TopicCategory(id: 4, name: 'Only new', color: '444444'),
          ],
          trackingState: TopicTrackingState(const [
            TrackedTopicState(
              topicId: 10,
              categoryId: 2,
              highestPostNumber: 4,
              lastReadPostNumber: 1,
              notificationLevel: 2,
            ),
            TrackedTopicState(
              topicId: 11,
              categoryId: 3,
              highestPostNumber: 4,
              lastReadPostNumber: 1,
              notificationLevel: 2,
            ),
            TrackedTopicState(
              topicId: 12,
              categoryId: 4,
              highestPostNumber: 1,
              createdInNewPeriod: true,
            ),
          ]),
        );
        final controller = await _loadCategories(api, connected: true);
        await _pumpPage(tester, controller);
        expect(
          controller.categoryUnreadTopicCountsFor('https://meta.discourse.org'),
          {2: 1, 3: 1},
        );
        expect(
          tester.widget<Text>(find.text('Unread parent')).style?.fontWeight,
          FontWeight.w700,
        );
        await _selectScope(tester, 'Unread');
        expect(_row(1), findsOneWidget);
        expect(_row(3), findsNothing);
        expect(_row(4), findsNothing);
        FakeSiteTracker.built.single.deliverTopicTracking(const {
          'topic_id': 10,
          'message_type': 'read',
          'payload': {'last_read_post_number': 4},
        });
        await tester.pumpAndSettle();
        expect(_row(1), findsNothing);
        expect(find.text('No categories with unread topics'), findsOneWidget);
      },
    );

    testWidgets(
      'keeps full-width rows readable at phone widths and 200 percent text',
      (tester) async {
        final controller = await _loadCategories(
          FakeDiscourseApi(
            feeds: const {'/latest.json': []},
            categoryList: const [
              TopicCategory(
                id: 1,
                name: 'A long category name that wraps with large text',
                color: '111111',
                topicCount: 42000,
                featuredTopics: [
                  CategoryFeaturedTopic(
                    id: 101,
                    title: 'A long latest topic that must fit within the row',
                    slug: 'long',
                  ),
                ],
              ),
              TopicCategory(id: 2, name: 'Two', color: '222222'),
              TopicCategory(id: 3, name: 'Three', color: '333333'),
            ],
          ),
        );
        for (final width in [1100.0, 700.0, 390.0]) {
          await _pumpPage(tester, controller, width: width);
          expect(
            tester.getTopLeft(_row(1)).dy,
            lessThan(tester.getTopLeft(_row(2)).dy),
          );
          expect(tester.getSize(_row(1)).width, tester.getSize(_row(2)).width);
          expect(tester.takeException(), isNull);
        }
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await controller.appSettings.setTextScale(AppTextScale.percent200);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      },
    );
  });

  group('paging', () {
    testWidgets(
      'filtered empty pages continue until a matching category is found',
      (tester) async {
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          categoryPages: {
            1: [
              for (var id = 1; id <= 30; id++)
                TopicCategory(id: id, name: 'Empty $id', color: '111111'),
            ],
            2: const [
              TopicCategory(id: 31, name: 'Also empty', color: '222222'),
            ],
            3: const [
              TopicCategory(
                id: 32,
                name: 'With topics',
                color: '333333',
                topicCount: 12,
              ),
            ],
            4: const [],
          },
        );
        final controller = await _loadCategories(api);
        await _pumpPage(tester, controller);
        expect(api.categoryPagesRequested, [1]);
        await _selectScope(tester, 'With topics');
        expect(api.categoryPagesRequested, [1, 2, 3, 4]);
        expect(_row(1), findsNothing);
        expect(_row(32), findsOneWidget);
        expect(find.text('No categories with topics'), findsNothing);
      },
    );

    test('keeps paging after a short page until an empty response', () async {
      final firstPage = [
        for (var id = 1; id <= 20; id++)
          TopicCategory(id: id, name: 'Category $id', color: '0088CC'),
      ];
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': []},
        categoryPages: {
          1: firstPage,
          2: const [
            TopicCategory(id: 21, name: 'Category 21', color: '0088CC'),
          ],
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

    testWidgets(
      'fills a tall viewport until the server returns no categories',
      (tester) async {
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
        expect(_row(1), findsOneWidget);
        expect(_row(2), findsOneWidget);
        expect(
          controller.categoryFeedFor(controller.currentInstance!.url).hasMore,
          isFalse,
        );
      },
    );

    testWidgets(
      'preserves scroll position while appending and exposes lazy rows',
      (tester) async {
        final firstPage = [
          for (var id = 1; id <= 60; id++)
            TopicCategory(id: id, name: 'Category $id', color: '0088CC'),
        ];
        final secondPage = [
          for (var id = 61; id < 80; id++)
            TopicCategory(id: id, name: 'Category $id', color: '0088CC'),
          const TopicCategory(
            id: 80,
            name: 'Category 80',
            color: '0088CC',
            featuredTopics: [
              CategoryFeaturedTopic(
                id: 800,
                title: 'Lazy featured topic',
                slug: 'lazy-featured-topic',
              ),
            ],
          ),
        ];
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          categoryPages: {1: firstPage, 2: secondPage, 3: const []},
        );
        final controller = await _loadCategories(api);
        await controller.appSettings.setLimitContentSize(true);
        final siteUrl = controller.currentInstance!.url;
        final semantics = tester.ensureSemantics();
        try {
          await _pumpPage(tester, controller);

          expect(api.categoryPagesRequested, [1]);
          expect(_row(80), findsNothing);

          final scrollView = tester.widget<CustomScrollView>(
            find.byType(CustomScrollView),
          );
          final scrollController = scrollView.controller!;
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -100),
          );
          await tester.pumpAndSettle();
          final offsetBeforeAppend = scrollController.offset;
          expect(offsetBeforeAppend, greaterThan(0));

          await controller.loadMoreCategories(siteUrl);
          await tester.pumpAndSettle();

          expect(api.categoryPagesRequested, [1, 2]);
          expect(scrollController.offset, offsetBeforeAppend);
          expect(controller.categoryFeedFor(siteUrl).categoryIds.last, 80);
          expect(_row(80), findsNothing);

          final scrollable = find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          );
          await tester.scrollUntilVisible(
            _row(80),
            500,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();

          expect(_row(80), findsOneWidget);
          expect(
            tester.getSemantics(_featuredTopic(800)),
            isSemantics(
              label: 'Lazy featured topic',
              isButton: true,
              isFocusable: true,
              hasTapAction: true,
              hasFocusAction: true,
            ),
          );
          expect(api.categoryPagesRequested, [1, 2, 3]);
          expect(controller.categoryFeedFor(siteUrl).hasMore, isFalse);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'stops automatic paging once rows overflow and keeps distant rows lazy',
      (tester) async {
        final secondPage = [
          for (var id = 2; id <= 51; id++)
            TopicCategory(id: id, name: 'Category $id', color: '0088CC'),
        ];
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          categoryPages: {
            1: const [
              TopicCategory(id: 1, name: 'Category 1', color: '0088CC'),
            ],
            2: secondPage,
            3: const [
              TopicCategory(id: 52, name: 'Not loaded yet', color: '0088CC'),
            ],
          },
        );
        final controller = await _loadCategories(api);

        await _pumpPage(tester, controller);

        expect(api.categoryPagesRequested, [1, 2]);
        expect(
          controller
              .categoryFeedFor(controller.currentInstance!.url)
              .categoryIds
              .last,
          51,
        );
        expect(_row(51), findsNothing);
        expect(_row(52), findsNothing);
        expect(
          controller.categoryFeedFor(controller.currentInstance!.url).nextPage,
          3,
        );
      },
    );
  });
}
