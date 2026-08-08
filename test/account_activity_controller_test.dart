import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/shell/account_activity_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _notification = DiscourseNotification(
  id: 11,
  kind: NotificationKind.replied,
  title: 'A reply',
);
const _reminder = DiscourseNotification(
  id: 12,
  kind: NotificationKind.bookmarkReminder,
  title: 'A reminder',
);
const _bookmark = Bookmark(id: 9, title: 'Saved topic');

class _AccountApi implements AccountActivityApi {
  _AccountApi({
    this.totals,
    this.notificationList,
    this.bookmarkList,
    this.reminderList = const [],
  });

  final NotificationTotals? totals;
  final List<DiscourseNotification>? notificationList;
  final List<Bookmark>? bookmarkList;
  final List<DiscourseNotification> reminderList;
  final List<String> bookmarksRequested = [];
  final List<int> markedRead = [];

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => totals ?? (throw StateError('No totals configured'));

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    String? clientId,
  }) async =>
      notificationList ?? (throw StateError('No notifications configured'));

  @override
  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    bookmarksRequested.add(username);
    return (
      reminders: reminderList,
      bookmarks: bookmarkList ?? (throw StateError('No bookmarks configured')),
    );
  }

  @override
  Future<void> markNotificationRead({
    required String siteUrl,
    required String apiKey,
    required int id,
    String? clientId,
  }) async {
    markedRead.add(id);
  }
}

DiscourseInstance _connectedInstance() => instance(
  'meta.discourse.org',
).copyWith(user: const DiscourseUser(id: 7, username: 'sam'));

