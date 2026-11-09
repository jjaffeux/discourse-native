import 'dart:math';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _selected = 'https://meta.discourse.org';
const _other = 'https://team.discourse.org';

const _bothPlatforms = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.macOS,
});

bool get _isPhone => defaultTargetPlatform == TargetPlatform.iOS;

/// Elements rebuilt for one message, by the part of the shell they draw.
///
/// On a phone the account menu wraps the whole shell, rail and sidebar
/// included, so each element counts towards its innermost surface only.
final class _Rebuilds {
  int total = 0;
  int sidebar = 0;
  int accountMenu = 0;
  int rail = 0;

  void clear() {
    total = 0;
    sidebar = 0;
    accountMenu = 0;
    rail = 0;
  }

  void record(Element element) {
    total++;
    var inSidebar = element.widget is InstanceSidebar;
    var inMenu = element.widget is UserMenuButton;
    var inRail = element.widget is InstanceRail;
    element.visitAncestorElements((ancestor) {
      inSidebar |= ancestor.widget is InstanceSidebar;
      inMenu |= ancestor.widget is UserMenuButton;
      inRail |= ancestor.widget is InstanceRail;
      return true;
    });
    if (inRail) {
      rail++;
    } else if (inSidebar) {
      sidebar++;
    } else if (inMenu) {
      accountMenu++;
    }
  }
}

_Rebuilds _recordRebuilds() {
  final rebuilds = _Rebuilds();
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    rebuilds.record(element);
  };
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  return rebuilds;
}

Future<void> _pumpForums(WidgetTester tester) async {
  const user = DiscourseUser(id: 7, username: 'reader');
  await pumpShell(
    tester,
    _isPhone ? const Size(390, 844) : const Size(1440, 844),
    instances: [
      instance('meta.discourse.org', user: user),
      instance('team.discourse.org', user: user),
    ],
    api: FakeDiscourseApi(
      user: user,
      feeds: {
        '/latest.json': [
          for (var id = 1; id <= 40; id++)
            Topic(
              id: id,
              title: 'Topic $id with a longer title that wraps',
              slug: 'topic-$id',
              bumpedAt: DateTime.utc(2026, 9, 1),
            ),
        ],
      },
    ),
    authenticator: FakeAuthenticator()
      ..keys[_selected] = 'key'
      ..keys[_other] = 'other-key',
  );
}

FakeSiteTracker _tracker(String siteUrl) =>
    FakeSiteTracker.built.singleWhere((tracker) => tracker.siteUrl == siteUrl);

void _notify(FakeSiteTracker tracker, int count) =>
    tracker.deliverNotification({'all_unread_notifications_count': count});

void _review(FakeSiteTracker tracker, int count) =>
    tracker.deliverReviewableCounts({'unseen_reviewable_count': count});

// A live message reaches its notifier synchronously, but a deferred
// publication can run ahead of the first frame.
Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

/// What `User#publish_notifications_state` puts on `/notification/:id`.
Map<String, Object?> _notificationState({
  required int unread,
  int personalMessages = 0,
}) => {
  'unread_notifications': unread,
  'unread_high_priority_notifications': 0,
  'read_first_notification': true,
  'last_notification': null,
  'recent': [
    [unread, false],
  ],
  'seen_notification_id': unread,
  'all_unread_notifications_count': unread,
  'grouped_unread_notifications': {'1': unread},
  'available_notification_types': const [1],
  'new_personal_messages_notifications_count': personalMessages,
};

/// What `TopicTrackingState.publish_unread` puts on its channel.
Map<String, Object?> _unreadTracking(int topicId) => {
  'topic_id': topicId,
  'message_type': 'unread',
  'payload': {
    'highest_post_number': 2,
    'updated_at': '2026-09-02T00:00:00.000Z',
    'created_at': '2026-09-02T00:00:00.000Z',
    'category_id': 1,
    'archetype': 'regular',
  },
};

Future<void> _settleLiveMessage(WidgetTester tester) async {
  await _frames(tester);
  await tester.pump(const Duration(milliseconds: 400));
  await _frames(tester);
}

void _report(String metric, int value) {
  // ignore: avoid_print
  print('PERF_PROOF notification-badges $metric=$value');
}

Finder _railBadge(String siteUrl, int count) => find.descendant(
  of: find.byKey(ValueKey('instance-rail-badge-$siteUrl'), skipOffstage: false),
  matching: find.text('$count', skipOffstage: false),
  skipOffstage: false,
);

Finder _bellCount(int count) => find.descendant(
  of: find.byKey(UserMenuButton.unreadDotKey),
  matching: find.text('$count'),
);

