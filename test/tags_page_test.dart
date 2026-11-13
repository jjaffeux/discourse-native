import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/tags_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart' as harness;
import 'support/skeleton_expectations.dart';

const Size _viewport = Size(1200, 900);
const String _siteUrl = 'https://meta.discourse.org';

Future<ShellController> _loadController({
  required FakeDiscourseApi api,
  DiscourseUser? user,
  bool mobileNavigation = false,
}) async {
  final stored = instance('meta.discourse.org', title: 'Discourse Meta');
  final site = user == null ? stored : stored.copyWith(user: user);
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: FakeAuthenticator.signedIn([site], site: api),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
    mobileNavigationEnabled: mobileNavigation,
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
  for (final (name, mobile, size) in [
    ('desktop', false, _viewport),
    ('phone', true, const Size(390, 844)),
  ]) {
    testWidgets(
      'only the tag of the list the tab came from is marked on $name',
      (tester) async {
        const first = SidebarTag(
          id: 17,
          name: 'first',
          slug: 'first',
          count: 3,
        );
        const second = SidebarTag(id: 18, name: 'second', slug: 'second');
        const third = SidebarTag(id: 19, name: 'third', slug: 'third');
        final controller = await _loadController(
          api: FakeDiscourseApi(
            feeds: const {
              '/latest.json': [],
              '/tag/first/17.json': [],
              '/tag/second/18.json': [],
            },
            tagList: const [first, second, third],
          ),
          user: const DiscourseUser(
            id: 1,
            username: 'reader',
            displaySidebarTags: true,
            sidebarTags: [first, second],
          ),
          mobileNavigation: mobile,
        );
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
                home: Scaffold(
                  body: MainContent(
                    layout: mobile ? ShellLayout.compact : ShellLayout.expanded,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Finder row(int id) => find.byKey(ValueKey('tag-directory-tag-$id'));
        DItem item(int id) => tester.widget<DItem>(
          find.descendant(of: row(id), matching: find.byType(DItem)),
        );
        Iterable<int> marked() => [17, 18, 19].where((id) => item(id).selected);
        Future<void> showDirectory() async {
          controller.selectDestination(_allTagsDestination(controller));
          await tester.pumpAndSettle();
        }

        await showDirectory();
        expect(marked(), isEmpty);
        final restingSize = tester.getSize(row(17));

        controller.openTag(first);
        await tester.pumpAndSettle();
        await showDirectory();
        expect(marked(), [17]);

        // The mockup's treatment, without the item's checkmark or a resize.
        final tokens = DTokens.of(tester.element(row(17)));
        final card = tester.widget<DCard>(row(17));
        expect(card.border, isTrue);
        expect(card.borderColor, tokens.primary);
        expect(card.backgroundColor, Colors.transparent);
        expect(item(17).showSelectionIndicator, isFalse);
        expect(tester.getSize(row(17)), restingSize);
        expect(tester.widget<DCard>(row(18)).border, isFalse);

        await tester.tap(row(18));
        await tester.pumpAndSettle();
        expect(controller.currentContent?.tagId, 18);
        await showDirectory();
        expect(marked(), [18]);
      },
    );
  }

  for (final mobile in [false, true]) {
    testWidgets(
      'All tags shows a viewport-filling Native skeleton on ${mobile ? 'mobile' : 'desktop'} and retains rows during refresh',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final api = _HeldTagApi();
        addTearDown(() {
          if (!api.tagsGate.isCompleted) api.tagsGate.complete();
        });
        const user = _directoryUser;
        final site = instance('meta.discourse.org').copyWith(user: user);
        await harness.pumpShell(
          tester,
          mobile ? harness.phone : harness.desktop,
          instances: [site],
          api: api,
          authenticator: FakeAuthenticator.signedIn([site], site: api),
          revealMobileNavigation: mobile,
        );
        final allTags = _sidebarText('All tags');
        await tester.ensureVisible(allTags);
        await tester.tap(allTags);
        await tester.pump();
        await api.started.future;
        await tester.pump(const Duration(milliseconds: 400));
        final page = find.byType(TagsPage);
        expect(page, findsOneWidget);
        // The phone bar offers no All tags place, so the page is Topics'.
        if (mobile) {
          expect(
            ShellScope.read(tester.element(page)).mobileNavigation.tab,
            MobileTab.topics,
          );
        }
        expectSkeletonFillsViewport(
          tester,
          label: 'Loading tags',
          bottom: tester.getRect(page).bottom - 24,
        );
        expect(find.byType(TagDirectoryRow), findsNothing);
        expect(find.text('No tags yet'), findsNothing);

        api.tagsGate.complete();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('tag-directory-tag-17')),
          findsOneWidget,
        );
        expect(find.byType(DSkeletonRegion), findsNothing);

        api.tagsGate = Completer<void>();
        final shell = ShellScope.read(tester.element(page));
        final refresh = shell.loadTags(_siteUrl, force: true);
        await tester.pump();
        expect(shell.tagDirectoryFeedFor(_siteUrl).loading, isTrue);
        expect(
          find.byKey(const ValueKey('tag-directory-tag-17')),
          findsOneWidget,
        );
        expect(find.byType(DSkeletonRegion), findsNothing);
        api.tagsGate.complete();
        await refresh;
        await tester.pumpAndSettle();
        api.result = const [];
        await shell.loadTags(_siteUrl, force: true);
        await tester.pumpAndSettle();
        expect(find.text('No tags yet'), findsOneWidget);
        expect(find.byType(DSkeletonRegion), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(
        mobile ? TargetPlatform.iOS : TargetPlatform.linux,
      ),
    );
  }

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
        ['selected-tag', 'Edit', 'All tags'],
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
        ['site-top-tag', 'Edit', 'All tags'],
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

  test(
    'tag refresh keeps the snapshot until visible tag data changes',
    () async {
      final tags = <SidebarTag>[_loadedTag];
      final controller = await _loadController(
        api: FakeDiscourseApi(feeds: const {'/latest.json': []}, tagList: tags),
      );
      await controller.loadTags(_siteUrl);
      final original = controller.tagDirectoryFeedFor(_siteUrl).tags;
      expect(original, [_loadedTag]);

      tags[0] = SidebarTag.fromJson(_loadedTag.toJson())!;
      await controller.loadTags(_siteUrl, force: true);
      expect(controller.tagDirectoryFeedFor(_siteUrl).tags, same(original));

      tags[0] = SidebarTag.fromJson({..._loadedTag.toJson(), 'count': 7})!;
      await controller.loadTags(_siteUrl, force: true);
      final updated = controller.tagDirectoryFeedFor(_siteUrl).tags;
      expect(updated.single.count, 7);
      expect(original.single.count, 3);
    },
  );

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

      expect(_sidebarText('Tags'), findsOneWidget);
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
        find.descendant(of: row, matching: find.text('3 topics')),
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

  testWidgets('the directory title retracts on scroll like the reference', (
    tester,
  ) async {
    final tags = [
      for (var id = 1; id <= 120; id++)
        SidebarTag(id: id, name: 'tag-$id', slug: 'tag-$id', count: 200 - id),
    ];
    final controller = await _loadController(
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}, tagList: tags),
      user: const DiscourseUser(
        id: 1,
        username: 'reader',
        displaySidebarTags: true,
      ),
    );
    await _pumpShell(tester, controller);
    await tester.tap(_sidebarText('All tags'));
    await tester.pumpAndSettle();

    final title = find
        .descendant(of: find.byType(TagsPage), matching: find.text('Tags'))
        .hitTestable();
    final grid = find.byKey(const ValueKey('tag-directory-tag-4'));
    final scroller = Scrollable.of(tester.element(grid)).position;
    Future<void> wheel(double amount) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(TagsPage)),
          scrollDelta: Offset(0, amount),
        ),
      );
      await tester.pumpAndSettle();
    }

    expect(title, findsOneWidget);
    await wheel(600);
    expect(title, findsNothing);
    // Past the end-of-scroll hold, a short scroll back brings the title in
    // while the list is still well away from its top.
    await tester.pump(const Duration(milliseconds: 500));
    await wheel(-160);
    expect(scroller.pixels, greaterThan(200));
    expect(title, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await wheel(400);
    expect(title, findsNothing);
    scroller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

const _loadedTag = SidebarTag(
  id: 17,
  name: 'priority-high',
  slug: 'priority-high',
  description: 'Topics which need prompt attention',
  count: 3,
);

const _directoryUser = DiscourseUser(
  id: 1,
  username: 'reader',
  displaySidebarTags: true,
  sidebarTags: [_loadedTag],
);

final class _HeldTagApi extends FakeDiscourseApi {
  _HeldTagApi()
    : super(user: _directoryUser, feeds: const {'/latest.json': []});

  final started = Completer<void>();
  Completer<void> tagsGate = Completer<void>();
  List<SidebarTag> result = const [_loadedTag];

  @override
  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    tagRequests.add(siteUrl);
    if (!started.isCompleted) started.complete();
    await tagsGate.future;
    return result;
  }
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
