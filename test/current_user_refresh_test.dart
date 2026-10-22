import 'dart:async';

import 'package:discourse_native/src/data/current_user_refresh.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const site = 'https://example.com';
  const initial = DiscourseUser(id: 7, username: 'reader', draftCount: 8);
  const replayed = DiscourseUser(id: 7, username: 'reader', draftCount: 3);

  test(
    'force bursts share the next read while ordinary callers join active',
    () async {
      final reads = <Completer<DiscourseUser?>>[];
      final refresh = CurrentUserRefresh(
        lease: SiteLifecycle().capture(site),
        read: () {
          final read = Completer<DiscourseUser?>();
          reads.add(read);
          return read.future;
        },
      );
      addTearDown(refresh.retire);
      final first = refresh.request();
      final ordinary = refresh.request();
      final forced = List.generate(12, (_) => refresh.request(force: true));
      var forceSettled = false;
      unawaited(Future.wait(forced).then((_) => forceSettled = true));
      expect(reads, hasLength(1));
      reads.first.complete(initial);
      expect(await first, same(initial));
      expect(await ordinary, same(initial));
      expect(reads, hasLength(2));
      expect(forceSettled, isFalse);

      final joinsReplay = refresh.request();
      final later = List.generate(9, (_) => refresh.request(force: true));
      reads[1].complete(replayed);
      expect(await Future.wait(forced), everyElement(same(replayed)));
      expect(await joinsReplay, same(replayed));
      expect(reads, hasLength(3));
      const latest = DiscourseUser(id: 7, username: 'reader', draftCount: 1);
      reads[2].complete(latest);
      expect(await Future.wait(later), everyElement(same(latest)));
      await Future<void>.delayed(Duration.zero);
      expect(reads, hasLength(3));
    },
  );

  test(
    'retiring an account settles waiters and suppresses its pending replay',
    () async {
      final lifecycle = SiteLifecycle();
      final oldRead = Completer<DiscourseUser?>();
      var oldReads = 0;
      final old = CurrentUserRefresh(
        lease: lifecycle.capture(site),
        read: () {
          oldReads++;
          return oldRead.future;
        },
      );
      final active = old.request();
      final pending = old.request(force: true);
      lifecycle.invalidate(site);
      expect(await active, isNull);
      expect(await pending, isNull);
      expect(await old.request(force: true), isNull);

      final replacement = CurrentUserRefresh(
        lease: lifecycle.capture(site),
        read: () async => replayed,
      );
      addTearDown(replacement.retire);
      expect(await replacement.request(), same(replayed));
      oldRead.complete(initial);
      await Future<void>.delayed(Duration.zero);
      expect(oldReads, 1);
      expect(await replacement.request(), same(replayed));
    },
  );

  for (final throwsSynchronously in [true, false]) {
    test(
      'a failed read settles and permits retry, synchronous=$throwsSynchronously',
      () async {
        final gate = Completer<DiscourseUser?>();
        var reads = 0;
        final refresh = CurrentUserRefresh(
          lease: SiteLifecycle().capture(site),
          read: () {
            reads++;
            if (reads > 1) return Future.value(replayed);
            if (throwsSynchronously) throw StateError('failed');
            return gate.future;
          },
        );
        addTearDown(refresh.retire);
        final failed = expectLater(refresh.request(), throwsStateError);
        final next = refresh.request(force: true);
        if (!throwsSynchronously) gate.completeError(StateError('failed'));
        await failed;
        expect(await next, same(replayed));
        expect(reads, 2);
      },
    );
  }

  test(
    'read reentrancy queues only one replay before the first await',
    () async {
      final gate = Completer<DiscourseUser?>();
      late final CurrentUserRefresh refresh;
      late Future<DiscourseUser?> forced;
      var reads = 0;
      refresh = CurrentUserRefresh(
        lease: SiteLifecycle().capture(site),
        read: () {
          reads++;
          if (reads == 1) {
            forced = refresh.request(force: true);
            expect(refresh.request(), isNotNull);
            return gate.future;
          }
          return Future.value(replayed);
        },
      );
      addTearDown(refresh.retire);
      final first = refresh.request();
      gate.complete(initial);
      expect(await first, same(initial));
      expect(await forced, same(replayed));
      expect(reads, 2);
    },
  );
}