void main() {
  for (final (kind, deliver) in const [
    ('notification', _notify),
    ('reviewable', _review),
  ]) {
    testWidgets('a $kind count on another forum rebuilds only its rail row', (
      tester,
    ) async {
      await _pumpForums(tester);
      final tracker = _tracker(_other);
      final platform = defaultTargetPlatform.name;
      final rebuilds = _recordRebuilds();
      var elements = 0;
      var sidebar = 0;
      var accountMenu = 0;
      var rail = 0;

      for (var count = 1; count <= 10; count++) {
        rebuilds.clear();
        deliver(tracker, count);
        await _frames(tester);
        elements = max(elements, rebuilds.total);
        sidebar = max(sidebar, rebuilds.sidebar);
        accountMenu = max(accountMenu, rebuilds.accountMenu);
        rail = max(rail, rebuilds.rail);
      }

      _report('${platform}_other_${kind}_elements', elements);
      _report('${platform}_other_${kind}_sidebar', sidebar);
      _report('${platform}_other_${kind}_account_menu', accountMenu);
      _report('${platform}_other_${kind}_rail', rail);
      expect(_railBadge(_other, 10), findsOneWidget);
      expect(rail, greaterThan(0));
      expect(sidebar, 0);
      expect(accountMenu, 0);
      expect(elements, lessThanOrEqualTo(80));
    }, variant: _bothPlatforms);

    testWidgets('a $kind count on the selected forum redraws only its badges', (
      tester,
    ) async {
      await _pumpForums(tester);
      final tracker = _tracker(_selected);
      final platform = defaultTargetPlatform.name;
      final rebuilds = _recordRebuilds();
      // The first message is the one that creates the forum's totals, which
      // every reader rightly redraws for.
      deliver(tracker, 1);
      await _frames(tester);
      _report('${platform}_selected_${kind}_first_elements', rebuilds.total);

      var elements = 0;
      var sidebar = 0;
      for (var count = 2; count <= 10; count++) {
        rebuilds.clear();
        deliver(tracker, count);
        await _frames(tester);
        elements = max(elements, rebuilds.total);
        sidebar = max(sidebar, rebuilds.sidebar);
      }

      _report('${platform}_selected_${kind}_steady_elements', elements);
      _report('${platform}_selected_${kind}_steady_sidebar', sidebar);
      expect(_bellCount(10), findsWidgets);
      expect(_railBadge(_selected, 10), findsOneWidget);
      expect(elements, greaterThan(0));
      expect(sidebar, 0);
      expect(elements, lessThanOrEqualTo(_isPhone ? 340 : 150));
    }, variant: _bothPlatforms);
  }

  testWidgets(
    'the tracking message after a count leaves the sidebar as built',
    (tester) async {
      await _pumpForums(tester);
      final tracker = _tracker(_selected);
      final platform = defaultTargetPlatform.name;
      tracker.deliverNotification(_notificationState(unread: 1));
      await _settleLiveMessage(tester);
      final rebuilds = _recordRebuilds();

      tracker.deliverNotification(_notificationState(unread: 2));
      await _settleLiveMessage(tester);
      rebuilds.clear();
      tracker.deliverTopicTracking(_unreadTracking(9001));
      await _settleLiveMessage(tester);
      final sidebar = rebuilds.sidebar;
      final total = rebuilds.total;

      // ignore: avoid_print
      print('PERF_PROOF sidebar-totals ${platform}_tracking_sidebar=$sidebar');
      // ignore: avoid_print
      print('PERF_PROOF sidebar-totals ${platform}_tracking_total=$total');
      expect(_bellCount(2), findsWidgets);
      expect(sidebar, lessThanOrEqualTo(68));
      expect(total, lessThanOrEqualTo(_isPhone ? 801 : 364));
    },
    variant: _bothPlatforms,
  );

  testWidgets('a count that a sidebar row draws reaches it and leaves it', (
    tester,
  ) async {
    await _pumpForums(tester);
    final tracker = _tracker(_selected);
    final badge = find.byKey(const ValueKey('sidebar-badge-messages'));
    expect(badge, findsNothing);

    tracker.deliverNotification(
      _notificationState(unread: 3, personalMessages: 2),
    );
    await _settleLiveMessage(tester);
    expect(badge, findsOneWidget);

    tracker.deliverNotification(_notificationState(unread: 1));
    await _settleLiveMessage(tester);
    expect(badge, findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a personal message still reaches its sidebar row', (
    tester,
  ) async {
    await _pumpForums(tester);
    final badge = find.byKey(const ValueKey('sidebar-badge-messages'));
    expect(badge, findsNothing);

    _tracker(_other).deliverNotification(const {
      'new_personal_messages_notifications_count': 3,
    });
    await _frames(tester);
    expect(badge, findsNothing);

    _tracker(_selected).deliverNotification(const {
      'new_personal_messages_notifications_count': 2,
    });
    await _frames(tester);
    expect(badge, findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('switching forums moves the bell to the new forum\'s count', (
    tester,
  ) async {
    await _pumpForums(tester);
    final meta = _tracker(_selected);
    final team = _tracker(_other);
    final ShellController shell = ShellScope.read(
      tester.element(find.byType(UserMenuButton).first),
    );

    _notify(meta, 2);
    _notify(team, 5);
    await _frames(tester);
    expect(_bellCount(2), findsWidgets);
    expect(_railBadge(_other, 5), findsOneWidget);

    shell.selectInstance(1);
    await tester.pumpAndSettle();
    expect(_bellCount(5), findsWidgets);

    _notify(team, 6);
    await _frames(tester);
    expect(_bellCount(6), findsWidgets);

    _notify(meta, 8);
    await _frames(tester);
    expect(_bellCount(6), findsWidgets);
    expect(_bellCount(8), findsNothing);
    expect(_railBadge(_selected, 8), findsOneWidget);
  }, variant: _bothPlatforms);

  testWidgets('a cleared count clears its badge', (tester) async {
    await _pumpForums(tester);
    final meta = _tracker(_selected);

    _notify(meta, 4);
    await _frames(tester);
    expect(_bellCount(4), findsWidgets);

    _notify(meta, 0);
    await _frames(tester);
    expect(find.byKey(UserMenuButton.unreadDotKey), findsNothing);
    expect(
      find.byKey(
        const ValueKey('instance-rail-badge-$_selected'),
        skipOffstage: false,
      ),
      findsNothing,
    );
  }, variant: _bothPlatforms);
}
