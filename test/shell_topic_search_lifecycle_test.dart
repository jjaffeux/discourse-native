import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _topic = Topic(id: 1, title: 'One', slug: 'one');
const _otherTopic = Topic(id: 2, title: 'Two', slug: 'two');
const _hit = SearchPostHit(
  postId: 1,
  topicId: 1,
  postNumber: 1,
  topicTitle: 'One',
  topicSlug: 'one',
  username: 'reader',
  excerpt: SearchExcerpt([SearchExcerptSegment('Match')]),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShellController shell;
  late String site;

  Future<ShellController> createShell({bool mobile = false}) async {
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('one.example'),
        instance('two.example'),
      ]),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      mobileNavigationEnabled: mobile,
    );
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  setUp(() async {
    shell = await createShell();
    site = shell.currentInstance!.url;
  });

  test(
    'a mobile plugin panel ends highlighting but its sidebar overlay does not',
    () async {
      final mobile = await createShell(mobile: true);
      final mobileSite = mobile.currentInstance!.url;
      final tab = mobile.activeTabId!;
      mobile.openSearchResult(_hit, words: 'matched words');
      mobile.toggleMobileSidebar();
      expect(
        mobile.search.wordsFor(mobileSite, tab, 'topic-1'),
        'matched words',
      );
      expect(mobile.handleBack(), isTrue);
      expect(mobile.currentContent?.topicId, 1);
      expect(
        mobile.search.wordsFor(mobileSite, tab, 'topic-1'),
        'matched words',
      );

      mobile.selectMobilePanel(null);
      expect(mobile.currentContent?.topicId, 1);
      expect(
        mobile.search.wordsFor(mobileSite, tab, 'topic-1'),
        'matched words',
      );
      mobile.selectMobilePanel('chat');
      expect(mobile.currentContent?.topicId, 1);
      expect(mobile.search.wordsFor(mobileSite, tab, 'topic-1'), isEmpty);
      mobile.openSearchResult(_hit, words: 'fresh words');
      expect(mobile.search.wordsFor(mobileSite, tab, 'topic-1'), 'fresh words');
      expect(mobile.handleBack(), isTrue);
      expect(mobile.currentContent?.topicId, 1);
      expect(mobile.search.wordsFor(mobileSite, tab, 'topic-1'), isEmpty);
    },
  );

  for (final departure in [
    'back',
    'replace',
    'topic',
    'tab',
    'site',
    'close',
  ]) {
    test('$departure clears only the departed topic search words', () {
      shell.applySearchToList('list words', const []);
      final list = shell.currentContent!;
      final tab = shell.activeTabId!;
      shell.openSearchResult(_hit, words: 'matched words');
      expect(shell.search.wordsFor(site, tab, 'topic-1'), 'matched words');

      switch (departure) {
        case 'back':
          expect(shell.handleBack(), isTrue);
        case 'replace':
          shell.replaceCurrentContent(
            ContentRoute.topicList(TopicListMode.topWeekly),
          );
        case 'topic':
          shell.openTopic(_otherTopic);
        case 'tab':
          shell.createTab();
        case 'site':
          shell.selectInstance(1);
        case 'close':
          shell.closeTab(tab);
      }

      expect(shell.search.wordsFor(site, tab, 'topic-1'), isEmpty);
      expect(shell.search.wordsFor(site, tab, list.id), 'list words');

      if (departure == 'site') shell.selectInstance(0);
      if (departure == 'close') expect(shell.reopenClosedTab(tab), isTrue);
      if (departure == 'tab') shell.selectTab(tab);
      shell.openTopic(_topic);
      expect(shell.search.wordsFor(site, tab, 'topic-1'), isEmpty);
      shell.openSearchResult(_hit, words: 'fresh words');
      expect(
        shell.search.wordsFor(site, shell.activeTabId, 'topic-1'),
        'fresh words',
      );
    });
  }

  test('post jumps and closing the search panel keep topic words', () {
    shell.openSearchResult(_hit, words: 'matched words');
    final tab = shell.activeTabId!;
    shell.search.openPanel();
    shell.search.closePanel();
    shell.openCurrentTopicPost(3);
    expect(shell.currentContent?.postNumber, 3);
    expect(shell.search.wordsFor(site, tab, 'topic-1'), 'matched words');
    shell.replaceCurrentContent(
      ContentRoute.topic(
        topicId: 1,
        slug: 'renamed',
        title: 'One',
        postNumber: 4,
      ),
    );
    expect(shell.search.wordsFor(site, tab, 'topic-1'), 'matched words');
  });

  test('focusing another visible panel preserves its highlighted topic', () {
    shell.desktopTopicTabs = true;
    shell.openSearchResult(_hit, words: 'main words');
    final main = shell.activeTabId!;
    shell.openContentInPanel(
      ContentRoute.topic(topicId: 2, slug: 'two', title: 'Two'),
      panel: ForumPanel.secondary,
    );
    final secondary = shell.activeTabId!;
    shell.setPageSearchWords(site, 'topic-2', 'secondary words');
    expect(shell.search.wordsFor(site, main, 'topic-1'), 'main words');

    shell.selectTab(main);
    expect(
      shell.search.wordsFor(site, secondary, 'topic-2'),
      'secondary words',
    );
    shell.openTopic(_otherTopic);
    expect(shell.search.wordsFor(site, main, 'topic-1'), isEmpty);
    expect(
      shell.search.wordsFor(site, secondary, 'topic-2'),
      'secondary words',
    );

    shell.selectTab(secondary);
    shell.createTab(panel: ForumPanel.secondary);
    expect(shell.search.wordsFor(site, secondary, 'topic-2'), isEmpty);
  });
}
