import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_api.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_controller.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _summaryPath = '/discourse-ai/summarization/t/7.json';

Map<String, dynamic> summaryResponse({bool done = false}) => {
  if (done) 'done': true,
  'ai_topic_summary': {
    'summarized_text': 'The important parts of the discussion.',
    'algorithm': 'test-model',
    'updated_at': '2026-08-24T12:00:00Z',
    'outdated': false,
    'can_regenerate': true,
    'new_posts_since_summary': 0,
  },
};

void main() {
  test('topic extension reads the guardian-scoped availability fields', () {
    const plugin = AiSummaryPlugin();

    expect(plugin.readTopic(const {}, _siteUrl), isNull);
    expect(
      plugin.readTopic(const {
        'summarizable': true,
        'has_cached_summary': true,
      }, _siteUrl),
      const AiSummaryAvailability(summarizable: true, hasCachedSummary: true),
    );
  });

  test(
    'cached summary uses the read endpoint without authentication',
    () async {
      final transport = FakeDiscourseApi(
        pluginResponses: {'GET $_summaryPath': summaryResponse()},
      );
      final controller = AiSummaryController(
        api: AiSummaryApi(transport),
        credentials: FakeApiCredentialReader(),
        lifecycle: SiteLifecycle(),
        trackerFor: (_) => null,
      );

      final summary = await controller.load(
        siteUrl: _siteUrl,
        topicId: 7,
        hasCachedSummary: true,
      );

      expect(summary.text, 'The important parts of the discussion.');
      expect(summary.algorithm, 'test-model');
      expect(transport.pluginReadPaths, [_summaryPath]);
      expect(transport.pluginWrites, isEmpty);
    },
  );

  test('new summary waits for the completed message-bus payload', () async {
    final transport = FakeDiscourseApi(
      pluginResponses: const {'POST $_summaryPath': {}},
    );
    final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'api-key';
    final tracker = FakeSiteTracker(
      siteUrl: _siteUrl,
      onIncomingTopics: () {},
      onNotifications: (_) {},
      onReviewableCounts: (_) {},
      apiKey: 'api-key',
    );
    final controller = AiSummaryController(
      api: AiSummaryApi(transport),
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      trackerFor: (_) => tracker,
    );

    final pending = controller.load(
      siteUrl: _siteUrl,
      topicId: 7,
      hasCachedSummary: false,
    );
    await Future<void>.delayed(Duration.zero);
    tracker.deliverPluginMessage(
      '/discourse-ai/summaries/topic/7',
      summaryResponse(done: true),
    );

    expect((await pending).text, 'The important parts of the discussion.');
    expect(transport.pluginWrites.single.method, 'POST');
    expect(transport.pluginWrites.single.body, {'stream': true});
    expect(tracker.pluginChannelCallbacks.values.single, isEmpty);
  });
}
