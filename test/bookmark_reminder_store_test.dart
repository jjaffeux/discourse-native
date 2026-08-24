import 'package:discourse_native/src/data/bookmark_reminder_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('last custom reminders are isolated by site and account', () async {
    const store = BookmarkReminderStore();
    final reminder = DateTime.parse('2030-01-02T03:04:05+01:00');

    await store.write('https://one.example', 'Reader', reminder);

    expect(
      await store.read('https://one.example', 'reader'),
      DateTime.utc(2030, 1, 2, 2, 4, 5),
    );
    expect(await store.read('https://two.example', 'reader'), isNull);
    expect(await store.read('https://one.example', 'someone-else'), isNull);
  });

  test('malformed persisted choices decode as absent', () async {
    SharedPreferences.setMockInitialValues({
      'bookmark.last-custom.https%3A%2F%2Fone.example.reader': 'not-a-date',
    });

    expect(
      await const BookmarkReminderStore().read('https://one.example', 'reader'),
      isNull,
    );
  });
}
