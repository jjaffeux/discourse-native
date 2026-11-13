import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/current_user_reconciler.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/data/topic_tracking_reconciler.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/tag_notification.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/notification_preference_transactions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  test('foreign notification messages skip preference session lookup', () {
    final f = _Fixture();
    final foreign = SiteLifecycle().capture(_site);
    const data = {'notification_level_change': 0};
    f.owner.observeTopicMessage(_site, 7, data, foreign);
    expect(f.trackingLookups, 0);
    f.owner.observeTopicMessage(_site, 7, data, f.lifecycle.capture(_site));
    expect(f.trackingLookups, 1);
  });

  test('canonical equal choice repairs stale detail without writing', () async {
    final fixture = _Fixture();
    fixture.tracking.observeNotificationLevel(7, TopicNotificationLevel.normal);
    expect(
      await fixture.owner.updateTopic(_site, 7, TopicNotificationLevel.normal),
      isTrue,
    );
    expect(fixture.api.topicNotificationLevelsUpdated, isEmpty);
    expect(
      fixture.store.read<TopicDetail>(_site, 7)?.notificationLevel,
      TopicNotificationLevel.normal,
    );
  });

  test(
    'choice equal to stale detail still writes against canonical state',
    () async {
      final fixture = _Fixture();
      fixture.tracking.observeNotificationLevel(
        7,
        TopicNotificationLevel.watching,
      );
      expect(
        await fixture.owner.updateTopic(
          _site,
          7,
          TopicNotificationLevel.tracking,
        ),
        isTrue,
      );
      expect(
        fixture.api.topicNotificationLevelsUpdated.single.notificationLevel,
        TopicNotificationLevel.tracking,
      );
      expect(
        fixture.tracking.notificationLevel(7),
        TopicNotificationLevel.tracking,
      );
    },
  );

  test(
    'reentrant topic selection owns admission before Store publication',
    () async {
      final fixture = _Fixture();
      fixture.store.put(
        _site,
        const Topic(id: 7, title: 'Topic', slug: 'topic'),
      );
      Future<bool>? replacement;
      final ref = fixture.store.ref<TopicDetail>(_site, 7);
      ref.addListener(() {
        if (ref.value!.notificationLevel == TopicNotificationLevel.muted) {
          replacement = fixture.owner.updateTopic(
            _site,
            7,
            TopicNotificationLevel.watching,
          );
        }
      });

      final first = fixture.owner.updateTopic(
        _site,
        7,
        TopicNotificationLevel.muted,
      );

      expect(await first, isFalse);
      expect(await replacement!, isTrue);
      expect(
        fixture.api.topicNotificationLevelsUpdated.single.notificationLevel,
        TopicNotificationLevel.watching,
      );
      expect(ref.value!.notificationLevel, TopicNotificationLevel.watching);
      expect(fixture.store.read<Topic>(_site, 7)!.muted, isFalse);
    },
  );

  test(
    'topic mute updates rows optimistically, rolls back, and follows live changes',
    () async {
      final f = _Fixture();
      f.store.put(_site, const Topic(id: 7, title: 'Topic', slug: 'topic'));
      final gate = Completer<void>();
      f.api.topicGates.add(gate);
      f.api.topicFailure = StateError('unreachable');
      final writing = f.owner.updateTopic(
        _site,
        7,
        TopicNotificationLevel.muted,
      );
      expect(f.store.read<Topic>(_site, 7)!.muted, isTrue);
      await pumpEventQueue();
      gate.complete();
      expect(await writing, isFalse);
      expect(f.store.read<Topic>(_site, 7)!.muted, isFalse);
      final lease = f.lifecycle.capture(_site);
      f.owner.observeTopicMessage(_site, 7, {
        'notification_level_change': 0,
      }, lease);
      expect(f.store.read<Topic>(_site, 7)!.muted, isTrue);
      f.owner.observeTopicMessage(_site, 7, {
        'notification_level_change': 3,
      }, lease);
      expect(f.store.read<Topic>(_site, 7)!.muted, isFalse);
    },
  );

  test('reentrant category selection appends to the account queue', () async {
    final fixture = _Fixture();
    Future<bool>? replacement;
    fixture.taxonomy.onProject = (id, level) {
      if (level == CategoryNotificationLevel.muted) {
        replacement = fixture.owner.updateCategory(
          _site,
          id,
          CategoryNotificationLevel.watching,
        );
      }
    };

    final first = fixture.owner.updateCategory(
      _site,
      1,
      CategoryNotificationLevel.muted,
    );

    expect(await first, isFalse);
    expect(await replacement!, isTrue);
    expect(fixture.api.writes.map((write) => write.id), [1]);
    expect(fixture.user.watchedCategoryIds, [1]);
    expect(fixture.user.mutedCategoryIds, isEmpty);
  });

  test('different category writes serialize across the account', () async {
    final fixture = _Fixture();
    final gate = Completer<List<int>?>();
    fixture.api.nextWrite = gate;
    final first = fixture.owner.updateCategory(
      _site,
      1,
      CategoryNotificationLevel.muted,
    );
    await pumpEventQueue();
    final second = fixture.owner.updateCategory(
      _site,
      2,
      CategoryNotificationLevel.tracking,
    );
    await pumpEventQueue();
    expect(fixture.api.writes.map((write) => write.id), [1]);

    gate.complete([3]);

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(fixture.api.writes.map((write) => write.id), [1, 2]);
    expect(fixture.user.mutedCategoryIds, [1]);
    expect(fixture.user.trackedCategoryIds, [2]);
    expect(fixture.user.watchedCategoryIds, isEmpty);
  });

  test(
    'lease retirement alone releases a replacement account from an old tail',
    () async {
      final fixture = _Fixture();
      final gate = Completer<List<int>?>();
      fixture.api.nextWrite = gate;
      final first = fixture.owner.updateCategory(
        _site,
        1,
        CategoryNotificationLevel.muted,
      );
      await pumpEventQueue();
      final queued = fixture.owner.updateCategory(
        _site,
        2,
        CategoryNotificationLevel.watching,
      );

      fixture.lifecycle.invalidate(_site);
      fixture.replaceAccount();
      final replacement = fixture.owner.updateCategory(
        _site,
        1,
        CategoryNotificationLevel.tracking,
      );
      expect(await replacement, isTrue);
      expect(fixture.api.writes, hasLength(2));

      gate.complete([2]);
      expect(await first, isFalse);
      expect(await queued, isFalse);
      expect(fixture.user.trackedCategoryIds, [1]);
      expect(fixture.user.mutedCategoryIds, isEmpty);
      expect(fixture.api.writes, hasLength(2));
    },
  );

  test(
    'retirement during credential IO cannot read replacement client identity',
    () async {
      final credentials = _HeldCredentials();
      final fixture = _Fixture(credentials: credentials);
      final first = fixture.owner.updateTopic(
        _site,
        7,
        TopicNotificationLevel.muted,
      );
      await pumpEventQueue();

      fixture.lifecycle.invalidate(_site);
      fixture.replaceAccount();
      credentials.key.complete('old-key');

      expect(await first, isFalse);
      expect(credentials.clientReads, 0);
      expect(fixture.api.topicNotificationLevelsUpdated, isEmpty);
    },
  );

  for (final failure in ['publication', 'refresh']) {
    test(
      'confirmed category POST stays successful after $failure failure',
      () async {
        final fixture = _Fixture();
        fixture.failPublication = failure == 'publication';
        fixture.failRefresh = failure == 'refresh';

        expect(
          await fixture.owner.updateCategory(
            _site,
            1,
            CategoryNotificationLevel.muted,
          ),
          isTrue,
        );
        await pumpEventQueue();
        fixture.failPublication = false;
        fixture.failRefresh = false;
        expect(
          await fixture.owner.updateCategory(
            _site,
            2,
            CategoryNotificationLevel.watching,
          ),
          isTrue,
        );
        expect(fixture.api.writes, hasLength(2));
        expect(fixture.user.watchedCategoryIds, [2]);
      },
    );
  }

  test(
    'unknown category write outcome rolls back without publishing memberships',
    () async {
      final fixture = _Fixture();
      final gate = Completer<List<int>?>();
      fixture.api.nextWrite = gate;
      final result = fixture.owner.updateCategory(
        _site,
        1,
        CategoryNotificationLevel.muted,
      );
      await pumpEventQueue();
      gate.completeError(StateError('connection lost after dispatch'));

      expect(await result, isFalse);
      expect(
        fixture.store.read<TopicCategory>(_site, 1)!.notificationLevel,
        CategoryNotificationLevel.normal,
      );
      expect(fixture.user.mutedCategoryIds, isEmpty);
      expect(fixture.refreshes, 0);
    },
  );

  test(
    'a replacement tracking account on the same lease retires older writes',
    () async {
      final fixture = _Fixture();
      final gate = Completer<void>();
      fixture.api.topicGates.add(gate);
      final stale = fixture.owner.updateTopic(
        _site,
        7,
        TopicNotificationLevel.muted,
      );
      await pumpEventQueue();

      fixture.tracking = TopicTrackingReconciler();
      final replacement = fixture.owner.updateTopic(
        _site,
        7,
        TopicNotificationLevel.watching,
      );
      await pumpEventQueue();
      gate.complete();

      expect(await stale, isFalse);
      expect(await replacement, isTrue);
      expect(
        fixture.store.read<TopicDetail>(_site, 7)?.notificationLevel,
        TopicNotificationLevel.watching,
      );
      expect(
        fixture.tracking.notificationLevel(7),
        TopicNotificationLevel.watching,
      );
    },
  );

  test('a finished write does not pin a later rollback baseline', () async {
    final fixture = _Fixture();
    expect(
      await fixture.owner.updateTopic(
        _site,
        7,
        TopicNotificationLevel.watching,
      ),
      isTrue,
    );
    await pumpEventQueue();
    fixture.owner.observeTopicMessage(_site, 7, const {
      'notification_level_change': 1,
    }, fixture.lifecycle.capture(_site));
    fixture.api.topicFailure = StateError('rejected');

    expect(
      await fixture.owner.updateTopic(_site, 7, TopicNotificationLevel.muted),
      isFalse,
    );
    expect(
      fixture.store.read<TopicDetail>(_site, 7)?.notificationLevel,
      TopicNotificationLevel.normal,
    );
    expect(
      fixture.tracking.notificationLevel(7),
      TopicNotificationLevel.normal,
    );
  });

  test('a missing API key rolls back topic and category choices', () async {
    final fixture = _Fixture(credentials: FakeApiCredentialReader());

    expect(
      await fixture.owner.updateTopic(
        _site,
        7,
        TopicNotificationLevel.watching,
      ),
      isFalse,
    );
    expect(
      await fixture.owner.updateCategory(
        _site,
        1,
        CategoryNotificationLevel.muted,
      ),
      isFalse,
    );
    expect(
      fixture.store.read<TopicDetail>(_site, 7)?.notificationLevel,
      TopicNotificationLevel.tracking,
    );
    expect(
      fixture.tracking.notificationLevel(7),
      TopicNotificationLevel.tracking,
    );
    expect(
      fixture.store.read<TopicCategory>(_site, 1)!.notificationLevel,
      CategoryNotificationLevel.normal,
    );
    expect(fixture.api.topicNotificationLevelsUpdated, isEmpty);
    expect(fixture.api.writes, isEmpty);
  });

  test(
    'a preference read begun before a newer category write is discarded',
    () async {
      final fixture = _Fixture();
      final first = Completer<List<int>?>()..complete(null);
      fixture.api.nextWrite = first;
      expect(
        await fixture.owner.updateCategory(
          _site,
          1,
          CategoryNotificationLevel.muted,
        ),
        isTrue,
      );
      final staleRead = fixture.preferenceReads.single;
      fixture.api.accounts['key'] = fixture.user;
      expect(
        await fixture.owner.updateCategory(
          _site,
          1,
          CategoryNotificationLevel.normal,
        ),
        isTrue,
      );

      await staleRead();
      expect(fixture.user.mutedCategoryIds, isEmpty);
    },
  );

  test(
    'a confirmed category write invalidates the sidebar and announces it',
    () async {
      final fixture = _Fixture();
      expect(
        await fixture.owner.updateCategory(
          _site,
          1,
          CategoryNotificationLevel.muted,
        ),
        isTrue,
      );
      expect(fixture.taxonomy.invalidations, 1);
      expect(fixture.changes, 1);
    },
  );

  test(
    'publication that retires the account stops its follow-up effects',
    () async {
      final fixture = _Fixture();
      fixture.onPublish = () => fixture.owner.forget(_site);
      expect(
        await fixture.owner.updateCategory(
          _site,
          1,
          CategoryNotificationLevel.muted,
        ),
        isTrue,
      );
      expect(fixture.taxonomy.invalidations, 0);
      expect(fixture.refreshes, 0);
      expect(fixture.changes, 0);
    },
  );

  test(
    'an earlier finished category write keeps later writes serialized',
    () async {
      final fixture = _Fixture();
      final first = Completer<List<int>?>();
      final second = Completer<List<int>?>();
      fixture.api.nextWrite = first;
      final writes = [
        fixture.owner.updateCategory(_site, 1, CategoryNotificationLevel.muted),
      ];
      await pumpEventQueue();
      writes.add(
        fixture.owner.updateCategory(
          _site,
          2,
          CategoryNotificationLevel.tracking,
        ),
      );
      fixture.api.nextWrite = second;
      first.complete([]);
      await pumpEventQueue();
      expect(fixture.api.writes.map((write) => write.id), [1, 2]);

      writes.add(
        fixture.owner.updateCategory(
          _site,
          1,
          CategoryNotificationLevel.watching,
        ),
      );
      await pumpEventQueue();
      expect(fixture.api.writes.map((write) => write.id), [1, 2]);

      second.complete([]);
      expect(await Future.wait(writes), [true, true, true]);
      expect(fixture.api.writes.map((write) => write.id), [1, 2, 1]);
    },
  );

  test('a disposed owner refuses new writes', () async {
    final fixture = _Fixture();
    fixture.owner.dispose();
    expect(
      await fixture.owner.updateTopic(
        _site,
        7,
        TopicNotificationLevel.watching,
      ),
      isFalse,
    );
    expect(
      await fixture.owner.updateCategory(
        _site,
        1,
        CategoryNotificationLevel.muted,
      ),
      isFalse,
    );
    expect(fixture.api.topicNotificationLevelsUpdated, isEmpty);
    expect(fixture.api.writes, isEmpty);
  });
  group('tag levels', () {
    TagNotificationLevel? level(_Fixture f, [String tag = 'ux']) =>
        f.store.read<TagNotificationPreference>(_site, tag)?.level;

    Future<_Fixture> loaded([
      TagNotificationLevel initial = TagNotificationLevel.tracking,
    ]) async {
      final f = _Fixture();
      f.api.tagNotificationLevels['ux'] = initial;
      await f.owner.refreshTag(_site, 'ux');
      return f;
    }

    test('reading publishes the level the server holds', () async {
      final f = await loaded(TagNotificationLevel.watchingFirstPost);
      expect(f.api.tagNotificationLevelReads, ['ux']);
      expect(level(f), TagNotificationLevel.watchingFirstPost);
    });

    test('a failed read leaves no level to draw', () async {
      final f = _Fixture();
      f.api.tagNotificationReadFailure = StateError('unreachable');
      await f.owner.refreshTag(_site, 'ux');
      expect(level(f), isNull);
      expect(
        await f.owner.updateTag(_site, 'ux', TagNotificationLevel.muted),
        isFalse,
      );
      expect(f.api.tagNotificationLevelsUpdated, isEmpty);
    });

    test(
      'a write shows at once, then adopts the muted tags and refreshes tracking',
      () async {
        final f = await loaded();
        final gate = Completer<void>();
        f.api
          ..tagNotificationWriteGate = gate
          ..mutedTagIdsAfterTagWrite = [41, 44];

        final writing = f.owner.updateTag(
          _site,
          'ux',
          TagNotificationLevel.muted,
        );
        expect(level(f), TagNotificationLevel.muted);
        expect(f.user.mutedTagIds, isNull);

        gate.complete();
        expect(await writing, isTrue);
        expect(f.api.tagNotificationLevelsUpdated.single, (
          tag: 'ux',
          notificationLevel: TagNotificationLevel.muted,
        ));
        expect(level(f), TagNotificationLevel.muted);
        expect(f.user.mutedTagIds, [41, 44]);
        expect(f.refreshes, 1);
      },
    );

    test('a refused write returns to the confirmed level', () async {
      final f = await loaded();
      final gate = Completer<void>();
      f.api
        ..tagNotificationWriteGate = gate
        ..tagNotificationWriteFailure = StateError('refused')
        ..mutedTagIdsAfterTagWrite = [41];

      final writing = f.owner.updateTag(
        _site,
        'ux',
        TagNotificationLevel.watching,
      );
      expect(level(f), TagNotificationLevel.watching);
      gate.complete();

      expect(await writing, isFalse);
      expect(level(f), TagNotificationLevel.tracking);
      expect(f.user.mutedTagIds, isNull);
      expect(f.refreshes, 0);
    });

    test('choosing the held level writes nothing', () async {
      final f = await loaded();
      expect(
        await f.owner.updateTag(_site, 'ux', TagNotificationLevel.tracking),
        isTrue,
      );
      expect(f.api.tagNotificationLevelsUpdated, isEmpty);
    });

    test('a newer choice replaces one not yet sent', () async {
      final f = await loaded();
      final first = f.owner.updateTag(_site, 'ux', TagNotificationLevel.muted);
      final second = f.owner.updateTag(
        _site,
        'ux',
        TagNotificationLevel.watching,
      );

      expect(await first, isFalse);
      expect(await second, isTrue);
      expect(
        f.api.tagNotificationLevelsUpdated.single.notificationLevel,
        TagNotificationLevel.watching,
      );
      expect(level(f), TagNotificationLevel.watching);
    });

    test('a read that started before a write cannot overwrite it', () async {
      final f = await loaded();
      final held = Completer<void>();
      f.api.tagNotificationReadGates.add(held);
      final reading = f.owner.refreshTag(_site, 'ux');
      await pumpEventQueue();

      expect(
        await f.owner.updateTag(_site, 'ux', TagNotificationLevel.watching),
        isTrue,
      );
      held.complete();
      await reading;

      expect(level(f), TagNotificationLevel.watching);
    });

    test('an older read cannot overwrite a newer one', () async {
      final f = await loaded();
      final older = Completer<void>();
      final newer = Completer<void>();
      f.api.tagNotificationReadGates.addAll([older, newer]);
      final first = f.owner.refreshTag(_site, 'ux');
      await pumpEventQueue();
      f.api.tagNotificationLevels['ux'] = TagNotificationLevel.watching;
      final second = f.owner.refreshTag(_site, 'ux');
      await pumpEventQueue();

      newer.complete();
      await second;
      older.complete();
      await first;

      expect(level(f), TagNotificationLevel.watching);
    });

    test('a read from a replaced account publishes nothing', () async {
      final f = _Fixture();
      final held = Completer<void>();
      f.api
        ..tagNotificationReadGates.add(held)
        ..tagNotificationLevels['ux'] = TagNotificationLevel.muted;
      final reading = f.owner.refreshTag(_site, 'ux');
      await pumpEventQueue();

      f.lifecycle.invalidate(_site);
      f.replaceAccount();
      held.complete();
      await reading;

      expect(level(f), isNull);
    });
  });
}

