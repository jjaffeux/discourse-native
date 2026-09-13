import 'dart:async';

import 'package:discourse_native/src/plugins/discourse_placeholder/placeholder_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test(
    'late restoration never overwrites newer input or resurrects a reset',
    () async {
      final store = MemoryPlaceholderPersistence()..readGate = Completer();
      final session = PlaceholderSession(
        persistence: store,
        currentUser: (_) => 1,
      );
      final values = session.acquire('https://example.com', 2, 3);
      values.change('X', 'new');
      values.change('Y', '', defaultValue: 'default');
      store.readGate!.complete({'X': 'old', 'Y': 'old', 'Z': 'restored'});
      await session.flush();
      expect(values.overrides, {'X': 'new', 'Z': 'restored'});
      session.release(values);
      await session.close();
    },
  );

  test('leases share changes and remount restores from persistence', () async {
    final store = MemoryPlaceholderPersistence();
    final session = PlaceholderSession(
      persistence: store,
      currentUser: (_) => 1,
    );
    final first = session.acquire('https://example.com', 2, 3);
    final second = session.acquire('https://example.com', 2, 3);
    await session.flush();
    first.change('X', 'local');
    expect(second.overrides, {'X': 'local'});
    session.release(first);
    session.release(second);
    await session.flush();
    final remounted = session.acquire('https://example.com', 2, 3);
    await session.flush();
    expect(remounted.overrides, {'X': 'local'});
    remounted.change('X', 'default', defaultValue: 'default');
    await session.flush();
    expect(store.values[remounted.id], isEmpty);
    session.release(remounted);
    await session.close();
  });

  test('account replacement rejects stale reads and writes', () async {
    var user = 1;
    final store = MemoryPlaceholderPersistence()..readGate = Completer();
    final session = PlaceholderSession(
      persistence: store,
      currentUser: (_) => user,
    );
    final old = session.acquire('https://example.com', 2, 3);
    user = 9;
    old.change('X', 'stale');
    store.readGate!.complete({'X': 'old account'});
    await session.flush();
    expect(old.overrides, isEmpty);
    expect(store.writes, isEmpty);
    store.readGate = null;
    final replacement = session.acquire('https://example.com', 2, 3);
    await session.flush();
    expect(replacement.overrides, isEmpty);
    session.release(old);
    session.release(replacement);
    await session.close();
  });

  test('forget detaches active leases and removes accepted writes', () async {
    final store = MemoryPlaceholderPersistence();
    final session = PlaceholderSession(
      persistence: store,
      currentUser: (_) => 1,
    );
    final values = session.acquire('https://example.com', 2, 3);
    await session.flush();
    values.change('X', 'saved');
    await session.forget('https://example.com');
    values.change('X', 'stale');
    expect(values.overrides, isEmpty);
    expect(store.values, isEmpty);
    expect(store.writes, hasLength(1));
    session.release(values);
    await session.close();
  });
}
