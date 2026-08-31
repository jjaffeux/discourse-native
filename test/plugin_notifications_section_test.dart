import 'dart:async';

import 'package:discourse_native/src/plugin_api/notification_feed_host.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://forum.example';
const _wireType = NotificationWireType(901, 'test_alert');

String _confirmation(int unreadCount) =>
    'Mark all $unreadCount test alerts as read?';

const _dismissibleSource = PluginNotificationFeedSource(
  id: PluginNotificationFeedId(owner: PluginId('test-plugin'), name: 'alerts'),
  filterByTypes: [NotificationTypeName('test_alert')],
  reconnectMessage: 'Reconnect.',
  failureMessage: 'Failed.',
  emptyMessage: 'Nothing here.',
  dismissal: PluginNotificationFeedDismissal(
    notificationTypes: [_wireType],
    buttonLabel: 'Dismiss',
    buttonTooltip: 'Mark test alerts as read',
    confirmationMessage: _confirmation,
  ),
);

const _plainSource = PluginNotificationFeedSource(
  id: PluginNotificationFeedId(
    owner: PluginId('test-plugin'),
    name: 'plain-alerts',
  ),
  filterByTypes: [NotificationTypeName('test_alert')],
  reconnectMessage: 'Reconnect.',
  failureMessage: 'Failed.',
  emptyMessage: 'Nothing here.',
);

void main() {
  testWidgets('feeds without dismissal metadata keep the existing UI', (
    tester,
  ) async {
    final host = _FeedHost(const NotificationFeed.of([]));
    addTearDown(host.dispose);

    await _pumpSection(
      tester,
      host: host,
      source: _plainSource,
      unreadCount: 4,
    );

    expect(find.text('Nothing here.'), findsOneWidget);
    expect(find.text('Dismiss'), findsNothing);
  });

  testWidgets('view-all opens its plugin link from a populated feed', (
    tester,
  ) async {
    var opened = false;
    final host = _FeedHost(
      const NotificationFeed.of([
        DiscourseNotification.test(
          id: 1,
          typeId: NotificationTypeId(901),
          title: 'Test alert',
        ),
      ]),
      openResult: true,
    );
    addTearDown(host.dispose);

    await _pumpSection(
      tester,
      host: host,
      source: _plainSource,
      unreadCount: 0,
      viewAll: const PluginNotificationFeedLink(
        label: 'View all alerts',
        path: '/u/reader/activity/alerts',
      ),
      onOpened: () => opened = true,
    );

    expect(find.text('View all alerts'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('plugin-notification-view-all-test-plugin/plain-alerts'),
      ),
    );
    await tester.pumpAndSettle();

    expect(host.openedUrls, ['https://forum.example/u/reader/activity/alerts']);
    expect(opened, isTrue);
  });

  testWidgets('empty-state action replaces view-all for an empty feed', (
    tester,
  ) async {
    var opened = false;
    final host = _FeedHost(const NotificationFeed.of([]), openResult: true);
    addTearDown(host.dispose);

    await _pumpSection(
      tester,
      host: host,
      source: _plainSource,
      unreadCount: 0,
      viewAll: const PluginNotificationFeedLink(
        label: 'View all alerts',
        path: '/u/reader/activity/alerts',
      ),
      emptyStateAction: const PluginNotificationFeedLink(
        label: 'Notification preferences',
        path: '/my/preferences/notifications',
      ),
      onOpened: () => opened = true,
    );

    expect(find.text('Nothing here.'), findsOneWidget);
    expect(find.text('View all alerts'), findsNothing);
    expect(find.text('Notification preferences'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey(
          'plugin-notification-empty-action-test-plugin/plain-alerts',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(host.openedUrls, [
      'https://forum.example/my/preferences/notifications',
    ]);
    expect(opened, isTrue);
  });

  testWidgets('dismissal confirms the authoritative count and shows loading', (
    tester,
  ) async {
    final gate = Completer<void>();
    final host = _FeedHost(const NotificationFeed.of([]), gate: gate);
    addTearDown(host.dispose);
    await _pumpSection(
      tester,
      host: host,
      source: _dismissibleSource,
      unreadCount: 173,
    );

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Mark all 173 test alerts as read?'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'plugin-notification-dismiss-confirm-test-plugin/alerts',
        ),
      ),
    );
    await tester.pump();

    expect(host.dismissCalls, 1);
    final button = tester.widget<DButton>(
      find.byKey(
        const ValueKey('plugin-notification-dismiss-test-plugin/alerts'),
      ),
    );
    expect(button.loading, isTrue);

    gate.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('plugin-notification-dismiss-error-test-plugin/alerts'),
      ),
      findsNothing,
    );
  });

  testWidgets('a failed dismissal leaves a retryable inline error', (
    tester,
  ) async {
    final host = _FeedHost(
      const NotificationFeed.of([]),
      failure: StateError('failed'),
    );
    addTearDown(host.dispose);
    await _pumpSection(
      tester,
      host: host,
      source: _dismissibleSource,
      unreadCount: 2,
    );

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey(
          'plugin-notification-dismiss-confirm-test-plugin/alerts',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't mark notifications as read. Try again."),
      findsOneWidget,
    );
    expect(find.text('Dismiss'), findsOneWidget);
  });
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required _FeedHost host,
  required PluginNotificationFeedSource source,
  required int unreadCount,
  PluginNotificationFeedLink? viewAll,
  PluginNotificationFeedLink? emptyStateAction,
  VoidCallback? onOpened,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: PluginNotificationsSection(
        siteUrl: _siteUrl,
        onOpened: onOpened ?? _ignore,
        host: host,
        source: source,
        unreadCount: unreadCount,
        viewAll: viewAll,
        emptyStateAction: emptyStateAction,
      ),
    ),
  ),
);

void _ignore() {}

final class _FeedHost extends ChangeNotifier
    implements PluginNotificationFeedHost {
  _FeedHost(this.feed, {this.gate, this.failure, this.openResult = false});

  NotificationFeed feed;
  final Completer<void>? gate;
  final Object? failure;
  final bool openResult;
  int dismissCalls = 0;
  final List<String> openedUrls = [];

  @override
  Future<void> dismissPluginNotifications(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) async {
    dismissCalls++;
    if (gate case final gate?) await gate.future;
    if (failure case final failure?) throw failure;
  }

  @override
  Future<void> loadPluginNotificationFeed(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) async {}

  @override
  Listenable notificationFeedListenable(PluginNotificationFeedId id) => this;

  @override
  NotificationFeed notificationFeedFor(
    PluginNotificationFeedId id,
    String siteUrl,
  ) => feed;

  @override
  Future<bool> openPluginNotificationUrl(String url) async {
    openedUrls.add(url);
    return openResult;
  }

  @override
  String pluginAbsoluteUrl(String path, {required String siteUrl}) =>
      '$siteUrl$path';

  @override
  void readPluginNotification(
    String siteUrl,
    DiscourseNotification notification,
  ) {}
}