final class _Fixture {
  _Fixture({ApiCredentialReader? credentials}) {
    replaceAccount();
    owner = NotificationPreferenceTransactions(
      store: store,
      credentials:
          credentials ?? (FakeApiCredentialReader()..keys[_site] = 'key'),
      lifecycle: lifecycle,
      topics: api,
      categories: api,
      tags: api,
      site: api,
      currentUsers: NotificationPreferenceCurrentUsers(
        read: (_) => user,
        reconcilerFor: (_) => currentUser,
        publish: (_, lease, updated) {
          if (failPublication) throw StateError('persistence unavailable');
          user = updated;
          onPublish?.call();
        },
      ),
      taxonomy: taxonomy,
      trackingEffects: NotificationPreferenceTracking(
        forSite: (_) {
          trackingLookups++;
          return tracking;
        },
        refresh:
            ({
              required siteUrl,
              required username,
              required lease,
              required tracking,
              required ticket,
              required requestCredentials,
              refreshCategoryPreferences,
            }) async {
              refreshes++;
              if (refreshCategoryPreferences != null) {
                preferenceReads.add(refreshCategoryPreferences);
              }
              if (failRefresh) throw StateError('refresh unavailable');
              tracking.cancelSnapshot(ticket);
            },
      ),
      topicChanged: (_) {},
      changed: () => changes++,
    );
    addTearDown(owner.dispose);
  }

