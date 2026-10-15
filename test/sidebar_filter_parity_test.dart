import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/keyboard_test_harness.dart';
import 'support/shell_test_harness.dart';

const site = 'https://meta.discourse.org';
const user = DiscourseUser(id: 7, username: 'reader', displaySidebarTags: true);
const parent = TopicCategory(
  id: 1,
  name: 'Product',
  slug: 'product',
  color: '563A93',
);
const child = TopicCategory(
  id: 2,
  name: 'Design',
  slug: 'design',
  color: '3188CC',
  parentCategoryId: 1,
);
const sibling = TopicCategory(
  id: 3,
  name: 'Development',
  slug: 'development',
  color: 'CE6736',
  parentCategoryId: 1,
);
const other = TopicCategory(
  id: 4,
  name: 'Support',
  slug: 'support',
  color: '3BBF7B',
);
const tags = [
  SidebarTag(id: 10, name: 'Alpha', slug: 'alpha', count: 8),
  SidebarTag(id: 11, name: 'Beta', slug: 'beta', count: 20),
];
const config = SiteConfig(taggingEnabled: true);

const filterMenuOptions = [
  TopicFilterOption(name: 'category:', type: 'category'),
  TopicFilterOption(name: 'tag:', type: 'tag'),
  TopicFilterOption(name: 'tag-group:', type: 'tag_group'),
  TopicFilterOption(name: 'topic:', type: 'text'),
  TopicFilterOption(name: 'users:', type: 'username'),
  TopicFilterOption(name: 'created-by:', type: 'username_group_list'),
  TopicFilterOption(name: 'group:', type: 'group'),
  TopicFilterOption(name: 'assigned:', type: 'username_group_list'),
  TopicFilterOption(name: 'status:'),
  TopicFilterOption(name: 'status:open'),
  TopicFilterOption(name: 'status:closed'),
  TopicFilterOption(name: 'status:solved'),
  TopicFilterOption(name: 'in:'),
  TopicFilterOption(name: 'in:pinned'),
  TopicFilterOption(name: 'in:watching'),
  TopicFilterOption(name: 'in:bookmarked'),
  TopicFilterOption(name: 'in:untagged'),
  TopicFilterOption(name: 'locale:', type: 'text'),
  TopicFilterOption(name: 'created-after:', type: 'date'),
  TopicFilterOption(name: 'created-before:', type: 'date'),
  TopicFilterOption(name: 'posts-min:', type: 'number'),
  TopicFilterOption(name: 'posts-max:', type: 'number'),
  TopicFilterOption(name: 'views-min:', type: 'number'),
  TopicFilterOption(name: 'views-max:', type: 'number'),
  TopicFilterOption(name: 'votes-min:', type: 'number'),
  TopicFilterOption(name: 'votes-max:', type: 'number'),
  TopicFilterOption(name: 'order:'),
  TopicFilterOption(name: 'order:activity'),
  TopicFilterOption(name: 'order:votes'),
];

Future<({ShellController shell, FakeDiscourseApi api})> fixture(
  WidgetTester tester, {
  Size size = desktop,
  List<SidebarTag> knownTags = tags,
  Map<String, List<TopicCategory>> categorySearches = const {},
  Completer<void>? filterOptionsGate,
  List<TopicFilterOption> filterOptions = const [
    TopicFilterOption(name: 'status:open', priority: 1),
  ],
}) async {
  final api = FakeDiscourseApi(
    user: user,
    categoryList: const [parent, child, sibling, other],
    categorySiteTopTags: knownTags,
    categorySearches: categorySearches,
    siteConfigs: const {site: config},
    feeds: const {
      '/latest.json': [],
      '/filter.json': [],
      '/c/product/1.json': [],
      '/c/product/design/2.json': [],
      '/tags/c/product/1/Alpha.json': [],
      '/tags/c/product/design/2/Alpha.json': [],
    },
    filterOptionsByPath: {'/filter.json': filterOptions},
    feedGates: {'/filter.json': ?filterOptionsGate},
    categoryFilterTagSearches: const {
      (1, ''): [
        TopicFilterLookupValue(name: 'Alpha', description: '8'),
        TopicFilterLookupValue(name: 'Beta', description: '20'),
      ],
      (2, ''): [TopicFilterLookupValue(name: 'Alpha', description: '4')],
    },
  );
  await pumpShell(
    tester,
    size,
    instances: [
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: user, config: config),
    ],
    authenticator: FakeAuthenticator()..keys[site] = 'key',
    api: api,
  );
  final shell = ShellScope.read(tester.element(primaryMainContent));
  await shell.forumSettings.setShared(
    const SharedAppearance(
      font: ForumFont.openSans,
      interfaceFont: ForumFont.openSans,
    ),
  );
  await tester.pumpAndSettle();
  return (shell: shell, api: api);
}

