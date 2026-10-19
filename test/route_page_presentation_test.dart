import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_summary.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/native_ui_evidence.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.linux]) {
    for (final page in [
      CorePage.categories,
      CorePage.tags,
      CorePage.users,
      CorePage.drafts,
      CorePage.appearance,
      CorePage.forumAbout,
      CorePage.bookmarks,
    ]) {
      testWidgets('${page.name} has one page title on $platform', (
        tester,
      ) async {
        final route = switch (page) {
          CorePage.categories => ContentRoute.allCategories(),
          CorePage.appearance => ContentRoute.appearance(),
          CorePage.forumAbout => ContentRoute.forumAbout(),
          _ => ContentRoute(
            destination: PageDestination(page),
            title: switch (page) {
              CorePage.tags => 'Tags',
              CorePage.users => 'Users',
              CorePage.drafts => 'Drafts',
              CorePage.bookmarks => 'Bookmarks',
              _ => throw StateError('Unexpected test page'),
            },
            icon: DIcons.list,
          ),
        };
        final shell = await _shell(platform);
        shell.pushContent(route);
        if (page == CorePage.categories) {
          await shell.loadCategories(shell.currentInstance!.url);
        }
        await _pump(tester, shell, platform);

        final title = _pageTitles(tester, route.title);
        expect(title, findsOneWidget);
        final hasShellHeader =
            page == CorePage.forumAbout ||
            platform == TargetPlatform.iOS &&
                (page == CorePage.users || page == CorePage.appearance);
        expect(
          find.byKey(const ValueKey('content-header')),
          hasShellHeader ? findsOneWidget : findsNothing,
        );
        expect(tester.getRect(title).top, greaterThanOrEqualTo(0));
        expect(tester.takeException(), isNull);
        if (page == CorePage.users || page == CorePage.forumAbout) {
          await captureNativeUi(tester, '${platform.name}-${page.name}');
        }
      }, variant: TargetPlatformVariant.only(platform));
    }

    testWidgets('summary retains its platform header on $platform', (
      tester,
    ) async {
      final shell = await _shell(platform);
      shell.pushContent(
        const ContentRoute(
          destination: PageDestination(CorePage.summary),
          title: 'Summary',
          icon: DIcons.list,
        ),
      );
      await _pump(tester, shell, platform);
      expect(find.byType(UserSummaryView), findsOneWidget);
      final hasShellHeader = platform == TargetPlatform.iOS;
      expect(
        find.byKey(const ValueKey('content-header')),
        hasShellHeader ? findsOneWidget : findsNothing,
      );
      expect(
        _pageTitles(tester, 'Summary'),
        hasShellHeader ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));

    testWidgets('signed-out bookmarks retain shell title on $platform', (
      tester,
    ) async {
      final shell = await _shell(platform, connected: false);
      shell.pushContent(
        const ContentRoute(
          destination: PageDestination(CorePage.bookmarks),
          title: 'Bookmarks',
          icon: DIcons.bookmark,
        ),
      );
      await _pump(tester, shell, platform);
      expect(_pageTitles(tester, 'Bookmarks'), findsOneWidget);
      expect(find.byKey(const ValueKey('content-header')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }
}

Future<ShellController> _shell(
  TargetPlatform platform, {
  bool connected = true,
}) async {
  final user = connected ? const DiscourseUser(username: 'reader') : null;
  final site = DiscourseInstance(
    url: 'https://pages.example',
    title: 'Pages',
    user: user,
  );
  final api = FakeDiscourseApi(user: user);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: FakeAuthenticator.signedIn([site], site: api),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    mobileNavigationEnabled: platform == TargetPlatform.iOS,
  );
  addTearDown(shell.dispose);
  await shell.load();
  return shell;
}

Future<void> _pump(
  WidgetTester tester,
  ShellController shell,
  TargetPlatform platform,
) async {
  await prepareNativeUiEvidence(tester);
  final touch = platform == TargetPlatform.iOS;
  tester.view.physicalSize = touch
      ? const Size(390, 844)
      : const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: nativeUiEvidenceBuilder,
        theme: AppTheme.forBrightness(
          Brightness.light,
          fontFamily: 'Roboto',
        ).copyWith(platform: platform),
        home: Scaffold(
          body: MainContent(
            layout: touch ? ShellLayout.compact : ShellLayout.expanded,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _pageTitles(WidgetTester tester, String title) {
  final headers = tester
      .widgetList<DPageSurface>(find.byType(DPageSurface))
      .map((surface) => surface.header)
      .whereType<Widget>()
      .toSet();
  return find.descendant(
    of: find.byWidgetPredicate(headers.contains),
    matching: find.text(title),
  );
}