  final store = Store();
  final lifecycle = SiteLifecycle();
  final api = _Api();
  late final taxonomy = _Taxonomy(store);
  late final NotificationPreferenceTransactions owner;
  late TopicTrackingReconciler tracking;
  late CurrentUserReconciler currentUser;
  late DiscourseUser user;
  bool failPublication = false;
  bool failRefresh = false;
  int refreshes = 0;
  int trackingLookups = 0;
  int changes = 0;
  void Function()? onPublish;
  final preferenceReads = <Future<void> Function()>[];

  void replaceAccount() {
    final lease = lifecycle.capture(_site);
    tracking = TopicTrackingReconciler(isCurrent: () => lease.isCurrent);
    currentUser = CurrentUserReconciler(lease: lease);
    user = const DiscourseUser(
      id: 7,
      username: 'reader',
      trackedCategoryIds: [],
      watchedCategoryIds: [],
      watchedFirstPostCategoryIds: [],
      mutedCategoryIds: [],
      indirectlyMutedCategoryIds: [],
    );
    store.put(
      _site,
      const TopicDetail(
        id: 7,
        title: 'Topic',
        stream: [],
        notificationLevel: TopicNotificationLevel.tracking,
      ),
    );
    for (final id in [1, 2]) {
      store.put(
        _site,
        TopicCategory(id: id, name: 'Category $id', color: '111111'),
      );
    }
  }
}

