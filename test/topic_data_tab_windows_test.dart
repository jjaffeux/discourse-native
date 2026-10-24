import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_viewport_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

final class _CountingStore extends Store {
  int postReads = 0;

  @override
  T? read<T extends Storable<T>>(String siteUrl, Object id) {
    if (T == Post) postReads++;
    return super.read<T>(siteUrl, id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'paging an inactive ordinary-topic tab preserves both windows and anchors',
    () async {
      final site = instance('tabs.example');
      final posts = {
        for (var id = 1; id <= 100; id++)
          id: Post(
            id: id,
            postNumber: id,
            username: 'author',
            cooked: '<p>Post $id</p>',
          ),
      };
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': []},
        postsById: posts,
      );
      final store = _CountingStore();
      final controller = ShellController(
        store: store,
        instanceStore: FakeInstanceStore([site]),
        api: api,
        authenticator: FakeAuthenticator.signedIn([site], site: api),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
      )..desktopTopicTabs = true;
      addTearDown(controller.dispose);
      await controller.load();
      controller.store.put(
        site.url,
        TopicDetail(
          id: 7,
          title: 'Shared',
          postsCount: 100,
          stream: [for (var id = 1; id <= 100; id++) id],
        ),
      );
      controller.store.putAll(site.url, [
        for (var id = 20; id <= 39; id++) posts[id]!,
        for (var id = 70; id <= 89; id++) posts[id]!,
      ]);
      final firstId = controller.activeTabId!;
      controller.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'shared',
          title: 'Shared',
          postNumber: 25,
        ),
      );
      controller.saveTopicScrollPost(7, 25, viewportOffset: -12);
      controller.createTab();
      final secondId = controller.activeTabId!;
      controller.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'shared',
          title: 'Shared',
          postNumber: 75,
        ),
      );
      controller.saveTopicScrollPost(7, 75, viewportOffset: -4);
      final first = controller.tabContext(firstId);
      final second = controller.tabContext(secondId);
      expect(first.currentPostIds, [for (var id = 20; id <= 39; id++) id]);
      expect(second.currentPostIds, [for (var id = 70; id <= 89; id++) id]);

      final firstSnapshot = TopicViewportSnapshot.from(controller, tab: first);
      final secondSnapshot = TopicViewportSnapshot.from(
        controller,
        tab: second,
      );
      expect(firstSnapshot.initialPostIndex, 6);
      expect(secondSnapshot.initialPostIndex, 6);
      store.postReads = 0;
      for (var i = 0; i < 10; i++) {
        expect(
          TopicViewportSnapshot.from(controller, tab: first).initialPostIndex,
          6,
        );
        expect(
          TopicViewportSnapshot.from(controller, tab: second).initialPostIndex,
          6,
        );
      }
      expect(store.postReads, 0);
      expect(first.currentPostIds, same(firstSnapshot.postIds));
      expect(second.currentPostIds, same(secondSnapshot.postIds));
      expect(
        first.initialPostIndexFor(firstSnapshot.postIds, 26, hasEarlier: true),
        7,
      );

      await controller.loadMorePosts(batchSize: 5, tabId: firstId);

      expect(api.postFetches, [
        [40, 41, 42, 43, 44],
      ]);
      expect(controller.activeTabId, secondId);
      expect(first.currentContent?.postNumber, 25);
      expect(second.currentContent?.postNumber, 75);
      expect(first.currentPostIds, [for (var id = 20; id <= 44; id++) id]);
      expect(second.currentPostIds, [for (var id = 70; id <= 89; id++) id]);
      expect(controller.topicScrollPostNumber(7, tabId: firstId), 25);
      expect(controller.topicScrollPostNumber(7, tabId: secondId), 75);
      expect(controller.topicScrollPostOffset(7, tabId: firstId), -12);
      expect(controller.topicScrollPostOffset(7, tabId: secondId), -4);

      final held = first.currentPostIds;
      controller.closeTab(firstId);
      expect(first.isCurrent, isFalse);
      expect(controller.reopenClosedTab(firstId), isTrue);
      final reopened = controller.tabContext(firstId);
      expect(reopened.isCurrent, isTrue);
      expect(first.isCurrent, isFalse);
      expect(first.currentPostIds, isEmpty);
      expect(reopened.currentPostIds, held);
      expect(reopened.currentPostIds, isNot(same(held)));
      expect(second.isCurrent, isTrue);
    },
  );
}
