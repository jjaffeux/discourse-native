import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _macOS = TargetPlatformVariant({TargetPlatform.macOS});

String _title(int id) => 'Topic $id with a longer title that wraps';

/// What one navigation redrew inside the sidebar.
final class _SidebarRebuilds {
  int elements = 0;
  final tiles = <String>[];
  final roots = <String, int>{};

  void clear() {
    elements = 0;
    tiles.clear();
    roots.clear();
  }
}

_SidebarRebuilds _recordSidebarRebuilds() {
  final rebuilds = _SidebarRebuilds();
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    if (element.findAncestorWidgetOfExactType<InstanceSidebar>() == null) {
      return;
    }
    rebuilds.elements++;
    if (element.dirty) {
      var w = element.widget.runtimeType.toString();
      rebuilds.roots[w] = (rebuilds.roots[w] ?? 0) + 1;
    }
    if (element.widget case SidebarDestinationTile(:final destination)) {
      rebuilds.tiles.add(destination.id);
    }
  };
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  return rebuilds;
}

Future<ShellController> _pumpForum(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  Map<String, Completer<void>> feedGates = const {},
}) async {
  final categories = [
    for (var id = 1; id <= 30; id++)
      TopicCategory(
        id: id,
        name: 'Category $id',
        slug: 'category-$id',
        color: '0088cc',
      ),
  ];
  final topics = [
    for (var id = 1; id <= 40; id++)
      Topic(
        id: id,
        title: _title(id),
        slug: 'topic-$id',
        categoryId: (id % 10) + 1,
        bumpedAt: DateTime.utc(2026, 9, 1),
      ),
  ];
  final user = DiscourseUser(
    id: 7,
    username: 'reader',
    sidebarCategoryIds: [for (var id = 1; id <= 20; id++) id],
    sidebarTags: [
      for (var id = 1; id <= 10; id++)
        SidebarTag(id: id, name: 'tag$id', slug: 'tag$id'),
    ],
    displaySidebarTags: true,
    sidebarShowCountOfNewItems: true,
  );
  final api = FakeDiscourseApi(
    user: user,
    categoryList: categories,
    feedCategoriesByPath: {'/latest.json': categories},
    feedGates: feedGates,
    feeds: {'/latest.json': topics},
    siteConfigs: const {_site: SiteConfig(taggingEnabled: true)},
    customSidebarSectionsBySite: {
      _site: [
        for (var section = 1; section <= 2; section++)
          SidebarSection.customFromJson({
            'id': section,
            'title': 'Section $section',
            'public': false,
            'links': [
              for (var link = 1; link <= 4; link++)
                {
                  'id': section * 10 + link,
                  'name': 'Link $section.$link',
                  'value': '/link-$link',
                  'icon': 'link',
                },
            ],
          }, index: section)!,
      ],
    },
    topics: {
      1: topicPayload(
        id: 1,
        title: _title(1),
        posts: [
          for (var number = 1; number <= 20; number++)
            Post(
              id: 1000 + number,
              postNumber: number,
              username: 'sam',
              cooked: '<p>Reply $number</p>',
            ),
        ],
      ),
    },
  );
  await pumpShell(
    tester,
    size,
    instances: [instance('meta.discourse.org', user: user)],
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
  );
  await tester.pumpAndSettle();
  return ShellScope.read(tester.element(primaryMainContent));
}

Finder _row(String label) => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: find.widgetWithText(DSidebarMenuButton, label),
);

