import 'package:discourse_native/src/models/content_route.dart';
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

  testWidgets('existing content plugins keep the shell header by default', (
    tester,
  ) async {
    final shell = await _shellWith(const _StandardPlugin());
    const route = ContentRoute(
      id: 'test-standard',
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
      id: 'test-owned',
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
      id: 'test-standard',
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
      id: 'test-list-tile',
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
      id: 'test-standard',
      title: 'Threads',
      subtitle: 'Support',
      icon: DIcons.comments,
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
          id: 'test-standard',
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

Future<ShellController> _shellWith(SitePlugin plugin) async {
  final installed = PluginInstaller.install(
    PluginManifest([_ContentTestModule(plugin)]),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
    api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabsEnabled: false,
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
