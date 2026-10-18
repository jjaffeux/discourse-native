import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late ShellController shell;
  late FakeDiscourseApi api;
  late FakeForumTabStore tabs;
  const site = 'https://workspace.example';

  setUp(() async {
    final routes = [
      ContentRoute.topicList(TopicListMode.latest),
      for (final name in ['second', 'third'])
        ContentRoute(
          destination: ExtensionDestination(name, sourcePath: '/$name.json'),
          title: name,
          icon: DIcons.folder,
        ),
    ];
    tabs = FakeForumTabStore([
      ForumWorkspace(
        siteUrl: site,
        accountIdentity: 'anonymous',
        tabs: [
          for (final route in routes)
            ForumTab(
              id: route.id,
              rootDestinationId: route.id,
              contentStack: [route],
            ),
        ],
        activeTabId: 'latest',
      ),
    ]);
    api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/second.json': [], '/third.json': []},
    );
    shell = ShellController(
      instanceStore: FakeInstanceStore([instance('workspace.example')]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: tabs,
      trackers: FakeSiteTracker.reset(),
    );
    await shell.load();
    await shell.loadFeed('latest');
    shell.addListener(() {});
  });
  tearDown(() => shell.dispose());

  testWidgets('rapid selections persist and hydrate only the final target', (
    tester,
  ) async {
    final saves = tabs.saveCount;
    shell.selectTab('second');
    shell.selectTab('third');
    expect(shell.activeTabId, 'third');
    expect(tabs.saveCount, saves);
    expect(api.feedPaths, isNot(contains('/second.json')));
    expect(api.feedPaths, isNot(contains('/third.json')));

    await tester.pump();

    expect(tabs.saveCount, saves + 1);
    expect(tabs.workspaces.single.activeTabId, 'third');
    expect(api.feedPaths, isNot(contains('/second.json')));
    expect(api.feedPaths.where((path) => path == '/third.json'), hasLength(1));
  });

  testWidgets('a closed pending selection cannot hydrate its retired tab', (
    tester,
  ) async {
    shell.selectTab('second');
    final retired = shell.tabContext('second');
    shell.closeTab('second');
    expect(retired.isCurrent, isFalse);
    expect(shell.activeTabId, 'third');
    final saves = tabs.saveCount;

    await tester.pump();

    expect(tabs.saveCount, saves);
    expect(api.feedPaths, isNot(contains('/second.json')));
    expect(api.feedPaths.where((path) => path == '/third.json'), hasLength(1));
    expect(shell.reopenClosedTab('second'), isTrue);
    expect(shell.activeTabId, 'second');
  });

  testWidgets('a listener selection supersedes the command that notified it', (
    tester,
  ) async {
    shell.addListener(() {
      if (shell.activeTabId == 'second') shell.selectTab('third');
    });
    final saves = tabs.saveCount;
    shell.selectTab('second');

    await tester.pump();

    expect(shell.activeTabId, 'third');
    expect(tabs.saveCount, saves + 1);
    expect(tabs.workspaces.single.activeTabId, 'third');
    expect(api.feedPaths, isNot(contains('/second.json')));
    expect(api.feedPaths.where((path) => path == '/third.json'), hasLength(1));
  });

  testWidgets('post-frame selection waits for the next document paint', (
    tester,
  ) async {
    final saves = tabs.saveCount;
    tester.binding.addPostFrameCallback((_) => shell.selectTab('second'));

    await tester.pump();

    expect(shell.activeTabId, 'second');
    expect(tabs.saveCount, saves);
    expect(api.feedPaths, isNot(contains('/second.json')));

    await tester.pump();

    expect(tabs.saveCount, saves + 1);
    expect(api.feedPaths.where((path) => path == '/second.json'), hasLength(1));
  });

  testWidgets('a full tab write consumes pending selection and anchor writes', (
    tester,
  ) async {
    shell.selectTab('second');
    shell.saveFeedScrollRow('second', 7);
    final saves = tabs.saveCount;
    shell.moveTab('third', 0);
    expect(tabs.saveCount, saves + 1);
    expect(tabs.workspaces.single.activeTab.anchors['second']?.itemId, 7);

    await tester.pump();
    await tester.pump(shell.anchorPersistDebounce);

    expect(tabs.saveCount, saves + 1);
    expect(api.feedPaths.where((path) => path == '/second.json'), hasLength(1));
  });

  testWidgets('selection settlement retains the captured account lease', (
    tester,
  ) async {
    shell.selectTab('second');
    shell.lifecycle.invalidate(site);

    await tester.pump();

    expect(shell.activeTabId, 'second');
    expect(tabs.workspaces.single.activeTabId, 'second');
    expect(api.feedPaths, isNot(contains('/second.json')));
  });
}
