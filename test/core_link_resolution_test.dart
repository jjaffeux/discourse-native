import 'dart:ui' show Color;

import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'background links select the deepest forum and its canonical color',
    () async {
      const root = DiscourseInstance(url: 'https://example.com', title: 'Root');
      const nested = DiscourseInstance(
        url: 'https://example.com/forum',
        title: 'Nested',
      );
      const category = TopicCategory(
        id: 12,
        name: 'Support',
        slug: 'support',
        color: '123456',
      );
      final shell = ShellController(
        instanceStore: FakeInstanceStore([root, nested]),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      await pumpEventQueue();
      shell.store.put(nested.url, category);
      expect(shell.filterCategoriesFor(nested.url), isEmpty);
      final selected = shell.currentInstance;
      final tab = shell.activeTab;

      expect(
        shell.openLinkInNewTab('/forum/c/support/12', title: 'Support title'),
        TabOpenResult.opened,
      );
      expect(shell.currentInstance, same(selected));
      expect(shell.activeTab, same(tab));
      shell.selectInstance(1);
      final opened = shell.tabsForCurrentForum.last.currentContent;
      expect(opened.feedPath, '/c/support/12.json');
      expect(opened.title, 'Support title');
      expect(opened.color, const Color(0xff123456));
    },
  );

  test('root links use configured homepage and site top period', () async {
    const site = DiscourseInstance(
      url: 'https://example.com/forum',
      title: 'Nested',
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: FakeDiscourseApi(
        siteConfigs: {
          site.url: const SiteConfig(
            defaultHomepage: 'categories',
            topPageDefaultPeriod: 'monthly',
          ),
        },
      ),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    await pumpEventQueue();
    expect(
      shell.destinationBookmarkRouteForUrl(site.url)?.id,
      'all-categories',
    );
    expect(
      shell.destinationBookmarkRouteForUrl('/forum/top')?.id,
      'top-monthly',
    );
    expect(shell.destinationBookmarkRouteForUrl('/forum?ignored=1'), isNull);
    expect(shell.destinationBookmarkRouteForUrl('/forum#ignored'), isNull);
  });
}
