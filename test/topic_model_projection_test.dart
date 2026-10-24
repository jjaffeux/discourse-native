import 'dart:convert';
import 'dart:isolate';

import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_plugin.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';

const _site = 'https://example.com';
const _probeKey = PluginDataKey<SendPort>(
  owner: 'projection-probe',
  name: 'isolate',
);
const _probeModels = DiscourseModelCodec(
  extensions: PluginRegistry([_ProbePlugin()]),
  recommendationSources: PluginRegistry([_ProbePlugin()]),
);

void main() {
  for (final large in [false, true]) {
    test(
      '${large ? 'large' : 'small'} topic reads project on the expected isolate',
      () async {
        final api = _api(_probeModels, large: large);
        final list = await api.topicList(siteUrl: _site, path: '/latest.json');
        final topic = await api.topic(siteUrl: _site, slug: 'topic', id: 7);
        final projected = [
          for (final item in list.topics) item.plugins.get(_probeKey),
          topic.detail.plugins.get(_probeKey),
          for (final post in topic.posts) post.plugins.get(_probeKey),
        ];
        final caller = projected
            .where((port) => port == Isolate.current.controlPort)
            .length;
        debugPrint(
          jsonEncode({
            'large': large,
            'topic_list_models': list.topics.length,
            'topic_post_models': topic.posts.length,
            'total_projection_hooks': projected.length,
            'caller_isolate_projection_hooks': caller,
            'worker_projection_hooks': projected.length - caller,
          }),
        );
        expect(projected, hasLength(121));
        expect(projected, everyElement(isNotNull));
        expect(caller, large ? 0 : 121);
        expect(topic.posts.last.id, 20);
        expect(topic.detail.stream, List.generate(20, (i) => i + 1));
        expect(() => list.topics.clear(), throwsUnsupportedError);
        expect(() => topic.posts.clear(), throwsUnsupportedError);
        api.close();
      },
    );
  }

  test('a live unsendable plugin keeps large reads on the caller', () async {
    final state = ReceivePort();
    addTearDown(state.close);
    final plugin = _StatefulPlugin(state);
    final models = DiscourseModelCodec(extensions: PluginRegistry([plugin]));
    expect(models.topicModelRecipe, isNull);
    final api = _api(models);
    addTearDown(api.close);
    final result = await api.topic(siteUrl: _site, slug: 'topic', id: 7);
    expect(result.detail.plugins.get(_probeKey), Isolate.current.controlPort);
    expect(plugin.calls, 21);
  });

  test('irrelevant live plugin state never enters the worker recipe', () async {
    final state = ReceivePort();
    addTearDown(state.close);
    final models = DiscourseModelCodec(
      extensions: PluginRegistry([
        const _ProbePlugin(),
        _UnrelatedPlugin(state),
      ]),
    );
    expect(models.topicModelRecipe, isNotNull);
    final api = _api(models);
    addTearDown(api.close);
    final result = await api.topic(siteUrl: _site, slug: 'topic', id: 7);
    expect(
      result.detail.plugins.get(_probeKey),
      isNot(Isolate.current.controlPort),
    );
  });

  test('installed metadata survives worker reconstruction', () async {
    final registry =
        Intl.withLocale(
              'en',
              () => PluginRegistry.validated(const [
                _LocaleSourcePlugin(),
                _LocaleRecordPlugin(),
              ]),
            )
            as PluginRegistry;
    final models = DiscourseModelCodec(
      extensions: registry,
      recommendationSources: registry,
    );
    await Intl.withLocale('fr', () async {
      for (final large in [false, true]) {
        final api = _api(models, large: large);
        addTearDown(api.close);
        final result = await api.topic(siteUrl: _site, slug: 'topic', id: 7);
        expect(
          result.detail.recommendations!.sources.single.definition.label,
          'en',
        );
        expect(
          result.detail.plugins.get(
            const PluginDataKey<SendPort>(owner: 'metadata-probe', name: 'en'),
          ),
          isNotNull,
        );
        expect(
          result.detail.plugins.get(
            const PluginDataKey<SendPort>(owner: 'metadata-probe', name: 'fr'),
          ),
          isNull,
        );
      }
    });
  });

  test('a bundled decoder subclass must explicitly opt in again', () {
    const models = DiscourseModelCodec(
      extensions: PluginRegistry([_CustomPollPlugin()]),
    );
    expect(models.topicModelRecipe, isNull);
  });

  test(
    'extension and recommendation recipes retain separate registries',
    () async {
      const models = DiscourseModelCodec(
        extensions: PluginRegistry([_ProbePlugin()]),
        recommendationSources: PluginRegistry([AiSummaryPlugin()]),
      );
      final api = _api(models);
      addTearDown(api.close);
      final result = await api.topic(siteUrl: _site, slug: 'topic', id: 7);
      expect(
        result.detail.plugins.get(_probeKey),
        isNot(Isolate.current.controlPort),
      );
      expect(
        result.detail.recommendations!.sources.last.definition.id,
        discourseAiRelatedTopicRecommendationSourceId,
      );
    },
  );

  test('bundled recipes preserve fields for a French locale request', () async {
    final installed = PluginInstaller.install(bundledPluginManifest);
    final models = installed.models;
    expect(models.topicModelRecipe, isNotNull);
    await Intl.withLocale('fr', () async {
      final api = _api(models);
      addTearDown(api.close);
      final result = await api.topic(siteUrl: _site, slug: 'topic', id: 7);
      final expected = models.topic(_topicPayload(large: true), _site);
      expect(result.detail, expected.detail);
      expect(result.posts, expected.posts);
      final topicKeys = installed.registry.plugins
          .whereType<TopicRecordPlugin<Object>>()
          .map((plugin) => plugin.record)
          .toList();
      final postKeys = installed.registry.plugins
          .whereType<PostRecordPlugin<Object>>()
          .map((plugin) => plugin.record)
          .toList();
      expect(topicKeys, hasLength(4));
      expect(postKeys, hasLength(6));
      for (final key in topicKeys) {
        expect(expected.detail.plugins.get(key), isNotNull, reason: key.id);
        expect(
          result.detail.plugins.get(key),
          expected.detail.plugins.get(key),
          reason: key.id,
        );
      }
      for (final key in postKeys) {
        expect(
          expected.posts.first.plugins.get(key),
          isNotNull,
          reason: key.id,
        );
        expect(
          result.posts.first.plugins.get(key),
          expected.posts.first.plugins.get(key),
          reason: key.id,
        );
      }
      expect(
        result.detail.plugins.get(alertDataKey)!.alerts.single.linkText,
        appL10n.openLink,
      );
      expect(
        result.detail.recommendations!.sources.last.definition.label,
        appL10n.related,
      );
      final list = await api.topicList(siteUrl: _site, path: '/latest.json');
      final expectedList = models.topicList(_listPayload(large: true), _site);
      expect(list.topics, expectedList.topics);
      expect(list.categories, expectedList.categories);
      expect(list.moreTopicsUrl, expectedList.moreTopicsUrl);
      expect(list.canCreateTopic, expectedList.canCreateTopic);
      expect(list.filterOptions, expectedList.filterOptions);
      expect(list.filter, expectedList.filter);
      expect(list.tagIds, expectedList.tagIds);
      for (final key in topicKeys) {
        expect(
          list.topics.first.plugins.get(key),
          expectedList.topics.first.plugins.get(key),
          reason: key.id,
        );
      }
    });
  });

  for (final large in [false, true]) {
    test(
      'malformed ${large ? 'large' : 'small'} roots keep lookup errors',
      () async {
        for (final source in [
          '[${large ? ' ' * 70000 : ''}]',
          '{${large ? ' ' * 70000 : ''}',
        ]) {
          final api = DiscourseApi(
            client: MockClient(
              (_) async => http.Response(
                source,
                200,
                headers: {'content-type': 'application/json'},
              ),
            ),
          );
          addTearDown(api.close);
          for (final read in [
            () => api.topic(siteUrl: _site, slug: 'topic', id: 7),
            () => api.topicList(siteUrl: _site, path: '/latest.json'),
          ]) {
            await expectLater(
              read(),
              throwsA(
                isA<SiteLookupException>().having(
                  (error) => error.cause,
                  'cause',
                  isA<FormatException>(),
                ),
              ),
            );
          }
        }
      },
    );

    test(
      'model errors stay outside lookup wrapping for ${large ? 'large' : 'small'} reads',
      () async {
        const models = DiscourseModelCodec(
          extensions: PluginRegistry([_ThrowingPlugin()]),
        );
        final api = _api(models, large: large);
        addTearDown(api.close);
        await expectLater(
          api.topic(siteUrl: _site, slug: 'topic', id: 7),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'plugin model failed',
            ),
          ),
        );
      },
    );
  }

  test(
    'worker projection respects the HTTP charset and authenticated transport',
    () async {
      final api = DiscourseApi(
        client: MockClient((request) async {
          expect(request.headers['User-Api-Key'], 'secret');
          expect(request.headers['User-Api-Client-Id'], 'client');
          expect(request.url.path, '/t/7.json');
          expect(request.url.queryParameters, {
            'post_number': '2',
            'summary': 'true',
          });
          return http.Response.bytes(
            latin1.encode(jsonEncode(_topicPayload(large: true))),
            200,
            headers: {'content-type': 'application/json; charset=iso-8859-1'},
          );
        }),
      );
      addTearDown(api.close);
      final result = await api.topic(
        siteUrl: _site,
        slug: 'old-title',
        id: 7,
        postNumber: 2,
        summary: true,
        apiKey: 'secret',
        clientId: 'client',
      );
      expect(result.detail.title, 'café');
    },
  );
}

