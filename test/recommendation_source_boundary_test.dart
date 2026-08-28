import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recommendation sources decode outside generic plugin record data', () {
    final pluginData = File(
      'lib/src/plugin_api/plugin_data.dart',
    ).readAsStringSync();
    final coreTopic = File('lib/src/models/topic.dart').readAsStringSync();
    final modelCodec = File(
      'lib/src/plugin_api/discourse_model_codec.dart',
    ).readAsStringSync();
    final discourseAi = File(
      'lib/src/plugins/discourse_ai/ai_summary_plugin.dart',
    ).readAsStringSync();

    expect(pluginData, isNot(contains('TopicRecommendationSource')));
    expect(coreTopic, contains("json.containsKey('suggested_topics')"));
    expect(coreTopic, isNot(contains('related_topics')));
    expect(coreTopic, isNot(contains('extensions is TopicRecommendation')));
    expect(modelCodec, isNot(contains('extensions is TopicRecommendation')));
    expect(discourseAi, contains("json.containsKey('related_topics')"));
  });
}
