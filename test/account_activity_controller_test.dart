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
const _secondReply = DiscourseNotification(
  id: 13,
  kind: NotificationKind.quoted,
  title: 'A quote',
);
const _chatNotification = DiscourseNotification(
  id: 14,
  kind: NotificationKind.chatMention,
  actor: 'alex',
  channelTitle: 'dev',
);
const _reminder = DiscourseNotification(
  id: 12,
  kind: NotificationKind.bookmarkReminder,
  title: 'A reminder',
);
const _bookmark = Bookmark(id: 9, title: 'Saved topic');

enum _NotificationFeedKind { all, replies, chat }

_NotificationFeedKind _notificationFeedKind(
  List<NotificationKind> filterByTypes,
) {
  if (filterByTypes.isEmpty) return _NotificationFeedKind.all;
  if (_sameKinds(filterByTypes, userMenuReplyNotificationKinds)) {
    return _NotificationFeedKind.replies;
  }
  if (_sameKinds(filterByTypes, userMenuChatNotificationKinds)) {
    return _NotificationFeedKind.chat;
  }
  throw StateError('Unexpected notification filter: $filterByTypes');
}

bool _sameKinds(List<NotificationKind> first, List<NotificationKind> second) =>
    first.length == second.length &&
    Iterable<int>.generate(
      first.length,
    ).every((index) => first[index] == second[index]);

class _AccountApi implements AccountActivityApi {
  _AccountApi({
    this.totals,
    this.notificationList,
    this.replyNotificationList,
    this.chatNotificationList,
    this.bookmarkList,
    this.reminderList = const [],
  });

