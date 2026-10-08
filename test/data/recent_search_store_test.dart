import 'package:discourse_native/src/data/recent_search_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'removed recents persist per site and account without affecting another account',
    () async {
      const store = RecentSearchStore();
      await store.write('https://example.com', 'sam', {'design keyboard'});
      await store.write('https://example.com', 'mira', {'private message'});
      expect(await store.read('https://example.com', 'sam'), {
        'design keyboard',
      });
      expect(await store.read('https://other.example', 'sam'), isEmpty);
      await store.write('https://example.com', 'sam', {});
      expect(await store.read('https://example.com', 'sam'), isEmpty);
      expect(await store.read('https://example.com', 'mira'), {
        'private message',
      });
    },
  );
}
