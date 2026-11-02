import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'rereading posts keeps the shell idle and new reads update badges',
    () async {
      const user = DiscourseUser(
        id: 7,
        username: 'reader',
        unifiedNewEnabled: true,
      );
      const totals = NotificationTotals(topicTrackingNew: 1);
      final site = instance(
        'meta.discourse.org',
      ).copyWith(user: user, notificationTotals: totals);
      final authenticator = FakeAuthenticator()..keys[site.url] = 'api-key';
      const topic = Topic(
        id: 7,
        title: 'A discussion',
        slug: 'a-discussion',
        highestPostNumber: 10,
        lastReadPostNumber: 1,
        unreadPosts: 9,
      );
      final api = FakeDiscourseApi(
        feeds: const {
          '/latest.json': [topic],
        },
        user: user,
        totals: totals,
        trackingState: TopicTrackingState([
          const TrackedTopicState(
            topicId: 7,
            highestPostNumber: 10,
            lastReadPostNumber: 1,
            notificationLevel: 2,
          ),
        ]),
      );
      final shell = ShellController(
        instanceStore: FakeInstanceStore([site]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        ownsApi: false,
      );
      addTearDown(shell.dispose);
      await shell.load();
      await pumpEventQueue();
      expect(shell.newReplyCount, 1);

      var notifications = 0;
      shell.addListener(() => notifications++);
      await shell.markTopicRead(site.url, 7, 5, caughtUp: false);
      await pumpEventQueue();
      expect(api.topicReadsRecorded, [(topicId: 7, postNumber: 5)]);
      expect(shell.store.read<Topic>(site.url, 7)?.lastReadPostNumber, 5);
      expect(notifications, 1);

      notifications = 0;
      for (var index = 0; index < 20; index++) {
        await shell.markTopicRead(
          site.url,
          7,
          index.isEven ? 1 : 5,
          caughtUp: false,
        );
        await pumpEventQueue();
      }
      expect(api.topicReadsRecorded, [(topicId: 7, postNumber: 5)]);
      expect(shell.store.read<Topic>(site.url, 7)?.lastReadPostNumber, 5);
      expect(shell.newReplyCount, 1);
      expect(
        notifications,
        0,
        reason: 'Unchanged reads must not rebuild shell consumers',
      );

      await shell.markTopicRead(site.url, 7, 3, caughtUp: false);
      await pumpEventQueue();
      expect(api.topicReadsRecorded.last, (topicId: 7, postNumber: 3));
      expect(shell.store.read<Topic>(site.url, 7)?.lastReadPostNumber, 5);
      expect(shell.newReplyCount, 1);
      expect(notifications, 0);

      await shell.markTopicRead(site.url, 7, 10, caughtUp: true);
      await pumpEventQueue();
      expect(api.topicReadsRecorded.last, (topicId: 7, postNumber: 10));
      expect(shell.store.read<Topic>(site.url, 7)?.lastReadPostNumber, 10);
      expect(shell.newReplyCount, 0);
      expect(notifications, 1);

      notifications = 0;
      await shell.markTopicRead(site.url, 7, 10, caughtUp: true);
      await pumpEventQueue();
      expect(api.topicReadsRecorded, hasLength(3));
      expect(shell.newReplyCount, 0);
      expect(notifications, 0);
    },
  );
}
