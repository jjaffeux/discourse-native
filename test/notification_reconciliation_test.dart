import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/bookmark_feed.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_feed.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/shell/notification_reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://example.com';
const _type = NotificationTypeId(2);
const _wireType = NotificationWireType(2, 'replied');
const _row = DiscourseNotification.test(id: 1, typeId: _type);

void main() {
  test('a registered extra feed joins read, rollback and dismissal', () {
    final fixture = _Fixture();
    final main = fixture.slot('main');
    fixture.owner.publish(main, const NotificationFeed.of([_row]));
    final extra = fixture.slot('extra');
    fixture.owner.publish(extra, const NotificationFeed.of([_row]));
    fixture.changes.clear();

    final reading = fixture.owner.beginRead(_row)!;
    expect(fixture.owner.feed(main).notifications.single.read, isTrue);
    expect(fixture.owner.feed(extra).notifications.single.read, isTrue);
    expect(fixture.changes, ['main', 'extra', 'owner']);
    fixture.changes.clear();
    fixture.owner.failRead(reading);
    expect(fixture.owner.feed(extra).notifications.single.read, isFalse);
    expect(fixture.changes, ['main', 'extra', 'owner']);

    final dismissal = fixture.owner.beginDismiss(
      types: [_wireType],
      source: main,
    )!;
    fixture.owner.confirmDismiss(dismissal);
    expect(fixture.owner.feed(extra).notifications.single.read, isTrue);
    expect(fixture.authorityBoundaries, 3);
  });

  test('reminders retain their whole snapshot and overlay late pins', () {
    final fixture = _Fixture();
    final reminders = NotificationFeedSlot.reminders(
      () => fixture.changes.add('reminders'),
    );
    const first = BookmarkFeed(reminders: [_row], loading: true, error: 'held');
    fixture.owner.publish(reminders, first);
    expect(fixture.owner.feed(reminders), same(first));
    final attempt = fixture.owner.beginRead(_row)!;
    final read = fixture.owner.feed(reminders);
    expect(read.reminders.single.read, isTrue);
    expect(read.bookmarks, same(first.bookmarks));
    expect(read.loading, isTrue);
    expect(read.error, 'held');
    fixture.owner.confirmRead(attempt);
    fixture.owner.publish(reminders, first);
    expect(fixture.owner.feed(reminders).reminders.single.read, isTrue);
    expect(fixture.authorityBoundaries, 2);
  });

  test(
    'same ID preserves each feed payload and duplicate transform semantics',
    () {
      final fixture = _Fixture();
      final first = fixture.slot('first');
      final second = fixture.slot('second');
      final firstRow = DiscourseNotification.fromJson(const {
        'id': 1,
        'notification_type': 2,
        'read': false,
        'custom': {'source': 'first'},
        'data': {'name': 'one'},
      });
      final secondRow = DiscourseNotification.fromJson(const {
        'id': 1,
        'notification_type': 2,
        'read': false,
        'custom': {'source': 'second'},
        'data': {'name': 'two'},
      });
      fixture.owner.publish(first, NotificationFeed.of([firstRow, firstRow]));
      fixture.owner.publish(second, NotificationFeed.of([secondRow]));
      final attempt = fixture.owner.beginRead(firstRow)!;
      expect(fixture.owner.feed(first).notifications.map((row) => row.read), [
        true,
        false,
      ]);
      expect(fixture.owner.feed(first).notifications.first.wire['custom'], {
        'source': 'first',
      });
      expect(
        fixture.owner.feed(second).notifications.single.data['name'],
        'two',
      );
      fixture.owner.failRead(attempt);
      expect(fixture.owner.feed(second).notifications.single.wire['custom'], {
        'source': 'second',
      });
      expect(fixture.owner.feed(first).notifications.map((row) => row.read), [
        false,
        false,
      ]);
    },
  );

  test('dismissal freezes coverage including already optimistic rows', () {
    final fixture = _Fixture();
    final feed = fixture.slot('feed');
    fixture.owner.publish(feed, const NotificationFeed.of([_row]));
    final reading = fixture.owner.beginRead(_row)!;
    final dismissal = fixture.owner.beginDismiss(
      types: [_wireType],
      source: feed,
    )!;
    fixture.owner.failRead(reading);
    const arrived = DiscourseNotification.test(id: 2, typeId: _type);
    fixture.owner.publish(feed, const NotificationFeed.of([_row, arrived]));
    fixture.owner.confirmDismiss(dismissal);
    expect(fixture.owner.feed(feed).notifications.map((row) => row.read), [
      true,
      false,
    ]);
    final readingNew = fixture.owner.beginRead(arrived)!;
    fixture.owner.failRead(readingNew);
    expect(fixture.owner.feed(feed).notifications.last.read, isFalse);
  });

  test('bulk dismissal changes the first eligible duplicate in each feed', () {
    final fixture = _Fixture();
    final feed = fixture.slot('feed');
    final reminders = NotificationFeedSlot.reminders(
      () => fixture.changes.add('reminders'),
    );
    const second = DiscourseNotification.test(id: 2, typeId: _type);
    const third = DiscourseNotification.test(id: 3, typeId: _type);
    const unrelated = DiscourseNotification.test(
      id: 9,
      typeId: NotificationTypeId(99),
      read: true,
    );
    final alreadyRead = _row.asRead();
    final thirdRead = third.asRead();
    final rows = [alreadyRead, _row, _row, second, thirdRead, unrelated];
    final original = NotificationFeed(
      notifications: rows,
      loading: true,
      loaded: true,
      error: 'held notifications',
    );
    final originalReminders = BookmarkFeed(
      reminders: rows,
      bookmarks: const [Bookmark(id: 42, title: 'Held bookmark')],
      loading: true,
      loaded: true,
      error: 'held reminders',
    );
    fixture.owner.publish(feed, original);
    fixture.owner.publish(reminders, originalReminders);
    fixture.changes.clear();

    final dismissal = fixture.owner.beginDismiss(types: [_wireType])!;
    fixture.owner.confirmDismiss(dismissal);

    final updated = fixture.owner.feed(feed);
    final updatedReminders = fixture.owner.feed(reminders);
    for (final projected in [
      updated.notifications,
      updatedReminders.reminders,
    ]) {
      expect(projected.map((row) => row.read), [
        true,
        true,
        false,
        true,
        true,
        true,
      ]);
      expect(projected[0], same(alreadyRead));
      expect(projected[2], same(_row));
      expect(projected[4], same(thirdRead));
      expect(projected[5], same(unrelated));
    }
    expect(rows[1].read, isFalse);
    expect(rows[3].read, isFalse);
    expect(updated.loading, isTrue);
    expect(updated.loaded, isTrue);
    expect(updated.error, 'held notifications');
    expect(updatedReminders.bookmarks, same(originalReminders.bookmarks));
    expect(updatedReminders.loading, isTrue);
    expect(updatedReminders.loaded, isTrue);
    expect(updatedReminders.error, 'held reminders');
    expect(fixture.changes, ['feed', 'reminders', 'owner']);

    fixture.owner.publish(feed, original);
    fixture.owner.publish(reminders, originalReminders);
    expect(fixture.owner.feed(feed).notifications.map((row) => row.read), [
      true,
      true,
      true,
      true,
      true,
      true,
    ]);
    expect(fixture.owner.feed(reminders).reminders.map((row) => row.read), [
      true,
      true,
      true,
      true,
      true,
      true,
    ]);
  });

  test('bulk dismissal retains snapshots for already read and missing IDs', () {
    final fixture = _Fixture();
    final source = fixture.slot('source');
    final extra = fixture.slot('extra');
    final reminders = NotificationFeedSlot.reminders(
      () => fixture.changes.add('reminders'),
    );
    const second = DiscourseNotification.test(id: 2, typeId: _type);
    const unrelated = DiscourseNotification.test(
      id: 9,
      typeId: NotificationTypeId(99),
    );
    fixture.owner.publish(source, const NotificationFeed.of([_row, second]));
    final dismissal = fixture.owner.beginDismiss(types: [_wireType])!;
    const empty = NotificationFeed();
    final alreadyRead = NotificationFeed.of([_row.asRead(), unrelated]);
    const missing = BookmarkFeed(reminders: [unrelated]);
    fixture.owner.publish(source, empty);
    fixture.owner.publish(extra, alreadyRead);
    fixture.owner.publish(reminders, missing);
    fixture.changes.clear();

    fixture.owner.confirmDismiss(dismissal);

    expect(fixture.owner.feed(source), same(empty));
    expect(fixture.owner.feed(extra), same(alreadyRead));
    expect(fixture.owner.feed(reminders), same(missing));
    expect(fixture.changes, isEmpty);
  });

  test(
    'bulk dismissal keeps newer arrivals unread after a late read failure',
    () {
      final fixture = _Fixture();
      final feed = fixture.slot('feed');
      const second = DiscourseNotification.test(id: 2, typeId: _type);
      const arrived = DiscourseNotification.test(id: 3, typeId: _type);
      fixture.owner.publish(feed, const NotificationFeed.of([_row, second]));
      final reading = fixture.owner.beginRead(_row)!;
      final dismissal = fixture.owner.beginDismiss(types: [_wireType])!;
      fixture.owner.publish(
        feed,
        const NotificationFeed.of([_row, second, arrived]),
      );

      fixture.owner.confirmDismiss(dismissal);
      fixture.owner.failRead(reading);

      expect(fixture.owner.feed(feed).notifications.map((row) => row.read), [
        true,
        true,
        false,
      ]);
    },
  );

  test(
    'trusted source covers rows with missing type names and other wire IDs',
    () {
      final fixture = _Fixture();
      final source = fixture.slot('source');
      final extra = fixture.slot('extra');
      const unknown = DiscourseNotification.test(
        id: 8,
        typeId: NotificationTypeId(99),
      );
      fixture.owner.publish(source, const NotificationFeed.of([unknown]));
      fixture.owner.publish(extra, const NotificationFeed.of([unknown, _row]));
      final ticket = fixture.owner.beginDismiss(
        types: [_wireType],
        source: source,
      )!;
      fixture.owner.confirmDismiss(ticket);
      expect(
        fixture.owner.feed(extra).notifications.every((row) => row.read),
        isTrue,
      );
    },
  );

  test(
    'equal grouped confirmations stop count rollback but not row rollback',
    () {
      final fixture = _Fixture();
      final feed = fixture.slot('feed');
      fixture.owner.publish(feed, const NotificationFeed.of([_row]));
      fixture.owner.applyGroupedSnapshot(
        NotificationTypeCounts.fromWire(const {'2': 2}),
      );
      final reading = fixture.owner.beginRead(_row)!;
      expect(_count(fixture.owner), 1);
      final totals = fixture.owner.beginTotalsRefresh();
      fixture.owner.acceptTotalsRefresh(
        totals,
        NotificationTotals(
          groupedUnreadNotifications: NotificationTypeCounts.fromWire(const {
            '2': 1,
          }),
        ),
      );
      fixture.owner.failRead(reading);
      expect(_count(fixture.owner), 1);
      expect(fixture.owner.feed(feed).notifications.single.read, isFalse);
    },
  );

  test(
    'unavailable grouped totals leave rollback and confirmed counts intact',
    () {
      final fixture = _Fixture();
      fixture.owner.applyGroupedSnapshot(
        NotificationTypeCounts.fromWire(const {'2': 2}),
      );
      final reading = fixture.owner.beginRead(_row)!;
      final totals = fixture.owner.beginTotalsRefresh();
      fixture.owner.acceptTotalsRefresh(totals, const NotificationTotals());
      fixture.owner.failRead(reading);
      expect(_count(fixture.owner), 2);
    },
  );

  test('foreign and retired tickets cannot mutate a replacement owner', () {
    final lifecycle = SiteLifecycle();
    final first = _Fixture(lifecycle: lifecycle);
    final firstFeed = first.slot('first');
    first.owner.publish(firstFeed, const NotificationFeed.of([_row]));
    final read = first.owner.beginRead(_row)!;
    final dismissal = first.owner.beginDismiss(types: [_wireType])!;
    final totals = first.owner.beginTotalsRefresh();
    final second = _Fixture(lifecycle: lifecycle);
    final secondFeed = second.slot('second');
    second.owner.publish(secondFeed, const NotificationFeed.of([_row]));
    second.changes.clear();
    second.owner.failRead(read);
    second.owner.confirmRead(read);
    second.owner.confirmDismiss(dismissal);
    expect(
      second.owner.acceptTotalsRefresh(
        totals,
        const NotificationTotals(unreadNotifications: 9),
      ),
      isNull,
    );
    expect(second.owner.feed(secondFeed).notifications.single.read, isFalse);
    expect(second.changes, isEmpty);
    lifecycle.invalidate(_site);
    first.owner.failRead(read);
    first.owner.confirmDismiss(dismissal);
    expect(
      first.owner.acceptTotalsRefresh(totals, const NotificationTotals()),
      isNull,
    );
    expect(first.owner.beginRead(_row), isNull);
    expect(first.owner.beginDismiss(types: [_wireType]), isNull);
  });

  test(
    'read publishes coherent totals and rows before any aspect callback',
    () {
      final fixture = _Fixture();
      final feed = fixture.slot('feed');
      fixture.owner.publish(feed, const NotificationFeed.of([_row]));
      fixture.owner.applyGroupedSnapshot(
        NotificationTypeCounts.fromWire(const {'2': 2}),
      );
      fixture.onTotals = (_) {
        expect(_count(fixture.owner), 1);
        expect(fixture.owner.feed(feed).notifications.single.read, isTrue);
      };
      fixture.owner.beginRead(_row);
    },
  );

  test('retirement during an aspect stops the remaining callback batch', () {
    final fixture = _Fixture();
    var retire = false;
    late NotificationFeedSlot<NotificationFeed> other;
    final first = NotificationFeedSlot.notifications(() {
      fixture.changes.add('first');
      if (retire) {
        expect(fixture.owner.feed(other).notifications.single.read, isTrue);
        fixture.owner.retire();
      }
    });
    other = fixture.slot('other');
    fixture.owner.publish(first, const NotificationFeed.of([_row]));
    fixture.owner.publish(other, const NotificationFeed.of([_row]));
    fixture.changes.clear();
    retire = true;
    fixture.owner.beginRead(_row);
    expect(fixture.changes, ['first']);
    expect(fixture.owner.beginRead(_row), isNull);
  });

  test('reentrant publications queue and retirement stops old dispatch', () {
    final fixture = _Fixture();
    var reentered = false;
    late NotificationFeedSlot<NotificationFeed> feed;
    feed = NotificationFeedSlot.notifications(() {
      fixture.changes.add('feed');
      if (!reentered) {
        reentered = true;
        fixture.owner.publish(feed, const NotificationFeed.of([_row]));
      }
    });
    fixture.owner.publish(feed, const NotificationFeed());
    expect(fixture.changes, ['feed', 'owner', 'feed', 'owner']);
    fixture.changes.clear();
    final other = fixture.slot('other');
    fixture.owner.publish(other, const NotificationFeed.of([_row]));
    fixture.changes.clear();
    fixture.onTotals = (_) => fixture.owner.retire();
    fixture.owner.applyGroupedSnapshot(
      NotificationTypeCounts.fromWire(const {'2': 1}),
    );
    expect(fixture.changes, isEmpty);
  });
}

int? _count(NotificationReconciliation owner) =>
    owner.totals?.groupedUnreadNotifications.toJson()?['2'] ?? 0;

final class _Fixture {
  _Fixture({SiteLifecycle? lifecycle}) {
    owner = NotificationReconciliation(
      lease: (lifecycle ?? SiteLifecycle()).capture(_site),
      totalsChanged: (totals) => onTotals?.call(totals),
      totalsAspectChanged: () => changes.add('totals'),
      changed: () => changes.add('owner'),
      groupedUnreadAuthorityAdvanced: () => authorityBoundaries++,
    );
  }

  late final NotificationReconciliation owner;
  final List<String> changes = [];
  int authorityBoundaries = 0;
  void Function(NotificationTotals)? onTotals;

  NotificationFeedSlot<NotificationFeed> slot(String name) =>
      NotificationFeedSlot.notifications(() => changes.add(name));
}