bool _highlighted(WidgetTester tester, String label) =>
    tester.widget<DSidebarMenuButton>(_row(label)).isActive;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'a navigation redraws only the sidebar rows its selection moves between',
    (tester) async {
      final shell = await _pumpForum(tester);
      final rebuilds = _recordSidebarRebuilds();

      await tester.tap(find.text(_title(1)).first);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.isTopic, isTrue);
      final openElements = rebuilds.elements;
      final openTiles = rebuilds.tiles.length;
      rebuilds.clear();

      await tester.tap(
        find.descendant(
          of: find.byType(TopicView).first,
          matching: find.byKey(const ValueKey('topic-close-reader')),
        ),
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.isTopic, isFalse);
      final closeElements = rebuilds.elements;
      final closeTiles = rebuilds.tiles.length;
      rebuilds.clear();

      await tester.tap(_row('Category 2'));
      await tester.pumpAndSettle();
      expect(_highlighted(tester, 'Category 2'), isTrue);
      final clickElements = rebuilds.elements;
      final clickTiles = rebuilds.tiles.toSet();

      // ignore: avoid_print
      print('PERF_PROOF sidebar-navigation open_elements=$openElements');
      // ignore: avoid_print
      print('PERF_PROOF sidebar-navigation open_tiles=$openTiles');
      // ignore: avoid_print
      print('PERF_PROOF sidebar-navigation close_elements=$closeElements');
      // ignore: avoid_print
      print('PERF_PROOF sidebar-navigation close_tiles=$closeTiles');
      // ignore: avoid_print
      print('PERF_PROOF sidebar-navigation click_elements=$clickElements');
      // ignore: avoid_print
      print(
        'PERF_PROOF sidebar-navigation '
        'click_tiles=${rebuilds.tiles.length}',
      );
      expect(openTiles, 0);
      expect(closeTiles, 0);
      expect(openElements, lessThanOrEqualTo(68));
      expect(closeElements, lessThanOrEqualTo(68));
      expect(clickTiles, unorderedEquals(['latest', 'category-2']));
      expect(clickElements, lessThanOrEqualTo(220));
      expect(tester.takeException(), isNull);
    },
    variant: _macOS,
  );

  testWidgets('the sidebar highlight and its rows follow the scope', (
    tester,
  ) async {
    final shell = await _pumpForum(tester, size: const Size(1440, 2400));
    final unlisted = shell
        .filterCategoriesFor(_site)
        .singleWhere((category) => category.id == 25);
    expect(_highlighted(tester, 'Topics'), isTrue);
    expect(_row('Category 25'), findsNothing);

    await tester.tap(_row('Category 2'));
    await tester.pumpAndSettle();
    expect(_highlighted(tester, 'Category 2'), isTrue);
    expect(_highlighted(tester, 'Topics'), isFalse);

    await tester.tap(_row('Category 3'));
    await tester.pumpAndSettle();
    expect(_highlighted(tester, 'Category 3'), isTrue);
    expect(_highlighted(tester, 'Category 2'), isFalse);

    shell.selectTopicListCategory(unlisted);
    await tester.pumpAndSettle();
    expect(_highlighted(tester, 'Category 25'), isTrue);
    expect(_highlighted(tester, 'Category 3'), isFalse);

    shell.selectTopicListCategory(null);
    await tester.pumpAndSettle();
    expect(_row('Category 25'), findsNothing);
    expect(_highlighted(tester, 'Topics'), isTrue);

    shell.selectTopicListTag('tag3');
    await tester.pumpAndSettle();
    expect(_highlighted(tester, 'tag3'), isTrue);
    expect(_highlighted(tester, 'Topics'), isFalse);

    shell.selectTopicListTag('unlisted-tag');
    await tester.pumpAndSettle();
    expect(_highlighted(tester, 'unlisted-tag'), isTrue);
    expect(_highlighted(tester, 'tag3'), isFalse);

    shell.selectTopicListTag(null);
    await tester.pumpAndSettle();
    expect(_row('unlisted-tag'), findsNothing);
    expect(_highlighted(tester, 'Topics'), isTrue);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('a refreshing row stops loading when the shell leaves its feed', (
    tester,
  ) async {
    final feedGates = <String, Completer<void>>{};
    final shell = await _pumpForum(tester, feedGates: feedGates);
    const loading = ValueKey('sidebar-destination-loading-latest');
    final latestTab = shell.activeTabId!;
    shell.openContentInNewTab(ContentRoute.group(const GroupRoute.directory()));
    await tester.pumpAndSettle();
    final groupsTab = shell.activeTabId!;
    shell.selectTab(latestTab);
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    feedGates['/latest.json'] = gate;

    await tester.tap(_row('Topics'));
    await tester.pump();
    expect(find.byKey(loading), findsOneWidget);

    shell.selectTab(groupsTab);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(loading), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: _macOS);
}
