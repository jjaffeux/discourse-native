import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/shell/account_activity_controller.dart';
import 'package:flutter/widgets.dart';

import '../test/support/fakes.dart'
    show FakeApiCredentialReader, FakeDiscourseApi;

const _site = 'https://forum.example';
const _instance = DiscourseInstance(
  url: _site,
  title: 'Forum',
  user: DiscourseUser(username: 'sam'),
);
const _latency = Duration(milliseconds: 30);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final times = <int>[];
  for (var i = 0; i < 7; i++) {
    final time = await _dismiss();
    if (i >= 2) times.add(time);
  }
  times.sort();
  stdout.writeln(
    jsonEncode({'dismiss_all_notification_rows_and_totals': times[2]}),
  );
  exit(0);
}

Future<int> _dismiss() async {
  final api = _NotificationApi();
  final controller = AccountActivityController(
    api: api,
    credentials: FakeApiCredentialReader()..keys[_site] = 'key',
    lifecycle: SiteLifecycle(),
  );
  try {
    await controller.loadNotifications(_instance);
    await controller.refresh(_instance);
    final watch = Stopwatch()..start();
    await controller.markAllNotificationsRead(_instance, [
      CoreNotificationTypes.replied,
    ]);
    watch.stop();
    final rows = controller.notificationsFor(_site).notifications;
    if (rows.single.id != 7 ||
        rows.single.isUnread ||
        controller.totalsFor(_site)?.unreadNotifications != 0 ||
        api.rowsRead != 2 ||
        api.totalsRead != 2 ||
        api.markedTypesRead.length != 1) {
      throw StateError(
        'Notification dismiss did not reconcile rows and totals',
      );
    }
    return watch.elapsedMicroseconds;
  } finally {
    controller.dispose();
  }
}

final class _NotificationApi extends FakeDiscourseApi {
  bool dismissed = false;
  int rowsRead = 0;
  int totalsRead = 0;

  @override
  Future<void> markNotificationsRead({
    required String siteUrl,
    required String apiKey,
    required List<NotificationTypeName> types,
    String? clientId,
  }) async {
    await Future<void>.delayed(_latency);
    await super.markNotificationsRead(
      siteUrl: siteUrl,
      apiKey: apiKey,
      types: types,
      clientId: clientId,
    );
    dismissed = true;
  }

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    bool background = false,
    String? clientId,
  }) async {
    rowsRead++;
    await Future<void>.delayed(_latency);
    return [
      DiscourseNotification(
        id: 7,
        typeId: const NotificationTypeId(2),
        read: dismissed,
      ),
    ];
  }

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    totalsRead++;
    await Future<void>.delayed(_latency);
    return NotificationTotals(unreadNotifications: dismissed ? 0 : 1);
  }
}
