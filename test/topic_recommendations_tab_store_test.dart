import 'dart:async';

import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:discourse_native/src/data/topic_recommendations_tab_store.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/topic_recommendation_source.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
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

  test('core migrates only its legacy suggested tab name', () async {
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
      coreSuggestedTopicRecommendationSourceId,
    );
  });

  test(
    'the installed Discourse AI codec migrates its legacy tab name',
    () async {
      SharedPreferences.setMockInitialValues({
        'discourse_native.topic_recommendations_tab.'
                'https%3A%2F%2Fmeta.discourse.org':
            'related',
      });
      const sourceMigrations = PluginRegistry([AiSummaryPlugin()]);

      expect(
        await store.read(
          siteUrl: 'https://meta.discourse.org',
          sourceMigrations: sourceMigrations,
        ),
        discourseAiRelatedTopicRecommendationSourceId,
      );
    },
  );

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

  test(
    'retirement spans stores sharing persistence without changing ordering',
    () async {
      final persistence = _HeldPersistence();
      final first = TopicRecommendationsTabStore(persistence: persistence);
      final replacement = TopicRecommendationsTabStore(
        persistence: persistence,
      );
      const site = 'https://meta.discourse.org';
      const other = 'https://team.discourse.org';
      const initial = TopicRecommendationSourceId('test/initial');
      const stale = TopicRecommendationSourceId('test/stale');
      const fresh = TopicRecommendationSourceId('test/fresh');
      final write = first.write(siteUrl: site, sourceId: initial);
      await persistence.writeStarted.future;
      final queued = replacement.write(siteUrl: site, sourceId: stale);
      final oldRead = replacement.read(siteUrl: site);
      first.forgetSites(ForgottenSites.removed(site, keeping: const [other]));
      persistence.values.remove(site);
      await first.write(siteUrl: other, sourceId: fresh);
      final freshWrite = replacement.write(siteUrl: site, sourceId: fresh);
      persistence.releaseWrite.complete();
      await Future.wait([write, queued, freshWrite]);
      expect(await oldRead, coreSuggestedTopicRecommendationSourceId);
      expect(persistence.writes, [
        (site, initial),
        (other, fresh),
        (site, fresh),
      ]);
      expect(await first.read(siteUrl: site), fresh);
      expect(await replacement.read(siteUrl: other), fresh);
    },
  );

  test(
    'a pending read cannot return a forgotten source to a replacement',
    () async {
      final persistence = _HeldPersistence()..holdRead = true;
      const site = 'https://meta.discourse.org';
      persistence.values[site] = 'test/old';
      final first = TopicRecommendationsTabStore(persistence: persistence);
      final replacement = TopicRecommendationsTabStore(
        persistence: persistence,
      );
      final oldRead = first.read(siteUrl: site);
      await persistence.readStarted.future;
      replacement.forgetSites(ForgottenSites.removed(site, keeping: const []));
      persistence.values.remove(site);
      expect(
        await replacement.read(siteUrl: site),
        coreSuggestedTopicRecommendationSourceId,
      );
      persistence.releaseRead.complete();
      expect(await oldRead, coreSuggestedTopicRecommendationSourceId);
    },
  );
}

final class _HeldPersistence implements TopicRecommendationsTabPersistence {
  final values = <String, String>{};
  final writes = <(String, TopicRecommendationSourceId)>[];
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();
  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();
  bool holdRead = false;

  @override
  Future<String?> readStoredSourceId({required String siteUrl}) async {
    final value = values[siteUrl];
    if (holdRead && !readStarted.isCompleted) {
      readStarted.complete();
      await releaseRead.future;
    }
    return value;
  }

  @override
  Future<bool> writeTab({
    required String siteUrl,
    required TopicRecommendationSourceId sourceId,
  }) async {
    writes.add((siteUrl, sourceId));
    values[siteUrl] = sourceId.value;
    if (!writeStarted.isCompleted) {
      writeStarted.complete();
      await releaseWrite.future;
    }
    return true;
  }
}
