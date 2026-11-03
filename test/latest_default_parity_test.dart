import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/content_navigation_controls.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/dashboard_fixture.dart';
import 'support/fakes.dart';
import 'support/native_ui_evidence.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
final _more = find.byKey(const ValueKey('sidebar-more-toggle'));
Finder _dashboard() => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: find.widgetWithText(DSidebarMenuButton, 'Dashboard'),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });

  test(
    'saved Start routes migrate across sites, panes and both histories',
    () async {
      final start = {
        'destination_type': 'page',
        'id': 'new-tab',
        'title': 'Start page',
        'icon': 'house',
      };
      final topic = ContentRoute.topic(
        topicId: 42,
        slug: 'topic',
        title: 'Topic',
      );
      final persistence = MemoryForumTabPersistence()
        ..value = jsonEncode({
          'version': 1,
          'selectedSiteUrl': _site,
          'workspaces': [
            for (final site in [_site, 'https://other.example'])
              {
                'site_url': site,
                'account_identity': 'anonymous',
                'active_tab_id': 'main',
                'tabs': [
                  for (final panel in ForumPanel.values)
                    {
                      'id': panel.name,
                      'panel': panel.name,
                      'root_destination_id': 'new-tab',
                      'content_stack': [start, topic.toJson()],
                      'back_history': [
                        {
                          'root_destination_id': 'new-tab',
                          'content_stack': [start],
                        },
                      ],
                      'forward_history': [
                        {
                          'root_destination_id': 'new-tab',
                          'content_stack': [start],
                        },
                      ],
                    },
                ],
              },
          ],
        });
      final store = ForumTabStore(persistence: persistence);
      final workspaces = await store.load();
      expect(workspaces, hasLength(2));
      for (final workspace in workspaces) {
        expect(workspace.tabs, hasLength(2));
        for (final tab in workspace.tabs) {
          expect(tab.rootDestinationId, 'latest');
          expect(tab.contentStack.first.id, 'latest');
          expect(tab.currentContent.topicId, 42);
          expect(tab.goBack().currentContent.id, 'latest');
          expect(tab.goForward().currentContent.id, 'latest');
          for (final entry in [...tab.backHistory, ...tab.forwardHistory]) {
            expect(entry.rootDestinationId, 'latest');
            expect(entry.contentStack.single.title, 'Latest topics');
          }
        }
      }
      await store.save(workspaces, selectedSiteUrl: _site);
      expect(persistence.value, isNot(contains('new-tab')));
      expect(MobileTab.tryParse('destination/new-tab'), MobileTab.topics);
      final extension = ForumTab.tryFromJson({
        'id': 'extension',
        'root_destination_id': 'new-tab',
        'content_stack': [
          const ContentRoute(
            destination: ExtensionDestination('new-tab'),
            title: 'Plugin',
            icon: DIcons.star,
          ).toJson(),
        ],
      })!;
      expect(extension.rootDestinationId, 'new-tab');
      expect(extension.currentContent.destination, isA<ExtensionDestination>());
    },
  );

  testWidgets('startup, new panes and tabs use Latest despite site homepage', (
    tester,
  ) async {
    const config = SiteConfig(
      defaultHomepage: 'categories',
      topMenu: ['categories', 'top'],
    );
    await prepareNativeUiEvidence(tester);
    await pumpShell(
      tester,
      desktop,
      instances: [instance('meta.discourse.org').copyWith(config: config)],
      api: FakeDiscourseApi(
        siteConfigs: {_site: config},
        feeds: {
          '/latest.json': [
            for (var id = 1; id <= 10; id++)
              Topic(id: id, title: 'Latest discussion $id', slug: 'latest-$id'),
          ],
        },
      ),
    );
    final shell = ShellScope.read(tester.element(primaryMainContent));
    for (final panel in ForumPanel.values) {
      expect(shell.selectedTabIn(panel)?.currentContent.id, 'latest');
      shell.createTab(panel: panel);
      await tester.pumpAndSettle();
      expect(shell.activeTab?.panel, panel);
      expect(shell.currentContent?.id, 'latest');
      expect(shell.currentContent?.tabTitle, 'Latest topics');
      expect(shell.destinationId, 'latest');
    }
    expect(find.text('Start page'), findsNothing);
    await _capture(tester, 'desktop-latest-light');
    if (Platform.environment['LATEST_DEFAULT_CAPTURE_DIR'] != null) {
      await tester.runAsync(
        () => shell.forumSettings.setThemeMode(_site, AppThemeMode.dark),
      );
      await tester.pumpAndSettle();
      await _capture(tester, 'desktop-latest-dark');
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Home resets the primary tab and scrolls only its Latest list', (
    tester,
  ) async {
    await pumpShell(
      tester,
      desktop,
      api: FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            for (var id = 1; id <= 60; id++)
              Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
          ],
        },
      ),
    );
    final shell = ShellScope.read(tester.element(primaryMainContent));
    final home = shell.activeTabId!;
    final secondary = shell.selectedTabIn(ForumPanel.secondary)!;
    final primaryScroll = tester
        .stateList<ScrollableState>(
          find.descendant(
            of: primaryMainContent,
            matching: find.byType(Scrollable),
          ),
        )
        .firstWhere((state) => state.position.maxScrollExtent > 500)
        .position;
    primaryScroll.jumpTo(500);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ContentNavigationControls.homeKey));
    await tester.pumpAndSettle();
    expect(primaryScroll.pixels, 0);
    expect(shell.selectedTabIn(ForumPanel.secondary), secondary);

    shell.createTab(panel: ForumPanel.main);
    shell.pushContent(ContentRoute.preferences());
    final reordered = shell.activeTab!;
    shell.moveTab(reordered.id, 0);
    shell.selectTab(home);
    expect(
      ForumWorkspace.tryFromJson(shell.currentWorkspace!.toJson())!.homeTab?.id,
      home,
    );
    shell.applySearchToList('narrowed', const []);
    await tester.pumpAndSettle();
    shell.createTab(panel: ForumPanel.secondary);
    await tester.pumpAndSettle();
    final other = shell.activeTab!;
    await tester.tap(find.byKey(ContentNavigationControls.homeKey));
    await tester.pumpAndSettle();
    expect(shell.activeTabId, home);
    expect(shell.currentContent?.id, 'latest');
    expect(shell.contentStack, hasLength(1));
    expect(shell.currentWorkspace!.tabById(other.id), other);
    expect(shell.currentWorkspace!.tabById(reordered.id), reordered);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'global search applies to the primary pane from a secondary list',
    (tester) async {
      await pumpShell(tester, desktop);
      final shell = ShellScope.read(tester.element(primaryMainContent));
      final main = shell.activeTabId!;
      final secondary = shell.selectedTabIn(ForumPanel.secondary)!;
      shell.selectTab(secondary.id);
      shell.applySearchToList('design', const []);
      await tester.pumpAndSettle();
      expect(shell.activeTabId, main);
      expect(shell.currentContent?.topicListSearch, 'design');
      expect(shell.selectedTabIn(ForumPanel.secondary), secondary);
      shell.selectTab(secondary.id);
      shell.openSearchResult(
        const SearchPostHit(
          postId: 1,
          topicId: 1,
          postNumber: 1,
          topicTitle: 'Search result',
          topicSlug: 'result',
          username: 'reader',
          excerpt: SearchExcerpt([SearchExcerptSegment('design')]),
        ),
        words: 'design',
      );
      await tester.pumpAndSettle();
      expect(shell.activeTabId, main);
      expect(shell.currentContent?.topicId, 1);
      expect(shell.search.wordsFor(_site, main, 'topic-1'), 'design');
      expect(shell.selectedTabIn(ForumPanel.secondary), secondary);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final (role, user, allowed) in [
    ('guest', null, false),
    ('member', const DiscourseUser(id: 7, username: 'reader'), false),
    (
      'moderator',
      const DiscourseUser(id: 7, username: 'moderator', staff: true),
      true,
    ),
    (
      'admin',
      const DiscourseUser(id: 7, username: 'admin', staff: true, admin: true),
      true,
    ),
  ]) {
    testWidgets('Dashboard is a More destination for $role', (tester) async {
      await prepareNativeUiEvidence(tester);
      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        authenticator: FakeAuthenticator()..keys[_site] = 'key',
        api: _DashboardSidebarApi(user),
      );
      expect(_dashboard(), findsNothing);
      await tester.tap(_more);
      await tester.pumpAndSettle();
      expect(_dashboard(), allowed ? findsOneWidget : findsNothing);
      if (allowed) {
        final shell = ShellScope.read(tester.element(primaryMainContent));
        shell.pushContent(ContentRoute.dashboard());
        await tester.pumpAndSettle();
        await tester.tap(_more);
        await tester.pumpAndSettle();
        expect(tester.widget<DSidebarMenuButton>(_more).expanded, isFalse);
        expect(_dashboard(), findsOneWidget);
        expect(
          tester.widget<DSidebarMenuButton>(_dashboard()).isActive,
          isTrue,
        );
        final row = tester.getRect(_dashboard());
        final more = tester.getRect(_more);
        expect(row.bottom, lessThanOrEqualTo(more.top));
        expect(row.left, closeTo(more.left, .01));
        await _capture(tester, 'desktop-$role-light');
        await tester.runAsync(
          () => shell.forumSettings.setThemeMode(_site, AppThemeMode.dark),
        );
        await tester.pumpAndSettle();
        await _capture(tester, 'desktop-$role-dark');
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
}

final class _DashboardSidebarApi extends FakeDiscourseApi {
  _DashboardSidebarApi(DiscourseUser? user)
    : super(
        user: user,
        feeds: {
          '/latest.json': [
            for (var id = 1; id <= 10; id++)
              Topic(id: id, title: 'Latest discussion $id', slug: 'latest-$id'),
          ],
        },
        pluginResponses: {
          'POST /admin/dashboard/reports/bulk.json': dashboardReportsFixture,
        },
      );

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async => Uri.parse(path).path == '/admin/dashboard.json'
      ? dashboardFixture
      : super.pluginGetJson(
          siteUrl: siteUrl,
          path: path,
          apiKey: apiKey,
          clientId: clientId,
        );
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['LATEST_DEFAULT_CAPTURE_DIR'];
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
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
      scene.dispose();
    }
  });
}
