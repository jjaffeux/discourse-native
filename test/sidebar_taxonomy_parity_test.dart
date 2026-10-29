import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/sidebar_taxonomy_editor.dart';
import 'package:discourse_native/src/shell/tags_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/native_ui_evidence.dart';

const _site = 'https://meta.discourse.org';
const _topics = [
  Topic(
    id: 101,
    title: 'Building accessible navigation',
    slug: 'accessible-navigation',
    categoryId: 3,
    postsCount: 8,
    replyCount: 7,
    views: 248,
    excerpt: 'Making forum navigation work for everyone.',
    tags: [TopicTag(id: 11, name: 'howto')],
  ),
  Topic(
    id: 102,
    title: 'A guide to category hierarchies',
    slug: 'category-hierarchies',
    categoryId: 3,
    postsCount: 4,
    replyCount: 3,
    views: 126,
    excerpt: 'Organize a growing community with categories and tags.',
    tags: [TopicTag(id: 11, name: 'howto')],
  ),
];
const _categories = [
  TopicCategory(
    id: 1,
    name: 'Product',
    slug: 'product',
    color: '7755AA',
    position: 0,
  ),
  TopicCategory(
    id: 2,
    name: 'Design',
    slug: 'design',
    color: '4488CC',
    parentCategoryId: 1,
    position: 0,
  ),
  TopicCategory(
    id: 3,
    name: 'Development',
    slug: 'development',
    color: 'CC6633',
    parentCategoryId: 1,
    position: 1,
  ),
  TopicCategory(
    id: 5,
    name: 'Feature requests',
    slug: 'feature-requests',
    color: 'CCAA33',
    parentCategoryId: 3,
    position: 0,
  ),
  TopicCategory(
    id: 4,
    name: 'Support',
    slug: 'support',
    color: '33AA88',
    position: 1,
  ),
];
const _release = SidebarTag(
  id: 10,
  name: 'release',
  slug: 'release',
  count: 12,
);
const _tags = [
  _release,
  SidebarTag(id: 11, name: 'howto', slug: 'howto', count: 148),
  SidebarTag(id: 12, name: 'accessibility', slug: 'accessibility', count: 46),
  SidebarTag(id: 13, name: 'design-system', slug: 'design-system', count: 31),
];
const _user = DiscourseUser(
  id: 7,
  username: 'reader',
  displaySidebarTags: true,
  sidebarCategoryIds: [1, 2, 4],
  sidebarTags: [_release],
);
const _config = SiteConfig(
  fixedCategoryPositions: true,
  defaultNavigationMenuCategoryIds: [4],
  defaultNavigationMenuTagNames: ['accessibility'],
);

