import 'dart:collection';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/topic_reader_projections.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://reader.example';

final class _CountingStore extends Store {
  int reads = 0;
  int probes = 0;
  int retainedVisits = 0;

  @override
  Iterable<T?> retainedRecords<T extends Storable<T>>(String siteUrl) =>
      super.retainedRecords<T>(siteUrl).map((record) {
        if (T == Post) retainedVisits++;
        return record;
      });

  @override
  T? read<T extends Storable<T>>(String siteUrl, Object id) {
    if (T == Post) reads++;
    return super.read<T>(siteUrl, id);
  }

  @override
  bool containsRecord<T extends Storable<T>>(String siteUrl, Object id) {
    if (T == Post) probes++;
    return super.containsRecord<T>(siteUrl, id);
  }
}

final class _CountingStream extends ListBase<int> {
  _CountingStream(this._ids);

  final List<int> _ids;
  int reads = 0;

  @override
  int get length => _ids.length;

  @override
  set length(int value) => _ids.length = value;

  @override
  int operator [](int index) {
    reads++;
    return _ids[index];
  }

  @override
  void operator []=(int index, int value) => _ids[index] = value;
}

Post _post(int id, {int? number, String cooked = 'body'}) =>
    Post(id: id, postNumber: number ?? id, username: 'reader', cooked: cooked);

