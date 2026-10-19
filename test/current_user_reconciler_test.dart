import 'package:discourse_native/src/data/current_user_reconciler.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _models = DiscourseModelCodec.core();
const _firstOption = PluginDataKey<String>(owner: 'test', name: 'first');
const _secondOption = PluginDataKey<String>(owner: 'test', name: 'second');
const _unrelatedOption = PluginDataKey<String>(
  owner: 'test',
  name: 'unrelated',
);

void main() {
  late SiteLifecycle lifecycle;
  late CurrentUserReconciler reconciler;

  setUp(() {
    lifecycle = SiteLifecycle();
    reconciler = CurrentUserReconciler(
      lease: lifecycle.capture(_site),
      models: _models,
    );
  });

  test('accepts the first user without treating it as an account change', () {
    final ticket = reconciler.beginSnapshot();
    const incoming = DiscourseUser(id: 7, username: 'sam', name: 'Sam');

    final result = reconciler.reconcile(
      ticket,
      previous: null,
      incoming: incoming,
    );

    expect(result, isNotNull);
    expect(result!.user.name, 'Sam');
    expect(result.accountChanged, isFalse);
    expect(result.seedGroupedUnreadCounts, isTrue);
  });

  test('accepts fresh same-account fields and retains unknown namespaces', () {
    final previous = DiscourseUser(
      id: 7,
      username: 'sam',
      name: 'Old name',
      hidePresence: false,
      draftCount: 2,
      plugins: PluginData.preserveNamespaces(const {
        'future-plugin/user': {'setting': 'held'},
      }),
    );
    final ticket = reconciler.beginSnapshot();
    const incoming = DiscourseUser(
      id: 7,
      username: 'renamed-sam',
      name: 'Fresh name',
      hidePresence: true,
      draftCount: 5,
    );

    final result = reconciler.reconcile(
      ticket,
      previous: previous,
      incoming: incoming,
    )!;

    expect(result.accountChanged, isFalse);
    expect(result.seedGroupedUnreadCounts, isTrue);
    expect(result.user.name, 'Fresh name');
    expect(result.user.hidePresence, isTrue);
    expect(result.user.draftCount, 5);
    expect(result.user.plugins.preservedNamespaces, {
      'future-plugin/user': {'setting': 'held'},
    });
  });

  test('a pending presence write protects the confirmed field', () {
    reconciler.presenceWriteStarted();
    final ticket = reconciler.beginSnapshot();

    final result = reconciler.reconcile(
      ticket,
      previous: const DiscourseUser(
        id: 7,
        username: 'sam',
        hidePresence: false,
      ),
      incoming: const DiscourseUser(
        id: 7,
        username: 'sam',
        name: 'Fresh name',
        hidePresence: true,
      ),
    )!;

    expect(result.user.hidePresence, isFalse);
    expect(result.user.name, 'Fresh name');
  });

  test(
    'presence settlement preserves older responses after success or failure',
    () {
      for (final confirmedValue in [true, false]) {
        final ticket = reconciler.beginSnapshot();
        reconciler.presenceWriteStarted();
        reconciler.presenceWriteSettled();

        final result = reconciler.reconcile(
          ticket,
          previous: DiscourseUser(
            id: 7,
            username: 'sam',
            hidePresence: confirmedValue,
          ),
          incoming: DiscourseUser(
            id: 7,
            username: 'sam',
            name: 'Fresh name',
            hidePresence: !confirmedValue,
          ),
        )!;

        expect(result.user.hidePresence, confirmedValue);
        expect(result.user.name, 'Fresh name');
      }
    },
  );

  test(
    'equal live grouped authority blocks stale totals but not fresh fields',
    () {
      final counts = NotificationTypeCounts.fromWire(const {'1': 3});
      final ticket = reconciler.beginSnapshot();
      reconciler.groupedUnreadChanged();

      final stale = reconciler.reconcile(
        ticket,
        previous: DiscourseUser(
          id: 7,
          username: 'sam',
          groupedUnreadNotifications: counts,
        ),
        incoming: DiscourseUser(
          id: 7,
          username: 'sam',
          name: 'Fresh name',
          groupedUnreadNotifications: NotificationTypeCounts.fromWire(const {
            '1': 9,
          }),
        ),
      )!;

      expect(stale.user.groupedUnreadNotifications.toJson(), {'1': 3});
      expect(stale.user.name, 'Fresh name');
      expect(stale.seedGroupedUnreadCounts, isFalse);

      final current = reconciler.reconcile(
        reconciler.beginSnapshot(),
        previous: stale.user,
        incoming: DiscourseUser(
          id: 7,
          username: 'sam',
          groupedUnreadNotifications: NotificationTypeCounts.fromWire(const {
            '1': 9,
          }),
        ),
      )!;
      expect(current.user.groupedUnreadNotifications.toJson(), {'1': 9});
      expect(current.seedGroupedUnreadCounts, isTrue);
    },
  );

  test('equal draft authority protects a live count from an old response', () {
    final ticket = reconciler.beginSnapshot();
    reconciler.draftCountChanged();

    final result = reconciler.reconcile(
      ticket,
      previous: const DiscourseUser(id: 7, username: 'sam', draftCount: 4),
      incoming: const DiscourseUser(
        id: 7,
        username: 'sam',
        name: 'Fresh name',
        draftCount: 1,
      ),
    )!;

    expect(result.user.draftCount, 4);
    expect(result.user.name, 'Fresh name');
  });

  test(
    'a category write protects all five lists and unrelated fields refresh',
    () {
      final ticket = reconciler.beginSnapshot();
      reconciler.categoryPreferencesChanged();

      final result = reconciler.reconcile(
        ticket,
        previous: const DiscourseUser(
          id: 7,
          username: 'sam',
          trackedCategoryIds: [1],
          watchedCategoryIds: [2],
          watchedFirstPostCategoryIds: [3],
          mutedCategoryIds: [4],
          indirectlyMutedCategoryIds: [5],
        ),
        incoming: const DiscourseUser(
          id: 7,
          username: 'sam',
          name: 'Fresh name',
          trackedCategoryIds: [11],
          watchedCategoryIds: [12],
          watchedFirstPostCategoryIds: [13],
          mutedCategoryIds: [14],
          indirectlyMutedCategoryIds: [15],
        ),
      )!;

      expect(result.user.name, 'Fresh name');
      expect(result.user.trackedCategoryIds, [1]);
      expect(result.user.watchedCategoryIds, [2]);
      expect(result.user.watchedFirstPostCategoryIds, [3]);
      expect(result.user.mutedCategoryIds, [4]);
      expect(result.user.indirectlyMutedCategoryIds, [5]);
    },
  );

  test('category tickets guard bootstrap and selective same-account reads', () {
    final beforeWrite = reconciler.beginSnapshot();
    expect(reconciler.categoryPreferencesAreCurrent(beforeWrite), isTrue);
    expect(
      reconciler.acceptsCategoryPreferences(
        beforeWrite,
        previous: null,
        incoming: const DiscourseUser(id: 7, username: 'sam'),
      ),
      isFalse,
    );

    final afterWrite = reconciler.categoryPreferencesChanged();
    expect(reconciler.categoryPreferencesAreCurrent(beforeWrite), isFalse);
    expect(reconciler.categoryPreferencesAreCurrent(afterWrite), isTrue);
    expect(
      reconciler.acceptsCategoryPreferences(
        afterWrite,
        previous: const DiscourseUser(id: 7, username: 'sam'),
        incoming: const DiscourseUser(id: 7, username: 'renamed-sam'),
      ),
      isTrue,
    );
    expect(
      reconciler.acceptsCategoryPreferences(
        afterWrite,
        previous: const DiscourseUser(id: 7, username: 'sam'),
        incoming: const DiscourseUser(id: 8, username: 'sam'),
      ),
      isFalse,
    );

    reconciler.categoryPreferencesChanged();
    expect(
      reconciler.acceptsCategoryPreferences(
        afterWrite,
        previous: const DiscourseUser(id: 7, username: 'sam'),
        incoming: const DiscourseUser(id: 7, username: 'sam'),
      ),
      isFalse,
    );
  });

  test('plugin replay keeps each latest option and unrelated plugin data', () {
    final previous = DiscourseUser(
      id: 7,
      username: 'sam',
      plugins: PluginData.preserveNamespaces(const {
        'future-plugin/user': {'held': true},
      }),
    );
    final ticket = reconciler.beginSnapshot();
    final first = reconciler.updatePluginOption(
      'first',
      previous: previous,
      update: (data) => data
          .withValue(_firstOption, 'obsolete')
          .withValue(_unrelatedOption, null),
    );
    final second = reconciler.updatePluginOption(
      'second',
      previous: first,
      update: (data) => data.withValue(_secondOption, 'confirmed'),
    );
    final latest = reconciler.updatePluginOption(
      'first',
      previous: second,
      update: (data) => data.withValue(_firstOption, 'latest'),
    );
    expect(latest.plugins.get(_firstOption), 'latest');
    expect(latest.plugins.get(_secondOption), 'confirmed');

    final incoming = DiscourseUser(
      id: 7,
      username: 'sam',
      name: 'Fresh name',
      plugins: PluginData.preserveNamespaces(const {
        'future-plugin/new': {'fresh': true},
      }).withValue(_unrelatedOption, 'fresh-from-server'),
    );
    final result = reconciler.reconcile(
      ticket,
      previous: latest,
      incoming: incoming,
    )!;

    expect(result.user.name, 'Fresh name');
    expect(result.user.plugins.get(_firstOption), 'latest');
    expect(result.user.plugins.get(_secondOption), 'confirmed');
    expect(result.user.plugins.get(_unrelatedOption), 'fresh-from-server');
    expect(result.user.plugins.preservedNamespaces, {
      'future-plugin/user': {'held': true},
      'future-plugin/new': {'fresh': true},
    });

    final later = reconciler.reconcile(
      reconciler.beginSnapshot(),
      previous: result.user,
      incoming: DiscourseUser(
        id: 7,
        username: 'sam',
        plugins: PluginData.none.withValue(_firstOption, 'server-current'),
      ),
    )!;
    expect(later.user.plugins.get(_firstOption), 'server-current');
  });

  test(
    'account change clears old overlays but later changes cross old tickets',
    () {
      const oldAccount = DiscourseUser(id: 7, username: 'sam');
      final editedOld = reconciler.updatePluginOption(
        'first',
        previous: oldAccount,
        update: (data) => data.withValue(_firstOption, 'old-account'),
      );
      final oldSameLeaseTicket = reconciler.beginSnapshot();
      final newerOld = reconciler.updatePluginOption(
        'second',
        previous: editedOld,
        update: (data) => data.withValue(_secondOption, 'retired-option'),
      );
      reconciler.groupedUnreadChanged();
      final changed = reconciler.reconcile(
        oldSameLeaseTicket,
        previous: newerOld,
        incoming: const DiscourseUser(id: 8, username: 'alex', name: 'Alex'),
      )!;

      expect(changed.accountChanged, isTrue);
      expect(changed.seedGroupedUnreadCounts, isTrue);
      expect(changed.user.plugins.get(_firstOption), isNull);

      final newAccount = reconciler.updatePluginOption(
        'first',
        previous: changed.user,
        update: (data) => data.withValue(_firstOption, 'new-account'),
      );
      final delayed = reconciler.reconcile(
        oldSameLeaseTicket,
        previous: newAccount,
        incoming: const DiscourseUser(id: 8, username: 'alex', name: 'Later'),
      )!;

      expect(delayed.accountChanged, isFalse);
      expect(delayed.user.name, 'Later');
      expect(delayed.user.plugins.get(_firstOption), 'new-account');
      expect(delayed.user.plugins.get(_secondOption), isNull);
    },
  );

  test(
    'concurrent same-lease responses remain admissible in arrival order',
    () {
      final first = reconciler.beginSnapshot();
      final second = reconciler.beginSnapshot();

      final changed = reconciler.reconcile(
        second,
        previous: const DiscourseUser(id: 7, username: 'sam'),
        incoming: const DiscourseUser(id: 8, username: 'alex'),
      )!;
      final laterArrival = reconciler.reconcile(
        first,
        previous: changed.user,
        incoming: const DiscourseUser(id: 7, username: 'sam', name: 'Later'),
      );

      expect(laterArrival, isNotNull);
      expect(laterArrival!.accountChanged, isTrue);
      expect(laterArrival.user.id, 7);
      expect(laterArrival.user.name, 'Later');
    },
  );

  test('foreign, invalidated and retired owners reject their tickets', () {
    final ticket = reconciler.beginSnapshot();
    final foreign = CurrentUserReconciler(
      lease: lifecycle.capture(_site),
      models: _models,
    );
    const user = DiscourseUser(id: 7, username: 'sam');

    expect(foreign.reconcile(ticket, previous: null, incoming: user), isNull);
    expect(foreign.categoryPreferencesAreCurrent(ticket), isFalse);
    expect(
      foreign.acceptsCategoryPreferences(
        ticket,
        previous: user,
        incoming: user,
      ),
      isFalse,
    );

    lifecycle.invalidate(_site);
    expect(
      reconciler.reconcile(ticket, previous: null, incoming: user),
      isNull,
    );
    expect(reconciler.categoryPreferencesAreCurrent(ticket), isFalse);

    final replacement = CurrentUserReconciler(
      lease: lifecycle.capture(_site),
      models: _models,
    );
    expect(
      replacement.reconcile(ticket, previous: null, incoming: user),
      isNull,
    );
    expect(
      replacement.reconcile(
        replacement.beginSnapshot(),
        previous: null,
        incoming: user,
      ),
      isNotNull,
    );

    final replacementTicket = replacement.beginSnapshot();
    replacement.retire();
    expect(
      replacement.reconcile(replacementTicket, previous: null, incoming: user),
      isNull,
    );
    expect(
      replacement.categoryPreferencesAreCurrent(replacementTicket),
      isFalse,
    );
    expect(
      replacement
          .updatePluginOption(
            'first',
            previous: user,
            update: (data) => data.withValue(_firstOption, 'rejected'),
          )
          .plugins
          .get(_firstOption),
      isNull,
    );
  });
}
