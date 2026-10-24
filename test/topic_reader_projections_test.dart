import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/topic_reader_projections.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://reader.example';

final class _CountingStore extends Store {
  int reads = 0;
  int probes = 0;

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
