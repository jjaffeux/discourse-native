import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/models/forum_workspace.dart'
    show ForumWorkspace;
import 'package:discourse_native/src/plugins/gamification/gamification_admin_page.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_module.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/shell_test_harness.dart';
import 'gamification_fixture.dart';

void main() {
  for (final panel in ForumPanel.values) {
    testWidgets('leaderboard URL opens in a background ${panel.name} tab', (
      tester,
    ) async {
      final (shell, context) = await _pumpLinkShell(tester);
      final before = shell.activeTab;
      final beforeCount = shell.tabsForCurrentForum.length;
      var navigated = 0;

      expect(
        await openLink(
          context,
          '$gameSite/leaderboard',
          newTab: true,
          panel: panel,
          onNavigated: () => navigated++,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();

      expect(shell.activeTab, before);
      expect(shell.tabsForCurrentForum, hasLength(beforeCount + 1));
      final opened = shell.tabsForCurrentForum.last;
      expect(opened.currentContent.id, 'gamification');
      expect(opened.panel, panel);
      expect(navigated, 0);
    }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));
  }

  testWidgets('cross-forum leaderboard new tab preserves the source forum', (
    tester,
  ) async {
    final (shell, context) = await _pumpLinkShell(tester, otherSite: true);
    final before = shell.activeTab;
    final sourceSite = shell.currentInstance!.url;

    expect(
      await openLink(context, '$gameSite/leaderboard', newTab: true),
      isTrue,
    );
    await tester.pumpAndSettle();

    expect(shell.currentInstance!.url, sourceSite);
    expect(shell.activeTab, before);
    expect(
      shell
          .workspaceFor(gameSite)!
          .tabs
          .where((tab) => tab.currentContent.id == 'gamification'),
      hasLength(1),
    );
    expect(
      shell.workspaceFor(gameSite)!.activeTab.currentContent.id,
      isNot('gamification'),
    );
    expect(
      shell.workspaceFor(gameSite)!.tabs.last.currentContent.id,
      'gamification',
    );
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('leaderboard URL targets the foreground secondary panel', (
    tester,
  ) async {
    final (shell, context) = await _pumpLinkShell(tester);
    final before = shell.activeTab!;
    var navigated = 0;

    expect(
      await openLink(
        context,
        '$gameSite/leaderboard',
        panel: ForumPanel.secondary,
        onNavigated: () => navigated++,
      ),
      isTrue,
    );
    await tester.pumpAndSettle();

    expect(shell.activeTab!.panel, ForumPanel.secondary);
    expect(shell.currentContent!.id, 'gamification');
    expect(shell.selectedTabIn(ForumPanel.main), before);
    expect(navigated, 1);
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets(
    'a full destination refuses a leaderboard new tab without mutation',
    (tester) async {
      final (shell, context) = await _pumpLinkShell(tester);
      for (
        var i = shell.tabsForCurrentForum.length;
        i < ForumWorkspace.maximumTabs;
        i++
      ) {
        shell.createTab();
      }
      await tester.pumpAndSettle();
      final before = shell.currentWorkspace;
      var navigated = 0;

      expect(
        await openLink(
          context,
          '$gameSite/leaderboard',
          newTab: true,
          panel: ForumPanel.secondary,
          onNavigated: () => navigated++,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();

      expect(shell.currentWorkspace, before);
      expect(navigated, 0);
      expect(shell.currentContent!.id, isNot('gamification'));
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  for (final size in [const Size(1360, 900), const Size(390, 844)]) {
    testWidgets(
      'real shell Back restores leaderboard period and scroll at ${size.width}',
      (tester) async {
        final fixture = GamificationFixture();
        addTearDown(fixture.dispose);
        fixture.publicResponse = gameResponse(
          users: [for (var id = 1; id <= 35; id++) gameUser(id: id, rank: id)],
        );
        final api = _GameShellApi(fixture);
        await pumpShell(
          tester,
          size,
          revealMobileNavigation: size.width < 600,
          instances: [
            DiscourseInstance(
              url: gameSite,
              title: 'Community',
              apiVersion: 4,
              loginRequired: false,
              user: api.user,
              config: fixture.config.value,
            ),
          ],
          api: api,
          authenticator: FakeAuthenticator()..keys[gameSite] = 'key',
          pluginManifest: const PluginManifest([gamificationModule]),
        );
        final shell = ShellScope.read(
          tester.element(find.byType(UserMenuButton).first),
        );
        expect(await shell.openPluginUrl('$gameSite/leaderboard'), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(GamificationPage), findsOneWidget);
        await tester.tap(find.text('All time'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Last week'));
        await tester.pumpAndSettle();
        final scroll = find.descendant(
          of: find.byType(GamificationPage),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        await tester.drag(scroll.first, const Offset(0, -550));
        await tester.pumpAndSettle();
        final before = tester
            .state<ScrollableState>(scroll.first)
            .position
            .pixels;
        expect(before, greaterThan(100));
        await tester.tap(find.text('Manage leaderboards'));
        await tester.pumpAndSettle();
        expect(find.byType(GamificationAdminPage), findsOneWidget);
        expect(shell.handleBack(canReturnToSidebar: false), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(GamificationPage), findsOneWidget);
        expect(find.text('Last week'), findsOneWidget);
        expect(
          tester.state<ScrollableState>(scroll.first).position.pixels,
          closeTo(before, 1),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({
        size.width < 600 ? TargetPlatform.iOS : TargetPlatform.macOS,
      }),
    );
  }
}

Future<(ShellController, BuildContext)> _pumpLinkShell(
  WidgetTester tester, {
  bool otherSite = false,
}) async {
  final fixture = GamificationFixture();
  addTearDown(fixture.dispose);
  final api = _GameShellApi(fixture);
  const sourceSite = 'https://source.example';
  await pumpShell(
    tester,
    const Size(1360, 900),
    instances: [
      for (final url in [if (otherSite) sourceSite, gameSite])
        DiscourseInstance(
          url: url,
          title: 'Community',
          apiVersion: 4,
          loginRequired: false,
          user: api.user,
          config: fixture.config.value,
        ),
    ],
    api: api,
    authenticator: FakeAuthenticator()
      ..keys[gameSite] = 'key'
      ..keys[sourceSite] = 'source-key',
    pluginManifest: const PluginManifest([gamificationModule]),
  );
  final shell = ShellScope.read(
    tester.element(find.byType(UserMenuButton).first),
  );
  shell.desktopTopicTabs = true;
  await tester.pumpAndSettle();
  return (shell, tester.element(find.byType(UserMenuButton).first));
}

final class _GameShellApi extends FakeDiscourseApi {
  _GameShellApi(this.fixture)
    : super(
        user: fixture.user,
        feeds: const {'/latest.json': []},
        siteConfigs: {gameSite: fixture.config.value},
      );
  final GamificationFixture fixture;
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) => fixture.transport.pluginGetJson(
    siteUrl: siteUrl,
    path: path,
    apiKey: apiKey,
    clientId: clientId,
  );
  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => fixture.transport.pluginWriteJson(
    siteUrl: siteUrl,
    path: path,
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );
}
