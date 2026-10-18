import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('read does not rebuild when the controller notifies', (
    tester,
  ) async {
    final controller = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);

    var listeningBuilds = 0;
    var readingBuilds = 0;

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Builder(
                builder: (context) {
                  listeningBuilds += 1;
                  expect(ShellScope.of(context), same(controller));
                  return const SizedBox.shrink();
                },
              ),
              Builder(
                builder: (context) {
                  readingBuilds += 1;
                  expect(ShellScope.read(context), same(controller));
                  expect(ShellScope.maybeRead(context), same(controller));
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );

    expect(listeningBuilds, 1);
    expect(readingBuilds, 1);

    await controller.load();
    await tester.pump();

    expect(listeningBuilds, 2);
    expect(readingBuilds, 1);
  });

  testWidgets('maybeRead returns null outside the shell', (tester) async {
    ShellController? controller;

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          controller = ShellScope.maybeRead(context);
          return const SizedBox.shrink();
        },
      ),
    );

    expect(controller, isNull);
  });

  testWidgets(
    'panel selectors keep displayed ownership across focus and shell replacement',
    (tester) async {
      ShellController createShell() => ShellController(
        instanceStore: FakeInstanceStore([instance('scope.example')]),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      final first = createShell();
      final second = createShell();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.load();
      await second.load();
      first.desktopTopicTabs = true;
      final mainId = first.activeTabId!;
      first.createTab(panel: ForumPanel.secondary);
      final focused = first.activeTabId;
      ShellTabContext? captured;
      var builds = 0;
      Widget app(ShellController shell) => ShellScope(
        controller: shell,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ForumTabScope(
            tabId: mainId,
            panel: ForumPanel.main,
            child: ForumTabSelector<String?>(
              select: (shell, tab) {
                captured = tab;
                return tab.currentContent?.id;
              },
              builder: (context, route, _) {
                builds++;
                return Text(route ?? 'empty');
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(first));
      expect(find.text('latest'), findsOneWidget);
      final held = captured!;
      final before = builds;
      first.selectTab(mainId);
      first.selectTab(focused!);
      await tester.pump();
      expect(builds, before);
      expect(captured!.tabId, mainId);
      expect(first.activeTabId, focused);
      await tester.pumpWidget(app(second));
      expect(find.text('empty'), findsOneWidget);
      expect(captured!.shell, same(second));
      expect(held.shell, same(first));
      expect(second.currentContent?.id, 'latest');
    },
  );

  testWidgets('selector rebuilds only when its selected value changes', (
    tester,
  ) async {
    final controller = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);

    var builds = 0;
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ShellSelector<int>(
            select: (shell) => shell.instances.length,
            builder: (context, count, child) {
              builds += 1;
              return Text('$count');
            },
          ),
        ),
      ),
    );

    expect(builds, 1);
    expect(find.text('0'), findsOneWidget);

    await controller.load();
    await tester.pump();
    expect(builds, 1);

    await controller.addInstance(instance('meta.discourse.org'));
    await tester.pump();
    expect(builds, 2);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('account activity does not invalidate ShellScope dependents', (
    tester,
  ) async {
    final controller = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    var shellBuilds = 0;
    var activityBuilds = 0;

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Builder(
                builder: (context) {
                  ShellScope.of(context);
                  shellBuilds++;
                  return const SizedBox.shrink();
                },
              ),
              Builder(
                builder: (context) {
                  final shell = ShellScope.read(context);
                  return ListenableBuilder(
                    listenable: shell.accountActivity.totalsListenable,
                    builder: (context, _) {
                      activityBuilds++;
                      return const SizedBox.shrink();
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    controller.accountActivity.applyCounts(
      'https://meta.discourse.org',
      (held) => held.copyWith(unreadNotifications: 1),
    );
    await tester.pump();

    expect(shellBuilds, 1);
    expect(activityBuilds, 2);
  });
}
