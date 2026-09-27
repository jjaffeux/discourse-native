import 'dart:collection';
import 'dart:math';

import 'package:discourse_native/src/data/store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

const _site = 'https://one.example';
const _otherSite = 'https://two.example';
const _thirdSite = 'https://three.example';
const _fourthSite = 'https://four.example';

class _Record with Storable<_Record> {
  const _Record(this.id, this.label);

  final int id;
  final String label;

  @override
  Object get storeId => id;
}

class _OtherRecord with Storable<_OtherRecord> {
  const _OtherRecord(this.id);

  final int id;

  @override
  Object get storeId => id;
}

class _ThirdRecord with Storable<_ThirdRecord> {
  const _ThirdRecord(this.id);

  final int id;

  @override
  Object get storeId => id;
}

class _MergingRecord with Storable<_MergingRecord> {
  const _MergingRecord(this.id, this.versions);

  final int id;
  final List<String> versions;

  @override
  Object get storeId => id;

  @override
  _MergingRecord merge(_MergingRecord incoming) =>
      _MergingRecord(id, [...versions, ...incoming.versions]);
}

void main() {
  group('Store', () {
    test('removes matching records only from the selected site and type', () {
      final store = Store();
      store.put(_site, const _Record(1, 'private'));
      store.put(_site, const _Record(2, 'public'));
      store.put(_otherSite, const _Record(1, 'private'));
      store.put(_site, const _OtherRecord(1));
      final ref = store.ref<_Record>(_site, 1);
      var notifications = 0;
      void listener() => notifications++;
      ref.addListener(listener);
      addTearDown(() => ref.removeListener(listener));
      store.removeMatching<_Record>(
        _site,
        (record) => record.label == 'private',
      );
      expect(ref.value, isNull);
      expect(notifications, 1);
      expect(store.read<_Record>(_site, 2)?.label, 'public');
      expect(store.read<_Record>(_otherSite, 1)?.label, 'private');
      expect(store.read<_OtherRecord>(_site, 1)?.id, 1);
    });

    test('keeps one stable ref through put, update, and remove', () {
      final store = Store();
      final ref = store.ref<_Record>(_site, 1);
      var notifications = 0;
      ref.addListener(() => notifications++);

      const arrived = _Record(1, 'arrived');
      expect(store.put(_site, arrived), same(arrived));
      expect(store.ref<_Record>(_site, 1), same(ref));
      expect(store.read<_Record>(_site, 1), same(arrived));

      store.update<_Record>(_site, 1, (held) => _Record(held.id, 'updated'));
      expect(ref.value?.label, 'updated');

      store.remove<_Record>(_site, 1);
      store.remove<_Record>(_site, 1);
      expect(ref.value, isNull);
      expect(store.ref<_Record>(_site, 1), same(ref));
      expect(store.length, 1);
      expect(notifications, 3);
    });

    test('uses the held record merge result as the canonical value', () {
      final store = Store();
      const first = _MergingRecord(1, ['first']);
      const second = _MergingRecord(1, ['second']);

      expect(store.put(_site, first), same(first));
      final merged = store.put(_site, second);

      expect(merged.versions, ['first', 'second']);
      expect(store.read<_MergingRecord>(_site, 1), same(merged));
      expect(store.ref<_MergingRecord>(_site, 1).value, same(merged));
    });

    test('putAll returns canonical records in payload order', () {
      final store = Store();
      const records = [
        _MergingRecord(1, ['one']),
        _MergingRecord(2, ['two']),
        _MergingRecord(1, ['new one']),
      ];

      final held = store.putAll(_site, records);

      expect(held.map((record) => record.versions), [
        ['one'],
        ['two'],
        ['one', 'new one'],
      ]);
      expect(store.length, 2);
    });

    test('keys records independently by site, type, and ID', () {
      final store = Store();
      final firstSite = store.ref<_Record>(_site, 1);
      final secondSite = store.ref<_Record>(_otherSite, 1);
      final otherType = store.ref<_OtherRecord>(_site, 1);

      store.put(_site, const _Record(1, 'first site'));
      store.put(_otherSite, const _Record(1, 'second site'));
      store.put(_site, const _OtherRecord(1));

      expect(firstSite.value?.label, 'first site');
      expect(secondSite.value?.label, 'second site');
      expect(otherType.value?.id, 1);
      expect(store.length, 3);
    });

    test('tracks a change generation per site and type', () {
      final store = Store();
      expect(store.generationOf<_Record>(_site), 0);

      store.put(_site, const _Record(1, 'first'));
      final afterPut = store.generationOf<_Record>(_site);
      expect(afterPut, greaterThan(0));
      expect(store.generationOf<_Record>(_otherSite), 0);
      expect(store.generationOf<_OtherRecord>(_site), 0);

      store.update<_Record>(_site, 1, (held) => _Record(held.id, 'second'));
      final afterUpdate = store.generationOf<_Record>(_site);
      expect(afterUpdate, greaterThan(afterPut));

      store.update<_Record>(_site, 1, (held) => held);
      expect(store.generationOf<_Record>(_site), afterUpdate);

      store.remove<_Record>(_site, 1);
      final afterRemove = store.generationOf<_Record>(_site);
      expect(afterRemove, greaterThan(afterUpdate));
      store.remove<_Record>(_site, 1);
      expect(store.generationOf<_Record>(_site), afterRemove);
    });

    test('absent updates and removals do not allocate refs', () {
      final store = Store();

      store.update<_Record>(
        _site,
        1,
        (held) => _Record(held.id, 'unreachable'),
      );
      store.remove<_Record>(_site, 1);

      expect(store.length, 0);
    });

    test('evicts least-recently-used records beyond the capacity', () {
      final store = Store(maxEntries: 2)
        ..put(_site, const _Record(1, 'one'))
        ..put(_site, const _Record(2, 'two'));

      // Reading one makes two the least-recently-used entry.
      expect(store.read<_Record>(_site, 1)?.label, 'one');
      store.put(_site, const _Record(3, 'three'));

      expect(store.length, 2);
      expect(store.read<_Record>(_site, 1)?.label, 'one');
      expect(store.read<_Record>(_site, 2), isNull);
      expect(store.read<_Record>(_site, 3)?.label, 'three');
    });

    test('checks record presence without touching LRU order', () {
      final store = Store(maxEntries: 2)
        ..put(_site, const _Record(1, 'one'))
        ..put(_site, const _Record(2, 'two'));

      expect(store.containsRecord<_Record>(_site, 1), isTrue);
      expect(store.containsRecord<_Record>(_site, 9), isFalse);
      store.put(_site, const _Record(3, 'three'));

      expect(store.containsRecord<_Record>(_site, 1), isFalse);
      expect(store.containsRecord<_Record>(_site, 2), isTrue);
      expect(store.containsRecord<_Record>(_site, 3), isTrue);
    });

    test('bounds long sessions by global, site, and record-kind shares', () {
      const policy = StorePolicy(
        maxEntries: 48,
        maxEntriesPerSite: 16,
        maxEntriesPerSiteAndType: 10,
      );
      final store = Store(policy: policy);
      const sites = [_site, _otherSite, 'https://three.example'];

      for (var id = 0; id < 10000; id++) {
        final site = sites[id % sites.length];
        if (id.isEven) {
          store.put(site, _Record(id, '$id'));
        } else {
          store.put(site, _OtherRecord(id));
        }
      }

      final statistics = store.statisticsForTesting;
      expect(statistics.entries, lessThanOrEqualTo(policy.maxEntries));
      expect(statistics.records, statistics.entries);
      expect(statistics.evictions, greaterThan(9000));
      expect(statistics.recordEvictions, statistics.evictions);
      for (final site in sites) {
        expect(
          statistics.entriesBySite[site],
          lessThanOrEqualTo(policy.maxEntriesPerSite!),
          reason: site,
        );
        expect(
          statistics.entriesFor<_Record>(site),
          lessThanOrEqualTo(policy.maxEntriesPerSiteAndType!),
          reason: '$site records',
        );
        expect(
          statistics.entriesFor<_OtherRecord>(site),
          lessThanOrEqualTo(policy.maxEntriesPerSiteAndType!),
          reason: '$site other records',
        );
      }
    });

    test('fair eviction protects smaller site and type working sets', () {
      final sites = Store(policy: const StorePolicy(maxEntries: 4))
        ..put(_site, const _Record(1, 'one'))
        ..put(_site, const _Record(2, 'two'))
        ..put(_otherSite, const _Record(1, 'other one'))
        ..put(_otherSite, const _Record(2, 'other two'));
      // Make the other site's rows globally oldest. Plain global LRU would
      // evict one even though the first site is the partition growing.
      sites
        ..read<_Record>(_site, 1)
        ..read<_Record>(_site, 2)
        ..put(_site, const _Record(3, 'three'));

      expect(sites.read<_Record>(_site, 1), isNull);
      expect(sites.read<_Record>(_site, 2), isNotNull);
      expect(sites.read<_Record>(_site, 3), isNotNull);
      expect(sites.read<_Record>(_otherSite, 1), isNotNull);
      expect(sites.read<_Record>(_otherSite, 2), isNotNull);

      final types = Store(policy: const StorePolicy(maxEntries: 4))
        ..put(_site, const _Record(1, 'one'))
        ..put(_site, const _Record(2, 'two'))
        ..put(_site, const _OtherRecord(1))
        ..put(_site, const _OtherRecord(2));
      types
        ..read<_Record>(_site, 1)
        ..read<_Record>(_site, 2)
        ..put(_site, const _Record(3, 'three'));

      expect(types.read<_Record>(_site, 1), isNull);
      expect(types.read<_Record>(_site, 2), isNotNull);
      expect(types.read<_Record>(_site, 3), isNotNull);
      expect(types.read<_OtherRecord>(_site, 1), isNotNull);
      expect(types.read<_OtherRecord>(_site, 2), isNotNull);
    });

    // Victims come from per-partition indexes, which must choose exactly what
    // the fairness rule chooses when stated directly as a walk of every held
    // ref in least-recently-used order. Each sequence must also still reach
    // every share its policy sets, and equal shares, or it proves nothing.
    for (final (shares, policy, reaches) in _differentialPolicies) {
      for (final seed in [1, 2, 3]) {
        test('evicts the refs a walk of every held ref chooses '
            '(shares: $shares, seed: $seed)', () {
          final reference = _expectReferenceEvictions(policy, seed);

          expect(reference.reached, containsAll(reaches));
        });
      }
    }

    // A full store evicts once per new record, so a 100-record putAll at the
    // production capacity took 6-10 ms on a desktop when each choice walked
    // every held ref. Eight times the capacity separates that walk (~7x) from
    // reading the oldest candidate of each partition (~1x).
    for (final (share, full) in _fullStores) {
      test('evicts through the $share at a cost independent of '
          'capacity', () {
        final stores = [full(512), full(4096)];

        final (:small, :large) = measureScaling(
          stores.first.insert,
          stores.last.insert,
        );

        expect(
          large,
          lessThan(small * 3),
          reason:
              'eight times the capacity took ${large / small} times as long',
        );
        for (final store in stores) {
          expect(store.held(), store.bound, reason: 'each insert evicted');
        }
      });
    }

    test('record eviction advances only the affected generation', () {
      final store = Store(maxEntries: 2)
        ..put(_site, const _Record(1, 'one'))
        ..put(_site, const _Record(2, 'two'));
      final beforeEviction = store.generationOf<_Record>(_site);

      store.put(_site, const _Record(3, 'three'));

      expect(
        store.generationOf<_Record>(_site),
        beforeEviction + 2,
        reason: 'one generation for eviction and one for insertion',
      );
      expect(store.generationOf<_OtherRecord>(_site), 0);
      expect(store.statisticsForTesting.recordEvictions, 1);

      final emptyRefs = Store(maxEntries: 2)
        ..ref<_Record>(_site, 1)
        ..ref<_Record>(_site, 2)
        ..ref<_Record>(_site, 3);
      expect(emptyRefs.generationOf<_Record>(_site), 0);
      expect(emptyRefs.statisticsForTesting.evictions, 1);
      expect(emptyRefs.statisticsForTesting.recordEvictions, 0);
    });

    test('pins observed refs while evicting an unobserved record', () {
      final store = Store(maxEntries: 2);
      final pinned = store.ref<_Record>(_site, 1);
      void listener() {}

      pinned.addListener(listener);
      addTearDown(() => pinned.removeListener(listener));
      store
        ..put(_site, const _Record(1, 'pinned'))
        ..put(_site, const _Record(2, 'evictable'))
        ..put(_site, const _Record(3, 'latest'));

      expect(store.ref<_Record>(_site, 1), same(pinned));
      expect(pinned.value?.label, 'pinned');
      expect(store.read<_Record>(_site, 2), isNull);
      expect(store.read<_Record>(_site, 3)?.label, 'latest');
    });

    test('reports pinned overflow without detaching listened refs', () {
      final store = Store(maxEntries: 2);
      final first = store.ref<_Record>(_site, 1);
      final second = store.ref<_Record>(_site, 2);
      void listener() {}

      first.addListener(listener);
      second.addListener(listener);
      addTearDown(() {
        first.removeListener(listener);
        second.removeListener(listener);
      });
      store
        ..put(_site, const _Record(1, 'first'))
        ..put(_site, const _Record(2, 'second'))
        ..put(_site, const _Record(3, 'third'));

      expect(store.ref<_Record>(_site, 1), same(first));
      expect(store.ref<_Record>(_site, 2), same(second));
      expect(first.value?.label, 'first');
      expect(second.value?.label, 'second');
      expect(store.statisticsForTesting.observedEntries, 2);
      expect(store.statisticsForTesting.overCapacity, 1);

      store.put(_site, const _Record(4, 'fourth'));

      expect(store.read<_Record>(_site, 3), isNull);
      expect(store.read<_Record>(_site, 4), isNotNull);
      expect(store.statisticsForTesting.entries, 3);
      expect(store.statisticsForTesting.overCapacity, 1);
    });

    test('fully deletes an unobserved tombstone', () {
      final store = Store()..put(_site, const _Record(1, 'one'));

      store.remove<_Record>(_site, 1);

      expect(store.length, 0);
    });

    test('forget clears only one site and starts it with fresh refs', () {
      final store = Store();
      final first = store.ref<_Record>(_site, 1);
      final second = store.ref<_Record>(_site, 2);
      final other = store.ref<_Record>(_otherSite, 1);
      var firstNotifications = 0;
      var secondNotifications = 0;
      var otherNotifications = 0;
      first.addListener(() => firstNotifications++);
      second.addListener(() => secondNotifications++);
      other.addListener(() => otherNotifications++);
      store.put(_site, const _Record(1, 'one'));
      store.put(_site, const _Record(2, 'two'));
      store.put(_otherSite, const _Record(1, 'other'));

      store.forget(_site);

      expect(first.value, isNull);
      expect(second.value, isNull);
      expect(other.value?.label, 'other');
      expect(firstNotifications, 2);
      expect(secondNotifications, 2);
      expect(otherNotifications, 1);
      expect(store.length, 1);
      expect(store.statisticsForTesting.entriesBySite, {_otherSite: 1});
      expect(store.statisticsForTesting.entriesFor<_Record>(_site), 0);

      final reconnected = store.ref<_Record>(_site, 1);
      expect(reconnected, isNot(same(first)));
      store.put(_site, const _Record(1, 'reconnected'));
      expect(reconnected.value?.label, 'reconnected');
      expect(first.value, isNull);
      expect(firstNotifications, 2);
    });

    test('forget allows listeners to perform reentrant store lookups', () {
      final store = Store();
      final ref = store.ref<_Record>(_site, 1);
      store.put(_site, const _Record(1, 'one'));
      late Ref<_Record> lookedUp;
      ref.addListener(() {
        lookedUp = store.ref<_Record>(_otherSite, 9);
      });

      expect(() => store.forget(_site), returnsNormally);
      expect(lookedUp, same(store.ref<_Record>(_otherSite, 9)));
      expect(store.length, 1);
    });
  });

  testWidgets('a ref rebuilds its value listener on changes', (tester) async {
    final store = Store();
    final ref = store.ref<_Record>(_site, 1);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<_Record?>(
          valueListenable: ref,
          builder: (context, record, child) => Text(record?.label ?? 'empty'),
        ),
      ),
    );
    expect(find.text('empty'), findsOneWidget);

    store.put(_site, const _Record(1, 'loaded'));
    await tester.pump();
    expect(find.text('loaded'), findsOneWidget);

    store.remove<_Record>(_site, 1);
    await tester.pump();
    expect(find.text('empty'), findsOneWidget);
  });
}

