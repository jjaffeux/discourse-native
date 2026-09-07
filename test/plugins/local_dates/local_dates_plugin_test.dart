import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_plugin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final environment = LocalDateEnvironment.forTesting(
    detectDeviceTimezone: () async => 'Etc/UTC',
  );
  final plugin = LocalDatesPlugin(environment: environment);
  final futureYear = DateTime.now().year + 1;
  final futureDate =
      '<span class="discourse-local-date" '
      'data-date="$futureYear-01-15" data-time="10:24:00" '
      'data-timezone="Europe/Paris">January 15</span>';

  setUpAll(() async {
    environment.ensureDatabase();
    await initializeDateFormatting('en');
  });
  tearDownAll(environment.dispose);

  group('futureBookmarkReminder', () {
    for (final entry in {
      'one paragraph': '<p>Meet at $futureDate.</p>',
      'three top-level elements':
          '<p>Meeting details</p><p>$futureDate</p><p>Bring notes.</p>',
      'a top-level date': futureDate,
    }.entries) {
      test('resolves a date to UTC in ${entry.key}', () {
        expect(
          plugin.futureBookmarkReminder(
            entry.value,
            accountTimezone: 'America/New_York',
          ),
          DateTime.utc(futureYear, 1, 15, 9, 24),
        );
      });
    }

    for (final entry in {
      'empty HTML': '',
      'plain text': 'No date here.',
      'one paragraph': '<p>No date here.</p>',
      'multiple paragraphs': '<p>One</p><p>Two</p><p>Three</p>',
    }.entries) {
      test('returns no reminder for ${entry.key} without dates', () {
        expect(
          plugin.futureBookmarkReminder(entry.value, accountTimezone: null),
          isNull,
        );
      });
    }

    test(
      'returns the first future date in post order after invalid and past dates',
      () {
        final cooked =
            '<p><span class="discourse-local-date" '
            'data-date="not-a-date">Invalid</span></p>'
            '<p><span class="discourse-local-date" '
            'data-date="${futureYear - 2}-01-15">Past</span></p>'
            '<p>$futureDate</p>'
            '<p><span class="discourse-local-date" '
            'data-date="$futureYear-01-01">Earlier future date</span></p>';

        expect(
          plugin.futureBookmarkReminder(cooked, accountTimezone: null),
          DateTime.utc(futureYear, 1, 15, 9, 24),
        );
      },
    );
  });
}
