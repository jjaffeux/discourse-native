import 'package:discourse_native/src/data/topic_tracking_reconciler.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _row = TrackedTopicState(
  topicId: 7,
  highestPostNumber: 100,
  lastReadPostNumber: 80,
  notificationLevel: 2,
  categoryId: 5,
  tagIds: {9},
);

Map<String, Object?> _newTopic(int id, {int category = 5}) => {
  'message_type': 'new_topic',
  'topic_id': id,
  'payload': {
    'highest_post_number': 1,
    'created_in_new_period': true,
    'category_id': category,
  },
};

void main() {
  test('report started before a full read cannot supersede its preference', () {
    final tracking = TopicTrackingReconciler();
    tracking.completeSnapshot(
      tracking.beginSnapshot()!,
      TopicTrackingState([_row]),
    );
    final report = tracking.beginSnapshot()!;
    final read = tracking.beginNotificationRead(7);
    tracking.completeSnapshot(report, TopicTrackingState([_row]));
    expect(
      read.reconcile(TopicNotificationLevel.normal),
      TopicNotificationLevel.normal,
    );
    expect(tracking.notificationLevel(7), TopicNotificationLevel.normal);
  });

  for (final seeded in [false, true]) {
    test('accepted tracking preference fences topic read, seeded=$seeded', () {
      final tracking = TopicTrackingReconciler();
      if (seeded) {
        tracking.completeSnapshot(
          tracking.beginSnapshot()!,
          TopicTrackingState([_row]),
        );
      }
      final read = tracking.beginNotificationRead(7);
      tracking.accept(const {
        'topic_id': 7,
        'message_type': 'notification_level_change',
        'payload': {'notification_level': 3},
      });
      expect(
        read.reconcile(TopicNotificationLevel.normal),
        TopicNotificationLevel.watching,
      );
      expect(tracking.notificationLevel(7), TopicNotificationLevel.watching);
      expect(tracking.topic(7)?.notificationLevel, seeded ? 3 : isNull);
    });
  }

  test('accepted tracking preference updates pending rollback baseline', () {
    final tracking = TopicTrackingReconciler();
    final choice = tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.watching,
      confirmed: TopicNotificationLevel.tracking,
    );
    final read = tracking.beginNotificationRead(7);
    tracking.accept(const {
      'topic_id': 7,
      'message_type': 'notification_level_change',
      'payload': {'notification_level': 1},
    });
    expect(
      read.reconcile(TopicNotificationLevel.muted),
      TopicNotificationLevel.watching,
    );
    expect(
      tracking.settleNotificationLevel(choice, succeeded: false),
      TopicNotificationLevel.normal,
    );
  });

  for (final seeded in [false, true]) {
    test(
      'notification reads preserve settlement without pinning, seeded=$seeded',
      () {
        final tracking = TopicTrackingReconciler();
        if (seeded) {
          tracking.completeSnapshot(
            tracking.beginSnapshot()!,
            TopicTrackingState([_row]),
          );
        }
        final older = tracking.beginNotificationRead(7);
        final choice = tracking.chooseNotificationLevel(
          7,
          TopicNotificationLevel.watching,
          confirmed: TopicNotificationLevel.tracking,
        );
        tracking.settleNotificationLevel(choice, succeeded: true);
        tracking.releaseNotificationChoice(choice);
        expect(
          older.reconcile(TopicNotificationLevel.tracking),
          TopicNotificationLevel.watching,
        );
        expect(tracking.notificationLevel(7), TopicNotificationLevel.watching);
        final fresh = tracking.beginNotificationRead(7);
        expect(
          fresh.reconcile(TopicNotificationLevel.normal),
          TopicNotificationLevel.normal,
        );
        expect(tracking.notificationLevel(7), TopicNotificationLevel.normal);
        expect(tracking.topic(7)?.notificationLevel, seeded ? 1 : isNull);
        if (seeded) {
          expect(tracking.topic(7)?.lastReadPostNumber, 80);
          expect(tracking.topic(7)?.highestPostNumber, 100);
          expect(tracking.topic(7)?.categoryId, 5);
          expect(tracking.topic(7)?.tagIds, {9});
        }
      },
    );
  }

  for (final fresh in [false, true]) {
    test(
      'only a fresh pending read can update rollback baseline, fresh=$fresh',
      () {
        final tracking = TopicTrackingReconciler();
        final older = tracking.beginNotificationRead(7);
        final choice = tracking.chooseNotificationLevel(
          7,
          TopicNotificationLevel.watching,
          confirmed: TopicNotificationLevel.tracking,
        );
        final read = fresh ? tracking.beginNotificationRead(7) : older;
        expect(
          read.reconcile(TopicNotificationLevel.normal),
          TopicNotificationLevel.watching,
        );
        expect(
          tracking.settleNotificationLevel(choice, succeeded: false),
          fresh
              ? TopicNotificationLevel.normal
              : TopicNotificationLevel.tracking,
        );
      },
    );
  }

  test('older serialized success fences pending read baseline', () {
    final tracking = TopicTrackingReconciler();
    final first = tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.muted,
      confirmed: TopicNotificationLevel.tracking,
    );
    final latest = tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.watching,
      confirmed: TopicNotificationLevel.muted,
    );
    final older = tracking.beginNotificationRead(7);
    expect(tracking.settleNotificationLevel(first, succeeded: true), isNull);
    expect(
      older.reconcile(TopicNotificationLevel.normal),
      TopicNotificationLevel.watching,
    );
    expect(
      tracking.settleNotificationLevel(latest, succeeded: false),
      TopicNotificationLevel.muted,
    );
  });

  test(
    'live observation fences an older pending read and supplies rollback',
    () {
      final tracking = TopicTrackingReconciler();
      final choice = tracking.chooseNotificationLevel(
        7,
        TopicNotificationLevel.watching,
        confirmed: TopicNotificationLevel.tracking,
      );
      final older = tracking.beginNotificationRead(7);
      tracking.observeNotificationLevel(7, TopicNotificationLevel.normal);
      expect(
        older.reconcile(TopicNotificationLevel.muted),
        TopicNotificationLevel.watching,
      );
      expect(
        tracking.settleNotificationLevel(choice, succeeded: false),
        TopicNotificationLevel.normal,
      );
    },
  );

  test(
    'read completion and unrelated activity do not supersede another read',
    () {
      final tracking = TopicTrackingReconciler();
      tracking.completeSnapshot(
        tracking.beginSnapshot()!,
        TopicTrackingState([_row]),
      );
      final first = tracking.beginNotificationRead(7);
      final later = tracking.beginNotificationRead(7);
      tracking.markRead(7, 95);
      tracking.observeNotificationLevel(8, TopicNotificationLevel.watching);
      expect(
        first.reconcile(TopicNotificationLevel.watching),
        TopicNotificationLevel.watching,
      );
      expect(
        later.reconcile(TopicNotificationLevel.normal),
        TopicNotificationLevel.normal,
      );
      expect(tracking.topic(7)?.lastReadPostNumber, 95);
    },
  );

  test(
    'fresh detail preference is replayed over an in-flight tracking report',
    () {
      final tracking = TopicTrackingReconciler();
      tracking.completeSnapshot(
        tracking.beginSnapshot()!,
        TopicTrackingState([_row]),
      );
      final report = tracking.beginSnapshot()!;
      final read = tracking.beginNotificationRead(7);
      expect(
        read.reconcile(TopicNotificationLevel.normal),
        TopicNotificationLevel.normal,
      );
      tracking.completeSnapshot(report, TopicTrackingState([_row]));
      expect(tracking.topic(7)?.notificationLevel, 1);
    },
  );

  test(
    'a later report replaces retained preference without resurrecting rows',
    () {
      final tracking = TopicTrackingReconciler();
      tracking.observeNotificationLevel(7, TopicNotificationLevel.watching);
      tracking.completeSnapshot(
        tracking.beginSnapshot()!,
        TopicTrackingState([_row]),
      );
      tracking.completeSnapshot(
        tracking.beginSnapshot()!,
        TopicTrackingState([_row.copyWith(notificationLevel: 1)]),
      );
      expect(tracking.notificationLevel(7), TopicNotificationLevel.normal);
      tracking.completeSnapshot(
        tracking.beginSnapshot()!,
        TopicTrackingState(),
      );
      expect(tracking.notificationLevel(7), TopicNotificationLevel.normal);
      expect(tracking.topic(7)?.notificationLevel, 1);
      tracking.observeNotificationLevel(8, TopicNotificationLevel.watching);
      tracking.completeSnapshot(
        tracking.beginSnapshot()!,
        TopicTrackingState(),
      );
      expect(tracking.notificationLevel(8), TopicNotificationLevel.watching);
      expect(tracking.topic(8), isNull);
    },
  );

  test('retired notification tickets cannot mutate a replacement account', () {
    final tracking = TopicTrackingReconciler();
    final read = tracking.beginNotificationRead(7);
    tracking.retire();
    final successor = TopicTrackingReconciler();
    successor.observeNotificationLevel(7, TopicNotificationLevel.watching);
    expect(read.isCurrent, isFalse);
    expect(read.reconcile(TopicNotificationLevel.normal), isNull);
    expect(successor.notificationLevel(7), TopicNotificationLevel.watching);
  });

  test('delayed report replays events, reads, then pending choice', () {
    final tracking = TopicTrackingReconciler();
    final load = tracking.beginSnapshot()!;
    tracking.accept(const {
      'topic_id': 7,
      'message_type': 'read',
      'payload': {
        'highest_post_number': 110,
        'last_read_post_number': 90,
        'notification_level': 2,
        'category_id': 6,
        'tags': [
          {'id': 10},
        ],
      },
    });
    tracking.markRead(7, 105);
    final choice = tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.normal,
      confirmed: TopicNotificationLevel.tracking,
    );
    expect(tracking.completeSnapshot(load, TopicTrackingState([_row])), isTrue);
    final row = tracking.topic(7)!;
    expect(row.highestPostNumber, 110);
    expect(row.lastReadPostNumber, 105);
    expect(row.categoryId, 6);
    expect(row.tagIds, {10});
    expect(row.notificationLevel, 1);
    expect(tracking.newActivityCounts.newReplies, 0);
    expect(
      tracking.settleNotificationLevel(choice, succeeded: false),
      TopicNotificationLevel.tracking,
    );
    expect(tracking.topic(7)?.lastReadPostNumber, 105);
    expect(tracking.topic(7)?.highestPostNumber, 110);
    expect(tracking.newActivityCounts.newReplies, 1);
  });

  test('local reads before a row exists remain an overlay after report', () {
    final tracking = TopicTrackingReconciler();
    tracking.markRead(7, 100);
    final load = tracking.beginSnapshot()!;
    tracking.completeSnapshot(load, TopicTrackingState([_row]));
    expect(tracking.topic(7)?.lastReadPostNumber, 100);
    tracking.accept(const {
      'topic_id': 7,
      'message_type': 'unread',
      'payload': {'highest_post_number': 101, 'last_read_post_number': 80},
    });
    expect(tracking.topic(7)?.lastReadPostNumber, 100);
    expect(tracking.newActivityCounts.newReplies, 1);
  });

  test('completed choices survive delayed bootstrap after queue release', () {
    final tracking = TopicTrackingReconciler();
    final bootstrap = tracking.beginBootstrap();
    final choice = tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.normal,
      confirmed: TopicNotificationLevel.tracking,
    );
    tracking.settleNotificationLevel(choice, succeeded: true);
    tracking.releaseNotificationChoice(choice);
    expect(
      tracking.completeBootstrap(bootstrap, TopicTrackingState([_row])),
      isTrue,
    );
    expect(tracking.topic(7)?.notificationLevel, 1);
    expect(tracking.hasSnapshot, isTrue);
    expect(tracking.phase, TopicTrackingPhase.live);
  });

  test('older success and echoes update rollback without settling newest', () {
    final tracking = TopicTrackingReconciler();
    tracking.completeSnapshot(
      tracking.beginSnapshot()!,
      TopicTrackingState([_row]),
    );
    final first = tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.muted,
      confirmed: TopicNotificationLevel.tracking,
    );
    final latest = tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.watching,
      confirmed: TopicNotificationLevel.muted,
    );
    expect(tracking.settleNotificationLevel(first, succeeded: true), isNull);
    tracking.releaseNotificationChoice(first);
    expect(tracking.topic(7)?.notificationLevel, 3);
    expect(
      tracking.observeNotificationLevel(7, TopicNotificationLevel.normal),
      TopicNotificationLevel.watching,
    );
    tracking.markRead(7, 100);
    expect(
      tracking.settleNotificationLevel(latest, succeeded: false),
      TopicNotificationLevel.normal,
    );
    expect(tracking.topic(7)?.lastReadPostNumber, 100);
    expect(tracking.newActivityCounts.newReplies, 0);
  });

  test('category refresh supersedes report and bootstrap authority', () {
    final tracking = TopicTrackingReconciler();
    final bootstrap = tracking.beginBootstrap();
    final old = tracking.beginSnapshot()!;
    final current = tracking.beginSnapshot(replace: true)!;
    expect(tracking.completeSnapshot(old, TopicTrackingState([_row])), isFalse);
    expect(tracking.failSnapshot(old), isFalse);
    expect(
      tracking.completeBootstrap(bootstrap, TopicTrackingState([_row])),
      isFalse,
    );
    tracking.cancelSnapshot(old);
    expect(tracking.phase, TopicTrackingPhase.loading);
    expect(current.isCurrent, isTrue);
    expect(tracking.completeSnapshot(current, TopicTrackingState()), isTrue);
    expect(tracking.revision, 1);
  });

  test(
    'preference barrier drops preceding events and keeps local overlays',
    () {
      final tracking = TopicTrackingReconciler();
      final load = tracking.beginSnapshot(replace: true)!;
      tracking.accept(_newTopic(8));
      tracking.markRead(7, 95);
      tracking.chooseNotificationLevel(
        7,
        TopicNotificationLevel.normal,
        confirmed: TopicNotificationLevel.tracking,
      );
      expect(tracking.preferencesReady(load), isTrue);
      tracking.accept(_newTopic(9));
      tracking.completeSnapshot(load, TopicTrackingState([_row]));
      expect(tracking.topic(8)?.isNew, isFalse);
      expect(tracking.topic(9)?.isNew, isTrue);
      expect(tracking.topic(7)?.lastReadPostNumber, 95);
      expect(tracking.topic(7)?.notificationLevel, 1);
      expect(tracking.newActivityCounts, (newTopics: 1, newReplies: 0));
    },
  );

  test('replay admission is fixed on arrival and never renews mute hints', () {
    var now = DateTime.utc(2026);
    const user = DiscourseUser(
      id: 1,
      username: 'reader',
      mutedCategoryIds: [5],
    );
    final tracking = TopicTrackingReconciler(clock: () => now);
    final load = tracking.beginSnapshot()!;
    expect(tracking.accept(_newTopic(7), user: user), isNull);
    tracking.accept(const {'topic_id': 7, 'message_type': 'unmuted'});
    tracking.accept(const {'topic_id': 8, 'message_type': 'unmuted'});
    expect(tracking.accept(_newTopic(8), user: user), isTrue);
    now = now.add(const Duration(seconds: 61));
    tracking.completeSnapshot(load, TopicTrackingState());
    expect(tracking.topic(7), isNull);
    expect(tracking.topic(8)?.isNew, isTrue);
    expect(tracking.admitsIncoming(_newTopic(7), user: user), isFalse);
    expect(tracking.accept(_newTopic(8), user: user), isNull);
    expect(tracking.newActivityCounts.newTopics, 1);
  });

  test('incoming admission and tracking share hints across report retry', () {
    const user = DiscourseUser(
      id: 1,
      username: 'reader',
      mutedCategoryIds: [5],
    );
    final tracking = TopicTrackingReconciler();
    final failed = tracking.beginSnapshot()!;
    tracking.admitsIncoming(const {'topic_id': 7, 'message_type': 'unmuted'});
    tracking.failSnapshot(failed);
    expect(tracking.phase, TopicTrackingPhase.retrying);
    expect(tracking.hasSnapshot, isFalse);
    final retry = tracking.beginSnapshot()!;
    expect(tracking.accept(_newTopic(7), user: user), isTrue);
    tracking.completeSnapshot(retry, TopicTrackingState());
    expect(tracking.newActivityCounts.newTopics, 1);
    tracking.accept(const {'topic_id': 7, 'message_type': 'muted'});
    expect(tracking.admitsIncoming(_newTopic(7), user: user), isFalse);
  });

  for (final truncated in [false, true]) {
    test('coverage before replay controls omissions, truncated=$truncated', () {
      final tracking = TopicTrackingReconciler();
      tracking.completeSnapshot(
        tracking.beginSnapshot()!,
        TopicTrackingState([
          _row.copyWith(lastReadPostNumber: 100),
          const TrackedTopicState(
            topicId: 8,
            highestPostNumber: 100,
            lastReadPostNumber: 100,
          ),
          const TrackedTopicState(
            topicId: 9,
            highestPostNumber: 100,
            lastReadPostNumber: 80,
            notificationLevel: 2,
          ),
        ]),
      );
      final load = tracking.beginSnapshot()!;
      tracking.accept(_newTopic(10000));
      tracking.completeSnapshot(
        load,
        TopicTrackingState([
          for (var id = 100; id < 100 + 4999 + (truncated ? 1 : 0); id++)
            TrackedTopicState(
              topicId: id,
              highestPostNumber: 1,
              createdInNewPeriod: true,
            ),
        ]),
      );
      expect(tracking.topic(8)?.lastReadPostNumber, 100);
      expect(tracking.topic(9)?.lastReadPostNumber, truncated ? isNull : 100);
      expect(tracking.topic(10000)?.isNew, isTrue);
    });
  }

  test('retirement rejects completions, choices and old tracker hints', () {
    var current = true;
    final tracking = TopicTrackingReconciler(isCurrent: () => current);
    final load = tracking.beginSnapshot()!;
    current = false;
    expect(
      tracking.completeSnapshot(load, TopicTrackingState([_row])),
      isFalse,
    );
    expect(tracking.accept(_newTopic(7)), isNull);
    expect(tracking.admitsIncoming(_newTopic(7)), isFalse);
    expect(tracking.failSnapshot(load), isFalse);
    tracking.retire();
    current = true;
    expect(tracking.beginSnapshot(), isNull);
    expect(tracking.revision, 0);
  });

  test('lost account authority ignores local intentions and bootstrap', () {
    var current = true;
    final tracking = TopicTrackingReconciler(isCurrent: () => current);
    tracking.completeSnapshot(
      tracking.beginSnapshot()!,
      TopicTrackingState([_row]),
    );
    final bootstrap = tracking.beginBootstrap();
    current = false;
    expect(bootstrap.isCurrent, isFalse);
    expect(tracking.markRead(7, 95), isFalse);
    tracking.markLastPostUnread(7, 60);
    tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.muted,
      confirmed: TopicNotificationLevel.tracking,
    );
    tracking.observeNotificationLevel(7, TopicNotificationLevel.watching);
    expect(tracking.revision, 1);
    expect(tracking.topic(7)?.lastReadPostNumber, 80);
    expect(tracking.notificationLevel(7), TopicNotificationLevel.tracking);
  });

  test('only the newest live bootstrap installs, never over a report', () {
    final report = TopicTrackingState([_row]);
    final tracking = TopicTrackingReconciler();
    final replaced = tracking.beginBootstrap();
    final cancelled = tracking.beginBootstrap();
    expect(replaced.isCurrent, isFalse);
    expect(cancelled.isCurrent, isTrue);
    expect(tracking.completeBootstrap(replaced, report), isFalse);
    tracking.cancelBootstrap(cancelled);
    expect(cancelled.isCurrent, isFalse);
    expect(tracking.completeBootstrap(cancelled, report), isFalse);

    final superseded = tracking.beginBootstrap();
    final failed = tracking.beginSnapshot()!;
    expect(superseded.isCurrent, isFalse);
    tracking.failSnapshot(failed);
    expect(tracking.completeBootstrap(superseded, report), isFalse);

    final load = tracking.beginSnapshot()!;
    final concurrent = tracking.beginBootstrap();
    expect(tracking.completeBootstrap(concurrent, report), isFalse);
    expect(load.isCurrent, isTrue);
    expect(tracking.hasSnapshot, isFalse);
    expect(tracking.revision, 0);
  });

  for (final replace in [false, true]) {
    test('unseeded events replay unless a category read replaces them, '
        'replace=$replace', () {
      final tracking = TopicTrackingReconciler();
      tracking.accept(_newTopic(8));
      final load = tracking.beginSnapshot(replace: replace)!;
      tracking.completeSnapshot(load, TopicTrackingState());
      expect(tracking.topic(8)?.isNew, !replace);
    });
  }

  test('seeded events observed during bootstrap IO replay onto it', () {
    final tracking = TopicTrackingReconciler();
    tracking.completeSnapshot(tracking.beginSnapshot()!, TopicTrackingState());
    final bootstrap = tracking.beginBootstrap();
    tracking.accept(_newTopic(8));
    expect(tracking.completeBootstrap(bootstrap, TopicTrackingState()), isTrue);
    expect(tracking.topic(8)?.isNew, isTrue);
  });

  test('an installed bootstrap ends the retry phase', () {
    final tracking = TopicTrackingReconciler();
    tracking.failSnapshot(tracking.beginSnapshot()!);
    final bootstrap = tracking.beginBootstrap();
    expect(tracking.completeBootstrap(bootstrap, TopicTrackingState()), isTrue);
    expect(tracking.phase, TopicTrackingPhase.live);
  });

  test('a cancelled bootstrap journal does not replay onto its successor', () {
    final tracking = TopicTrackingReconciler();
    tracking.completeSnapshot(tracking.beginSnapshot()!, TopicTrackingState());
    final cancelled = tracking.beginBootstrap();
    tracking.accept(_newTopic(8));
    tracking.cancelBootstrap(cancelled);
    final bootstrap = tracking.beginBootstrap();
    expect(tracking.completeBootstrap(bootstrap, TopicTrackingState()), isTrue);
    expect(tracking.topic(8)?.isNew, isFalse);
  });

  for (final ending in ['failed', 'cancelled']) {
    test('a $ending report journal does not replay onto the next report', () {
      final tracking = TopicTrackingReconciler();
      final ended = tracking.beginSnapshot()!;
      tracking.accept(_newTopic(8));
      if (ending == 'failed') {
        tracking.failSnapshot(ended);
      } else {
        tracking.cancelSnapshot(ended);
      }
      final next = tracking.beginSnapshot()!;
      tracking.completeSnapshot(next, TopicTrackingState());
      expect(tracking.topic(8)?.isNew, isFalse);
    });
  }

  test('a rejected choice stops overriding before its queue releases', () {
    final tracking = TopicTrackingReconciler();
    tracking.completeSnapshot(
      tracking.beginSnapshot()!,
      TopicTrackingState([_row]),
    );
    final choice = tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.watching,
      confirmed: TopicNotificationLevel.tracking,
    );
    expect(
      tracking.settleNotificationLevel(choice, succeeded: false),
      TopicNotificationLevel.tracking,
    );
    expect(tracking.notificationLevel(7), TopicNotificationLevel.tracking);
    tracking.completeSnapshot(
      tracking.beginSnapshot()!,
      TopicTrackingState([_row.copyWith(notificationLevel: 1)]),
    );
    expect(tracking.topic(7)?.notificationLevel, 1);
    expect(tracking.notificationLevel(7), TopicNotificationLevel.normal);
  });

  test('queued choices keep the first confirmed level as rollback', () {
    final tracking = TopicTrackingReconciler();
    final first = tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.muted,
      confirmed: TopicNotificationLevel.tracking,
    );
    final latest = tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.watching,
      confirmed: tracking.notificationLevel(7)!,
    );
    expect(tracking.settleNotificationLevel(first, succeeded: false), isNull);
    expect(
      tracking.settleNotificationLevel(latest, succeeded: false),
      TopicNotificationLevel.tracking,
    );
  });

  test('a choice made on another account cannot settle this one', () {
    final other = TopicTrackingReconciler();
    final foreign = other.chooseNotificationLevel(
      7,
      TopicNotificationLevel.muted,
      confirmed: TopicNotificationLevel.tracking,
    );
    final tracking = TopicTrackingReconciler();
    final choice = tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.watching,
      confirmed: TopicNotificationLevel.normal,
    );
    expect(tracking.settleNotificationLevel(foreign, succeeded: true), isNull);
    expect(
      tracking.settleNotificationLevel(choice, succeeded: false),
      TopicNotificationLevel.normal,
    );
  });

  test('a read begun before a rejected write cannot replace its rollback', () {
    final tracking = TopicTrackingReconciler();
    final choice = tracking.chooseNotificationLevel(
      7,
      TopicNotificationLevel.watching,
      confirmed: TopicNotificationLevel.tracking,
    );
    final read = tracking.beginNotificationRead(7);
    tracking.settleNotificationLevel(choice, succeeded: false);
    expect(
      read.reconcile(TopicNotificationLevel.normal),
      TopicNotificationLevel.tracking,
    );
    expect(tracking.notificationLevel(7), TopicNotificationLevel.tracking);
  });

  test('an accepted level change reports whether the row changed', () {
    final tracking = TopicTrackingReconciler();
    tracking.completeSnapshot(
      tracking.beginSnapshot()!,
      TopicTrackingState([_row]),
    );
    Map<String, Object?> level(int value) => {
      'topic_id': 7,
      'message_type': 'notification_level_change',
      'payload': {'notification_level': value},
    };
    expect(tracking.accept(level(2)), isFalse);
    expect(tracking.accept(level(3)), isTrue);
  });

  test('a dropped row answers with the level its last report carried', () {
    final tracking = TopicTrackingReconciler();
    tracking.completeSnapshot(tracking.beginSnapshot()!, TopicTrackingState());
    tracking.observeNotificationLevel(7, TopicNotificationLevel.normal);
    tracking.completeSnapshot(
      tracking.beginSnapshot()!,
      TopicTrackingState([_row]),
    );
    tracking.completeSnapshot(
      tracking.beginSnapshot()!,
      TopicTrackingState([
        for (var id = 100; id < 100 + TopicTrackingState.maxReportTopics; id++)
          TrackedTopicState(
            topicId: id,
            highestPostNumber: 1,
            createdInNewPeriod: true,
          ),
      ]),
    );
    expect(tracking.topic(7), isNull);
    expect(tracking.notificationLevel(7), TopicNotificationLevel.tracking);
  });

  test('local read positions never regress and yield to mark-unread', () {
    const other = TrackedTopicState(
      topicId: 8,
      highestPostNumber: 100,
      lastReadPostNumber: 80,
      notificationLevel: 2,
    );
    final tracking = TopicTrackingReconciler();
    tracking.completeSnapshot(
      tracking.beginSnapshot()!,
      TopicTrackingState([_row, other]),
    );
    tracking.markRead(7, 95);
    tracking.markRead(7, 90);
    tracking.markRead(8, 100);
    tracking.markLastPostUnread(8, 99);
    tracking.completeSnapshot(
      tracking.beginSnapshot()!,
      TopicTrackingState([_row, other]),
    );
    expect(tracking.topic(7)?.lastReadPostNumber, 95);
    expect(tracking.topic(8)?.lastReadPostNumber, 80);
  });
}