const _partitionShare = 'site-and-type share';
const _siteShare = 'site share';
const _globalShare = 'global share';
const _tiedShares = 'tied shares';

const _differentialPolicies = [
  (
    'global, site, and site-and-type',
    StorePolicy(
      maxEntries: 24,
      maxEntriesPerSite: 12,
      maxEntriesPerSiteAndType: 6,
    ),
    [_partitionShare, _siteShare, _globalShare, _tiedShares],
  ),
  ('global', StorePolicy(maxEntries: 14), [_globalShare, _tiedShares]),
  (
    'global and site',
    StorePolicy(maxEntries: 24, maxEntriesPerSite: 10),
    [_siteShare, _globalShare, _tiedShares],
  ),
  (
    'global and site-and-type',
    StorePolicy(maxEntries: 20, maxEntriesPerSiteAndType: 5),
    [_partitionShare, _globalShare, _tiedShares],
  ),
];

StorePolicy _productionShaped(int capacity) => StorePolicy(
  maxEntries: capacity,
  maxEntriesPerSite: capacity ~/ 2,
  maxEntriesPerSiteAndType: capacity ~/ 4,
);

/// A store filled to one share's bound: every further [_Record] that [insert]
/// stores evicts through that share, so what [held] counts stays at [bound].
typedef _FullStore = ({int Function() insert, int Function() held, int bound});

