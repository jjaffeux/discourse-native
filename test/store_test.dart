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
      // Other sites and types are untouched by this write.
      expect(store.generationOf<_Record>(_otherSite), 0);
      expect(store.generationOf<_OtherRecord>(_site), 0);

      store.update<_Record>(_site, 1, (held) => _Record(held.id, 'second'));
      final afterUpdate = store.generationOf<_Record>(_site);
      expect(afterUpdate, greaterThan(afterPut));

      // A change that resolves to the identical record is not a change.
      store.update<_Record>(_site, 1, (held) => held);
      expect(store.generationOf<_Record>(_site), afterUpdate);

      store.remove<_Record>(_site, 1);
      final afterRemove = store.generationOf<_Record>(_site);
      expect(afterRemove, greaterThan(afterUpdate));
      // Removing what is already gone changes nothing.
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
