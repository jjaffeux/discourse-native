import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_navigation.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('scoped tracking header and badge notification workload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final reports = <Map<String, Object?>>[];
    for (final topicCount in [20, 5000]) {
      final categories = [
        for (var id = 1; id <= 10; id++)
          TopicCategory(
            id: id,
            name: 'Category $id',
            slug: 'category-$id',
            color: '123456',
          ),
      ];
      final tags = [
        for (var id = 1; id <= 10; id++)
          SidebarTag(id: id, name: 'tag-$id', slug: 'tag-$id'),
      ];
      final topics = [
        for (var index = 0; index < topicCount; index++)
          TrackedTopicState(
            topicId: index + 1,
            categoryId: index % 10 + 1,
            highestPostNumber: 5,
            lastReadPostNumber: (index ~/ 100).isEven ? null : 1,
            createdInNewPeriod: true,
            notificationLevel: 2,
            tagIds: {(index ~/ 10) % 10 + 1},
          ),
      ];
      final shell = await _shell(topics, categories, tags);
      final siteUrl = shell.currentInstance!.url;
      final primaryId = shell.activeTabId;
      shell.pushContent(
        ContentRoute.filteredTopicList(
          TopicListMode.newActivity,
          categoryId: 1,
          tags: const ['tag-1'],
        ),
      );
      shell.openContentInNewTab(
        ContentRoute.filteredTopicList(
          TopicListMode.newActivity,
          categoryId: 2,
          tags: const ['tag-1'],
        ),
        select: true,
      );
      final secondaryId = shell.activeTabId;
      expect(secondaryId, isNot(primaryId));
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: Column(
                children: [
                  for (final tabId in [primaryId, secondaryId])
                    Expanded(
                      child: ForumTabScope(
                        tabId: tabId,
                        panel: ForumPanel.main,
                        child: const TopicListNavigation(
                          child: SizedBox.expand(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      List<int> badgeCounts() => [
        for (var id = 1; id <= 10; id++)
          shell.sidebarBadgeFor('category-$id').count,
        for (var id = 1; id <= 10; id++) shell.sidebarBadgeFor('tag-$id').count,
      ];

      void verify() {
        final expectedBadges = [
          for (var id = 1; id <= 10; id++)
            _count(topics, categories, categoryId: id).all,
          for (var id = 1; id <= 10; id++)
            _count(topics, categories, tagId: id).all,
        ];
        expect(badgeCounts(), expectedBadges);
        final menus = tester.widgetList<TopicFeedMenu>(
          find.byType(TopicFeedMenu),
        );
        expect(menus, hasLength(2));
        for (final (index, menu) in menus.indexed) {
          final expected = _count(
            topics,
            categories,
            categoryId: index + 1,
            tagId: 1,
          );
          expect(menu.newCount, expected.all);
          expect(menu.topicCount, expected.topics);
          expect(menu.replyCount, expected.replies);
          expect(menu.unreadCount, expected.replies);
        }
        expect(tester.takeException(), isNull);
      }

      verify();
      var notifications = 0;
      var badgeChecksum = 0;
      var badgeProjectionMicroseconds = 0;
      void readSidebarBadges() {
        final clock = Stopwatch()..start();
        final counts = badgeCounts();
        clock.stop();
        badgeProjectionMicroseconds += clock.elapsedMicroseconds;
        badgeChecksum += counts.fold(0, (sum, count) => sum + count);
        notifications++;
      }

      shell.addListener(readSidebarBadges);
      final samples = <Map<String, int>>[];
      final expectedChecksum = badgeCounts().fold(
        0,
        (sum, count) => sum + count,
      );
      for (var round = 0; round < 6; round++) {
        notifications = 0;
        badgeChecksum = 0;
        badgeProjectionMicroseconds = 0;
        final clock = Stopwatch()..start();
        for (var index = 0; index < 100; index++) {
          if (index.isEven) {
            shell.openAppSettingsModal();
          } else {
            shell.closeAppSettingsModal();
          }
          await tester.pump();
        }
        clock.stop();
        expect(notifications, 100);
        expect(badgeChecksum, expectedChecksum * 100);
        verify();
        if (round > 0) {
          samples.add({
            'notificationToPumpMicroseconds': clock.elapsedMicroseconds,
            'badgeProjectionMicroseconds': badgeProjectionMicroseconds,
            'notifications': notifications,
            'badgeChecksum': badgeChecksum,
          });
        }
      }

      FakeSiteTracker.built.single.deliverTopicTracking(const {
        'topic_id': 1,
        'message_type': 'dismiss_new',
        'payload': {
          'topic_ids': [1],
        },
      });
      topics[0] = topics[0].copyWith(isSeen: true);
      await tester.pumpAndSettle();
      verify();

      categories[1] = const TopicCategory(
        id: 2,
        name: 'Category 2',
        slug: 'category-2',
        parentCategoryId: 1,
        color: '123456',
      );
      await shell.loadCategories(siteUrl, force: true);
      await tester.pumpAndSettle();
      verify();
      reports.add({
        'topics': topicCount,
        'sidebarRows': 20,
        'mountedFilteredHeaders': 2,
        'notificationsPerSample': 100,
        'warmupSamples': 1,
        'samples': samples,
        'trackingChangeVerified': true,
        'taxonomyChangeVerified': true,
        'errors': 0,
      });
      shell.removeListener(readSidebarBadges);
      await tester.pumpWidget(const SizedBox.shrink());
      shell.dispose();
    }
    final encoded = jsonEncode(reports);
    debugPrint('TRACKING_SCOPE_PROFILE $encoded', wrapWidth: 4096);
    final output = Platform.environment['TRACKING_SCOPE_BENCHMARK_OUTPUT'];
    if (output != null) File(output).writeAsStringSync(encoded);
  });
}

({int all, int topics, int replies}) _count(
  List<TrackedTopicState> topics,
  List<TopicCategory> categories, {
  int? categoryId,
  int? tagId,
}) {
  final included = <int>{?categoryId};
  var changed = true;
  while (changed) {
    changed = false;
    for (final category in categories) {
      if (included.contains(category.parentCategoryId) &&
          included.add(category.id)) {
        changed = true;
      }
    }
  }
  var fresh = 0;
  var unread = 0;
  for (final topic in topics) {
    if (categoryId != null && !included.contains(topic.categoryId)) continue;
    if (topic.isCategoryTopic &&
        categoryId != null &&
        topic.categoryId != categoryId) {
      continue;
    }
    if (tagId != null && !topic.tagIds.contains(tagId)) continue;
    if (topic.isUnread) {
      unread++;
    } else if (topic.isNew) {
      fresh++;
    }
  }
  return (all: fresh + unread, topics: fresh, replies: unread);
}

Future<ShellController> _shell(
  List<TrackedTopicState> topics,
  List<TopicCategory> categories,
  List<SidebarTag> tags,
) async {
  const user = DiscourseUser(
    id: 7,
    username: 'sam',
    unifiedNewEnabled: true,
    sidebarShowCountOfNewItems: true,
  );
  final totals = NotificationTotals(topicTrackingNew: topics.length);
  final site = instance('meta.discourse.org').copyWith(
    user: user,
    notificationTotals: totals,
    config: const SiteConfig(taggingEnabled: true),
  );
  final authenticator = FakeAuthenticator();
  authenticator.keys[site.url] = 'api-key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(
      topics: {},
      feeds: const {'/latest.json': [], '/new.json': []},
      user: user,
      totals: totals,
      trackingState: TopicTrackingState(topics),
      categoryList: categories,
      categorySiteTopTags: tags,
      tagList: tags,
    ),
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: true,
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  await shell.load();
  await shell.loadTags(site.url);
  return shell;
}
