import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/plugins/site_plugin.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShellController shell;

  setUp(() async {
    shell = ShellController(
      instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabsEnabled: false,
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      ownsApi: false,
    );
    addTearDown(shell.dispose);
    await shell.load();
  });

  testWidgets('existing content plugins keep the shell header by default', (
    tester,
  ) async {
    const route = ContentRoute(
      id: 'test-standard',
      title: 'Standard route',
      icon: DIcons.comment,
    );
    shell.pushContent(route);

    await _pump(tester, shell, const PluginRegistry([_StandardPlugin()]));

    expect(find.text('Standard route'), findsOneWidget);
    expect(find.byKey(const ValueKey('standard-body')), findsOneWidget);
  });

  testWidgets('a chrome owner keeps its body and suppresses only the header', (
    tester,
  ) async {
    const route = ContentRoute(
      id: 'test-owned',
      title: 'Shell title must be hidden',
      icon: DIcons.comment,
    );
    shell.pushContent(route);

    await _pump(tester, shell, const PluginRegistry([_ChromeOwnerPlugin()]));

    expect(find.text('Shell title must be hidden'), findsNothing);
    expect(find.byKey(const ValueKey('owned-body')), findsOneWidget);
    expect(find.text('Plugin chrome'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  ShellController shell,
  PluginRegistry registry,
) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MainContent(layout: ShellLayout.expanded, registry: registry),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