final class _Taxonomy implements NotificationPreferenceTaxonomy {
  _Taxonomy(this.store);
  final Store store;
  void Function(int, CategoryNotificationLevel)? onProject;
  int invalidations = 0;

  @override
  void invalidateCategorySidebar(String siteUrl) => invalidations++;

  @override
  void projectNotificationLevel(
    String siteUrl,
    int categoryId,
    CategoryNotificationLevel level,
    SiteLease lease, {
    required bool pending,
  }) {
    if (!lease.isCurrent) return;
    store.update<TopicCategory>(
      siteUrl,
      categoryId,
      (category) => category.withNotificationLevel(level),
    );
    onProject?.call(categoryId, level);
  }
}

final class _Api extends FakeDiscourseApi {
  Completer<List<int>?>? nextWrite;
  final writes = <({int id, CategoryNotificationLevel level})>[];
  final topicGates = <Completer<void>>[];
  Object? topicFailure;

  @override
  Future<void> updateTopicNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    await super.updateTopicNotificationLevel(
      siteUrl: siteUrl,
      apiKey: apiKey,
      topicId: topicId,
      notificationLevel: notificationLevel,
      clientId: clientId,
    );
    if (topicGates.isNotEmpty) await topicGates.removeAt(0).future;
    final failure = topicFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<List<int>?> updateCategoryNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int categoryId,
    required CategoryNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    writes.add((id: categoryId, level: notificationLevel));
    final gate = nextWrite;
    nextWrite = null;
    return gate == null ? [] : await gate.future;
  }
}

final class _HeldCredentials implements ApiCredentialReader {
  final key = Completer<String?>();
  int clientReads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) => key.future;

  @override
  Future<String> clientId() async {
    clientReads++;
    return 'client';
  }
}
