import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an already retired lease rejects a completed operation', () async {
    const site = 'https://meta.discourse.org';
    final lifecycle = SiteLifecycle();
    final lease = lifecycle.capture(site);
    lifecycle.invalidate(site);
    final error = StateError('retired');
    await expectLater(
      lease.waitWhileCurrent(
        Future.value(42),
        error,
        timeout: const Duration(seconds: 1),
      ),
      throwsA(same(error)),
    );
  });

  test('retirement invalidates a result completed in the same turn', () async {
    const site = 'https://meta.discourse.org';
    final lifecycle = SiteLifecycle();
    final lease = lifecycle.capture(site);
    final error = StateError('retired');
    final operation = Completer<int>.sync();
    unawaited(operation.future.then((_) => lifecycle.invalidate(site)));
    final pending = lease.waitWhileCurrent(operation.future, error);
    final rejected = expectLater(pending, throwsA(same(error)));

    operation.complete(42);

    await rejected;
  });

  test('only the current session can commit state for a site', () {
    final lifecycle = SiteLifecycle();
    final first = lifecycle.capture('https://meta.discourse.org');
    var commits = 0;

    expect(first.commit(() => commits++), isTrue);

    lifecycle.invalidate('https://meta.discourse.org');
    final second = lifecycle.capture('https://meta.discourse.org');

    expect(first.commit(() => commits++), isFalse);
    expect(second.commit(() => commits++), isTrue);
    expect(commits, 2);
  });

  test('invalidating one site does not disturb another', () {
    final lifecycle = SiteLifecycle();
    final firstSite = lifecycle.capture('https://meta.discourse.org');
    final secondSite = lifecycle.capture('https://other.example.com');

    lifecycle.invalidate('https://meta.discourse.org');

    expect(firstSite.commit(() {}), isFalse);
    expect(secondSite.commit(() {}), isTrue);
  });
  test('retirement observers see a stale lease and can detach', () {
    final lifecycle = SiteLifecycle();
    final lease = lifecycle.capture('https://forum.example');
    var called = 0;
    lease.onRetire(() {
      expect(lease.isCurrent, isFalse);
      called++;
    });
    final detach = lease.onRetire(() => fail('Detached observer ran.'));
    detach();
    lifecycle.invalidate('https://forum.example');
    lifecycle.invalidate('https://forum.example');
    expect(called, 1);
    var alreadyRetired = false;
    lease.onRetire(() => alreadyRetired = true);
    expect(alreadyRetired, isTrue);
  });

  test('an observer detached during retirement does not run', () {
    const site = 'https://forum.example';
    final lifecycle = SiteLifecycle();
    final lease = lifecycle.capture(site);
    late final void Function() detach;
    final calls = <String>[];
    lease.onRetire(() {
      calls.add('first');
      detach();
    });
    detach = lease.onRetire(() => calls.add('detached'));
    lease.onRetire(() => calls.add('last'));

    lifecycle.invalidate(site);

    expect(calls, ['first', 'last']);
  });

  test('an observer registered during retirement still runs', () {
    final lifecycle = SiteLifecycle();
    final lease = lifecycle.capture('https://forum.example');
    var lateObserverRan = false;
    lease.onRetire(() {
      lease.onRetire(() => lateObserverRan = true);
    });

    lifecycle.invalidate('https://forum.example');

    expect(lateObserverRan, isTrue);
  });

  test('retirement runs every observer before rethrowing a failure', () {
    final lifecycle = SiteLifecycle();
    final lease = lifecycle.capture('https://forum.example');
    final failure = StateError('retirement callback failed');
    final originalStack = StackTrace.fromString('original retirement stack');
    final calls = <int>[];
    lease.onRetire(() => calls.add(1));
    lease.onRetire(() {
      calls.add(2);
      Error.throwWithStackTrace(failure, originalStack);
    });
    lease.onRetire(() => calls.add(3));

    Object? observed;
    StackTrace? observedStack;
    try {
      lifecycle.invalidate('https://forum.example');
    } catch (error, stack) {
      observed = error;
      observedStack = stack;
    }
    expect(calls, [1, 2, 3]);
    expect(observed, same(failure));
    expect(observedStack.toString(), originalStack.toString());
    expect(lease.isCurrent, isFalse);
    lifecycle.invalidate('https://forum.example');
    expect(calls, [1, 2, 3]);
  });

  test(
    'multiple retirement failures preserve the first error and its stack',
    () {
      final lifecycle = SiteLifecycle();
      final lease = lifecycle.capture('https://forum.example');
      final first = StateError('first');
      final firstStack = StackTrace.fromString('first stack');
      var cleanupRan = false;
      lease.onRetire(() => Error.throwWithStackTrace(first, firstStack));
      lease.onRetire(() => throw StateError('second'));
      lease.onRetire(() => cleanupRan = true);

      Object? observed;
      StackTrace? observedStack;
      try {
        lifecycle.invalidate('https://forum.example');
      } catch (error, stack) {
        observed = error;
        observedStack = stack;
      }
      expect(cleanupRan, isTrue);
      expect(observed, same(first));
      expect(observedStack.toString(), firstStack.toString());
    },
  );

  test('failed retirement cleanup cannot remove a reentrant successor', () {
    const site = 'https://forum.example';
    final lifecycle = SiteLifecycle();
    final lease = lifecycle.capture(site);
    late SiteLease successor;
    final failure = StateError('old observer failed');
    var lastRan = false;
    lease.onRetire(() {
      successor = lifecycle.capture(site);
      throw failure;
    });
    lease.onRetire(() => lastRan = true);

    expect(() => lifecycle.invalidate(site), throwsA(same(failure)));
    expect(lastRan, isTrue);
    expect(successor.isCurrent, isTrue);
    expect(lifecycle.capture(site).session, same(successor.session));
    expect(() => lease.onRetire(() => throw failure), throwsA(same(failure)));
  });

  test('a retired lease keeps its own session identity', () {
    final lifecycle = SiteLifecycle();
    final first = lifecycle.capture('https://forum.example');
    final joined = lifecycle.capture('https://forum.example');
    final firstSession = first.session;

    expect(joined.session, same(firstSession));

    lifecycle.invalidate('https://forum.example');
    final successor = lifecycle.capture('https://forum.example');

    expect(first.session, same(firstSession));
    expect(successor.session, isNot(same(firstSession)));
  });
}