DiscourseApi _api(DiscourseModelCodec models, {bool large = true}) =>
    DiscourseApi(
      models: models,
      client: MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path == '/latest.json'
                ? _listPayload(large: large)
                : _topicPayload(large: large),
          ),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

Map<String, dynamic> _topicFields() => {
  'summarizable': true,
  'has_cached_summary': true,
  'can_assign': true,
  'assigned_to_user': {'id': 42, 'username': 'sam'},
  'event_starts_at': '2026-10-24T12:00:00Z',
  'alert_data': [
    {'status': 'firing', 'identifier': 'high-load'},
  ],
};

Map<String, dynamic> _listPayload({required bool large}) => {
  if (large) 'padding': 'x' * 70000,
  'topic_list': {
    'topics': [
      for (var i = 1; i <= 100; i++)
        {'id': i, 'title': 'Topic $i', ..._topicFields()},
    ],
  },
};

Map<String, dynamic> _topicPayload({required bool large}) => {
  if (large) 'padding': 'x' * 70000,
  'id': 7,
  'title': 'café',
  ..._topicFields(),
  'related_topics': [
    {'id': 99, 'title': 'Related'},
  ],
  'post_stream': {
    'stream': [for (var i = 1; i <= 20; i++) i],
    'posts': [
      for (var i = 1; i <= 20; i++)
        {
          'id': i,
          'post_number': i,
          'topic_id': 7,
          'cooked': '<p>Post $i</p>',
          'accepted_answer': true,
          'can_accept_answer': true,
          'polls': [
            {
              'name': 'poll',
              'options': [
                {'id': 'a', 'html': 'One', 'votes': 1},
              ],
              'voters': 1,
            },
          ],
          'reactions': [
            {'id': 'heart', 'count': 2},
          ],
          'event': {'id': i, 'name': 'Meeting'},
          'calendar_details': <Object?>[],
          'can_assign': true,
          'assigned_to_user': {'id': 42, 'username': 'sam'},
        },
    ],
  },
};

