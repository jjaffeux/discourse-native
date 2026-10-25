import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