final List<(String, _FullStore Function(int capacity))> _fullStores = [
  (
    _partitionShare,
    (capacity) {
      // Another type's older records precede the partition's own.
      final store = Store(policy: _productionShaped(capacity));
      var id = 0;
      for (var index = 0; index < capacity ~/ 4; index++) {
        store.put(_site, _OtherRecord(id++));
      }
      for (var index = 0; index < capacity ~/ 4; index++) {
        store.put(_site, _Record(id++, ''));
      }
      return (
        insert: () => store.put(_site, _Record(id++, '')).id,
        held: () => store.statisticsForTesting.entriesFor<_Record>(_site),
        bound: capacity ~/ 4,
      );
    },
  ),
  (
    _siteShare,
    (capacity) {
      final store = Store(policy: _productionShaped(capacity));
      var id = 0;
      for (var index = 0; index < capacity ~/ 4; index++) {
        store.put(_site, _OtherRecord(id++));
      }
      for (var index = 0; index < capacity ~/ 8; index++) {
        store
          ..put(_site, _ThirdRecord(id++))
          ..put(_site, _Record(id++, ''));
      }
      return (
        insert: () => store.put(_site, _Record(id++, '')).id,
        held: () => store.statisticsForTesting.entriesBySite[_site] ?? 0,
        bound: capacity ~/ 2,
      );
    },
  ),
  (
    _globalShare,
    (capacity) {
      final store = Store(policy: _productionShaped(capacity));
      var id = 0;
      for (final site in [_site, _otherSite, _thirdSite, _fourthSite]) {
        for (var index = 0; index < capacity ~/ 8; index++) {
          store
            ..put(site, _OtherRecord(id++))
            ..put(site, _Record(id++, ''));
        }
      }
      return (
        insert: () => store.put(_site, _Record(id++, '')).id,
        held: () => store.statisticsForTesting.entries,
        bound: capacity,
      );
    },
  ),
];