AccountActivityController _controller(
  AccountActivityApi api,
  FakeApiCredentialReader credentials, {
  SiteLifecycle? lifecycle,
  TotalsLoaded? onTotalsLoaded,
}) => AccountActivityController(
  api: api,
  credentials: credentials,
  lifecycle: lifecycle ?? SiteLifecycle(),
  onTotalsLoaded: onTotalsLoaded,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refreshes per-site totals and reports capabilities', () async {
    const totals = NotificationTotals(
      unreadNotifications: 3,
      hasChatEnabled: true,
    );
    final api = _AccountApi(totals: totals);
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final loaded = <NotificationTotals>[];
    final controller = _controller(
      api,
      credentials,
      onTotalsLoaded: (_, totals) => loaded.add(totals),
    );
    addTearDown(controller.dispose);
    var changes = 0;
    controller.addListener(() => changes++);

    final result = await controller.refresh(_connectedInstance());

    expect(result, totals);
    expect(controller.totalsFor(_siteUrl), totals);
    expect(loaded, [totals]);
    expect(changes, 1);
  });

  test('loads notification and bookmark feeds independently', () async {
    final api = _AccountApi(
      notificationList: const [_notification],
      bookmarkList: const [_bookmark],
      reminderList: const [_notification],
    );
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);
    final connected = _connectedInstance();

    await Future.wait([
      controller.loadNotifications(connected),
      controller.loadBookmarks(connected),
    ]);

    expect(controller.notificationsFor(_siteUrl).notifications, const [
      _notification,
    ]);
    expect(controller.bookmarksFor(_siteUrl).reminders, const [_notification]);
    expect(controller.bookmarksFor(_siteUrl).bookmarks, const [_bookmark]);
    expect(api.bookmarksRequested, ['sam']);
  });

  test('each activity aspect notifies only its own consumers', () async {
    final api = _AccountApi(
      notificationList: const [_notification],
      bookmarkList: const [_bookmark],
    );
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);
    var totalsChanges = 0;
    var notificationChanges = 0;
    var bookmarkChanges = 0;
    controller.totalsListenable.addListener(() => totalsChanges++);
    controller.notificationsListenable.addListener(() => notificationChanges++);
    controller.bookmarksListenable.addListener(() => bookmarkChanges++);

    await controller.loadNotifications(_connectedInstance());

    expect(totalsChanges, 0);
    expect(notificationChanges, 2);
    expect(bookmarkChanges, 0);
  });

  test('coalesces repeated notification loads for one site', () async {
    final gate = Completer<void>();
    final api = _GatedNotificationsApi(gate);
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);

    final first = controller.loadNotifications(_connectedInstance());
    final second = controller.loadNotifications(_connectedInstance());
    await Future<void>.delayed(Duration.zero);

    expect(api.calls, 1);
    gate.complete();
    await Future.wait([first, second]);
  });

  test('a newer totals request owns the result', () async {
    final first = Completer<NotificationTotals>();
    final second = Completer<NotificationTotals>();
    final api = _GatedTotalsApi([first, second]);
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);

    final older = controller.refresh(_connectedInstance());
    await api.firstStarted.future;
    final newer = controller.refresh(_connectedInstance());
    await api.secondStarted.future;
    second.complete(const NotificationTotals(unreadNotifications: 2));
    await newer;
    first.complete(const NotificationTotals(unreadNotifications: 1));
    await older;

    expect(controller.totalsFor(_siteUrl)?.unreadNotifications, 2);
  });

  test('a live counter update survives an older totals response', () async {
    final gate = Completer<NotificationTotals>();
    final api = _GatedTotalsApi([gate]);
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);

    final loading = controller.refresh(_connectedInstance());
    await api.firstStarted.future;
    controller.applyCounts(
      _siteUrl,
      (held) => held.copyWith(unreadNotifications: 5),
    );
    gate.complete(
      const NotificationTotals(
        unreadNotifications: 1,
        topicTrackingUnread: 7,
        hasChatEnabled: true,
      ),
    );
    await loading;

    final totals = controller.totalsFor(_siteUrl)!;
    expect(totals.unreadNotifications, 5);
    expect(totals.topicTrackingUnread, 7);
    expect(totals.hasChatEnabled, isTrue);
  });

  test('reading a reminder reconciles both feeds and totals', () async {
    const totals = NotificationTotals(unreadNotifications: 0);
    final api = _AccountApi(
      totals: totals,
      notificationList: const [_notification],
      bookmarkList: const [_bookmark],
      reminderList: const [_notification],
    );
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);
    final connected = _connectedInstance();
    await controller.loadNotifications(connected);
    await controller.loadBookmarks(connected);

    controller.readNotification(connected, _notification);

    expect(
      controller.notificationsFor(_siteUrl).notifications.single.read,
      isTrue,
    );
    expect(controller.bookmarksFor(_siteUrl).reminders.single.read, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(api.markedRead, [11]);
    expect(controller.totalsFor(_siteUrl), totals);
  });

  test('reading only rebuilds feeds that contain the notification', () async {
    final api = _AccountApi(
      notificationList: const [_notification],
      bookmarkList: const [_bookmark],
      reminderList: const [_reminder],
    );
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);
    final connected = _connectedInstance();
    await controller.loadNotifications(connected);
    await controller.loadBookmarks(connected);

    var notificationChanges = 0;
    var bookmarkChanges = 0;
    controller.notificationsListenable.addListener(() => notificationChanges++);
    controller.bookmarksListenable.addListener(() => bookmarkChanges++);

    controller.readNotification(connected, _notification);

    expect(notificationChanges, 1);
    expect(bookmarkChanges, 0);

    notificationChanges = 0;
    controller.readNotification(connected, _reminder);

    expect(notificationChanges, 0);
    expect(bookmarkChanges, 1);
    await Future<void>.delayed(Duration.zero);
    expect(api.markedRead, [11, 12]);
  });

  test(
    'coalesces a mark-read write until its reconciliation finishes',
    () async {
      final api = _GatedReadApi(2);
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      final controller = _controller(api, credentials);
      addTearDown(controller.dispose);
      final connected = _connectedInstance();

      controller.readNotification(connected, _notification);
      controller.readNotification(connected, _notification);
      await api.started[0].future;

      expect(api.markedRead, [11]);

      api.gates[0].complete();
      await api.reconciled.future;
      await Future<void>.delayed(Duration.zero);
      controller.readNotification(connected, _notification);
      await api.started[1].future;

      expect(api.markedRead, [11, 11]);

      api.gates[1].complete();
      await api.completed[1].future;
    },
  );

  test('an old read completion cannot clear a new session request', () async {
    final api = _GatedReadApi(2);
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final lifecycle = SiteLifecycle();
    final controller = _controller(api, credentials, lifecycle: lifecycle);
    addTearDown(controller.dispose);
    final connected = _connectedInstance();

    controller.readNotification(connected, _notification);
    await api.started[0].future;
    lifecycle.invalidate(_siteUrl);
    controller.forget(_siteUrl);
    controller.readNotification(connected, _notification);
    await api.started[1].future;

    api.gates[0].complete();
    await api.completed[0].future;
    await Future<void>.delayed(Duration.zero);
    controller.readNotification(connected, _notification);

    expect(api.markedRead, [11, 11]);

    api.gates[1].complete();
    await api.completed[1].future;
    await api.reconciled.future;
  });

  test(
    'a response from a forgotten account cannot repopulate its feed',
    () async {
      final gate = Completer<void>();
      final api = _GatedNotificationsApi(gate);
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      final lifecycle = SiteLifecycle();
      final controller = _controller(api, credentials, lifecycle: lifecycle);
      addTearDown(controller.dispose);

      final loading = controller.loadNotifications(_connectedInstance());
      await Future<void>.delayed(Duration.zero);
      lifecycle.invalidate(_siteUrl);
      controller.forget(_siteUrl);
      gate.complete();
      await loading;

      expect(controller.notificationsFor(_siteUrl).loaded, isFalse);
    },
  );
}

final class _GatedNotificationsApi extends _AccountApi {
  _GatedNotificationsApi(this._notificationGate);

  final Completer<void> _notificationGate;
  int calls = 0;

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    String? clientId,
  }) async {
    calls++;
    await _notificationGate.future;
    return const [_notification];
  }
}

final class _GatedTotalsApi extends _AccountApi {
  _GatedTotalsApi(this._answers);

  final List<Completer<NotificationTotals>> _answers;
  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> secondStarted = Completer<void>();
  int _calls = 0;

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    final call = _calls++;
    if (call == 0) firstStarted.complete();
    if (call == 1) secondStarted.complete();
    return _answers[call].future;
  }
}

final class _GatedReadApi extends _AccountApi {
  _GatedReadApi(int calls)
    : gates = List.generate(calls, (_) => Completer<void>()),
      started = List.generate(calls, (_) => Completer<void>()),
      completed = List.generate(calls, (_) => Completer<void>()),
      super(totals: const NotificationTotals());

  final List<Completer<void>> gates;
  final List<Completer<void>> started;
  final List<Completer<void>> completed;
  final Completer<void> reconciled = Completer<void>();

  @override
  Future<void> markNotificationRead({
    required String siteUrl,
    required String apiKey,
    required int id,
    String? clientId,
  }) async {
    final call = markedRead.length;
    markedRead.add(id);
    started[call].complete();
    await gates[call].future;
    completed[call].complete();
  }

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    if (!reconciled.isCompleted) reconciled.complete();
    return const NotificationTotals();
  }
}