Finder row(String label) => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: find.widgetWithText(DSidebarMenuButton, label),
);
Finder get field => find.byKey(const ValueKey('topic-filter-input'));
TextField textField(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(of: field, matching: find.byType(TextField)),
);

Future<void> openFilters(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: primaryMainContent,
      matching: find.byKey(const ValueKey('topic-list-filter')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    const keyboard = MethodChannel('org.discourse.native/keyboard');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          keyboard,
          (_) async => throw MissingPluginException(),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keyboard, null),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  setUpAll(() async {
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
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
    'sidebar browses children, leaf siblings, and toggles one selected scope',
    (tester) async {
      final (shell: shell, api: api) = await fixture(tester);
      await tester.tap(row('Product'));
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.categoryId, 1);
      expect(row('Support'), findsNothing);
      expect(row('Design'), findsOneWidget);
      expect(row('Development'), findsOneWidget);
      expect(
        api.filterTagRequests,
        contains((siteUrl: site, term: '', categoryId: 1)),
      );
      expect(
        tester.widget<DSidebarMenuButton>(row('Product')).isActive,
        isTrue,
      );
      expect(
        tester.widget<DSidebarMenuButton>(row('Topics')).isActive,
        isFalse,
      );
      await tester.tap(row('Design'));
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.categoryId, 2);
      expect(row('Development'), findsOneWidget);
      await tester.tap(row('Alpha'));
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.categoryId, 2);
      expect(shell.topicListContent?.tagName, 'Alpha');
      expect(tester.widget<DSidebarMenuButton>(row('Alpha')).isActive, isTrue);
      expect(
        tester.widget<DSidebarMenuButton>(row('Design')).isActive,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('sidebar-tags-up')));
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.tagName, isNull);
      await tester.tap(find.byKey(const ValueKey('sidebar-categories-up')));
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.categoryId, isNull);
      expect(row('Support'), findsOneWidget);
      expect(tester.widget<DSidebarMenuButton>(row('Topics')).isActive, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'section headings retain typography and alignment across scopes at $scale',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final (shell: shell, api: _) = await fixture(tester);

        ({TextStyle style, Size size, double left}) heading(String label) {
          final text = find.descendant(
            of: find.byType(InstanceSidebar),
            matching: find.text(label),
          );
          final paragraph = tester.renderObject<RenderParagraph>(text);
          return (
            style: paragraph.text.style!,
            size: Size(
              paragraph.getMaxIntrinsicWidth(double.infinity),
              paragraph.size.height,
            ),
            left: tester.getTopLeft(text).dx,
          );
        }

        final categories = heading('Categories');
        final tagHeading = heading('Tags');
        await capture(tester, 'sidebar-headings-root-$scale');
        await tester.tap(row('Product'));
        await tester.pumpAndSettle();
        await tester.tap(row('Alpha'));
        await tester.pumpAndSettle();
        await capture(tester, 'sidebar-headings-selected-$scale');
        expect(heading('Categories'), categories);
        expect(heading('Tags'), tagHeading);

        await tester.tap(find.byKey(const ValueKey('sidebar-tags-up')));
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.tagName, isNull);
        expect(heading('Tags'), tagHeading);
        await tester.tap(find.byKey(const ValueKey('sidebar-categories-up')));
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.categoryId, isNull);
        expect(heading('Categories'), categories);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'an uncached selected tag stays visible and tags are ordered by actual usage',
    (tester) async {
      final (shell: shell, api: _) = await fixture(tester);
      final suggestions = await shell.searchFilterTags(siteUrl: site, term: '');
      expect(suggestions.map((item) => item.name), ['Beta', 'Alpha']);
      shell.selectTopicListTag('Uncached');
      await tester.pumpAndSettle();
      expect(row('Uncached'), findsOneWidget);
      expect(
        tester.widget<DSidebarMenuButton>(row('Uncached')).isActive,
        isTrue,
      );
      expect(
        tester.widget<DSidebarMenuButton>(row('Topics')).isActive,
        isFalse,
      );
      await tester.tap(row('Uncached'));
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.tagName, isNull);
      expect(tester.widget<DSidebarMenuButton>(row('Topics')).isActive, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'a list tag picker round-trips names that differ from URL slugs',
    (tester) async {
      const tag = SidebarTag(id: 12, name: 'User experience', slug: 'ux');
      final (shell: shell, api: _) = await fixture(tester, knownTags: [tag]);
      for (var selection = 0; selection < 2; selection++) {
        await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(DCommandList<String>),
            matching: find.text(tag.name),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('topic-filter-done-tags')));
        await tester.pumpAndSettle();
        expect(
          shell.topicListContent?.tagNames,
          selection == 0 ? [tag.name] : <String>[],
        );
        expect(
          tester.widget<DSidebarMenuButton>(row(tag.name)).isActive,
          selection == 0,
        );
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'a searched category outside the cached tree becomes a reusable scope',
    (tester) async {
      const remoteParent = TopicCategory(
        id: 10,
        name: 'Knowledge',
        slug: 'knowledge',
        color: '222222',
      );
      const remote = TopicCategory(
        id: 20,
        name: 'Remote leaf',
        slug: 'remote',
        color: '777777',
        parentCategoryId: 10,
      );
      final (shell: shell, api: _) = await fixture(
        tester,
        categorySearches: {
          'remote': [remoteParent, remote],
        },
      );
      await openFilters(tester);
      await tester.enterText(field, 'category:remote');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Knowledge › Remote leaf'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.categoryId, 20);
      expect(
        shell.filterCategoriesFor(site).map((item) => item.id),
        containsAll([10, 20]),
      );
      expect(
        tester.widget<DSidebarMenuButton>(row('Remote leaf')).isActive,
        isTrue,
      );
      await openFilters(tester);
      expect(find.text('Category: Remote leaf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'category navigation from Start and Messages opens the focused tab list',
    (tester) async {
      final (shell: shell, api: _) = await fixture(tester);
      shell.selectTopicListCategory(child);
      await tester.pumpAndSettle();
      final originalTab = shell.activeTabId!;
      final originalRoute = shell.currentContent;
      shell.openContentInNewTab(ContentRoute.newTab());
      await tester.pumpAndSettle();
      final startTab = shell.activeTabId;
      await tester.tap(row('Support'));
      await tester.pumpAndSettle();
      expect(shell.activeTabId, startTab);
      expect(shell.topicListContent?.categoryId, 4);
      expect(
        shell.currentWorkspace?.tabById(originalTab)?.currentContent,
        originalRoute,
      );
      await tester.tap(row('Messages'));
      await tester.pumpAndSettle();
      await tester.tap(row('Product'));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.isTopicListFilter, isTrue);
      expect(shell.currentContent?.isMessages, isFalse);
      expect(shell.topicListContent?.categoryId, 1);
      expect(
        shell.currentWorkspace?.tabById(originalTab)?.currentContent,
        originalRoute,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'scope tokens count, stage replacement, drill by keyboard and clear the live list',
    (tester) async {
      final (shell: shell, api: _) = await fixture(tester);
      shell.selectTopicListCategory(parent);
      shell.selectTopicListTag('Alpha');
      await tester.pumpAndSettle();
      expect(find.text('Filters · 2'), findsOneWidget);
      await openFilters(tester);
      expect(find.text('Category: Product'), findsOneWidget);
      expect(find.text('Tags: Alpha'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topic-filter-token-edit-0')));
      await tester.pumpAndSettle();
      expect(textField(tester).controller!.text, 'category:');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-filter-category-into-1')),
        findsNothing,
      );
      expect(find.text('Design'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Category: Design'), findsOneWidget);
      expect(
        shell.topicListContent?.categoryId,
        1,
        reason: 'selection is staged until Apply',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.categoryId, 2);
      expect(shell.topicListContent?.tagName, 'Alpha');
      await openFilters(tester);
      await clearMenu(tester);
      await tester.pumpAndSettle();
      expect(shell.topicListContent?.categoryId, isNull);
      expect(shell.topicListContent?.tagName, isNull);
      expect(
        find.descendant(of: primaryMainContent, matching: find.text('Filters')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('closing a staged replacement reopens the applied scopes', (
    tester,
  ) async {
    final (shell: shell, api: _) = await fixture(tester);
    shell.selectTopicListCategory(parent);
    await tester.pumpAndSettle();
    await openFilters(tester);
    await tester.tap(find.byKey(const ValueKey('topic-filter-token-edit-0')));
    await tester.pumpAndSettle();
    await tester.enterText(field, 'category:design');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Product › Design'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(shell.topicListContent?.categoryId, 1);
    await openFilters(tester);
    expect(find.text('Category: Product'), findsOneWidget);
    expect(find.text('Category: Design'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('mobile scopes leave Messages and select the Topics surface', (
    tester,
  ) async {
    final (shell: shell, api: _) = await fixture(tester, size: phone);
    expect(shell.mobileNavigationEnabled, isTrue);
    shell.selectMobileDestination(
      MobileTab.messages,
      const SidebarDestination(
        id: 'messages',
        label: 'Messages',
        icon: DIcons.inbox,
      ),
    );
    await tester.pumpAndSettle();
    shell.changeSidebarScope(categoryId: parent.id);
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.tab, MobileTab.topics);
    expect(shell.topicListContent?.categoryId, 1);
    expect(shell.currentContent?.isMessages, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final material in DAppearanceMaterial.values) {
      if (platform == TargetPlatform.iOS) {
        testWidgets('Filters move with native keyboard timing ($material)', (
          tester,
        ) async {
          const channel = MethodChannel('org.discourse.native/keyboard');
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            (_) async => false,
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null),
          );
          tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
          tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
          final (shell: shell, api: _) = await fixture(
            tester,
            size: phone,
            filterOptions: filterMenuOptions,
          );
          await shell.forumSettings.setShared(
            SharedAppearance(material: material),
          );
          await tester.pumpAndSettle();
          await openFilters(tester);
          final sheet = find.byType(DSheetContent);
          final opened = tester.getRect(sheet);
          final results = find.descendant(
            of: find.byType(DCommandList<String>),
            matching: find.byType(Scrollable),
          );
          final position = tester
              .state<ScrollableState>(results.first)
              .position;
          await tester.tap(field);
          await tester.pump();
          await sendKeyboardFrame(tester);
          await tester.pump();
          expect(tester.getRect(sheet), opened);
          for (var step = 1; step <= 4; step++) {
            if (step > 1) {
              tester.view.viewInsets = FakeViewPadding(bottom: step * 60);
            }
            await tester.pump(const Duration(milliseconds: 50));
            final rect = tester.getRect(sheet);
            final progress = step / 8;
            expect(rect.left, closeTo(6 * progress, .1));
            expect(
              rect.top,
              closeTo(opened.top + (55 - opened.top) * progress, .2),
            );
            expect(position.pixels, 0);
          }
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pump(const Duration(milliseconds: 201));
          final shown = tester.getRect(sheet);
          expect(shown.top, closeTo(55, 1));
          expect(shown.left, 6);
          expect(shown.bottom, closeTo(538, 1));
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), shown);
          await sendKeyboardFrame(tester, inset: 0);
          await tester.pumpAndSettle();
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet).left, 6);
          expect(tester.getRect(sheet).bottom, closeTo(804, 1));
          await tester.tapAt(const Offset(8, 20));
          await tester.pumpAndSettle();
          expect(sheet, findsNothing);
          await openFilters(tester);
          expect(tester.getRect(sheet).left, 0);
          expect(tester.takeException(), isNull);
        }, variant: TargetPlatformVariant.only(platform));
      }

      testWidgets(
        'async Filters keep their default height on $platform ($material)',
        (tester) async {
          final gate = Completer<void>();
          final (shell: shell, api: _) = await fixture(
            tester,
            size: phone,
            filterOptions: filterMenuOptions,
            filterOptionsGate: gate,
          );
          await shell.forumSettings.setShared(
            SharedAppearance(material: material),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: primaryMainContent,
              matching: find.byKey(const ValueKey('topic-list-filter')),
            ),
          );
          final sheet = find.byType(DSheetContent);
          for (var frame = 0; frame < 24; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (sheet.evaluate().isNotEmpty) {
              expect(tester.getRect(sheet).left, 0);
            }
          }
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet).top, closeTo(phone.height * .45, 1));
          expect(tester.getRect(sheet).left, 0);
          gate.complete();
          for (var frame = 0; frame < 24; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(sheet, findsOneWidget);
            expect(tester.getRect(sheet).top, closeTo(phone.height * .45, 1));
            expect(tester.getRect(sheet).left, 0);
          }
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet).height, closeTo(phone.height * .55, 1));
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(platform),
      );

      testWidgets(
        'focusing Filters animates its bounds after the keyboard on $platform ($material)',
        (tester) async {
          const channel = MethodChannel('org.discourse.native/keyboard');
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            (_) async => false,
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null),
          );
          tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
          tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
          final (shell: shell, api: _) = await fixture(
            tester,
            size: phone,
            filterOptions: filterMenuOptions,
          );
          await shell.forumSettings.setShared(
            SharedAppearance(material: material),
          );
          await tester.pumpAndSettle();
          await openFilters(tester);
          final sheet = find.byType(DSheetContent);
          final opened = tester.getRect(sheet);
          final results = find.descendant(
            of: find.byType(DCommandList<String>),
            matching: find.byType(Scrollable),
          );
          final position = tester
              .state<ScrollableState>(results.first)
              .position;
          expect(
            tester.getRect(results.first).bottom,
            closeTo(tester.getRect(sheet).bottom - 10 - DSpacing.xs, .1),
            reason: 'Filters can scroll through the bottom safe area',
          );
          await tester.tap(field);
          await tester.pump();
          expect(tester.getRect(sheet), opened);
          for (final keyboard in [100.0, 200.0, 300.0]) {
            tester.view.viewInsets = FakeViewPadding(
              bottom: keyboard * tester.view.devicePixelRatio,
            );
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.getRect(sheet), opened);
            await tester.pump();
            expect(tester.getRect(sheet), opened);
          }
          await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('keyboardReady', true),
            ),
            (_) {},
          );
          await tester.pump();
          await tester.pump();
          expect(tester.getRect(sheet), opened);
          var previous = opened;
          for (var frame = 0; frame < 4; frame++) {
            await tester.pump(const Duration(milliseconds: 32));
            final current = tester.getRect(sheet);
            expect(current.left, inExclusiveRange(previous.left, 6));
            expect(current.top, lessThan(previous.top));
            expect(current.width, lessThan(previous.width));
            expect(current.bottom, lessThan(previous.bottom));
            expect(
              current.height,
              inInclusiveRange(opened.height - 40, phone.height - 355),
            );
            expect(position.pixels, 0);
            expect(current.top, greaterThan(55));
            expect(current.bottom, greaterThan(phone.height - 300));
            expect(
              current.left / 6,
              closeTo((opened.top - current.top) / (opened.top - 55), .01),
              reason: 'spacing animates alongside position and size',
            );
            previous = current;
          }
          await tester.pump(const Duration(milliseconds: 153));
          expect(tester.getRect(sheet).left, 6);
          expect(tester.getRect(sheet).top, closeTo(55, 1));
          expect(tester.getRect(sheet).bottom, closeTo(phone.height - 306, 1));
          expect(position.pixels, 0);
          final placed = tester.getRect(sheet);
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), placed);
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(platform),
      );

      testWidgets(
        'Filters reserve the expansion gesture and accept backdrop swipes on $platform ($material)',
        (tester) async {
          tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
          tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
          final (shell: shell, api: _) = await fixture(
            tester,
            size: const Size(390, 700),
            filterOptions: filterMenuOptions,
          );
          await shell.forumSettings.setShared(
            SharedAppearance(material: material),
          );
          await tester.pumpAndSettle();
          await openFilters(tester);
          final sheet = find.byType(DSheetContent);
          final results = find.descendant(
            of: find.byType(DCommandList<String>),
            matching: find.byType(Scrollable),
          );
          final position = tester.state<ScrollableState>(results).position;
          await tester.fling(results, const Offset(0, -180), 5000);
          for (var frame = 0; frame < 24; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(position.pixels, 0);
            expect(position.isScrollingNotifier.value, isFalse);
            expect(tester.getRect(sheet).left, 0);
          }
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet).top, closeTo(55, 1));
          expect(position.maxScrollExtent, greaterThan(100));
          await tester.fling(results, const Offset(0, -60), 800);
          await tester.pumpAndSettle();
          expect(position.pixels, greaterThan(0));
          await tester.tapAt(const Offset(8, 20));
          await tester.pumpAndSettle();
          expect(sheet, findsNothing);
          await openFilters(tester);
          final opened = tester.getRect(sheet);
          final above = Offset(opened.center.dx, opened.top - 60);
          final short = await tester.startGesture(above);
          await short.moveBy(const Offset(0, 40));
          await short.moveBy(const Offset(0, 50));
          await tester.pump();
          expect(tester.getRect(sheet).top, greaterThan(opened.top));
          await short.up();
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet), opened);
          await tester.dragFrom(above, const Offset(0, 220));
          await tester.pumpAndSettle();
          expect(sheet, findsNothing);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(platform),
      );

      testWidgets(
        'filter sheet expands, floats, and preserves its query on $platform ($material)',
        (tester) async {
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = true);
          final (shell: shell, api: _) = await fixture(
            tester,
            size: phone,
            filterOptions: filterMenuOptions,
          );
          await shell.forumSettings.setShared(
            SharedAppearance(
              font: ForumFont.openSans,
              interfaceFont: ForumFont.openSans,
              material: material,
            ),
          );
          await shell.forumSettings.setThemeMode(site, AppThemeMode.dark);
          await tester.pumpAndSettle();
          await openFilters(tester);
          final sheet = find.byType(DSheetContent);
          expect(tester.getRect(sheet).width, phone.width);
          expect(tester.getRect(sheet).top, closeTo(phone.height * .45, 1));
          expect(textField(tester).focusNode!.hasFocus, isFalse);
          await capture(tester, 'filter-$platform-$material-collapsed');
          await tester.drag(
            find.byKey(const ValueKey('sheet-drag-handle')),
            const Offset(0, -350),
          );
          await tester.pumpAndSettle();
          final expandedTop = tester.getRect(sheet).top;
          await capture(tester, 'filter-$platform-$material-expanded');
          final results = find.descendant(
            of: find.byType(DCommandList<String>),
            matching: find.byType(Scrollable),
          );
          final position = tester
              .state<ScrollableState>(results.first)
              .position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet).left, 6);
          expect(tester.getRect(sheet).top, closeTo(expandedTop, 1));
          expect(position.extentAfter, closeTo(0, 1));
          await capture(tester, 'filter-$platform-$material-inset');
          final reverse = await tester.startGesture(
            tester.getCenter(results.first),
          );
          await reverse.moveBy(const Offset(0, 40));
          await reverse.moveBy(const Offset(0, 6));
          await tester.pump();
          await tester.pump();
          final distance = position.extentAfter;
          expect(distance, inExclusiveRange(0, 40));
          await reverse.moveBy(const Offset(0, 6));
          await tester.pump();
          expect(position.extentAfter, greaterThan(distance));
          await reverse.up();
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet).left, 6);
          await tester.enterText(field, 'posted');
          tester.view.viewInsets = FakeViewPadding(
            bottom: 300 * tester.view.devicePixelRatio,
          );
          addTearDown(tester.view.resetViewInsets);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet).left, 6);
          expect(
            tester.getRect(sheet).bottom,
            lessThanOrEqualTo(phone.height - 300),
          );
          expect(textField(tester).controller!.text, 'posted');
          await capture(tester, 'filter-$platform-$material-keyboard');
          expect(tester.takeException(), isNull);
          debugDisableShadows = true;
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }

  for (final size in [desktop, phone]) {
    testWidgets(
      'compact filters stay usable at $size and 200 percent text',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final (shell: shell, api: _) = await fixture(tester, size: size);
        shell.selectTopicListCategory(parent);
        shell.selectTopicListTag('Alpha');
        await tester.pumpAndSettle();
        await shell.forumSettings.setThemeMode(
          site,
          size == phone ? AppThemeMode.dark : AppThemeMode.light,
        );
        await tester.pumpAndSettle();
        await openFilters(tester);
        if (size == phone) {
          await tester.drag(
            find.byKey(const ValueKey('sheet-drag-handle')),
            const Offset(0, -350),
          );
          await tester.pumpAndSettle();
        }
        await capture(
          tester,
          size == phone ? 'filters-phone-large' : 'filters-desktop-large',
        );
        await clearMenu(tester);
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.categoryId, isNull);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(
        size == phone ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
    );
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['SIDEBAR_FILTER_REVIEW_DIR'];
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

Future<void> clearMenu(WidgetTester tester) async {
  final remove = find.byKey(const ValueKey('topic-filter-token-remove-0'));
  while (remove.evaluate().isNotEmpty) {
    await tester.tap(remove);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('topic-filter-apply')));
  await tester.pumpAndSettle();
}
