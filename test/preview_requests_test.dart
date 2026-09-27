// Pure `test` only: the shell constructs this notifier from pure-Dart entry
// points too, so it must keep working with no Flutter binding.
import 'package:discourse_native/src/shell/preview_requests.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://meta.discourse.org';
const _otherSite = 'https://discuss.example.com';

void main() {
  test('one fetch runs at a time and the next clears its failure', () {
    final requests = PreviewRequests<int>();
    addTearDown(requests.dispose);
    var notifications = 0;
    requests.addListener(() => notifications++);

    expect(requests.begin(_site, 1), isTrue);
    expect(requests.begin(_site, 1), isFalse);
    expect(requests.begin(_otherSite, 1), isTrue);
    expect(requests.isPending(_site, 1), isTrue);
    expect(notifications, 2);

    requests.finish(_site, 1, error: 'Unavailable');
    expect(requests.isPending(_site, 1), isFalse);
    expect(requests.errorFor(_site, 1), 'Unavailable');
    expect(requests.errorFor(_otherSite, 1), isNull);
    expect(notifications, 3);

    expect(requests.begin(_site, 1), isTrue);
    expect(requests.errorFor(_site, 1), isNull);
    requests.finish(_site, 1);
    expect(requests.errorFor(_site, 1), isNull);
    expect(notifications, 5);
  });

  test('forgetting a site drops only its fetches and failures', () {
    final requests = PreviewRequests<String>();
    addTearDown(requests.dispose);
    requests
      ..begin(_site, 'sam')
      ..begin(_site, 'alex')
      ..finish(_site, 'alex', error: 'Gone')
      ..begin(_otherSite, 'sam')
      ..finish(_otherSite, 'sam', error: 'Elsewhere');
    var notifications = 0;
    requests.addListener(() => notifications++);

    requests.forget(_site);
    expect(requests.isPending(_site, 'sam'), isFalse);
    expect(requests.errorFor(_site, 'alex'), isNull);
    expect(requests.errorFor(_otherSite, 'sam'), 'Elsewhere');
    expect(notifications, 1);

    // A fetch that outlived its site's state records nothing.
    requests
      ..finish(_site, 'sam', error: 'Stale')
      ..forget(_site);
    expect(requests.errorFor(_site, 'sam'), isNull);
    expect(notifications, 1);
  });

  test('a disposed notifier ignores fetches that settle late', () {
    final requests = PreviewRequests<int>()..dispose();

    expect(requests.begin(_site, 1), isFalse);
    requests.finish(_site, 1, error: 'Late');
    expect(requests.errorFor(_site, 1), isNull);
  });
}