Future<({ShellController shell, FakeDiscourseApi api, FakeInstanceStore store})>
_fixture(
  WidgetTester tester, {
  bool phone = false,
  Completer<void>? writeGate,
  WriteException? writeFailure,
}) async {
  SharedPreferences.setMockInitialValues({});
  final api =
      FakeDiscourseApi(
          user: _user,
          categoryList: _categories,
          tagList: _tags,
          userPreferencesWriteGate: writeGate,
          writeFailure: writeFailure,
          siteConfigs: const {_site: _config},
          feeds: const {
            '/latest.json': _topics,
            '/tag/howto/11.json': _topics,
            '/c/product/development/3.json': _topics,
            '/tags/c/product/development/3/howto.json': _topics,
          },
        )
        ..userPreferences = const UserPreferences(
          username: 'reader',
          canEdit: true,
          sidebarCategoryIds: [1, 2, 4],
          sidebarTags: [_release],
        );
  final store = FakeInstanceStore([
    instance(
      'meta.discourse.org',
      title: 'Discourse Meta',
    ).copyWith(user: _user, config: _config),
  ]);
  final shell = ShellController(
    instanceStore: store,
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
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1100, 820);
  tester.view.devicePixelRatio = 1;
  if (phone) {
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  }
  addTearDown(tester.view.reset);
  await prepareNativeUiEvidence(tester);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: phone
            ? AppTheme.light.copyWith(platform: TargetPlatform.iOS)
            : AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        builder: (context, child) =>
            nativeUiEvidenceBuilder(context, DToaster(child: child!)),
        home: Scaffold(
          body: phone
              ? const InstanceSidebar(mobile: true)
              : const Row(
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
  return (shell: shell, api: api, store: store);
}

Finder _choice(int id, {bool tag = false}) =>
    find.byKey(ValueKey('sidebar-choice-${tag ? 'tag' : 'category'}-$id'));
Finder _edit(bool categories) => find
    .descendant(
      of: find.byType(InstanceSidebar),
      matching: find.widgetWithText(DSidebarMenuButton, 'Edit'),
    )
    .at(categories ? 0 : 1);

void main() {
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
    'category editor filters, resets, saves server preferences and keeps saved siblings',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (:shell, :api, :store) = await _fixture(tester);
      shell.changeSidebarScope(categoryId: 3, tag: 'howto');
      await tester.pumpAndSettle();
      final categories = shell.categorySidebarSectionFor(_site)!.destinations;
      expect(categories.map((d) => d.label), [
        'Product',
        'Design',
        'Development',
        'Feature requests',
        'Support',
        'Edit',
        'All categories',
      ]);
      expect(categories.take(5).map((d) => d.indent), [0, 1, 1, 2, 0]);
      expect(categories[2].onSecondaryTap, isNotNull);
      expect(
        find.bySemanticsLabel('Save Development to sidebar'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Save howto to sidebar'), findsOneWidget);
      await captureNativeUi(tester, 'desktop-hierarchy-transient');
      semantics.dispose();
      await tester.tap(_edit(true));
      await tester.pumpAndSettle();
      expect(find.byType(SidebarTaxonomyEditor), findsOneWidget);
      expect(tester.widget<DCheckbox>(_choice(2)).value, isTrue);
      expect(
        tester.getTopLeft(_choice(2)).dx,
        greaterThan(tester.getTopLeft(_choice(1)).dx),
      );
      await captureNativeUi(tester, 'desktop-category-editor');
      await tester.tap(find.text('Selected'));
      await tester.pumpAndSettle();
      expect(_choice(3), findsNothing);
      await tester.tap(find.text('Unselected'));
      await tester.pumpAndSettle();
      expect(_choice(1), findsNothing);
      expect(_choice(3), findsOneWidget);
      await tester.tap(find.text('All'));
      await tester.enterText(find.byType(TextField), 'Design');
      await tester.pumpAndSettle();
      expect(_choice(2), findsOneWidget);
      expect(_choice(1), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Reset to default'));
      await tester.pumpAndSettle();
      expect(tester.widget<DCheckbox>(_choice(4)).value, isTrue);
      expect(tester.widget<DCheckbox>(_choice(1)).value, isFalse);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.userPreferenceUpdates.single.values, {
        'sidebar_category_ids': [4],
      });
      expect(shell.currentUserFor(_site)!.sidebarCategoryIds, [4]);
      expect((await store.load()).single.user!.sidebarCategoryIds, [4]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tag editor saves names and directory sorts cards by topic count with real navigation',
    (tester) async {
      final (:shell, :api, :store) = await _fixture(tester);
      await tester.tap(_edit(false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset to default'));
      await tester.pumpAndSettle();
      expect(tester.widget<DCheckbox>(_choice(12, tag: true)).value, isTrue);
      expect(tester.widget<DCheckbox>(_choice(10, tag: true)).value, isFalse);
      await captureNativeUi(tester, 'desktop-tag-editor');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.userPreferenceUpdates.single.values, {
        'sidebar_tag_names': ['accessibility'],
      });
      expect((await store.load()).single.user!.sidebarTags.map((t) => t.name), [
        'accessibility',
      ]);
      shell.selectDestination(
        shell.tagSidebarSectionFor(_site)!.destinations.last,
      );
      await tester.pumpAndSettle();
      expect(find.byType(TagsPage), findsOneWidget);
      final cards = tester
          .widgetList<TagDirectoryRow>(find.byType(TagDirectoryRow))
          .toList();
      expect(cards.map((r) => r.tag.name), [
        'howto',
        'accessibility',
        'design-system',
        'release',
      ]);
      expect(find.text('148 topics'), findsOneWidget);
      await captureNativeUi(tester, 'desktop-tags-directory');
      await tester.tap(find.byKey(const ValueKey('tag-directory-tag-11')));
      await tester.pumpAndSettle();
      expect(api.feedPaths.last, '/tag/howto/11.json');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel discards edits and a retired account cannot save', (
    tester,
  ) async {
    final (:shell, :api, :store) = await _fixture(tester);
    await tester.tap(_edit(true));
    await tester.pumpAndSettle();
    await tester.tap(_choice(3));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(api.userPreferenceUpdates, isEmpty);
    expect((await store.load()).single.user!.sidebarCategoryIds, [1, 2, 4]);
    await tester.tap(_edit(true));
    await tester.pumpAndSettle();
    shell.lifecycle.invalidate(_site);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.userPreferenceUpdates, isEmpty);
  });

  testWidgets(
    'transient plus actions save category IDs and tag names without losing existing choices',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (:shell, :api, :store) = await _fixture(tester);
      shell.changeSidebarScope(categoryId: 3, tag: 'howto');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is DSidebarMenuAction &&
              widget.semanticLabel == 'Save Development to sidebar',
        ),
      );
      await tester.pumpAndSettle();
      expect(shell.currentUserFor(_site)!.sidebarCategoryIds, [1, 2, 4, 3]);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is DSidebarMenuAction &&
              widget.semanticLabel == 'Save howto to sidebar',
        ),
      );
      await tester.pumpAndSettle();
      expect(api.userPreferenceUpdates.map((update) => update.values), [
        {
          'sidebar_category_ids': [1, 2, 4, 3],
        },
        {
          'sidebar_tag_names': ['release', 'howto'],
        },
      ]);
      expect(
        (await store.load()).single.user!.sidebarTags.map((tag) => tag.name),
        ['release', 'howto'],
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'failed saves keep the editor open and cancelling restores the confirmed draft',
    (tester) async {
      final (:shell, :api, :store) = await _fixture(
        tester,
        writeFailure: const WriteException(
          WriteFailure.validation,
          errors: ['Sidebar choices could not be saved.'],
        ),
      );
      await tester.tap(_edit(true));
      await tester.pumpAndSettle();
      await tester.tap(_choice(3));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Sidebar choices could not be saved.'), findsOneWidget);
      expect(find.byType(SidebarTaxonomyEditor), findsOneWidget);
      expect((await store.load()).single.user!.sidebarCategoryIds, [1, 2, 4]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        shell.preferences
            .stateFor(_site)!
            .dirty(PreferenceSection.sidebarCategories),
        isFalse,
      );
      expect(api.userPreferenceUpdates, hasLength(1));
    },
  );

  testWidgets(
    'a failed transient save reports the server error and keeps the plus action',
    (tester) async {
      final (:shell, :api, :store) = await _fixture(
        tester,
        writeFailure: const WriteException(
          WriteFailure.validation,
          errors: ['Sidebar choices could not be saved.'],
        ),
      );
      shell.changeSidebarScope(categoryId: 3);
      await tester.pumpAndSettle();
      final action = find.byWidgetPredicate(
        (widget) =>
            widget is DSidebarMenuAction &&
            widget.semanticLabel == 'Save Development to sidebar',
      );
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Sidebar choices could not be saved.'), findsOneWidget);
      expect(action, findsOneWidget);
      expect((await store.load()).single.user!.sidebarCategoryIds, [1, 2, 4]);
      expect(api.userPreferenceUpdates, hasLength(1));
    },
  );

  testWidgets('phone category editor renders a Native adaptive sheet', (
    tester,
  ) async {
    final (:shell, :api, :store) = await _fixture(tester, phone: true);
    await tester.ensureVisible(_edit(true));
    await tester.tap(_edit(true));
    await tester.pumpAndSettle();
    await captureNativeUi(tester, 'phone-category-editor');
    expect(tester.takeException(), isNull);
    expect(shell.currentUserFor(_site), isNotNull);
    expect(api.userPreferenceUpdates, isEmpty);
    expect(await store.load(), hasLength(1));
  });
}