  final NotificationTotals? totals;
  final List<DiscourseNotification>? notificationList;
  final List<DiscourseNotification>? replyNotificationList;
  final List<DiscourseNotification>? chatNotificationList;
  final List<Bookmark>? bookmarkList;
  final List<DiscourseNotification> reminderList;
  final List<String> bookmarksRequested = [];
  final List<String> totalsRequested = [];
  final List<int> markedRead = [];

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    totalsRequested.add(siteUrl);
    return totals ?? (throw StateError('No totals configured'));
  }

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationKind> filterByTypes = const [],
    String? clientId,
  }) async => switch (_notificationFeedKind(filterByTypes)) {
    _NotificationFeedKind.all =>
      notificationList ?? (throw StateError('No notifications configured')),
    _NotificationFeedKind.replies =>
      replyNotificationList ??
          (throw StateError('No reply notifications configured')),
    _NotificationFeedKind.chat =>
      chatNotificationList ??
          (throw StateError('No chat notifications configured')),
  };

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
  Duration minimumRefreshInterval = const Duration(minutes: 5),
  DateTime Function()? clock,
}) => AccountActivityController(
  api: api,
  credentials: credentials,
  lifecycle: lifecycle ?? SiteLifecycle(),
  onTotalsLoaded: onTotalsLoaded,
  minimumRefreshInterval: minimumRefreshInterval,
  clock: clock,
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

  test('reentrant disposal suppresses the totals post-load callback', () async {
    const totals = NotificationTotals(hasChatEnabled: true);
    final api = _AccountApi(totals: totals);
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    var loaded = false;
    final controller = _controller(
      api,
      credentials,
      onTotalsLoaded: (_, _) => loaded = true,
    );
    controller.addListener(controller.dispose);

    final result = await controller.refresh(_connectedInstance());

    expect(result, totals);
    expect(loaded, isFalse);
  });

  test(
    'loads notification, reply, chat, and bookmark feeds independently',
    () async {
      final api = _AccountApi(
        notificationList: const [_notification],
        replyNotificationList: const [_secondReply],
        chatNotificationList: const [_chatNotification],
        bookmarkList: const [_bookmark],
        reminderList: const [_notification],
      );
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      final controller = _controller(api, credentials);
      addTearDown(controller.dispose);
      final connected = _connectedInstance();

      await Future.wait([
        controller.loadNotifications(connected),
        controller.loadReplyNotifications(connected),
        controller.loadChatNotifications(connected),
        controller.loadBookmarks(connected),
      ]);

      expect(controller.notificationsFor(_siteUrl).notifications, const [
        _notification,
      ]);
      expect(controller.replyNotificationsFor(_siteUrl).notifications, const [
        _secondReply,
      ]);
      expect(controller.chatNotificationsFor(_siteUrl).notifications, const [
        _chatNotification,
      ]);
      expect(controller.bookmarksFor(_siteUrl).reminders, const [
        _notification,
      ]);
      expect(controller.bookmarksFor(_siteUrl).bookmarks, const [_bookmark]);
      expect(api.bookmarksRequested, ['sam']);
    },
  );

  test('a forced bookmark load replays behind an older request', () async {
    final api = _SequencedBookmarksApi(2);
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);
    final connected = _connectedInstance();

    final first = controller.loadBookmarks(connected);
    await api.started[0].future;
    final forced = controller.loadBookmarks(connected, force: true);

    api.answers[0].complete((
      reminders: const <DiscourseNotification>[],
      bookmarks: const [_bookmark],
    ));
    await first;
    await api.started[1].future;
    expect(controller.bookmarksFor(_siteUrl).bookmarks, const [_bookmark]);

    const fresh = Bookmark(id: 10, title: 'Fresh bookmark');
    api.answers[1].complete((
      reminders: const <DiscourseNotification>[],
      bookmarks: const [fresh],
    ));
    await forced;

    expect(controller.bookmarksFor(_siteUrl).bookmarks, const [fresh]);
    expect(api.calls, 2);
  });

  test('each activity aspect notifies only its own consumers', () async {
    final api = _AccountApi(
      notificationList: const [_notification],
      replyNotificationList: const [_notification],
      chatNotificationList: const [_chatNotification],
      bookmarkList: const [_bookmark],
    );
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);
    var totalsChanges = 0;
    var notificationChanges = 0;
    var replyNotificationChanges = 0;
    var chatNotificationChanges = 0;
    var bookmarkChanges = 0;
    controller.totalsListenable.addListener(() => totalsChanges++);
    controller.notificationsListenable.addListener(() => notificationChanges++);
    controller.replyNotificationsListenable.addListener(
      () => replyNotificationChanges++,
    );
    controller.chatNotificationsListenable.addListener(
      () => chatNotificationChanges++,
    );
    controller.bookmarksListenable.addListener(() => bookmarkChanges++);

    await controller.loadNotifications(_connectedInstance());

    expect(totalsChanges, 0);
    expect(notificationChanges, 2);
    expect(replyNotificationChanges, 0);
    expect(chatNotificationChanges, 0);
    expect(bookmarkChanges, 0);

    await controller.loadChatNotifications(_connectedInstance());

    expect(totalsChanges, 0);
    expect(notificationChanges, 2);
    expect(replyNotificationChanges, 0);
    expect(chatNotificationChanges, 2);
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

    expect(second, same(first));
    expect(api.calls, 1);
    gate.complete();
    await Future.wait([first, second]);
  });

  test('coalesces repeated reply notification loads for one site', () async {
    final gate = Completer<void>();
    final api = _GatedNotificationsApi(gate);
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);

    final first = controller.loadReplyNotifications(_connectedInstance());
    final second = controller.loadReplyNotifications(_connectedInstance());
    await Future<void>.delayed(Duration.zero);

    expect(second, same(first));
    expect(api.calls, 1);
    expect(api.filters.single, userMenuReplyNotificationKinds);
    gate.complete();
    await Future.wait([first, second]);
  });

  test(
    'coalesces repeated chat notification loads with the exact filter',
    () async {
      final gate = Completer<void>();
      final api = _GatedNotificationsApi(gate);
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      final controller = _controller(api, credentials);
      addTearDown(controller.dispose);

      final first = controller.loadChatNotifications(_connectedInstance());
      final second = controller.loadChatNotifications(_connectedInstance());
      await Future<void>.delayed(Duration.zero);

      expect(second, same(first));
      expect(api.calls, 1);
      expect(api.filters.single, userMenuChatNotificationKinds);
      gate.complete();
      await Future.wait([first, second]);
    },
  );

  test('coalesces repeated bookmark loads onto one future', () async {
    final api = _AccountApi(bookmarkList: const [_bookmark]);
    final credentials = _GatedCredentialReader();
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);

    final first = controller.loadBookmarks(_connectedInstance());
    await credentials.started.future;
    final second = controller.loadBookmarks(_connectedInstance());

    expect(second, same(first));
    credentials.result.complete('key');
    await Future.wait([first, second]);
    expect(controller.bookmarksFor(_siteUrl).loaded, isTrue);
  });

  test('ordinary overlapping totals refreshes share one request', () async {
    final first = Completer<NotificationTotals>();
    final api = _GatedTotalsApi([first]);
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);

    final older = controller.refresh(_connectedInstance());
    await api.firstStarted.future;
    final newer = controller.refresh(_connectedInstance());
    final newest = controller.refresh(_connectedInstance());
    await Future<void>.delayed(Duration.zero);

    expect(api._calls, 1);
    expect(api.secondStarted.isCompleted, isFalse);
    first.complete(const NotificationTotals(unreadNotifications: 1));
    await Future.wait([older, newer, newest]);

    expect(api._calls, 1);
    expect(controller.totalsFor(_siteUrl)?.unreadNotifications, 1);
  });

  test(
    'a forced refresh queues one reconciliation behind an active one',
    () async {
      final first = Completer<NotificationTotals>();
      final second = Completer<NotificationTotals>();
      final api = _GatedTotalsApi([first, second]);
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      final controller = _controller(api, credentials);
      addTearDown(controller.dispose);

      final initial = controller.refresh(_connectedInstance());
      await api.firstStarted.future;
      final forced = controller.refresh(_connectedInstance(), force: true);
      final duplicate = controller.refresh(_connectedInstance(), force: true);
      await Future<void>.delayed(Duration.zero);

      expect(api._calls, 1);
      first.complete(const NotificationTotals(unreadNotifications: 1));
      await initial;
      await api.secondStarted.future;
      expect(api._calls, 2);
      second.complete(const NotificationTotals(unreadNotifications: 2));
      await Future.wait([forced, duplicate]);

      expect(controller.totalsFor(_siteUrl)?.unreadNotifications, 2);
    },
  );

  test('forget completes a forced waiter whose replay is active', () async {
    final first = Completer<NotificationTotals>();
    final replay = Completer<NotificationTotals>();
    final api = _GatedTotalsApi([first, replay]);
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);

    final initial = controller.refresh(_connectedInstance());
    await api.firstStarted.future;
    final forced = controller.refresh(_connectedInstance(), force: true);

    first.complete(const NotificationTotals(unreadNotifications: 1));
    await initial;
    await api.secondStarted.future;

    var forcedCompleted = false;
    NotificationTotals? forcedResult;
    unawaited(
      forced.then<void>((result) {
        forcedCompleted = true;
        forcedResult = result;
      }),
    );
    controller.forget(_siteUrl);
    await Future<void>.delayed(Duration.zero);

    expect(forcedCompleted, isTrue);
    expect(forcedResult, isNull);

    replay.complete(const NotificationTotals(unreadNotifications: 2));
    await pumpEventQueue();
    expect(controller.totalsFor(_siteUrl), isNull);
  });

  test('dispose completes a forced waiter whose replay is active', () async {
    final first = Completer<NotificationTotals>();
    final replay = Completer<NotificationTotals>();
    final api = _GatedTotalsApi([first, replay]);
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);

    final initial = controller.refresh(_connectedInstance());
    await api.firstStarted.future;
    final forced = controller.refresh(_connectedInstance(), force: true);

    first.complete(const NotificationTotals(unreadNotifications: 1));
    await initial;
    await api.secondStarted.future;

    var forcedCompleted = false;
    NotificationTotals? forcedResult;
    unawaited(
      forced.then<void>((result) {
        forcedCompleted = true;
        forcedResult = result;
      }),
    );
    controller.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(forcedCompleted, isTrue);
    expect(forcedResult, isNull);

    replay.complete(const NotificationTotals(unreadNotifications: 2));
    await pumpEventQueue();
  });

  test('recent totals are reused until explicitly refreshed', () async {
    var now = DateTime(2026, 8, 11, 10);
    final api = _AccountApi(
      totals: const NotificationTotals(unreadNotifications: 1),
    );
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials, clock: () => now);
    addTearDown(controller.dispose);

    await controller.refresh(_connectedInstance());
    await controller.refresh(_connectedInstance());
    expect(api.totalsRequested, hasLength(1));

    now = now.add(const Duration(minutes: 6));
    await controller.refresh(_connectedInstance());
    expect(api.totalsRequested, hasLength(2));

    await controller.refresh(_connectedInstance(), force: true);
    expect(api.totalsRequested, hasLength(3));
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

  test(
    'reading a notification reconciles every cached feed and totals',
    () async {
      const totals = NotificationTotals(unreadNotifications: 0);
      final api = _AccountApi(
        totals: totals,
        notificationList: const [_notification],
        replyNotificationList: const [_notification],
        chatNotificationList: const [_notification],
        bookmarkList: const [_bookmark],
        reminderList: const [_notification],
      );
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      final controller = _controller(api, credentials);
      addTearDown(controller.dispose);
      final connected = _connectedInstance();
      await controller.loadNotifications(connected);
      await controller.loadReplyNotifications(connected);
      await controller.loadChatNotifications(connected);
      await controller.loadBookmarks(connected);

      controller.readNotification(connected, _notification);

      expect(
        controller.notificationsFor(_siteUrl).notifications.single.read,
        isTrue,
      );
      expect(
        controller.replyNotificationsFor(_siteUrl).notifications.single.read,
        isTrue,
      );
      expect(
        controller.chatNotificationsFor(_siteUrl).notifications.single.read,
        isTrue,
      );
      expect(controller.bookmarksFor(_siteUrl).reminders.single.read, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(api.markedRead, [11]);
      expect(controller.totalsFor(_siteUrl), totals);
    },
  );

  test('a stale refresh cannot restore a locally read notification', () async {
    final api = _GatedActivityRefreshApi();
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);
    final connected = _connectedInstance();
    await Future.wait([
      controller.loadNotifications(connected),
      controller.loadReplyNotifications(connected),
      controller.loadChatNotifications(connected),
      controller.loadBookmarks(connected),
    ]);

    final refreshes = Future.wait([
      controller.loadNotifications(connected),
      controller.loadReplyNotifications(connected),
      controller.loadChatNotifications(connected),
      controller.loadBookmarks(connected),
    ]);
    await Future.wait([
      api.notificationsRefreshStarted.future,
      api.repliesRefreshStarted.future,
      api.chatRefreshStarted.future,
      api.bookmarksRefreshStarted.future,
    ]);

    controller.readNotification(connected, _notification);
    api.notificationsRefresh.complete();
    api.repliesRefresh.complete();
    api.chatRefresh.complete();
    api.bookmarksRefresh.complete();
    await refreshes;

    expect(
      controller.notificationsFor(_siteUrl).notifications.single.read,
      isTrue,
    );
    expect(
      controller.replyNotificationsFor(_siteUrl).notifications.single.read,
      isTrue,
    );
    expect(
      controller.chatNotificationsFor(_siteUrl).notifications.single.read,
      isTrue,
    );
    expect(controller.bookmarksFor(_siteUrl).reminders.single.read, isTrue);
  });

  test(
    'a failed read write lets a later response restore unread state',
    () async {
      final api = _FailedReadApi();
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      final controller = _controller(api, credentials);
      addTearDown(controller.dispose);
      final connected = _connectedInstance();
      await Future.wait([
        controller.loadNotifications(connected),
        controller.loadReplyNotifications(connected),
        controller.loadChatNotifications(connected),
        controller.loadBookmarks(connected),
      ]);

      controller.readNotification(connected, _notification);
      await api.failed.future;
      await pumpEventQueue();
      await Future.wait([
        controller.loadNotifications(connected),
        controller.loadReplyNotifications(connected),
        controller.loadChatNotifications(connected),
        controller.loadBookmarks(connected),
      ]);

      expect(
        controller.notificationsFor(_siteUrl).notifications.single.isUnread,
        isTrue,
      );
      expect(
        controller
            .replyNotificationsFor(_siteUrl)
            .notifications
            .single
            .isUnread,
        isTrue,
      );
      expect(
        controller.chatNotificationsFor(_siteUrl).notifications.single.isUnread,
        isTrue,
      );
      expect(
        controller.bookmarksFor(_siteUrl).reminders.single.isUnread,
        isTrue,
      );
    },
  );

  test('reading only rebuilds feeds that contain the notification', () async {
    final api = _AccountApi(
      notificationList: const [_notification],
      replyNotificationList: const [_notification],
      chatNotificationList: const [_chatNotification],
      bookmarkList: const [_bookmark],
      reminderList: const [_reminder],
    );
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
    final controller = _controller(api, credentials);
    addTearDown(controller.dispose);
    final connected = _connectedInstance();
    await controller.loadNotifications(connected);
    await controller.loadReplyNotifications(connected);
    await controller.loadChatNotifications(connected);
    await controller.loadBookmarks(connected);

    var notificationChanges = 0;
    var replyNotificationChanges = 0;
    var chatNotificationChanges = 0;
    var bookmarkChanges = 0;
    controller.notificationsListenable.addListener(() => notificationChanges++);
    controller.replyNotificationsListenable.addListener(
      () => replyNotificationChanges++,
    );
    controller.chatNotificationsListenable.addListener(
      () => chatNotificationChanges++,
    );
    controller.bookmarksListenable.addListener(() => bookmarkChanges++);

    controller.readNotification(connected, _notification);

    expect(notificationChanges, 1);
    expect(replyNotificationChanges, 1);
    expect(chatNotificationChanges, 0);
    expect(bookmarkChanges, 0);

    notificationChanges = 0;
    replyNotificationChanges = 0;
    chatNotificationChanges = 0;
    controller.readNotification(connected, _reminder);

    expect(notificationChanges, 0);
    expect(replyNotificationChanges, 0);
    expect(chatNotificationChanges, 0);
    expect(bookmarkChanges, 1);

    notificationChanges = 0;
    replyNotificationChanges = 0;
    chatNotificationChanges = 0;
    bookmarkChanges = 0;
    controller.readNotification(connected, _chatNotification);

    expect(notificationChanges, 0);
    expect(replyNotificationChanges, 0);
    expect(chatNotificationChanges, 1);
    expect(bookmarkChanges, 0);
    await Future<void>.delayed(Duration.zero);
    expect(api.markedRead, [11, 12, 14]);
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

  test(
    'a filtered response from a forgotten account cannot repopulate replies',
    () async {
      final gate = Completer<void>();
      final api = _GatedNotificationsApi(gate);
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      final lifecycle = SiteLifecycle();
      final controller = _controller(api, credentials, lifecycle: lifecycle);
      addTearDown(controller.dispose);

      final loading = controller.loadReplyNotifications(_connectedInstance());
      await Future<void>.delayed(Duration.zero);
      lifecycle.invalidate(_siteUrl);
      controller.forget(_siteUrl);
      gate.complete();
      await loading;

      expect(controller.replyNotificationsFor(_siteUrl).loaded, isFalse);
    },
  );

  test(
    'a filtered response from a forgotten account cannot repopulate chat',
    () async {
      final gate = Completer<void>();
      final api = _GatedNotificationsApi(gate);
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      final lifecycle = SiteLifecycle();
      final controller = _controller(api, credentials, lifecycle: lifecycle);
      addTearDown(controller.dispose);

      final loading = controller.loadChatNotifications(_connectedInstance());
      await Future<void>.delayed(Duration.zero);
      lifecycle.invalidate(_siteUrl);
      controller.forget(_siteUrl);
      gate.complete();
      await loading;

      expect(controller.chatNotificationsFor(_siteUrl).loaded, isFalse);
    },
  );

  test(
    'a late forgotten load cannot detach replacement load waiters',
    () async {
      final api = _SequencedNotificationsApi(2);
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'key';
      final lifecycle = SiteLifecycle();
      final controller = _controller(api, credentials, lifecycle: lifecycle);
      addTearDown(controller.dispose);
      final connected = _connectedInstance();

      final forgotten = controller.loadNotifications(connected);
      await api.started[0].future;
      lifecycle.invalidate(_siteUrl);
      controller.forget(_siteUrl);

      final replacement = controller.loadNotifications(connected);
      await api.started[1].future;
      api.gates[0].complete();
      await forgotten;

      final joinedReplacement = controller.loadNotifications(connected);
      expect(joinedReplacement, same(replacement));
      expect(api.calls, 2);

      api.gates[1].complete();
      await Future.wait([replacement, joinedReplacement]);
      expect(controller.notificationsFor(_siteUrl).loaded, isTrue);
    },
  );

  for (final activity
      in <
        ({
          String name,
          Future<void> Function(
            AccountActivityController controller,
            DiscourseInstance instance,
          )
          begin,
        })
      >[
        (
          name: 'totals request',
          begin: (controller, instance) async {
            await controller.refresh(instance);
          },
        ),
        (
          name: 'notification request',
          begin: (controller, instance) =>
              controller.loadNotifications(instance),
        ),
        (
          name: 'reply notification request',
          begin: (controller, instance) =>
              controller.loadReplyNotifications(instance),
        ),
        (
          name: 'chat notification request',
          begin: (controller, instance) =>
              controller.loadChatNotifications(instance),
        ),
        (
          name: 'bookmark request',
          begin: (controller, instance) => controller.loadBookmarks(instance),
        ),
        (
          name: 'mark-read request',
          begin: (controller, instance) async {
            controller.readNotification(instance, _notification);
          },
        ),
      ]) {
    test(
      'forget during credential lookup prevents stale ${activity.name}',
      () async {
        final api = _CountingAccountApi();
        final credentials = _GatedCredentialReader();
        final controller = _controller(api, credentials);
        addTearDown(controller.dispose);

        final operation = activity.begin(controller, _connectedInstance());
        await credentials.started.future;
        controller.forget(_siteUrl);
        credentials.result.complete('stale-key');
        await operation;
        await pumpEventQueue();

        expect(api.calls, isEmpty);
      },
    );
  }
}

final class _GatedCredentialReader extends FakeApiCredentialReader {
  final Completer<void> started = Completer<void>();
  final Completer<String?> result = Completer<String?>();

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

final class _CountingAccountApi extends _AccountApi {
  final List<String> calls = [];

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    calls.add('totals');
    return const NotificationTotals();
  }

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationKind> filterByTypes = const [],
    String? clientId,
  }) async {
    calls.add(switch (_notificationFeedKind(filterByTypes)) {
      _NotificationFeedKind.all => 'notifications',
      _NotificationFeedKind.replies => 'reply-notifications',
      _NotificationFeedKind.chat => 'chat-notifications',
    });
    return const [];
  }

  @override
  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    calls.add('bookmarks');
    return (
      reminders: const <DiscourseNotification>[],
      bookmarks: const <Bookmark>[],
    );
  }

  @override
  Future<void> markNotificationRead({
    required String siteUrl,
    required String apiKey,
    required int id,
    String? clientId,
  }) async {
    calls.add('mark-read');
  }
}

