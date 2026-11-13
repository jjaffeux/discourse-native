import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/recent_destinations_store.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _account = 'user:1';

const _fromSidebar = ContentRoute(
  destination: FeedDestination(
    key: 'category-12',
    sourcePath: '/c/discourse-native-app/12.json',
  ),
  title: 'Discourse Native App',
  icon: DIcons.folder,
);

const _fromLink = ContentRoute(
  destination: FeedDestination(
    key: 'list-/c/native/12.json',
    sourcePath: '/c/native/12.json',
  ),
  title: 'Discourse Native App',
  icon: DIcons.folder,
);

const _other = ContentRoute(
  destination: FeedDestination(
    key: 'category-13',
    sourcePath: '/c/support/13.json',
  ),
  title: 'Support',
  icon: DIcons.folder,
);

void main() {
  test('overlapping loads share storage and preserve local visits', () async {
    final persistence = _HeldRecentPersistence();
    final first = RecentDestinationsStore(persistence: persistence);
    final second = RecentDestinationsStore(persistence: persistence);
    final loading = first.load();
    final joined = second.load();
    await persistence.started.future;
    first.remember(_site, _account, _fromSidebar);
    second.remember(_site, _account, _other);
    persistence.response.complete(null);
    await Future.wait([loading, joined]);

    expect(first.categoriesFor(_site, _account), [_fromSidebar]);
    expect(second.categoriesFor(_site, _account), [_other]);
    expect(persistence.reads, 1);
  });

  test(
    'account identities cannot collide through delimiter characters',
    () async {
      final persistence = MemoryRecentDestinationsPersistence();
      final store = RecentDestinationsStore(persistence: persistence);
      store.remember(_site, 'user:1\u0000other', _fromSidebar);
      store.remember('$_site\u0000user:1', 'other', _other);
      await store.save();
      final restored = RecentDestinationsStore(persistence: persistence);
      await restored.load();
      expect(restored.categoriesFor(_site, 'user:1\u0000other'), [
        _fromSidebar,
      ]);
      expect(restored.categoriesFor('$_site\u0000user:1', 'other'), [_other]);
    },
  );

  test(
    'superseded history is never serialized and accepted snapshots stay fixed',
    () async {
      final persistence = _HeldWritePersistence();
      final store = RecentDestinationsStore(persistence: persistence);
      var serializations = 0;
      final counted = _CountedRoute(() => serializations++);
      store.remember(_site, _account, counted);
      final first = store.save();
      await persistence.started.future;
      final saves = <Future<void>>[];
      for (var index = 0; index < 100; index++) {
        saves.add(store.save());
      }
      // A visit after save is not part of any accepted snapshot.
      store.remember(_site, _account, _other);
      persistence.release.complete();
      await Future.wait([first, ...saves]);
      expect(serializations, 2);
      expect(persistence.writes, 2);
      final restored = RecentDestinationsStore(persistence: persistence);
      await restored.load();
      expect(restored.categoriesFor(_site, _account).map((r) => r.id), [
        'category-12',
      ]);
    },
  );

  group('RecentDestinationsStore categories', () {
    test(
      'a renamed category updates its single recent visit and saved title',
      () async {
        final persistence = MemoryRecentDestinationsPersistence();
        final store = RecentDestinationsStore(persistence: persistence);
        expect(store.remember(_site, _account, _fromSidebar), isTrue);
        final renamed = _fromSidebar.withDisplay(title: 'Native App renamed');

        expect(store.remember(_site, _account, renamed), isTrue);
        expect(store.categoriesFor(_site, _account), hasLength(1));
        expect(
          store.categoriesFor(_site, _account).single.title,
          'Native App renamed',
        );
        expect(store.categoriesFor(_site, _account).single.id, _fromSidebar.id);
        expect(store.remember(_site, _account, renamed), isFalse);
        await store.save();

        final restored = RecentDestinationsStore(persistence: persistence);
        await restored.load();
        expect(restored.categoriesFor(_site, _account), hasLength(1));
        expect(
          restored.categoriesFor(_site, _account).single.title,
          'Native App renamed',
        );
      },
    );

    test('a category opened from the sidebar and from a link is one visit', () {
      final store = RecentDestinationsStore.memory();

      store.remember(_site, _account, _fromSidebar);
      store.remember(_site, _account, _other);
      expect(store.remember(_site, _account, _fromLink), isTrue);

      expect(store.categoriesFor(_site, _account).map((route) => route.id), [
        _fromLink.id,
        _other.id,
      ]);
    });

    test('distinct slug-only links stay distinct', () {
      final store = RecentDestinationsStore.memory();
      const first = ContentRoute(
        destination: FeedDestination(
          key: 'list-/c/general.json',
          sourcePath: '/c/general.json',
        ),
        title: 'General',
        icon: DIcons.folder,
      );
      const second = ContentRoute(
        destination: FeedDestination(
          key: 'list-/c/support.json',
          sourcePath: '/c/support.json',
        ),
        title: 'Support',
        icon: DIcons.folder,
      );

      store.remember(_site, _account, first);
      store.remember(_site, _account, second);

      expect(store.categoriesFor(_site, _account).map((route) => route.id), [
        second.id,
        first.id,
      ]);
    });

    test('duplicates saved by an earlier build collapse on load', () async {
      final persistence = MemoryRecentDestinationsPersistence()
        ..value = jsonEncode({
          'version': RecentDestinationsStore.formatVersion,
          'entries': [
            {
              'site_url': _site,
              'account_identity': _account,
              'categories': [
                _fromLink.toJson(),
                _fromSidebar.toJson(),
                _other.toJson(),
              ],
              'channels': const <Object>[],
              'topics': const <Object>[],
            },
          ],
        });
      final store = RecentDestinationsStore(persistence: persistence);

      await store.load();

      expect(store.categoriesFor(_site, _account).map((route) => route.id), [
        _fromLink.id,
        _other.id,
      ]);
    });
  });

  group('RecentDestinationsStore hydration', () {
    const otherSite = 'https://other.example';
    final fresh = ContentRoute.topic(
      topicId: 77,
      slug: 'fresh',
      title: 'Fresh',
    );
    final older = ContentRoute.topic(
      topicId: 76,
      slug: 'older',
      title: 'Older',
    );

    Future<String> document() async {
      final persistence = MemoryRecentDestinationsPersistence();
      final seed = RecentDestinationsStore(persistence: persistence)
        ..remember(_site, _account, older)
        ..remember(_site, _account, _fromSidebar)
        ..remember(otherSite, _account, _other);
      await seed.save();
      return persistence.value!;
    }

    test(
      'merges visits made during a delayed read with saved history',
      () async {
        final raw = await document();
        final persistence = _HeldRecentPersistence();
        final store = RecentDestinationsStore(persistence: persistence);
        final loading = store.load();
        await persistence.started.future;
        store.remember(_site, _account, fresh);
        final saving = store.save();
        expect(persistence.written, isNull);
        persistence.response.complete(raw);
        await Future.wait([loading, saving]);

        expect(store.topicsFor(_site, _account), [fresh, older]);
        expect(store.categoriesFor(_site, _account), [_fromSidebar]);
        expect(store.categoriesFor(otherSite, _account), [_other]);
        await store.save();
        expect(persistence.written, contains('Fresh'));
        expect(persistence.written, contains('Older'));
      },
    );

    test(
      'forget during hydration excludes old visits but permits new ones',
      () async {
        final raw = await document();
        final persistence = _HeldRecentPersistence();
        final store = RecentDestinationsStore(persistence: persistence);
        final loading = store.load();
        await persistence.started.future;
        expect(store.forgetSite(_site), isTrue);
        store.remember(_site, _account, fresh);
        persistence.response.complete(raw);
        await loading;

        expect(store.topicsFor(_site, _account), [fresh]);
        expect(store.categoriesFor(_site, _account), isEmpty);
        expect(store.categoriesFor(otherSite, _account), [_other]);
      },
    );

    test(
      'retaining forums during hydration cannot revive excluded history',
      () async {
        final raw = await document();
        final persistence = _HeldRecentPersistence();
        final store = RecentDestinationsStore(persistence: persistence);
        final loading = store.load();
        await persistence.started.future;
        expect(store.retainSites({otherSite}), isTrue);
        store.remember(_site, _account, fresh);
        persistence.response.complete(raw);
        await loading;

        expect(store.topicsFor(_site, _account), [fresh]);
        expect(store.categoriesFor(_site, _account), isEmpty);
        expect(store.categoriesFor(otherSite, _account), [_other]);
      },
    );

    test(
      'later removals also discard visits staged during hydration',
      () async {
        final raw = await document();
        final persistence = _HeldRecentPersistence();
        final store = RecentDestinationsStore(persistence: persistence);
        final loading = store.load();
        await persistence.started.future;
        store.remember(_site, _account, fresh);
        store.retainSites({_site});
        store.retainSites({otherSite});
        persistence.response.complete(raw);
        await loading;

        expect(store.hasVisits(_site, _account), isFalse);
        expect(store.hasVisits(otherSite, _account), isFalse);
      },
    );

    for (final retain in [false, true]) {
      test(
        '${retain ? 'retaining' : 'forgetting'} unseen stored visits requests a merged save',
        () async {
          final raw = await document();
          final persistence = _HeldRecentPersistence();
          final store = RecentDestinationsStore(persistence: persistence);
          final loading = store.load();
          await persistence.started.future;
          final needsSave = retain
              ? store.retainSites({otherSite})
              : store.forgetSite(_site);
          expect(needsSave, isTrue);
          final saving = needsSave ? store.save() : Future<void>.value();
          expect(persistence.written, isNull);
          persistence.response.complete(raw);
          await Future.wait([loading, saving]);

          final reloaded = RecentDestinationsStore(
            persistence: MemoryRecentDestinationsPersistence()
              ..value = persistence.written,
          );
          await reloaded.load();
          expect(reloaded.hasVisits(_site, _account), isFalse);
          expect(reloaded.categoriesFor(otherSite, _account), [_other]);
          expect(
            retain ? store.retainSites({otherSite}) : store.forgetSite(_site),
            isFalse,
          );
        },
      );
    }

    test(
      'staged visits retain recency, updated metadata, and the five-visit limit',
      () async {
        final persistence = _HeldRecentPersistence();
        final store = RecentDestinationsStore(persistence: persistence);
        final loading = store.load();
        await persistence.started.future;
        for (var id = 80; id <= 86; id++) {
          store.remember(
            _site,
            _account,
            ContentRoute.topic(
              topicId: id,
              slug: 'topic-$id',
              title: 'Topic $id',
            ),
          );
        }
        store.remember(
          _site,
          _account,
          ContentRoute.topic(topicId: 84, slug: 'renamed', title: 'Renamed'),
        );
        persistence.response.complete(await document());
        await loading;
        final topics = store.topicsFor(_site, _account);
        expect(topics.map((route) => route.topicId), [84, 86, 85, 83, 82]);
        expect(topics.first.title, 'Renamed');
        expect(store.categoriesFor(_site, _account), [_fromSidebar]);
      },
    );

    test('completed hydration permits a later explicit storage read', () async {
      final persistence = _HeldRecentPersistence();
      final store = RecentDestinationsStore(persistence: persistence);
      final first = store.load();
      await persistence.started.future;
      persistence.response.complete(await document());
      await first;
      persistence.response = Completer<String?>();
      final next = store.load();
      await pumpEventQueue();
      expect(persistence.reads, 2);
      persistence.response.complete(null);
      await next;
      expect(store.hasVisits(_site, _account), isFalse);
    });

    test('overlapping loads share one hydration result', () async {
      final persistence = _HeldRecentPersistence();
      final store = RecentDestinationsStore(persistence: persistence);
      final loading = store.load();
      await persistence.started.future;
      final joined = store.load();
      expect(joined, same(loading));
      persistence.response.complete(await document());
      await Future.wait([loading, joined]);
      expect(persistence.reads, 1);
    });

    test('malformed hydration keeps visits made while reading', () async {
      final persistence = _HeldRecentPersistence();
      final store = RecentDestinationsStore(persistence: persistence);
      final loading = store.load();
      await persistence.started.future;
      store.remember(_site, _account, fresh);
      persistence.response.complete('invalid');
      await loading;
      expect(store.topicsFor(_site, _account), [fresh]);
    });

    test(
      'failed hydration retains live visits without overwriting unread storage',
      () async {
        final persistence = _HeldRecentPersistence();
        final store = RecentDestinationsStore(persistence: persistence);
        final loading = store.load();
        await persistence.started.future;
        store.remember(_site, _account, fresh);
        persistence.response.completeError(StateError('unavailable'));
        await loading;
        expect(store.topicsFor(_site, _account), [fresh]);
        await store.save();
        expect(persistence.written, isNull);
        persistence.response = Completer<String?>();
        final retry = store.load();
        await pumpEventQueue();
        persistence.response.complete(await document());
        await retry;
        expect(store.topicsFor(_site, _account), [fresh, older]);
        await store.save();
        expect(persistence.written, contains('Fresh'));
        expect(persistence.written, contains('Older'));
      },
    );
  });

  group('RecentDestinationsStore forums', () {
    const otherSite = 'https://other.example';
    final message = ContentRoute.topic(
      topicId: 7,
      slug: 'contract-renewal',
      title: 'Contract renewal with Acme',
    );

    /// Two accounts' visits to [_site] and one to [otherSite], already saved.
    Future<(MemoryRecentDestinationsPersistence, RecentDestinationsStore)>
    visited() async {
      final persistence = MemoryRecentDestinationsPersistence();
      final store = RecentDestinationsStore(persistence: persistence)
        ..remember(_site, _account, message)
        ..remember(_site, 'anonymous', _other)
        ..remember(otherSite, _account, _fromSidebar);
      await store.save();
      expect(persistence.value, contains(message.title));
      return (persistence, store);
    }

    Future<void> expectOnlyOtherSite(
      MemoryRecentDestinationsPersistence persistence,
    ) async {
      final reloaded = RecentDestinationsStore(persistence: persistence);
      await reloaded.load();
      expect(reloaded.hasVisits(_site, _account), isFalse);
      expect(reloaded.hasVisits(_site, 'anonymous'), isFalse);
      expect(reloaded.categoriesFor(otherSite, _account), [_fromSidebar]);
      expect(persistence.value, isNot(contains(message.title)));
      expect(persistence.value, isNot(contains(_site)));
    }

    test(
      'forgetting a forum drops every account and keeps the others',
      () async {
        final (persistence, store) = await visited();

        expect(store.forgetSite(_site), isTrue);
        expect(store.forgetSite(_site), isFalse);
        await store.save();

        await expectOnlyOtherSite(persistence);
      },
    );

    test('retaining forums drops every account of the rest', () async {
      final (persistence, store) = await visited();

      expect(store.retainSites({otherSite}), isTrue);
      expect(store.retainSites({otherSite}), isFalse);
      await store.save();

      await expectOnlyOtherSite(persistence);
    });
  });
}

final class _HeldRecentPersistence implements RecentDestinationsPersistence {
  final started = Completer<void>();
  var response = Completer<String?>();
  int reads = 0;
  String? written;

  @override
  Future<String?> read() {
    reads++;
    if (!started.isCompleted) started.complete();
    return response.future;
  }

  @override
  Future<bool> write(String value) async {
    written = value;
    return true;
  }
}

final class _CountedRoute extends ContentRoute {
  const _CountedRoute(this.onEncode)
    : super(
        destination: const FeedDestination(
          key: 'category-12',
          sourcePath: '/c/12.json',
        ),
        title: 'Counted',
        icon: DIcons.folder,
      );

  final void Function() onEncode;

  @override
  Map<String, Object?> toJson() {
    onEncode();
    return super.toJson();
  }
}

final class _HeldWritePersistence implements RecentDestinationsPersistence {
  final started = Completer<void>();
  final release = Completer<void>();
  String? value;
  int writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<bool> write(String value) async {
    if (++writes == 1) {
      started.complete();
      await release.future;
    }
    this.value = value;
    return true;
  }
}
