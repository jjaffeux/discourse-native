import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/data/topic_tracking_reconciler.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/topic_tracking_directory.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _otherSite = 'https://other.example';
const _reader = DiscourseUser(id: 1, username: 'reader');

Map<String, Object?> _newTopic(int id, {int category = 5}) => {
  'message_type': 'new_topic',
  'topic_id': id,
  'payload': {
    'highest_post_number': 1,
    'created_in_new_period': true,
    'category_id': category,
  },
};

Map<String, Object?> _dismiss(String type, List<int> ids) => {
  'message_type': type,
  'payload': {'topic_ids': ids},
};

Topic _topic(
  int id, {
  bool seen = false,
  bool listReadStateKnown = true,
  int? lastRead = 2,
  int highest = 10,
}) => Topic(
  id: id,
  title: 'Topic $id',
  slug: 'topic-$id',
  seen: seen,
  listReadStateKnown: listReadStateKnown,
  lastReadPostNumber: lastRead,
  highestPostNumber: highest,
  unreadPosts: 4,
  newPosts: 3,
);

final class _Fixture {
  _Fixture() {
    directory = TopicTrackingDirectory(
      lifecycle: lifecycle,
      store: store,
      models: const DiscourseModelCodec.core(),
      userFor: (_) => user,
      configFor: (_) => config,
      changed: changed.add,
    );
  }

  final lifecycle = SiteLifecycle();
  final store = Store();
  final changed = <String>[];
  DiscourseUser? user = _reader;
  SiteConfig config = const SiteConfig();
  late final TopicTrackingDirectory directory;

  TopicTrackingAccount get account => directory.capture(_site)!;

  void seed(TopicTrackingAccount account, List<TrackedTopicState> rows) {
    expect(
      account.reconciler.completeSnapshot(
        account.reconciler.beginSnapshot()!,
        TopicTrackingState(rows),
      ),
      isTrue,
    );
  }
}