final class _GatedNotificationsApi extends _AccountApi {
  _GatedNotificationsApi(this._notificationGate);

  final Completer<void> _notificationGate;
  int calls = 0;
  final List<List<NotificationKind>> filters = [];

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationKind> filterByTypes = const [],
    String? clientId,
  }) async {
    calls++;
    filters.add(List.unmodifiable(filterByTypes));
    await _notificationGate.future;
    return const [_notification];
  }
}

final class _SequencedNotificationsApi extends _AccountApi {
  _SequencedNotificationsApi(int count)
    : gates = List.generate(count, (_) => Completer<void>()),
      started = List.generate(count, (_) => Completer<void>());

  final List<Completer<void>> gates;
  final List<Completer<void>> started;
  int calls = 0;

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationKind> filterByTypes = const [],
    String? clientId,
  }) async {
    final call = calls++;
    started[call].complete();
    await gates[call].future;
    return const [_notification];
  }
}

final class _SequencedBookmarksApi extends _AccountApi {
  _SequencedBookmarksApi(int count)
    : answers = List.generate(count, (_) => Completer<BookmarkPayload>()),
      started = List.generate(count, (_) => Completer<void>());

  final List<Completer<BookmarkPayload>> answers;
  final List<Completer<void>> started;
  int calls = 0;

