import 'package:discourse_native/src/data/store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://one.example';
const _otherSite = 'https://two.example';

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
