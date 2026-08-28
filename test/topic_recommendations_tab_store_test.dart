import 'package:discourse_native/src/data/topic_recommendations_tab_store.dart';
import 'package:discourse_native/src/plugin_api/topic_recommendation_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = TopicRecommendationsTabStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('core suggestions show until another source is saved', () async {
    expect(
      await store.read(siteUrl: 'https://meta.discourse.org'),
      coreSuggestedTopicRecommendationSourceId,
    );

    await store.write(
      siteUrl: 'https://meta.discourse.org',
      sourceId: const TopicRecommendationSourceId('test/popular'),
    );

    expect(
      await store.read(siteUrl: 'https://meta.discourse.org'),
      const TopicRecommendationSourceId('test/popular'),
    );
  });

  test('tab choices are independent by forum', () async {
    await store.write(
      siteUrl: 'https://meta.discourse.org',
      sourceId: const TopicRecommendationSourceId('test/popular'),
    );

    expect(
      await store.read(siteUrl: 'https://team.discourse.org'),
      coreSuggestedTopicRecommendationSourceId,
    );
    expect(
      await store.read(siteUrl: 'https://meta.discourse.org'),
      const TopicRecommendationSourceId('test/popular'),
    );
  });

  test('migrates the legacy suggested and related tab names', () async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.topic_recommendations_tab.'
              'https%3A%2F%2Fmeta.discourse.org':
          'suggested',
      'discourse_native.topic_recommendations_tab.'
              'https%3A%2F%2Fteam.discourse.org':
          'related',
    });

    expect(
      await store.read(siteUrl: 'https://meta.discourse.org'),
      coreSuggestedTopicRecommendationSourceId,
    );
    expect(
      await store.read(siteUrl: 'https://team.discourse.org'),
      const TopicRecommendationSourceId('discourse-ai/related'),
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
      coreSuggestedTopicRecommendationSourceId,
    );
  });
}