  @override
  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) {
    final call = calls++;
    started[call].complete();
    return answers[call].future;
  }
}

final class _GatedActivityRefreshApi extends _AccountApi {
  _GatedActivityRefreshApi()
    : super(
        totals: const NotificationTotals(),
        bookmarkList: const [_bookmark],
      );

  final Completer<void> notificationsRefreshStarted = Completer<void>();
  final Completer<void> repliesRefreshStarted = Completer<void>();
  final Completer<void> chatRefreshStarted = Completer<void>();
  final Completer<void> bookmarksRefreshStarted = Completer<void>();
  final Completer<void> notificationsRefresh = Completer<void>();
  final Completer<void> repliesRefresh = Completer<void>();
  final Completer<void> chatRefresh = Completer<void>();
  final Completer<void> bookmarksRefresh = Completer<void>();
  int _notificationCalls = 0;
  int _replyCalls = 0;
  int _chatCalls = 0;
  int _bookmarkCalls = 0;

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationKind> filterByTypes = const [],
    String? clientId,
  }) async {
    final kind = _notificationFeedKind(filterByTypes);
    final call = switch (kind) {
      _NotificationFeedKind.all => ++_notificationCalls,
      _NotificationFeedKind.replies => ++_replyCalls,
      _NotificationFeedKind.chat => ++_chatCalls,
    };
    if (call == 2) {
      final (started, refresh) = switch (kind) {
        _NotificationFeedKind.all => (
          notificationsRefreshStarted,
          notificationsRefresh,
        ),
        _NotificationFeedKind.replies => (
          repliesRefreshStarted,
          repliesRefresh,
        ),
        _NotificationFeedKind.chat => (chatRefreshStarted, chatRefresh),
      };
      started.complete();
      await refresh.future;
    }
    return const [_notification];
  }

  @override
  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    if (++_bookmarkCalls == 2) {
      bookmarksRefreshStarted.complete();
      await bookmarksRefresh.future;
    }
    return (reminders: const [_notification], bookmarks: const [_bookmark]);
  }
}

final class _FailedReadApi extends _AccountApi {
  _FailedReadApi()
    : super(
        notificationList: const [_notification],
        replyNotificationList: const [_notification],
        chatNotificationList: const [_notification],
        bookmarkList: const [_bookmark],
        reminderList: const [_notification],
      );

  final Completer<void> failed = Completer<void>();

  @override
  Future<void> markNotificationRead({
    required String siteUrl,
    required String apiKey,
    required int id,
    String? clientId,
  }) async {
    if (!failed.isCompleted) failed.complete();
    throw StateError('write failed');
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
