import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/notifications_menu.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');
const _pageBudgets = {TargetPlatform.macOS: 95, TargetPlatform.iOS: 286};
const _tabBudgets = {TargetPlatform.macOS: 96, TargetPlatform.iOS: 54};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final platform in _pageBudgets.keys) {
    final name = platform.name;
    final phone = platform == TargetPlatform.iOS;

    testWidgets('a tracking message leaves the bookmarks page alone on $name', (
      tester,
    ) async {
      await _pumpApp(tester, phone: phone);
      final shell = ShellScope.read(tester.element(primaryMainContent));
      shell.pushContent(
        const ContentRoute(
          destination: PageDestination(CorePage.bookmarks),
          title: 'Bookmarks',
          icon: DIcons.bookmark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BookmarkRow), findsWidgets);

      final tracked = await _rebuiltElements(
        () => _deliverTrackingMessage(tester),
      );

      // ignore: avoid_print
      print(
        'PERF_PROOF bookmarks-page ${name}_page_section_elements='
        '${tracked.section}',
      );
      // ignore: avoid_print
      print(
        'PERF_PROOF bookmarks-page ${name}_page_total_elements='
        '${tracked.total}',
      );
      expect(tracked.section, 0);
      expect(tracked.total, lessThanOrEqualTo(_pageBudgets[platform]!));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));

    testWidgets('a tracking message leaves the bookmarks tab alone on $name', (
      tester,
    ) async {
      await _pumpApp(tester, phone: phone);
      await tester.tap(notificationsMenuTrigger());
      await tester.pumpAndSettle();
      final tab = find.byKey(const ValueKey('user-menu-tab-bookmarks'));
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(find.byType(BookmarkSection), findsOneWidget);

      final tracked = await _rebuiltElements(
        () => _deliverTrackingMessage(tester),
      );

      // ignore: avoid_print
      print(
        'PERF_PROOF bookmarks-page ${name}_tab_section_elements='
        '${tracked.section}',
      );
      // ignore: avoid_print
      print(
        'PERF_PROOF bookmarks-page ${name}_tab_total_elements='
        '${tracked.total}',
      );
      expect(tracked.section, 0);
      expect(tracked.total, lessThanOrEqualTo(_tabBudgets[platform]!));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }
}

Future<void> _pumpApp(WidgetTester tester, {required bool phone}) async {
  await pumpShell(
    tester,
    phone ? const Size(390, 844) : const Size(1440, 900),
    instances: [instance('meta.discourse.org', user: _user)],
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    api: FakeDiscourseApi(
      user: _user,
      feeds: {
        '/latest.json': [
          for (var id = 1; id <= 30; id++)
            Topic(
              id: id,
              title: 'Topic $id',
              slug: 'topic-$id',
              bumpedAt: DateTime.utc(2026, 9, 1),
            ),
        ],
      },
      categoryList: const [
        TopicCategory(id: 1, name: 'Support', slug: 'support', color: '0088cc'),
      ],
      reminderList: const [
        DiscourseNotification.test(
          id: 41,
          typeId: NotificationTypeId(24),
          title: 'Better image handling',
          topicId: 7,
          slug: 'better-image-handling',
        ),
      ],
      bookmarkList: [
        for (var id = 1; id <= 40; id++)
          Bookmark(
            id: id,
            bookmarkableId: id + 100,
            bookmarkableType: 'Post',
            postNumber: 2,
            categoryId: 1,
            title: 'Bookmark number $id',
            author: 'alice',
            path: '/t/bookmark-$id/$id/2',
          ),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

/// The message `TopicTrackingState.publish_unread` sends a tracking user.
Future<void> _deliverTrackingMessage(WidgetTester tester) async {
  FakeSiteTracker.built
      .singleWhere((tracker) => tracker.siteUrl == _site)
      .deliverTopicTracking({
        'topic_id': 9001,
        'message_type': 'unread',
        'payload': {
          'highest_post_number': 50,
          'updated_at': '2026-09-02T00:00:00.000Z',
          'created_at': '2026-09-02T00:00:00.000Z',
          'category_id': 1,
          'archetype': 'regular',
        },
      });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<({int section, int total})> _rebuiltElements(
  Future<void> Function() action,
) async {
  final section = <Element>{};
  final total = <Element>{};
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    total.add(element);
    var inSection = element.widget is BookmarkSection;
    if (!inSection) {
      element.visitAncestorElements((ancestor) {
        inSection = ancestor.widget is BookmarkSection;
        return !inSection;
      });
    }
    if (inSection) section.add(element);
  };
  try {
    await action();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return (section: section.length, total: total.length);
}