final class _ProbePlugin
    implements
        IsolateTopicDecoderPlugin,
        PostRecordPlugin<SendPort>,
        TopicRecordPlugin<SendPort> {
  const _ProbePlugin();
  @override
  SitePlugin Function() get isolateTopicDecoderFactory => _ProbePlugin.new;
  @override
  String get name => 'projection-probe';
  @override
  PluginDataKey<SendPort> get record => _probeKey;
  @override
  SendPort readPost(Map<String, dynamic> json, String siteUrl) =>
      Isolate.current.controlPort;
  @override
  SendPort readTopic(Map<String, dynamic> json, String siteUrl) =>
      Isolate.current.controlPort;
  @override
  SendPort? mergeAfterPostEdit(SendPort? held, SendPort? incoming) =>
      incoming ?? held;
}

final class _StatefulPlugin
    implements
        SitePlugin,
        PostRecordPlugin<SendPort>,
        TopicRecordPlugin<SendPort> {
  _StatefulPlugin(this.state);
  final ReceivePort state;
  int calls = 0;
  @override
  String get name => 'stateful';
  @override
  PluginDataKey<SendPort> get record => _probeKey;
  @override
  SendPort readPost(Map<String, dynamic> json, String siteUrl) {
    calls++;
    return state.sendPort;
  }

  @override
  SendPort readTopic(Map<String, dynamic> json, String siteUrl) {
    calls++;
    return Isolate.current.controlPort;
  }

  @override
  SendPort? mergeAfterPostEdit(SendPort? held, SendPort? incoming) =>
      incoming ?? held;
}

