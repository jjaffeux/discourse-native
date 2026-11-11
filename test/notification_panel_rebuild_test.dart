import 'dart:math';

import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/notifications_menu.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');
const _repliedType = 2;
const _pluginBodyKey = ValueKey('totals-plugin-body');

const _bothPlatforms = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.macOS,
});

bool get _isPhone => defaultTargetPlatform == TargetPlatform.iOS;

/// A notification as `NotificationSerializer` writes it.
DiscourseNotification _notification(int id) => DiscourseNotification.fromJson({
  'id': id,
  'user_id': _user.id,
  'notification_type': _repliedType,
  'read': id > 5,
  'high_priority': false,
  'created_at': '2026-09-01T00:00:00.000Z',
  'post_number': 2,
  'topic_id': id,
  'fancy_title': 'Reply on topic $id',
  'slug': 'topic-$id',
  'data': {
    'topic_title': 'Reply on topic $id',
    'original_post_id': id,
    'original_post_type': 1,
    'original_username': 'alice',
    'revision_number': null,
    'display_username': 'alice',
  },
  'acting_user_avatar_template': '/user_avatar/meta/alice/{size}/1_2.png',
  'acting_user_name': 'Alice',
});

/// What `User#publish_notifications_state` publishes on `/notification/:id`.
Map<String, Object?> _notificationState(int unread) => {
  'unread_notifications': unread,
  'unread_high_priority_notifications': 0,
  'read_first_notification': true,
  'last_notification': {'id': 1, 'notification_type': _repliedType},
  'recent': [
    [1, false],
    [2, false],
  ],
  'seen_notification_id': 1,
  'all_unread_notifications_count': unread,
  'grouped_unread_notifications': {'$_repliedType': unread},
  'available_notification_types': [_repliedType],
  'new_personal_messages_notifications_count': 0,
};

/// What `User#publish_reviewable_counts` publishes.
Map<String, Object?> _reviewableCounts(int unseen) => {
  'reviewable_count': unseen,
  'unseen_reviewable_count': unseen,
};

final class _Rebuilds {
  int elements = 0;
  int rows = 0;

  void clear() {
    elements = 0;
    rows = 0;
  }
}

_Rebuilds _recordRebuilds() {
  final rebuilds = _Rebuilds();
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    rebuilds.elements++;
    if (element.widget is NotificationRow) rebuilds.rows++;
  };
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  return rebuilds;
}

void _report(String metric, int value) {
  // ignore: avoid_print
  print('PERF_PROOF notification-panel $metric=$value');
}

final class _Panel {
  _Panel(this.tracker, this.shell, this.feed);

  final FakeSiteTracker tracker;
  final ShellController shell;
  final List<DiscourseNotification> feed;
}

Future<_Panel> _openPanel(
  WidgetTester tester, {
  PluginManifest? pluginManifest,
}) async {
  final feed = [for (var id = 1; id <= 30; id++) _notification(id)];
  await pumpShell(
    tester,
    _isPhone ? const Size(390, 844) : const Size(1440, 900),
    instances: [instance('meta.discourse.org', user: _user)],
    api: FakeDiscourseApi(
      user: _user,
      totals: const NotificationTotals(unreadNotifications: 5),
      notificationList: feed,
    ),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    pluginManifest: pluginManifest,
  );
  final tracker = FakeSiteTracker.built.singleWhere(
    (candidate) => candidate.siteUrl == _site,
  );
  await tester.tap(notificationsMenuTrigger());
  await tester.pumpAndSettle();
  return _Panel(
    tracker,
    ShellScope.read(tester.element(find.byType(UserMenuPanel))),
    feed,
  );
}

Finder _tabCount(String section, int count) => find.descendant(
  of: find.byKey(ValueKey('user-menu-tab-$section')),
  matching: find.text('$count'),
);

/// The color the first row draws its actor's name in.
Color _actorColor(WidgetTester tester) {
  Color? color;
  final texts = find.descendant(
    of: find.byType(NotificationRow).first,
    matching: find.byType(RichText),
  );
  for (final element in texts.evaluate()) {
    (element.widget as RichText).text.visitChildren((span) {
      if (span is TextSpan && span.text?.startsWith('Alice') == true) {
        color = span.style?.color;
      }
      return color == null;
    });
  }
  return color!;
}