void main() {
  test('lease retirement removes its owner and stale capture stays closed', () {
    final fixture = _Fixture();
    addTearDown(fixture.directory.dispose);
    final lease = fixture.lifecycle.capture(_site);
    final original = fixture.directory.capture(_site, lease: lease)!;
    final pending = original.reconciler.beginSnapshot()!;

    fixture.lifecycle.invalidate(_site);

    expect(original.isCurrent, isFalse);
    expect(pending.isCurrent, isFalse);
    expect(fixture.directory.existing(_site), isNull);
    expect(fixture.directory.capture(_site, lease: lease), isNull);
    expect(fixture.directory.existing(_site), isNull);
    expect(original.reconciler.beginSnapshot(), isNull);
    final replacement = fixture.account;
    expect(replacement.isCurrent, isTrue);
    expect(replacement, isNot(same(original)));
    expect(replacement.lease.session, isNot(same(lease.session)));
  });

  test('identity replacement on the same lease retires old authority', () {
    final fixture = _Fixture();
    addTearDown(fixture.directory.dispose);
    final original = fixture.account;
    final oldSnapshot = original.reconciler.beginSnapshot()!;
    fixture.user = const DiscourseUser(id: 2, username: 'next-reader');

    expect(original.isCurrent, isFalse);
    expect(original.admitsIncoming(_newTopic(7)), isFalse);
    original.accept(_newTopic(7));
    expect(original.reconciler.topic(7), isNull);
    expect(fixture.directory.existing(_site), isNull);

    final replacement = fixture.account;
    expect(replacement.lease.session, same(original.lease.session));
    expect(replacement.reconciler, isNot(same(original.reconciler)));
    expect(
      original.reconciler.completeSnapshot(oldSnapshot, TopicTrackingState()),
      isFalse,
    );
    final newSnapshot = replacement.reconciler.beginSnapshot()!;
    replacement.accept(_newTopic(8));
    expect(
      replacement.reconciler.completeSnapshot(
        newSnapshot,
        TopicTrackingState(),
      ),
      isTrue,
    );
    expect(replacement.reconciler.topic(8)?.isNew, isTrue);
    expect(fixture.directory.capture(_site), same(replacement));
    expect(fixture.changed, [_site]);
  });

  test('matching requires both the held engine and its exact lease', () {
    final fixture = _Fixture();
    addTearDown(fixture.directory.dispose);
    final account = fixture.account;
    expect(
      fixture.directory.matching(
        _site,
        fixture.lifecycle.capture(_site),
        account.reconciler,
      ),
      same(account),
    );
    expect(
      fixture.directory.matching(
        _site,
        account.lease,
        TopicTrackingReconciler(),
      ),
      isNull,
    );
    expect(
      fixture.directory.matching(
        _site,
        fixture.lifecycle.capture(_otherSite),
        account.reconciler,
      ),
      isNull,
    );
    fixture.lifecycle.invalidate(_site);
    final replacement = fixture.account;
    expect(
      fixture.directory.matching(_site, account.lease, replacement.reconciler),
      isNull,
    );
    expect(
      fixture.directory.matching(_site, replacement.lease, account.reconciler),
      isNull,
    );
  });

  test('an older account transition cannot reopen a newer transition', () {
    final fixture = _Fixture();
    addTearDown(fixture.directory.dispose);
    final original = fixture.account;
    final finishOld = fixture.directory.beginAccountChange(_site);
    expect(original.isCurrent, isFalse);
    expect(fixture.directory.existing(_site), isNull);
    expect(fixture.directory.capture(_site), isNull);
    final finishNew = fixture.directory.beginAccountChange(_site);

    finishOld();
    finishOld();

    expect(fixture.directory.capture(_site), isNull);
    expect(original.admitsIncoming(_newTopic(7)), isFalse);
    fixture.user = const DiscourseUser(id: 2, username: 'next-reader');
    finishNew();
    final replacement = fixture.account;
    expect(replacement.isCurrent, isTrue);
    expect(replacement, isNot(same(original)));
    finishOld();
    expect(fixture.directory.capture(_site), same(replacement));
  });

  test(
    'immutable same-account preferences retain engine and apply immediately',
    () {
      final fixture = _Fixture();
      addTearDown(fixture.directory.dispose);
      final account = fixture.account;
      final engine = account.reconciler;
      expect(account.admitsIncoming(_newTopic(7)), isTrue);
      fixture.user = const DiscourseUser(
        id: 1,
        username: 'renamed-reader',
        mutedCategoryIds: [5],
      );

      expect(fixture.directory.capture(_site), same(account));
      expect(account.reconciler, same(engine));
      expect(account.admitsIncoming(_newTopic(7)), isFalse);
      account.accept(_newTopic(7));
      expect(engine.topic(7), isNull);
      fixture.user = const DiscourseUser(id: 1, username: 'renamed-reader');
      expect(account.admitsIncoming(_newTopic(7)), isTrue);
      account.accept(_newTopic(7));
      expect(engine.topic(7)?.isNew, isTrue);
      expect(fixture.changed, [_site]);

      fixture.config = const SiteConfig(muteAllCategoriesByDefault: true);
      expect(account.admitsIncoming(_newTopic(8)), isFalse);
      account.accept(_newTopic(8));
      expect(engine.topic(8), isNull);
    },
  );

  test('retry snapshot includes the message that triggered its opening', () {
    final fixture = _Fixture();
    addTearDown(fixture.directory.dispose);
    final account = fixture.account;
    fixture.seed(account, []);
    final failed = account.reconciler.beginSnapshot()!;
    expect(account.reconciler.failSnapshot(failed), isTrue);
    TopicTrackingSnapshot? retry;

    account.accept(
      _newTopic(7),
      retryBeforeAccept: () => retry = account.reconciler.beginSnapshot(),
    );

    expect(retry, isNotNull);
    expect(account.owns(retry!), isTrue);
    expect(
      account.reconciler.completeSnapshot(retry!, TopicTrackingState()),
      isTrue,
    );
    expect(account.reconciler.topic(7)?.isNew, isTrue);
    expect(fixture.changed, [_site]);
  });

  test('reentrant retirement during retry prevents accepting the message', () {
    final fixture = _Fixture();
    addTearDown(fixture.directory.dispose);
    final account = fixture.account;
    fixture.store.put(_site, _topic(7));
    account.accept(
      _dismiss('dismiss_new', [7]),
      retryBeforeAccept: () => fixture.lifecycle.invalidate(_site),
    );

    expect(account.reconciler.revision, 0);
    expect(fixture.store.read<Topic>(_site, 7)?.seen, isFalse);
    expect(fixture.changed, isEmpty);
    expect(fixture.directory.existing(_site), isNull);
  });

  for (final type in ['dismiss_new', 'dismiss_new_posts']) {
    test('$type stops Store updates after same-lease account replacement', () {
      final fixture = _Fixture();
      addTearDown(fixture.directory.dispose);
      final original = fixture.account;
      fixture.seed(original, [
        for (final id in [7, 8])
          TrackedTopicState(
            topicId: id,
            highestPostNumber: 12,
            lastReadPostNumber: 2,
            createdInNewPeriod: true,
          ),
      ]);
      fixture.store.putAll(_site, [_topic(7), _topic(8)]);
      TopicTrackingAccount? replacement;
      final first = fixture.store.ref<Topic>(_site, 7);
      void replaceAccount() {
        final finish = fixture.directory.beginAccountChange(_site);
        fixture.user = const DiscourseUser(id: 2, username: 'next-reader');
        finish();
        replacement = fixture.account;
      }

      first.addListener(replaceAccount);
      addTearDown(() => first.removeListener(replaceAccount));

      original.accept(_dismiss(type, [7, 8]));

      expect(replacement, isNotNull);
      expect(replacement!.lease.session, same(original.lease.session));
      expect(original.isCurrent, isFalse);
      final firstRow = fixture.store.read<Topic>(_site, 7)!;
      if (type == 'dismiss_new') {
        expect(firstRow.seen, isTrue);
      } else {
        expect(firstRow.lastReadPostNumber, 12);
        expect(firstRow.highestPostNumber, 12);
        expect(firstRow.unreadPosts, 0);
        expect(firstRow.newPosts, 0);
      }
      expect(fixture.store.read<Topic>(_site, 8), _topic(8));
      expect(fixture.changed, isEmpty);
      expect(replacement!.reconciler.topic(7), isNull);
    });

    test('$type updates loaded rows even with no tracking-state change', () {
      final fixture = _Fixture();
      addTearDown(fixture.directory.dispose);
      final account = fixture.account;
      fixture.store.put(_site, _topic(7));

      account.accept(_dismiss(type, [7]));

      final row = fixture.store.read<Topic>(_site, 7)!;
      if (type == 'dismiss_new') {
        expect(row.seen, isTrue);
      } else {
        expect(row.lastReadPostNumber, 10);
        expect(row.unreadPosts, 0);
        expect(row.newPosts, 0);
      }
      expect(account.reconciler.revision, 0);
      expect(fixture.changed, isEmpty);
    });
  }

  test(
    'projection keeps sparse and newer rows unread without enough coverage',
    () {
      final fixture = _Fixture();
      addTearDown(fixture.directory.dispose);
      final account = fixture.account;
      fixture.seed(account, [
        const TrackedTopicState(
          topicId: 7,
          highestPostNumber: 10,
          lastReadPostNumber: 10,
        ),
      ]);
      final sparse = _topic(7, highest: 0);
      expect(account.project(sparse), same(sparse));
      final newer = _topic(7, highest: 12);
      expect(account.project(newer), same(newer));
      final unknownRead = _topic(7, lastRead: null);
      expect(account.project(unknownRead), same(unknownRead));

      final covered = account.project(_topic(7));
      expect(covered.lastReadPostNumber, 10);
      expect(covered.highestPostNumber, 10);
      expect(covered.unreadPosts, 0);
      expect(covered.newPosts, 0);
      final behind = account.project(_topic(7, highest: 8));
      expect(behind.lastReadPostNumber, 10);
      expect(behind.highestPostNumber, 10);
    },
  );

  test(
    'projection applies seen state and preserves authoritative list state',
    () {
      final fixture = _Fixture();
      addTearDown(fixture.directory.dispose);
      final account = fixture.account;
      account.accept(_newTopic(7));
      final unknown = _topic(
        7,
        seen: true,
        listReadStateKnown: false,
        lastRead: null,
      );
      expect(account.project(unknown).seen, isFalse);
      final known = _topic(7, seen: true, lastRead: null);
      expect(account.project(known), same(known));

      account.accept(_dismiss('dismiss_new', [7]));
      final unseen = _topic(7, lastRead: null);
      expect(account.project(unseen).seen, isTrue);
      final absent = _topic(8);
      expect(account.project(absent), same(absent));
    },
  );

  test(
    'local read overlays survive reports and unread reset admits replies',
    () {
      final fixture = _Fixture();
      addTearDown(fixture.directory.dispose);
      final account = fixture.account;
      account.markRead(7, 10);
      fixture.seed(account, [
        const TrackedTopicState(
          topicId: 7,
          highestPostNumber: 10,
          lastReadPostNumber: 2,
          notificationLevel: 2,
        ),
      ]);

      expect(account.reconciler.topic(7)?.lastReadPostNumber, 10);
      expect(account.reconciler.newActivityCounts.newReplies, 0);
      final projected = account.project(_topic(7));
      expect(projected.lastReadPostNumber, 10);
      expect(projected.unreadPosts, 0);
      expect(projected.seen, isTrue);

      account.markLastPostUnread(7, 9);
      expect(account.reconciler.topic(7)?.lastReadPostNumber, 9);
      expect(account.reconciler.newActivityCounts.newReplies, 1);
      final row = _topic(7, seen: true, lastRead: 9);
      expect(account.project(row), same(row));
    },
  );

  test('disposal retires all accounts and keeps future capture closed', () {
    final fixture = _Fixture();
    final first = fixture.account;
    final second = fixture.directory.capture(_otherSite)!;
    final pending = first.reconciler.beginSnapshot()!;
    final row = _topic(7);
    fixture.store.put(_site, row);

    fixture.directory.dispose();
    fixture.directory.dispose();
    first.accept(_dismiss('dismiss_new', [7]));
    first.markRead(7, 10);
    first.markLastPostUnread(7, 9);

    expect(first.isCurrent, isFalse);
    expect(second.isCurrent, isFalse);
    expect(first.owns(pending), isFalse);
    expect(pending.isCurrent, isFalse);
    expect(first.admitsIncoming(_newTopic(7)), isFalse);
    expect(first.reconciler.beginSnapshot(), isNull);
    expect(first.project(row), same(row));
    expect(fixture.store.read<Topic>(_site, 7), same(row));
    expect(fixture.directory.existing(_site), isNull);
    expect(fixture.directory.existing(_otherSite), isNull);
    expect(fixture.directory.capture(_site), isNull);
    expect(fixture.directory.capture(_otherSite), isNull);
    expect(fixture.changed, isEmpty);
  });
}