final class _UnrelatedPlugin implements SitePlugin {
  _UnrelatedPlugin(this.state);
  final ReceivePort state;
  @override
  String get name => 'unrelated';
}

final class _CustomPollPlugin extends PollPlugin {
  const _CustomPollPlugin();
  @override
  Polls? readPost(Map<String, dynamic> json, String siteUrl) => null;
}

final class _ThrowingPlugin
    implements IsolateTopicDecoderPlugin, PostRecordPlugin<SendPort> {
  const _ThrowingPlugin();
  @override
  SitePlugin Function() get isolateTopicDecoderFactory => _ThrowingPlugin.new;
  @override
  String get name => 'throwing';
  @override
  PluginDataKey<SendPort> get record => _probeKey;
  @override
  SendPort readPost(Map<String, dynamic> json, String siteUrl) =>
      throw const FormatException('plugin model failed');
  @override
  SendPort? mergeAfterPostEdit(SendPort? held, SendPort? incoming) => incoming;
}

final class _LocaleSourcePlugin
    implements IsolateTopicDecoderPlugin, TopicRecommendationSourcePlugin {
  const _LocaleSourcePlugin();
  @override
  String get name => 'projection-probe';
  @override
  SitePlugin Function() get isolateTopicDecoderFactory =>
      _LocaleSourcePlugin.new;
  @override
  List<TopicRecommendationSourceCodec> get topicRecommendationSourceCodecs =>
      const [_LocaleSourceCodec()];
}

final class _LocaleSourceCodec extends TopicRecommendationSourceCodec {
  const _LocaleSourceCodec();
  @override
  TopicRecommendationSourceDefinition get definition =>
      TopicRecommendationSourceDefinition(
        id: const TopicRecommendationSourceId('projection-probe/locale'),
        label: Intl.getCurrentLocale(),
      );
  @override
  List<Map<String, dynamic>> decodeTopicRows(Map<String, dynamic> json) =>
      const [];
}

final class _LocaleRecordPlugin
    implements IsolateTopicDecoderPlugin, TopicRecordPlugin<SendPort> {
  const _LocaleRecordPlugin();
  @override
  String get name => 'metadata-probe';
  @override
  SitePlugin Function() get isolateTopicDecoderFactory =>
      _LocaleRecordPlugin.new;
  @override
  PluginDataKey<SendPort> get record =>
      PluginDataKey(owner: name, name: Intl.getCurrentLocale());
  @override
  SendPort readTopic(Map<String, dynamic> json, String siteUrl) =>
      Isolate.current.controlPort;
}