typedef _Key = (String, Type, int);

/// Addresses one record type's generic Store API from a randomized sequence.
abstract interface class _Kind {
  Type get type;

  Object put(Store store, String siteUrl, int id);

  List<Object> putAll(Store store, String siteUrl, List<int> ids);

  Object? read(Store store, String siteUrl, int id);

  Ref<Object> ref(Store store, String siteUrl, int id);

  void remove(Store store, String siteUrl, int id);

  bool contains(Store store, String siteUrl, int id);

  int generation(Store store, String siteUrl);
}

final class _KindOf<T extends Storable<T>> implements _Kind {
  _KindOf(this._create);

  final T Function(int id) _create;

  @override
  Type get type => T;

  @override
  Object put(Store store, String siteUrl, int id) =>
      store.put<T>(siteUrl, _create(id));

  @override
  List<Object> putAll(Store store, String siteUrl, List<int> ids) =>
      store.putAll<T>(siteUrl, [for (final id in ids) _create(id)]);

  @override
  Object? read(Store store, String siteUrl, int id) =>
      store.read<T>(siteUrl, id);

  @override
  Ref<Object> ref(Store store, String siteUrl, int id) =>
      store.ref<T>(siteUrl, id);

  @override
  void remove(Store store, String siteUrl, int id) =>
      store.remove<T>(siteUrl, id);

