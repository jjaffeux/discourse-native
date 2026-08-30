import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/tags_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const Size _viewport = Size(1200, 900);
const String _siteUrl = 'https://meta.discourse.org';

Future<ShellController> _loadController({
  required FakeDiscourseApi api,
  DiscourseUser? user,
}) async {
  final stored = instance('meta.discourse.org', title: 'Discourse Meta');
  final site = user == null ? stored : stored.copyWith(user: user);
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
  return controller;
}

Future<void> _pumpShell(WidgetTester tester, ShellController controller) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Row(
            children: [
              SizedBox(width: 280, child: InstanceSidebar()),
              Expanded(child: MainContent(layout: ShellLayout.expanded)),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _sidebarText(String label) => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: find.text(label),
);

SidebarDestination _allTagsDestination(ShellController controller) => controller
    .tagSidebarSectionFor(_siteUrl)!
    .destinations
    .singleWhere((destination) => destination.id == 'all-tags');

void main() {
  test(
    'connected sidebar tags win and an empty selection uses site top tags',
    () async {
      const selected = SidebarTag(
        id: 7,
        name: 'selected-tag',
        slug: 'selected-tag',
      );
      const siteTop = SidebarTag(
        id: 8,
        name: 'site-top-tag',
        slug: 'site-top-tag',
      );

      final selectedController = await _loadController(
        api: FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          categorySiteTopTags: const [siteTop],
        ),
        user: const DiscourseUser(
          id: 1,
          username: 'reader',
          displaySidebarTags: true,
          sidebarTags: [selected],
        ),
      );
      expect(
        selectedController
            .tagSidebarSectionFor(_siteUrl)!
            .destinations
            .map((destination) => destination.label),
        ['selected-tag', 'All tags'],
      );

      final fallbackController = await _loadController(
        api: FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          categorySiteTopTags: const [siteTop],
        ),
        user: const DiscourseUser(
          id: 1,
          username: 'reader',
          displaySidebarTags: true,
        ),
      );
      expect(
        fallbackController
            .tagSidebarSectionFor(_siteUrl)!
            .destinations
            .map((destination) => destination.label),
        ['site-top-tag', 'All tags'],
      );

      final hiddenController = await _loadController(
        api: FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          categorySiteTopTags: const [siteTop],
        ),
        user: const DiscourseUser(
          id: 1,
          username: 'reader',
          sidebarTags: [selected],
        ),
      );
      expect(hiddenController.tagSidebarSectionFor(_siteUrl), isNull);
    },
  );

  test('anonymous defaults win before the site top-tag fallback', () async {
    const siteTop = SidebarTag(
      id: 8,
      name: 'site-top-tag',
      slug: 'site-top-tag',
    );
    const anonymousDefault = SidebarTag(
      id: 9,
      name: 'welcome-tag',
      slug: 'welcome-tag',
    );
    final controller = await _loadController(
      api: FakeDiscourseApi(
        feeds: const {'/latest.json': []},
        categorySiteTopTags: const [siteTop],
        categoryAnonymousDefaultTags: const [anonymousDefault],
      ),
    );

    expect(
      controller
          .tagSidebarSectionFor(_siteUrl)!
          .destinations
          .map((destination) => destination.label),
      ['welcome-tag', 'All tags'],
    );
  });

  testWidgets(
    'sidebar All tags loads the native directory and a row opens its feed',
    (tester) async {
      const tag = SidebarTag(
        id: 17,
        name: 'priority-high',
        slug: 'priority-high',
        description: 'Topics which need prompt attention',
        count: 3,
      );
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': [], '/tag/priority-high/17.json': []},
        tagList: const [tag],
      );
      final controller = await _loadController(
        api: api,
        user: const DiscourseUser(
          id: 1,
          username: 'reader',
          displaySidebarTags: true,
          sidebarTags: [tag],
        ),
      );
      await _pumpShell(tester, controller);

      expect(_sidebarText('TAGS'), findsOneWidget);
      expect(_sidebarText('priority-high'), findsOneWidget);
      expect(_sidebarText('All tags'), findsOneWidget);

      await tester.tap(_sidebarText('All tags'));
      await tester.pumpAndSettle();

      expect(controller.destinationId, 'all-tags');
      expect(find.byType(TagsPage), findsOneWidget);
      expect(api.tagRequests, [_siteUrl]);
      final row = find.byKey(const ValueKey('tag-directory-tag-17'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.text('Topics which need prompt attention'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('3')),
        findsOneWidget,
      );

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'tag-17');
      expect(controller.currentContent?.feedPath, '/tag/priority-high/17.json');
      expect(api.feedPaths.last, '/tag/priority-high/17.json');
      expect(find.byType(TagsPage), findsNothing);
    },
  );

  testWidgets('an initial directory failure shows a retryable error state', (
    tester,
  ) async {
    final api = _FailingTagApi();
    final controller = await _loadController(
      api: api,
      user: const DiscourseUser(
        id: 1,
        username: 'reader',
        displaySidebarTags: true,
      ),
    );
    controller.selectDestination(_allTagsDestination(controller));

    await _pumpShell(tester, controller);

    expect(find.byType(TagsPage), findsOneWidget);
    expect(
      find.text("Couldn't load tags from meta.discourse.org."),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(api.tagRequests, [_siteUrl]);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(api.tagRequests, [_siteUrl, _siteUrl]);
    expect(
      find.text("Couldn't load tags from meta.discourse.org."),
      findsOneWidget,
    );
  });

  testWidgets('a refresh failure preserves cached tags and offers a retry', (
    tester,
  ) async {
    const tag = SidebarTag(
      id: 17,
      name: 'priority-high',
      slug: 'priority-high',
      count: 3,
    );
    final api = _RefreshFailingTagApi(tag);
    final controller = await _loadController(
      api: api,
      user: const DiscourseUser(
        id: 1,
        username: 'reader',
        displaySidebarTags: true,
      ),
    );
    controller.selectDestination(_allTagsDestination(controller));
    await _pumpShell(tester, controller);

    const rowKey = ValueKey('tag-directory-tag-17');
    expect(find.byKey(rowKey), findsOneWidget);

    await controller.loadTags(_siteUrl, force: true);
    await tester.pumpAndSettle();

    expect(find.byKey(rowKey), findsOneWidget);
    expect(
      find.text("Couldn't load tags from meta.discourse.org."),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(api.tagRequests, [_siteUrl, _siteUrl, _siteUrl]);
    expect(find.byKey(rowKey), findsOneWidget);
  });
}

final class _FailingTagApi extends FakeDiscourseApi {
  _FailingTagApi() : super(feeds: const {'/latest.json': []});

  @override
  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    tagRequests.add(siteUrl);
    throw StateError('Tag directory failed.');
  }
}

final class _RefreshFailingTagApi extends FakeDiscourseApi {
  _RefreshFailingTagApi(this.tag) : super(feeds: const {'/latest.json': []});

  final SidebarTag tag;

  @override
  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    tagRequests.add(siteUrl);
    if (tagRequests.length == 1) return [tag];
    throw StateError('Tag directory refresh failed.');
  }
}
