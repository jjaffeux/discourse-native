import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'typed feeds keep their tab metadata despite a plugin key match',
    (tester) async {
      final shell = await _shellWith(const _TabMetadataPlugin());
      await _pump(tester, shell);
      final context = tester.element(find.byType(MainContent));
      const feed = ContentRoute(
        destination: FeedDestination(key: 'test-standard'),
        title: 'A core feed',
        icon: DIcons.list,
      );
      final tab = ForumTab(
        id: 'test',
        rootDestinationId: feed.id,
        contentStack: const [feed],
      );

      expect(
        shell.plugins.registry.forumTabDestination(
          context,
          'https://meta.discourse.org',
          tab,
        ),
        isNull,
      );
      expect(
        shell.plugins.registry
            .forumTabDestination(
              context,
              'https://meta.discourse.org',
              tab.copyWith(
                contentStack: const [
                  ContentRoute(
                    destination: ExtensionDestination('test-standard'),
                    title: 'Plugin page',
                    icon: DIcons.list,
                  ),
                ],
              ),
            )
            ?.label,
        'Plugin tab',
      );
    },
  );

  test(
    'typed feeds hydrate and refresh despite core and plugin homepage key matches',
    () async {
      final plugin = _HomepageHydratorPlugin();
      final api = FakeDiscourseApi(feeds: const {'/unread.json': []});
      final shell = await _shellWith(
        plugin,
        api: api,
        restoredRoute: const ContentRoute(
          destination: FeedDestination(
            key: 'users',
            mode: TopicListMode.unread,
          ),
          title: 'Unread',
          icon: DIcons.list,
        ),
      );
      await pumpEventQueue();
      expect(api.feedPaths, contains('/unread.json'));
      final before = api.feedPaths.length;
      await shell.refreshCurrentTab();
      expect(api.feedPaths.length, greaterThan(before));
      expect(api.feedPaths.last, '/unread.json');
      expect(plugin.hydrations, 0);
    },
  );

  testWidgets(
    'typed feeds keep their renderer when a plugin recognizes the key',
    (tester) async {
      final shell = await _shellWith(const _HeaderActionPlugin());
      shell.pushContent(
        const ContentRoute(
          destination: FeedDestination(
            key: 'test-standard',
            sourcePath: '/latest.json',
            mode: TopicListMode.latest,
          ),
          title: 'Latest',
          icon: DIcons.list,
        ),
      );
      await shell.loadFeed('test-standard');
      await _pump(tester, shell);
      expect(find.byKey(const ValueKey('standard-body')), findsNothing);
      expect(find.byKey(const ValueKey('plugin-header-action')), findsNothing);
      expect(
        find.byKey(const ValueKey('inbox-topic-list-pane')),
        findsOneWidget,
      );
    },
  );

  testWidgets('existing content plugins keep the shell header by default', (
    tester,
  ) async {
    final shell = await _shellWith(const _StandardPlugin());
    const route = ContentRoute(
      destination: ExtensionDestination('test-standard'),
      title: 'Standard route',
      icon: DIcons.comment,
    );
    shell.pushContent(route);

    await _pump(tester, shell);

    expect(find.text('Standard route'), findsOneWidget);
    expect(find.byKey(const ValueKey('standard-body')), findsOneWidget);
  });

  testWidgets('a chrome owner keeps its body and suppresses only the header', (
    tester,
  ) async {
    final shell = await _shellWith(const _ChromeOwnerPlugin());
    const route = ContentRoute(
      destination: ExtensionDestination('test-owned'),
      title: 'Shell title must be hidden',
      icon: DIcons.comment,
    );
    shell.pushContent(route);

    await _pump(tester, shell);

    expect(find.text('Shell title must be hidden'), findsNothing);
    expect(find.byKey(const ValueKey('owned-body')), findsOneWidget);
    expect(find.text('Plugin chrome'), findsOneWidget);
  });

  testWidgets('a content-header plugin adds an action to standard chrome', (
    tester,
  ) async {
    final shell = await _shellWith(const _HeaderActionPlugin());
    const route = ContentRoute(
      destination: ExtensionDestination('test-standard'),
      title: 'Standard route',
      icon: DIcons.comment,
    );
    shell.pushContent(route);

    await _pump(tester, shell);

    expect(find.byKey(const ValueKey('plugin-header-action')), findsOneWidget);
    expect(find.text('Standard route'), findsOneWidget);
  });

  testWidgets('content tiles paint ink on the main content surface', (
    tester,
  ) async {
    final shell = await _shellWith(const _ListTilePlugin());
    const route = ContentRoute(
      destination: ExtensionDestination('test-list-tile'),
      title: 'List tile route',
      icon: DIcons.comment,
    );
    shell.pushContent(route);

    await _pump(tester, shell);

    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('the standard header', () {
    const stacked = ContentRoute(
      destination: ExtensionDestination('test-standard'),
      title: 'Threads',
      icon: DIcons.comments,
      subtitle: 'Support',
    );

    testWidgets('keeps its fixed height for a subtitle at normal text', (
      tester,
    ) async {
      final shell = await _shellWith(const _StandardPlugin());
      shell.pushContent(stacked);

      await _pump(tester, shell);

      final header = tester.getRect(_header);
      expect(header.height, shellHeaderHeight);
      final title = tester.getRect(find.text('Threads'));
      final subtitle = tester.getRect(find.text('Support'));
      expect(title.bottom, subtitle.top);
      expect(title.top - header.top, header.bottom - subtitle.bottom);
    });

    for (final scale in [1.5, 2.0, 3.0]) {
      testWidgets('grows with ${scale}x text so a subtitle keeps its inset', (
        tester,
      ) async {
        final shell = await _shellWith(const _StandardPlugin());
        shell.pushContent(stacked);
        await _pump(tester, shell);
        final normal = tester.getRect(_header);
        final inset = tester.getRect(find.text('Threads')).top - normal.top;

        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final header = tester.getRect(_header);
        final title = tester.getRect(find.text('Threads'));
        final subtitle = tester.getRect(find.text('Support'));
        expect(header.height, greaterThan(shellHeaderHeight));
        expect(title.height, greaterThanOrEqualTo(_titleLine(scale) - 1));
        expect(title.top - header.top, closeTo(inset, 1));
        expect(header.bottom - subtitle.bottom, closeTo(inset, 1));
        expect(_paragraph(tester, 'Threads').didExceedMaxLines, isFalse);
        expect(_paragraph(tester, 'Support').didExceedMaxLines, isFalse);
      });
    }

    testWidgets('keeps its fixed height for a single line at larger text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final shell = await _shellWith(const _StandardPlugin());
      shell.pushContent(
        const ContentRoute(
          destination: ExtensionDestination('test-standard'),
          title: 'Standard route',
          icon: DIcons.comment,
        ),
      );

      await _pump(tester, shell);

      expect(tester.getRect(_header).height, shellHeaderHeight);
      expect(tester.takeException(), isNull);
    });
  });
}