  @override
  bool contains(Store store, String siteUrl, int id) =>
      store.containsRecord<T>(siteUrl, id);

  @override
  int generation(Store store, String siteUrl) => store.generationOf<T>(siteUrl);
}

const _differentialSites = [_site, _otherSite, _thirdSite];
const _differentialIds = 12;
final List<_Kind> _differentialKinds = [
  _KindOf<_Record>((id) => _Record(id, '$id')),
  _KindOf<_OtherRecord>(_OtherRecord.new),
  _KindOf<_ThirdRecord>(_ThirdRecord.new),
];

/// Drives [Store] and [_ReferenceStore] through one randomized sequence and
/// expects the same refs to be held after every operation.
_ReferenceStore _expectReferenceEvictions(StorePolicy policy, int seed) {
  final random = Random(seed);
  final store = Store(policy: policy);
  final reference = _ReferenceStore(policy);
  final observed = <_Key, (Ref<Object>, _ReferenceCell)>{};
  final handles = <(_Key, Ref<Object>, _ReferenceCell)>[];
  void listener() {}

  for (var step = 0; step < 1500; step++) {
    // Favour one site so site shares differ while equal shares still occur.
    final siteUrl =
        _differentialSites[min(
          random.nextInt(4),
          _differentialSites.length - 1,
        )];
    final kind = _differentialKinds[random.nextInt(_differentialKinds.length)];
    final id = random.nextInt(_differentialIds);
    final key = (siteUrl, kind.type, id);
    final roll = random.nextInt(100);
    final String operation;
    if (roll < 35) {
      operation = 'put $key';
      reference.put(key, kind.put(store, siteUrl, id));
    } else if (roll < 45) {
      final ids = [
        for (var count = random.nextInt(5); count >= 0; count--)
          random.nextInt(_differentialIds),
      ];
      operation = 'putAll ${kind.type} $ids on $siteUrl';
      final stored = kind.putAll(store, siteUrl, ids);
      for (final (index, id) in ids.indexed) {
        reference.put((siteUrl, kind.type, id), stored[index]);
      }
    } else if (roll < 63) {
      operation = 'read $key';
      expect(
        kind.read(store, siteUrl, id),
        same(reference.read(key)),
        reason: 'seed $seed, step $step: $operation',
      );
    } else if (roll < 71) {
      operation = 'ref $key';
      handles.add((key, kind.ref(store, siteUrl, id), reference.ref(key)));
      if (handles.length > 48) handles.removeAt(0);
    } else if (roll < 79) {
      operation = 'observe $key';
      final ref = kind.ref(store, siteUrl, id);
      final cell = reference.ref(key);
      if (!observed.containsKey(key)) {
        ref.addListener(listener);
        cell.observers++;
        observed[key] = (ref, cell);
      }
    } else if (roll < 88) {
      operation = 'unobserve';
      if (observed.isNotEmpty) {
        final key = observed.keys.elementAt(random.nextInt(observed.length));
        final (ref, cell) = observed.remove(key)!;
        ref.removeListener(listener);
        cell.observers--;
      }
    } else if (roll < 98) {
      operation = 'remove $key';
      kind.remove(store, siteUrl, id);
      reference.remove(key);
    } else {
      operation = 'forget $siteUrl';
      store.forget(siteUrl);
      reference.forget(siteUrl);
      observed.removeWhere((key, entry) {
        if (key.$1 != siteUrl) return false;
        entry.$1.removeListener(listener);
        return true;
      });
    }

    final reason = 'seed $seed, step $step: $operation';
    expect(_describe(store), reference.describe(), reason: reason);
    expect(
      [
        for (final (key, ref, cell) in handles)
          if (reference.holds(key, cell) && !identical(ref.value, cell.value))
            key,
      ],
      isEmpty,
      reason: '$reason; a ref still held diverged from its reference',
    );
  }
  for (final (ref, _) in observed.values) {
    ref.removeListener(listener);
  }
  return reference;
}

