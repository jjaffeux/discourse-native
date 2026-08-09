import 'package:discourse_native/src/data/topic_recommendations_panel_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = TopicRecommendationsPanelStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('the panel is expanded until a collapsed choice is saved', () async {
    expect(await store.read(siteUrl: 'https://meta.discourse.org'), isFalse);

    await store.write(siteUrl: 'https://meta.discourse.org', collapsed: true);

    expect(await store.read(siteUrl: 'https://meta.discourse.org'), isTrue);
  });

  test('collapse choices are independent by forum', () async {
    await store.write(siteUrl: 'https://meta.discourse.org', collapsed: true);

    expect(await store.read(siteUrl: 'https://team.discourse.org'), isFalse);
    expect(await store.read(siteUrl: 'https://meta.discourse.org'), isTrue);
  });
}
