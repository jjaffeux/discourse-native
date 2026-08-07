import 'package:discourse_native/src/data/draft_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = DraftStore();

  const siteUrl = 'https://meta.discourse.org';
  const draftKey = 'topic_42';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('reads back what was written', () async {
    await store.write(siteUrl, draftKey, '{"reply": "Half a thought"}');

    expect(
      await store.read(siteUrl, draftKey),
      '{"reply": "Half a thought"}',
    );
  });

  test('reads nothing back for a draft never written', () async {
    expect(await store.read(siteUrl, draftKey), isNull);
  });

  test('clearing removes only the one draft', () async {
    await store.write(siteUrl, draftKey, 'kept elsewhere');
    await store.write(siteUrl, 'topic_43', 'also kept');
    await store.clear(siteUrl, draftKey);

    expect(await store.read(siteUrl, draftKey), isNull);
    expect(await store.read(siteUrl, 'topic_43'), 'also kept');
  });

  test('clearing a draft that was never written is nothing', () async {
    await store.clear(siteUrl, draftKey);
    expect(await store.read(siteUrl, draftKey), isNull);
  });

  test('the same draft key on two sites is two drafts', () async {
    await store.write(siteUrl, draftKey, 'first site');
    await store.write('https://other.example.com', draftKey, 'second site');

    expect(await store.read(siteUrl, draftKey), 'first site');
    expect(
      await store.read('https://other.example.com', draftKey),
      'second site',
    );
  });
}