Map<String, Object> _describe(Store store) {
  final statistics = store.statisticsForTesting;
  return {
    'entries': statistics.entries,
    'records': statistics.records,
    'observed': statistics.observedEntries,
    'evictions': statistics.evictions,
    'record evictions': statistics.recordEvictions,
    'by site': statistics.entriesBySite,
    'by partition': statistics.entriesByPartition,
    'held records': {
      for (final siteUrl in _differentialSites)
        for (final kind in _differentialKinds)
          for (var id = 0; id < _differentialIds; id++)
            if (kind.contains(store, siteUrl, id)) (siteUrl, kind.type, id),
    },
    'generations': {
      for (final siteUrl in _differentialSites)
        for (final kind in _differentialKinds)
          (siteUrl, kind.type): kind.generation(store, siteUrl),
    },
  };
}

final class _ReferenceCell {
  Object? value;
  int observers = 0;
}

/// Store's victim selection as it was before partitions were indexed: every
/// choice walks all held refs in least-recently-used order.
final class _ReferenceStore {
  _ReferenceStore(this.policy);

  final StorePolicy policy;
  final LinkedHashMap<_Key, _ReferenceCell> _cells = LinkedHashMap();
  final Map<(String, Type), int> _generations = {};
  final Set<String> reached = {};
  int _evictions = 0;
  int _recordEvictions = 0;