void main() {
  late _CountingStore store;
  late SiteLifecycle lifecycle;
  late TopicReaderProjections owner;

  setUp(() {
    store = _CountingStore();
    lifecycle = SiteLifecycle();
    owner = TopicReaderProjections(store);
  });
  tearDown(() => owner.dispose());

  TopicReaderProjection reader(String id) =>
      owner.forTab(_site, id, lifecycle.capture(_site))!;

  test('headless projections preserve anchored runs and structural keys', () {
    final tab = reader('a');
    final stream = [1, 2, 3, 4, 5, 6, 7];
    store.putAll(_site, [_post(1), _post(2), _post(5), _post(6), _post(7)]);
    final first = tab.project(stream, 2);
    expect(first.ids, [1, 2]);
    expect(first.range, (0, 1));
    expect(tab.project(stream, 5).ids, [5, 6, 7]);
    expect(tab.project(stream, 99).ids, [1, 2]);
    expect(tab.project(stream, null).ids, [1, 2]);
    final window = tab.project(stream, 5);
    expect(tab.initialIndex(window.ids, 6, hasEarlier: true), 2);
    store.reads = 0;
    for (var i = 0; i < 20; i++) {
      expect(tab.project(stream, 5), same(window));
      expect(tab.initialIndex(window.ids, 6, hasEarlier: true), 2);
    }
    expect(store.reads, 0);
    store.put(_site, _post(6, cooked: 'edited'));
    expect(tab.project(stream, 5), same(window));
    expect(store.reads, 0);
    store.put(_site, _post(6, number: 9));
    final renumbered = tab.project(stream, 5);
    expect(renumbered.ids, isNot(same(window.ids)));
    expect(tab.initialIndex(renumbered.ids, 8, hasEarlier: true), 2);
    store.remove<Post>(_site, 5);
    expect(tab.project(stream, 5).ids, [6, 7]);
    expect(tab.project(List.of(stream), 5).ids, isNot(same(renumbered.ids)));
  });

  test('unrelated structural changes do not scan stream or replace window', () {
    final tab = reader('a');
    final stream = _CountingStream([for (var id = 1; id <= 16000; id++) id]);
    store.putAll(_site, [_post(15900), _post(15901)]);
    final window = tab.project(stream, 15900);
    expect(window.ids, [15900, 15901]);
    expect(tab.initialIndex(window.ids, 15901, hasEarlier: true), 2);
    stream.reads = 0;
    store.reads = 0;
    store.probes = 0;
    for (var id = 20000; id < 22000; id++) {
      store.put(_site, _post(id));
      expect(tab.project(stream, 15900), same(window));
      store.remove<Post>(_site, id);
      expect(tab.project(stream, 15900), same(window));
      expect(tab.initialIndex(window.ids, 15901, hasEarlier: true), 2);
    }
    expect(stream.reads, 0);
    expect(store.reads, 0);
    expect(store.probes, 0);
    store.putAll(_site, [_post(15899), _post(15902)]);
    final expanded = tab.project(stream, 15900);
    expect(expanded.ids, [15899, 15900, 15901, 15902]);
    expect(tab.initialIndex(expanded.ids, 15901, hasEarlier: true), 3);
  });

  test(
    'missing target arrivals and structural updates replace saved index',
    () {
      final tab = reader('a');
      final stream = [1, 2, 3, 4, 5, 6];
      store.putAll(_site, [_post(1), _post(2), _post(5), _post(6)]);
      final fallback = tab.project(stream, 3);
      expect(fallback.ids, [5, 6]);
      store.put(_site, _post(3));
      final arrived = tab.project(stream, 3);
      expect(arrived.ids, [1, 2, 3]);
      expect(tab.initialIndex(arrived.ids, 3, hasEarlier: false), 2);
      store.update<Post>(_site, 2, (_) => _post(2, number: 4));
      final renumbered = tab.project(stream, 3);
      expect(tab.initialIndex(renumbered.ids, 3, hasEarlier: false), 1);
      store.remove<Post>(_site, 2);
      expect(tab.project(stream, 3).ids, [3]);
      store.forget(_site);
      expect(tab.project(stream, 3).ids, isEmpty);
      store.put(_site, _post(5));
      expect(tab.project(stream, 3).ids, [5]);
    },
  );

  test('unrelated insertion invalidates a window when it evicts its post', () {
    final bounded = Store(maxEntries: 2);
    final projections = TopicReaderProjections(bounded);
    addTearDown(projections.dispose);
    final tab = projections.forTab(_site, 'a', lifecycle.capture(_site))!;
    final stream = [1, 2];
    bounded.putAll(_site, [_post(1), _post(2)]);
    expect(tab.project(stream, null).ids, [1, 2]);
    bounded.put(_site, _post(99));
    expect(bounded.length, 2);
    expect(tab.project(stream, null).ids, [2]);
  });

  test('dependencies follow active streams and release with tab and lease', () {
    final a = reader('a');
    final ordinary = [1, 2, 3];
    final summary = [1, 3];
    for (var repeat = 0; repeat < 20; repeat++) {
      a.project(ordinary, null);
      expect(store.filteredStructureDependenciesForTesting, 1);
      a.project(summary, null);
      expect(store.filteredStructureDependenciesForTesting, 1);
    }
    final b = reader('b');
    b.project(summary, null);
    expect(store.structureDependenciesForTesting, (keys: 0, registrations: 0));
    expect(store.filteredStructureDependenciesForTesting, 2);
    owner.retainTabs(_site, lifecycle.capture(_site), {'b'});
    expect(store.filteredStructureDependenciesForTesting, 1);
    lifecycle.invalidate(_site);
    expect(store.filteredStructureDependenciesForTesting, 0);
    reader('b').project(ordinary, null);
    expect(store.filteredStructureDependenciesForTesting, 1);
    owner.dispose();
    expect(store.filteredStructureDependenciesForTesting, 0);
  });

  test(
    'sparse projections use first stream position and actual post numbers',
    () {
      final tab = reader('a');
      final stream = [900, 200, 800, 400, 600, 100, 700];
      store.putAll(_site, [
        _post(900, number: 1),
        _post(800, number: 90),
        _post(100, number: 80),
        _post(700, number: 2),
      ]);
      expect(tab.project(stream, 80).range, (2, 2));
      expect(tab.project(stream, 999).range, (0, 0));
      expect(tab.project(stream, null).range, (0, 0));
      store.put(_site, _post(200, number: 100));
      final arrived = tab.project(stream, 80);
      expect(arrived.ids, [900, 200, 800]);
      expect(tab.initialIndex(arrived.ids, 80, hasEarlier: false), 1);
      store.remove<Post>(_site, 200);
      expect(tab.project(stream, 80).range, (2, 2));

      store.forget(_site);
      store.putAll(_site, [_post(500, number: 4), _post(333, number: 100)]);
      expect(tab.project([500, 900, 500, 111, 333], 3).range, (0, 0));
    },
  );

  test('deep invalidation visits retained records rather than missing IDs', () {
    final tab = reader('a');
    final stream = [for (var id = 1; id <= 16000; id++) id];
    store.putAll(_site, [_post(15900), _post(15901)]);
    expect(tab.project(stream, 15900).ids, [15900, 15901]);
    expect(store.reads, lessThanOrEqualTo(5));
    expect(store.retainedVisits, 2);
    store.reads = 0;
    store.retainedVisits = 0;
    store.put(_site, _post(15899));
    expect(tab.project(stream, 15900).ids, [15899, 15900, 15901]);
    expect(store.reads, lessThanOrEqualTo(6));
    expect(store.retainedVisits, 3);
  });

  test(
    'short stream projection avoids visiting a larger retained partition',
    () {
      final tab = reader('a');
      store.putAll(_site, [for (var id = 1; id <= 200; id++) _post(id)]);
      expect(tab.project([4, 2, 6], 3).ids, [4, 2, 6]);
      expect(store.retainedVisits, 0);
      expect(store.reads, lessThanOrEqualTo(5));
    },
  );

  test('long stream head avoids visiting unrelated retained posts', () {
    final tab = reader('a');
    store.putAll(_site, [
      for (var id = 1; id <= 20; id++) _post(id),
      for (var id = 20000; id < 24000; id++) _post(id),
    ]);
    final stream = [for (var id = 1; id <= 16000; id++) id];
    expect(tab.project(stream, 10).ids, List.generate(20, (i) => i + 1));
    expect(store.retainedVisits, 0);
    store.put(_site, _post(2, number: 3));
    store.reads = 0;
    expect(tab.project(stream, 10).range, (0, 19));
    expect(store.retainedVisits, 0);
    expect(store.reads, lessThanOrEqualTo(30));
    expect(tab.project(stream, null).range, (0, 19));
    expect(store.retainedVisits, 0);
  });

  test('sparse projection invalidates after eviction and site forget', () {
    final bounded = Store(maxEntries: 2);
    final projections = TopicReaderProjections(bounded);
    addTearDown(projections.dispose);
    final tab = projections.forTab(_site, 'a', lifecycle.capture(_site))!;
    final stream = [for (var id = 1; id <= 100; id++) id];
    bounded.putAll(_site, [_post(90), _post(91)]);
    expect(tab.project(stream, 90).ids, [90, 91]);
    bounded.put(_site, _post(200));
    expect(tab.project(stream, 90).ids, [91]);
    bounded.forget(_site);
    expect(tab.project(stream, 90).ids, isEmpty);
    bounded.put(_site, _post(90));
    expect(tab.project(stream, 90).ids, [90]);
  });

  test('ordinary and summary stream identities select independent windows', () {
    final tab = reader('a');
    final ordinary = [1, 2, 3];
    final summary = [1, 3];
    store.putAll(_site, [_post(1), _post(3)]);
    expect(tab.project(ordinary, null).ids, [1]);
    final window = tab.project(summary, null);
    expect(window.ids, [1, 3]);
    expect(tab.project(summary, null), same(window));
    expect(tab.initialIndex(window.ids, 2, hasEarlier: false), 1);
    expect(tab.initialIndex(window.ids, 2, hasEarlier: true), 2);
    expect(tab.initialIndex(window.ids, 9, hasEarlier: false), isNull);
    expect(tab.project(ordinary, null).ids, [1]);
    expect(tab.project([], null).range, isNull);
  });

  test('alternating tabs retain their saved-index memo and list identity', () {
    final a = reader('a');
    final b = reader('b');
    final stream = [1, 2, 3, 4, 5];
    store.putAll(_site, [_post(1), _post(2), _post(4), _post(5)]);
    final left = a.project(stream, 1);
    final right = b.project(stream, 4);
    expect(a.initialIndex(left.ids, 2, hasEarlier: false), 1);
    expect(b.initialIndex(right.ids, 5, hasEarlier: true), 2);
    store.reads = 0;
    for (var i = 0; i < 20; i++) {
      expect(a.project(stream, 1), same(left));
      expect(a.initialIndex(left.ids, 2, hasEarlier: false), 1);
      expect(b.project(stream, 4), same(right));
      expect(b.initialIndex(right.ids, 5, hasEarlier: true), 2);
    }
    expect(store.reads, 0);
  });

  test('pending pages bound lookahead and preserve earlier slice policy', () {
    final tab = reader('a');
    final stream = [for (var id = 1; id <= 16000; id++) id];
    store.putAll(_site, [_post(4), _post(5), _post(8)]);
    final window = tab.project(stream, 4);
    store.probes = 0;
    store.reads = 0;
    expect(tab.pendingAfter(window, 4), [6, 7, 9, 10]);
    expect(store.probes, 5);
    expect(store.reads, 0);
    expect(tab.pendingBefore(window, 2), [2, 3]);
    expect(store.reads, 2);
    final empty = reader('b').project(stream, 16001);
    expect(empty.ids, [4, 5]);
    final unloaded = reader('c').project([20, 21], null);
    expect(tab.pendingAfter(unloaded, 1), [20]);
    expect(tab.pendingBefore(unloaded, 2), isEmpty);
  });

  test('mega edges use ordinary stream identity and fresh metadata', () {
    final tab = reader('a');
    store.putAll(_site, [_post(4), _post(5)]);
    const detail = TopicDetail(
      id: 7,
      title: 'Mega',
      stream: [4, 5],
      isMegaTopic: true,
      lastPostId: 6,
    );
    final window = tab.project(detail.stream, 4);
    expect(tab.megaEdge(window, detail, newer: false)?.id, 4);
    expect(tab.megaEdge(window, detail, newer: true)?.id, 5);
    expect(
      tab.megaEdge(window, detail.copyWith(lastPostId: 5), newer: true),
      isNull,
    );
    final summary = tab.project([4, 5], 4);
    expect(tab.megaEdge(summary, detail, newer: false), isNull);
    store.put(_site, _post(4, number: 1));
    expect(
      tab.megaEdge(tab.project(detail.stream, null), detail, newer: false),
      isNull,
    );
  });

  test('tab retirement cannot revive captured handles on ID reuse', () {
    final lease = lifecycle.capture(_site);
    final old = reader('reused');
    store.put(_site, _post(1));
    final stream = [1];
    final previous = old.project(stream, null);
    final other = reader('other');
    final otherWindow = other.project(stream, null);
    owner.retainTabs(_site, lease, {'other'});
    expect(old.isCurrent, isFalse);
    expect(old.project(stream, null).ids, isEmpty);
    expect(old.initialIndex(previous.ids, 1, hasEarlier: false), isNull);
    final successor = reader('reused');
    final current = successor.project(stream, null);
    expect(current.ids, [1]);
    expect(current.ids, isNot(same(previous.ids)));
    expect(other.project(stream, null), same(otherWindow));
    expect(old.pendingAfter(previous, 1), isEmpty);
    expect(successor.project(stream, null), same(current));
  });

  test('old account cleanup preserves a successor with the same tab ID', () {
    final lease = lifecycle.capture(_site);
    final old = reader('a');
    store.put(_site, _post(1));
    final stream = [1];
    final previous = old.project(stream, null);
    lifecycle.invalidate(_site);
    final successor = reader('a');
    final current = successor.project(stream, null);
    owner.retainTabs(_site, lease, {});
    expect(owner.forTab(_site, 'a', lease), isNull);
    expect(old.project(stream, null).ids, isEmpty);
    expect(old.initialIndex(previous.ids, 1, hasEarlier: false), isNull);
    expect(successor.project(stream, null), same(current));
    owner.dispose();
    expect(successor.project(stream, null).ids, isEmpty);
    expect(owner.forTab(_site, 'a', lifecycle.capture(_site)), isNull);
  });
}
