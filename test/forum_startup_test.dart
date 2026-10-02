import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/empty_state.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mobile in [false, true]) {
    test(
      '${mobile ? 'mobile' : 'desktop'} restores the last forum after reordering',
      () async {
        final sites = [instance('one.example'), instance('two.example')];
        final instances = FakeInstanceStore(sites);
        final persistence = MemoryForumTabPersistence();
        final first = _controller(instances, persistence, mobile: mobile);
        await first.load();
        first.selectInstance(1);
        first.pushContent(ContentRoute.newTab());
        await first.moveInstance(sites.last, 0);
        first.selectInstance(1);
        await first.flushForExit();
        first.dispose();

        final restarted = _controller(instances, persistence, mobile: mobile);
        addTearDown(restarted.dispose);
        await restarted.load();
        expect(restarted.instances.map((site) => site.url), [
          sites.last.url,
          sites.first.url,
        ]);
        expect(restarted.currentInstance?.url, sites.first.url);
        expect(restarted.instanceIndex, 1);
        expect(restarted.rootMode, ShellRootMode.forum);
      },
    );
  }

  test('adding a forum makes it the next startup forum', () async {
    final instances = FakeInstanceStore([instance('one.example')]);
    final persistence = MemoryForumTabPersistence();
    final first = _controller(instances, persistence);
    await first.load();
    expect(await first.addInstance(instance('added.example')), isTrue);
    await first.flushForExit();
    first.dispose();

    final restarted = _controller(instances, persistence);
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.currentInstance?.url, 'https://added.example');
  });

  test('a missing saved forum falls back to an available forum', () async {
    final persistence = MemoryForumTabPersistence();
    await ForumTabStore(
      persistence: persistence,
    ).save([], selectedSiteUrl: 'https://removed.example');
    final shell = _controller(
      FakeInstanceStore([instance('one.example')]),
      persistence,
    );
    addTearDown(shell.dispose);
    await shell.load();
    await shell.flushForExit();
    expect(shell.currentInstance?.url, 'https://one.example');
    expect(shell.forumTabs.selectedSiteUrl, 'https://one.example');
  });

  test('removing the last forum clears the saved selection', () async {
    final instances = FakeInstanceStore([instance('one.example')]);
    final persistence = MemoryForumTabPersistence();
    final first = _controller(instances, persistence);
    await first.load();
    expect(await first.removeInstance(first.currentInstance!), isTrue);
    await first.flushForExit();
    first.dispose();

    final restarted = _controller(instances, persistence);
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.hasInstances, isFalse);
    expect(restarted.forumTabs.selectedSiteUrl, isNull);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      '${platform.name} default startup reopens the saved forum without Aggregate',
      (tester) async {
        final instances = FakeInstanceStore([
          instance('one.example'),
          instance('two.example'),
        ]);
        final persistence = MemoryForumTabPersistence();
        await _pumpApp(tester, platform, instances, persistence);
        final shell = ShellScope.read(
          tester.element(find.byType(AdaptiveShell)),
        );
        shell.selectInstance(1);
        await tester.pumpAndSettle();
        await shell.flushForExit();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        await _pumpApp(tester, platform, instances, persistence);
        final restarted = ShellScope.read(
          tester.element(find.byType(AdaptiveShell)),
        );
        expect(restarted.currentInstance?.url, 'https://two.example');
        expect(find.byType(EmptyState), findsNothing);
        expect(
          find.byKey(const ValueKey('aggregate-rail-button')),
          findsNothing,
        );
        expect(find.text('All forums'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );

    testWidgets(
      '${platform.name} empty startup opens Add Forum and can reopen it after dismissal',
      (tester) async {
        await _pumpApp(
          tester,
          platform,
          FakeInstanceStore(),
          MemoryForumTabPersistence(),
        );
        expect(find.byType(EmptyState), findsOneWidget);
        expect(find.byType(DInput), findsOneWidget);
        expect(
          find.text('Enter the address of a Discourse forum.'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Close').last);
        await tester.pumpAndSettle();
        expect(
          find.text('Enter the address of a Discourse forum.'),
          findsNothing,
        );
        await tester.tap(find.widgetWithText(DButton, 'Add a site'));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter the address of a Discourse forum.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}

ShellController _controller(
  FakeInstanceStore instances,
  MemoryForumTabPersistence persistence, {
  bool mobile = false,
}) => ShellController(
  instanceStore: instances,
  forumTabs: ForumTabStore(persistence: persistence),
  api: FakeDiscourseApi(),
  authenticator: FakeAuthenticator(),
  drafts: FakeDraftStore(),
  trackers: FakeSiteTracker.reset(),
  forumTabsEnabled: !mobile,
  mobileNavigationEnabled: mobile,
);

Future<void> _pumpApp(
  WidgetTester tester,
  TargetPlatform platform,
  FakeInstanceStore instances,
  MemoryForumTabPersistence persistence,
) async {
  tester.view.physicalSize = platform == TargetPlatform.iOS
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    DiscourseApp(
      store: instances,
      forumTabs: ForumTabStore(persistence: persistence),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    ),
  );
  await tester.pumpAndSettle();
}
