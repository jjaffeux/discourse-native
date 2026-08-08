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
}
