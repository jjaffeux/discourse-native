import 'dart:async';

import 'package:discourse_native/src/plugins/discourse_placeholder/placeholder_session.dart';
import 'package:discourse_native/src/plugins/discourse_placeholder/placeholder_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('duplicate release cannot retire another acquisition', () async {
    final session = PlaceholderSession(
      persistence: MemoryPlaceholderPersistence(),
      currentUser: (_) => 1,
    );
    final first = session.acquire('https://example.com', 2, 3);
    final second = session.acquire('https://example.com', 2, 3);
    await session.flush();
    first.release();
    first.release();
    second.change('X', 'peer');
    expect(second.isCurrent, isTrue);
    expect(second.overrides, {'X': 'peer'});
    second.release();
    await session.close();
  });

  test('closing clears and notifies retained values', () async {
    final session = PlaceholderSession(
      persistence: MemoryPlaceholderPersistence(),
      currentUser: (_) => 1,
    );
    final values = session.acquire('https://example.com', 2, 3);
    await session.flush();
    values.change('X', 'private');
    await session.flush();
    var changes = 0;
    values.addListener(() => changes++);
    await session.close();
    expect(values.overrides, isEmpty);
    expect(changes, 1);
    expect(values.isCurrent, isFalse);
    values.release();
  });

  test(
    'a closed session rejects acquisition before consulting persistence',
    () async {
      var identities = 0;
      final session = PlaceholderSession(
        persistence: MemoryPlaceholderPersistence(),
        currentUser: (_) {
          identities++;
          return 1;
        },
      );
      await session.close();
      expect(
        () => session.acquire('https://example.com', 2, 3),
        throwsStateError,
      );
      expect(identities, 0);
    },
  );

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
      values.release();
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
    first.release();
    second.release();
    await session.flush();
    final remounted = session.acquire('https://example.com', 2, 3);
    await session.flush();
    expect(remounted.overrides, {'X': 'local'});
    remounted.change('X', 'default', defaultValue: 'default');
    await session.flush();
    expect(store.values[remounted.id], isEmpty);
    remounted.release();
    await session.close();
  });

  test('close notifications can release their own acquisitions', () async {
    final session = PlaceholderSession(
      persistence: MemoryPlaceholderPersistence(),
      currentUser: (_) => 1,
    );
    final first = session.acquire('https://example.com', 2, 3);
    final second = session.acquire('https://example.com', 2, 3);
    await session.flush();
    first.change('X', 'private');
    first.addListener(first.release);
    second.addListener(second.release);
    await session.close();
    expect(first.isCurrent, isFalse);
    expect(second.isCurrent, isFalse);
    first.release();
    second.release();
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
    old.release();
    replacement.release();
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
    values.release();
    await session.close();
  });

  test('replacement account edits survive an unfinished forget', () async {
    var user = 1;
    final store = _HeldWritePersistence();
    final session = PlaceholderSession(
      persistence: store,
      currentUser: (_) => user,
    );
    final old = session.acquire('https://example.com', 2, 3);
    await session.flush();
    old.change('X', 'old account');
    await store.writeStarted.future;

    final forgetting = session.forget('https://example.com');
    user = 2;
    final replacement = session.acquire('https://example.com', 2, 3);
    expect(old.isCurrent, isFalse);
    expect(replacement.isCurrent, isTrue);
    replacement.change('X', 'new account');
    store.writeGate.complete();
    await forgetting;
    await session.flush();
    old.release();
    replacement.release();

    final remounted = session.acquire('https://example.com', 2, 3);
    await session.flush();
    expect(remounted.overrides, {'X': 'new account'});
    remounted.release();
    await session.close();
  });

  test('a replacement lease does not restore values being forgotten', () async {
    final store = _HeldWritePersistence();
    final session = PlaceholderSession(
      persistence: store,
      currentUser: (_) => 1,
    );
    final old = session.acquire('https://example.com', 2, 3);
    await session.flush();
    store.values[old.id] = {'X': 'saved'};
    old.change('X', 'pending');
    await store.writeStarted.future;

    final forgetting = session.forget('https://example.com');
    final replacement = session.acquire('https://example.com', 2, 3);
    await pumpEventQueue();
    store.writeGate.complete();
    await forgetting;
    await session.flush();

    expect(replacement.overrides, isEmpty);
    expect(store.values, isEmpty);
    old.release();
    replacement.release();
    await session.close();
  });
}

final class _HeldWritePersistence extends MemoryPlaceholderPersistence {
  final writeStarted = Completer<void>();
  final writeGate = Completer<void>();

  @override
  Future<void> write(PlaceholderPostId post, String key, String? value) async {
    if (post.userId == 1) {
      writeStarted.complete();
      await writeGate.future;
    }
    await super.write(post, key, value);
  }
}