final Finder _header = find.byKey(const ValueKey('content-header'));

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text));

Future<void> _pump(WidgetTester tester, ShellController shell) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MainContent(
            layout: ShellLayout.expanded,
            registry: shell.plugins.registry,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<ShellController> _shellWith(
  SitePlugin plugin, {
  FakeDiscourseApi? api,
  ContentRoute? restoredRoute,
}) async {
  final installed = PluginInstaller.install(
    PluginManifest([_ContentTestModule(plugin)]),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
    api: api ?? FakeDiscourseApi(feeds: const {'/latest.json': []}),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabsEnabled: restoredRoute != null,
    forumTabs: restoredRoute == null
        ? null
        : FakeForumTabStore([
            ForumWorkspace(
              siteUrl: 'https://meta.discourse.org',
              accountIdentity: 'anonymous',
              tabs: [
                ForumTab(
                  id: 'restored',
                  rootDestinationId: 'latest',
                  contentStack: [restoredRoute],
                ),
              ],
              activeTabId: 'restored',
            ),
          ]),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    plugins: installed,
    ownsApi: false,
  );
  addTearDown(() async {
    shell.dispose();
    await installed.close();
  });
  await shell.load();
  return shell;
}

final class _ContentTestModule implements PluginModule {
  const _ContentTestModule(this.plugin);

  final SitePlugin plugin;

  @override
  PluginDescriptor get descriptor =>
      PluginDescriptor(id: PluginId(plugin.name));

  @override
  void register(PluginRegistrar registrar) => registrar.addCapability(plugin);
}

class _StandardPlugin implements SitePlugin, ContentPlugin {
  const _StandardPlugin();

  @override
  String get name => 'standard-test';

  @override
  Widget? content(BuildContext context, ContentRoute route) =>
      route.id == 'test-standard'
      ? const SizedBox(key: ValueKey('standard-body'))
      : null;
}

class _TabMetadataPlugin extends _StandardPlugin implements ForumTabPlugin {
  const _TabMetadataPlugin();

  @override
  SidebarDestination? forumTabDestination(
    BuildContext context,
    String siteUrl,
    ForumTab tab,
  ) => const SidebarDestination(
    id: 'test-standard',
    label: 'Plugin tab',
    icon: DIcons.list,
  );

  @override
  Listenable? forumTabListenable(BuildContext context, String siteUrl) => null;
}

class _HomepageHydratorPlugin extends _StandardPlugin
    implements HomepagePlugin, PluginRouteHydrator {
  int hydrations = 0;
  @override
  String get homepageId => 'users';
  @override
  ContentRoute? homepage(SiteConfig config, DiscourseUser? user) =>
      const ContentRoute(
        destination: ExtensionDestination('users'),
        title: 'Plugin',
        icon: DIcons.list,
      );
  @override
  bool handlesPluginRoute(String routeId) => routeId == 'users';
  @override
  Future<void> hydratePluginRoute(
    String siteUrl,
    String routeId, {
    bool force = false,
  }) async {
    hydrations++;
  }
}

class _ChromeOwnerPlugin
    implements SitePlugin, ContentPlugin, ContentChromePlugin {
  const _ChromeOwnerPlugin();

  @override
  String get name => 'chrome-owner-test';

  @override
  Widget? content(BuildContext context, ContentRoute route) =>
      route.id == 'test-owned'
      ? const Column(
          key: ValueKey('owned-body'),
          children: [Text('Plugin chrome')],
        )
      : null;

  @override
  bool ownsContentChrome(BuildContext context, ContentRoute route) =>
      route.id == 'test-owned';
}

class _HeaderActionPlugin
    implements SitePlugin, ContentPlugin, ContentHeaderPlugin {
  const _HeaderActionPlugin();

  @override
  String get name => 'header-action-test';

  @override
  Widget? content(BuildContext context, ContentRoute route) =>
      route.id == 'test-standard'
      ? const SizedBox(key: ValueKey('standard-body'))
      : null;

  @override
  List<Widget> contentHeaderActions(BuildContext context, ContentRoute route) =>
      const [SizedBox(key: ValueKey('plugin-header-action'))];
}

class _ListTilePlugin implements SitePlugin, ContentPlugin {
  const _ListTilePlugin();

  @override
  String get name => 'list-tile-test';

  @override
  Widget? content(BuildContext context, ContentRoute route) =>
      route.id == 'test-list-tile'
      ? CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: false,
          onChanged: (_) {},
          title: const Text('Choice'),
        )
      : null;
}

/// The title's whole line box at [scale], so a clipped title cannot pass.
double _titleLine(double scale) {
  final style = AppTheme.light.textTheme.titleSmall!;
  return style.fontSize! * scale * style.height!;
}