void main() {
  testWidgets('a live count does not rebuild the open panel rows', (
    tester,
  ) async {
    final panel = await _openPanel(tester);
    final platform = defaultTargetPlatform.name;
    expect(find.byType(NotificationRow), findsWidgets);
    // A phone's first live message costs more on both sides of this work, so
    // the cost that repeats is measured from the second.
    panel.tracker.deliverNotification(_notificationState(5));
    await tester.pumpAndSettle();
    final rebuilds = _recordRebuilds();

    Future<(int, int)> measure(void Function(int count) deliver) async {
      var elements = 0;
      var rows = 0;
      for (var count = 6; count <= 11; count++) {
        rebuilds.clear();
        deliver(count);
        await tester.pumpAndSettle();
        elements = max(elements, rebuilds.elements);
        rows = max(rows, rebuilds.rows);
      }
      return (elements, rows);
    }

    final (countElements, countRows) = await measure(
      (count) => panel.tracker.deliverNotification(_notificationState(count)),
    );
    final (reviewElements, reviewRows) = await measure(
      (count) =>
          panel.tracker.deliverReviewableCounts(_reviewableCounts(count)),
    );

    _report('${platform}_count_elements', countElements);
    _report('${platform}_count_rows', countRows);
    _report('${platform}_review_elements', reviewElements);
    _report('${platform}_review_rows', reviewRows);

    expect(_tabCount('all', 11), findsOneWidget);
    expect(countRows, 0);
    expect(reviewRows, 0);
    expect(countElements, lessThanOrEqualTo(_isPhone ? 764 : 516));
    expect(reviewElements, lessThanOrEqualTo(_isPhone ? 764 : 516));
  }, variant: _bothPlatforms);

  testWidgets('a live count still reaches the tab badges', (tester) async {
    final panel = await _openPanel(tester);

    panel.tracker.deliverNotification(_notificationState(9));
    await tester.pumpAndSettle();

    expect(_tabCount('all', 9), findsOneWidget);
    expect(_tabCount('replies', 9), findsOneWidget);
  }, variant: _bothPlatforms);

  testWidgets('a new notification appears in the open panel', (tester) async {
    final panel = await _openPanel(tester);
    panel.tracker.deliverNotification(_notificationState(9));
    await tester.pumpAndSettle();

    panel.feed.insert(
      0,
      DiscourseNotification.fromJson(const {
        'id': 99,
        'notification_type': _repliedType,
        'read': false,
        'topic_id': 99,
        'post_number': 2,
        'slug': 'just-arrived',
        'fancy_title': 'Just arrived',
        'data': {'display_username': 'bob'},
      }),
    );
    await panel.shell.loadNotifications(_site);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notification-row-99')), findsOneWidget);
  }, variant: _bothPlatforms);

  testWidgets('a theme change recolors the open panel rows', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final panel = await _openPanel(tester);
    // The theme must keep working after the panel has held one across a count.
    panel.tracker.deliverNotification(_notificationState(9));
    await tester.pumpAndSettle();
    final light = _actorColor(tester);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    expect(
      _actorColor(tester).computeLuminance(),
      greaterThan(light.computeLuminance()),
    );
  }, variant: _bothPlatforms);

  testWidgets('an open plugin section redraws from the totals it reads', (
    tester,
  ) async {
    final panel = await _openPanel(
      tester,
      pluginManifest: const PluginManifest([_TotalsModule()]),
    );
    final tab = find.byKey(const ValueKey('user-menu-tab-totals/activity'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(find.text('Plugin unread: 5'), findsOneWidget);

    panel.tracker.deliverNotification(_notificationState(9));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(_pluginBodyKey)).data,
      'Plugin unread: 9',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a body kept across a count dismisses the current panel', (
    tester,
  ) async {
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org', user: _user),
      ]),
      api: FakeDiscourseApi(
        user: _user,
        totals: const NotificationTotals(unreadNotifications: 5),
        notificationList: [_notification(1)],
      ),
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    final dismissed = <String>[];
    Widget panel(String owner) => ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: UserMenuPanel(onDismiss: () => dismissed.add(owner)),
          ),
        ),
      ),
    );
    await tester.pumpWidget(panel('first'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(panel('second'));
    controller.accountActivity.applyCounts(
      _site,
      (held) => held.copyWith(unreadNotifications: 4),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NotificationRow));
    await tester.pumpAndSettle();

    expect(dismissed, ['second']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

final class _TotalsModule implements PluginModule {
  const _TotalsModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('totals'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const _TotalsPlugin());
  }
}

final class _TotalsPlugin implements SitePlugin, UserMenuSectionPlugin {
  const _TotalsPlugin();

  @override
  String get name => 'totals';

  @override
  List<PluginUserMenuSection> userMenuSections(PluginUserMenuContext context) {
    Widget body() => Text(
      'Plugin unread: ${context.totals?.unreadNotifications ?? 0}',
      key: _pluginBodyKey,
    );
    return [
      PluginUserMenuSection(
        id: const PluginUserMenuSectionId(
          owner: PluginId('totals'),
          name: 'activity',
        ),
        icon: DIcons.bell,
        label: 'Totals',
        builder: (_, _) => body(),
        sliverBuilder: (_, _) => SliverToBoxAdapter(child: body()),
      ),
    ];
  }
}
