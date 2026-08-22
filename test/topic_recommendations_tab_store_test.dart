import 'package:discourse_native/src/data/topic_recommendations_tab_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = TopicRecommendationsTabStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('suggested topics show until another choice is saved', () async {
    expect(
      await store.read(siteUrl: 'https://meta.discourse.org'),
      TopicRecommendationsTab.suggested,
    );

    await store.write(
      siteUrl: 'https://meta.discourse.org',
      tab: TopicRecommendationsTab.related,
    );

    expect(
      await store.read(siteUrl: 'https://meta.discourse.org'),
      TopicRecommendationsTab.related,
    );
  });

  test('tab choices are independent by forum', () async {
    await store.write(
      siteUrl: 'https://meta.discourse.org',
      tab: TopicRecommendationsTab.related,
    );

    expect(
      await store.read(siteUrl: 'https://team.discourse.org'),
      TopicRecommendationsTab.suggested,
    );
    expect(
      await store.read(siteUrl: 'https://meta.discourse.org'),
      TopicRecommendationsTab.related,
    );
  });

  test('an unreadable stored value reads as suggested', () async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.topic_recommendations_tab.'
              'https%3A%2F%2Fmeta.discourse.org':
          'nonsense',
    });

    expect(
      await store.read(siteUrl: 'https://meta.discourse.org'),
      TopicRecommendationsTab.suggested,
    );
  });
}
