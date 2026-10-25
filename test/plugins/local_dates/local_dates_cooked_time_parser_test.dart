import 'package:discourse_native/src/plugins/local_dates/local_date.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_cooked_time_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  final parser = LocalDatesCookedTimeParser(
    formatter: LocalDateFormatter(environment: LocalDateEnvironment.instance),
  );

  setUpAll(LocalDateEnvironment.instance.ensureDatabase);

  test('resolves a cooked descendant in its declared source timezone', () {
    final scope = html
        .parseFragment(
          '<div><span class="discourse-local-date" '
          'data-date="2026-08-01" data-time="10:24:00" '
          'data-timezone="Europe/Paris">fallback</span></div>',
        )
        .querySelector('div')!;

    expect(parser.parseDescendant(scope), DateTime.utc(2026, 8, 1, 8, 24));
  });

  test('skips a sanitizer-allowed data-date span without the class', () {
    // Upstream allowlists `span[data-date]` and friends on their own, so an
    // author can hand-write one; only `span.discourse-local-date` is a date.
    final scope = html
        .parseFragment(
          '<div><p><span data-date="2020-01-01" data-time="00:00:00" '
          'data-timezone="UTC">hand-written</span> then '
          '<span class="discourse-local-date" data-date="2026-08-01" '
          'data-time="10:24:00" data-timezone="Europe/Paris">fallback</span>'
          '</p></div>',
        )
        .querySelector('div')!;

    expect(parser.parseDescendant(scope), DateTime.utc(2026, 8, 1, 8, 24));
  });

  test('declines cooked markup without a Local Dates descendant', () {
    final unrelated = html
        .parseFragment(
          '<div><time datetime="2026-08-01T10:24:00Z">fallback</time></div>',
        )
        .querySelector('div')!;

    expect(parser.parseDescendant(unrelated), isNull);
  });

  test('declines a malformed Local Dates descendant', () {
    final malformed = html
        .parseFragment(
          '<div><span class="discourse-local-date" '
          'data-date="not-a-date">fallback</span></div>',
        )
        .querySelector('div')!;

    expect(parser.parseDescendant(malformed), isNull);
  });
}