  bool holds(_Key key, _ReferenceCell cell) => identical(_cells[key], cell);

  _ReferenceCell ref(_Key key) {
    final held = _cells.remove(key);
    if (held != null) return _cells[key] = held;
    final created = _cells[key] = _ReferenceCell();
    _trim(key);
    return created;
  }

  Object? read(_Key key) {
    final held = _cells.remove(key);
    if (held == null) return null;
    _cells[key] = held;
    return held.value;
  }

  void put(_Key key, Object record) {
    final cell = ref(key);
    if (!identical(cell.value, record)) _bump(key);
    cell.value = record;
    _trim(key);
  }

  void remove(_Key key) {
    final cell = _cells[key];
    if (cell == null) return;
    if (cell.value != null) _bump(key);
    cell.value = null;
    if (cell.observers == 0) _cells.remove(key);
  }

  void forget(String siteUrl) {
    _generations.removeWhere((partition, _) => partition.$1 == siteUrl);
    _cells.removeWhere((key, _) => key.$1 == siteUrl);
  }

  Map<String, Object> describe() => {
    'entries': _cells.length,
    'records': _cells.values.where((cell) => cell.value != null).length,
    'observed': _cells.values.where((cell) => cell.observers > 0).length,
    'evictions': _evictions,
    'record evictions': _recordEvictions,
    'by site': {
      for (final siteUrl in _cells.keys.map((key) => key.$1).toSet())
        siteUrl: _count((key) => key.$1 == siteUrl),
    },
    'by partition': {
      for (final (siteUrl, type, _) in _cells.keys)
        (siteUrl: siteUrl, type: type): _count(
          (key) => key.$1 == siteUrl && key.$2 == type,
        ),
    },
    'held records': {
      for (final MapEntry(:key, :value) in _cells.entries)
        if (value.value != null) key,
    },
    'generations': {
      for (final siteUrl in _differentialSites)
        for (final kind in _differentialKinds)
          (siteUrl, kind.type): _generations[(siteUrl, kind.type)] ?? 0,
    },
  };

