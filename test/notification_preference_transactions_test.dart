import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/current_user_reconciler.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/data/topic_tracking_reconciler.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/notification_preference_transactions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
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
      site: api,
      currentUsers: NotificationPreferenceCurrentUsers(
        read: (_) => user,
        reconcilerFor: (_) => currentUser,
        publish: (_, lease, updated) {
          if (failPublication) throw StateError('persistence unavailable');
          user = updated;
        },
      ),
      taxonomy: taxonomy,
      trackingEffects: NotificationPreferenceTracking(
        forSite: (_) => tracking,
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
              if (failRefresh) throw StateError('refresh unavailable');
              tracking.cancelSnapshot(ticket);
            },
      ),
      topicChanged: (_) {},
      changed: () {},
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

  void replaceAccount() {
    final lease = lifecycle.capture(_site);
    tracking = TopicTrackingReconciler(isCurrent: () => lease.isCurrent);
    currentUser = CurrentUserReconciler(
      lease: lease,
      models: const DiscourseModelCodec.core(),
    );
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

  @override
  void invalidateCategorySidebar(String siteUrl) {}

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