  void _bump(_Key key) {
    final partition = (key.$1, key.$2);
    _generations[partition] = (_generations[partition] ?? 0) + 1;
  }

  int _count(bool Function(_Key key) matches) =>
      _cells.keys.where(matches).length;

  void _trim(_Key keep) {
    bool inPartition(_Key key) => key.$1 == keep.$1 && key.$2 == keep.$2;

    final partitionLimit = policy.maxEntriesPerSiteAndType;
    if (partitionLimit != null) {
      while (_count(inPartition) > partitionLimit &&
          _evict(_oldestEvictable(keep, inPartition), _partitionShare)) {}
    }

    final siteLimit = policy.maxEntriesPerSite;
    if (siteLimit != null) {
      while (_count((key) => key.$1 == keep.$1) > siteLimit &&
          _evict(_fairTypeVictim(keep, keep.$1), _siteShare)) {}
    }

    while (_cells.length > policy.maxEntries &&
        _evict(_fairSiteAndTypeVictim(keep), _globalShare)) {}
  }

  _Key? _oldestEvictable(_Key keep, bool Function(_Key key) matches) {
    for (final MapEntry(:key, :value) in _cells.entries) {
      if (key == keep || value.observers > 0 || !matches(key)) continue;
      return key;
    }
    return null;
  }

  _Key? _fairTypeVictim(_Key keep, String siteUrl) {
    final totals = <Type, int>{};
    final candidates = <Type, _Key>{};
    for (final MapEntry(:key, :value) in _cells.entries) {
      if (key.$1 != siteUrl) continue;
      totals[key.$2] = (totals[key.$2] ?? 0) + 1;
      if (key != keep && value.observers == 0) {
        candidates.putIfAbsent(key.$2, () => key);
      }
    }
    final type = _largest(totals, candidates);
    return type == null ? null : candidates[type];
  }

  _Key? _fairSiteAndTypeVictim(_Key keep) {
    final totals = <String, int>{};
    final candidates = <String, _Key>{};
    for (final MapEntry(:key, :value) in _cells.entries) {
      totals[key.$1] = (totals[key.$1] ?? 0) + 1;
      if (key != keep && value.observers == 0) {
        candidates.putIfAbsent(key.$1, () => key);
      }
    }
    final siteUrl = _largest(totals, candidates);
    return siteUrl == null ? null : _fairTypeVictim(keep, siteUrl);
  }

  /// The candidate with the largest total; equal totals keep the candidate
  /// met first, which is the least recently used.
  K? _largest<K>(Map<K, int> totals, Map<K, _Key> candidates) {
    K? largest;
    var largestTotal = -1;
    for (final key in candidates.keys) {
      final total = totals[key]!;
      if (total > largestTotal) {
        largest = key;
        largestTotal = total;
      }
    }
    if (candidates.keys.where((key) => totals[key] == largestTotal).length >
        1) {
      reached.add(_tiedShares);
    }
    return largest;
  }

  bool _evict(_Key? key, String share) {
    if (key == null) return false;
    final evicted = _cells.remove(key)!;
    reached.add(share);
    _evictions++;
    if (evicted.value != null) {
      _recordEvictions++;
      _bump(key);
    }
    return true;
  }
}
