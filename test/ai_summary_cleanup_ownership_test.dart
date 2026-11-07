import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_api.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('failed stream cleanup cannot abandon peer results or deadlines', () {
    fakeAsync((async) {
      final channels = _FailingChannels();
      final controller = _controller(channels);
      final completed = <String>[];
      for (final name in ['first', 'second']) {
        final request = controller.load(
          siteUrl: _site,
          topicId: 7,
          hasCachedSummary: false,
        );
        unawaited(
          request.result.then<void>(
            (_) => fail('Cancellation must retain its failure result.'),
            onError: (Object error) {
              expect(error, isA<AiSummaryCancelled>());
              completed.add(name);
            },
          ),
        );
      }
      async.flushMicrotasks();
      expect(async.nonPeriodicTimerCount, 2);
      Object? failure;
      try {
        controller.dispose();
      } catch (error) {
        failure = error;
      }
      async.flushMicrotasks();
      expect(completed, ['first', 'second']);
      expect(channels.cancellations, 2);
      expect(async.nonPeriodicTimerCount, 0);
      expect(failure, isNull);
    });
  });

  test('late HTTP failures remain observed after faulty cancellation', () {
    fakeAsync((async) {
      final channels = _FailingChannels();
      final api = _HeldSummaryApi();
      final controller = _controller(channels, api: api);
      var cancelled = 0;
      for (var i = 0; i < 2; i++) {
        unawaited(
          controller
              .load(siteUrl: _site, topicId: 7, hasCachedSummary: false)
              .result
              .then<void>(
                (_) => fail('Expected cancellation'),
                onError: (Object error) {
                  expect(error, isA<AiSummaryCancelled>());
                  cancelled++;
                },
              ),
        );
      }
      async.flushMicrotasks();
      expect(api.responses, hasLength(2));
      controller.dispose();
      async.flushMicrotasks();
      expect(cancelled, 2);
      for (final response in api.responses) {
        response.completeError(StateError('Late HTTP failure'));
      }
      async.flushMicrotasks();
      expect(channels.cancellations, 2);
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test(
    'cleanup failure preserves a successful summary and releases its deadline',
    () {
      fakeAsync((async) {
        final channels = _FailingChannels();
        final controller = _controller(channels);
        final request = controller.load(
          siteUrl: _site,
          topicId: 7,
          hasCachedSummary: false,
        );
        String? result;
        unawaited(
          request.result.then<void>((summary) {
            result = summary.text;
          }),
        );
        async.flushMicrotasks();
        expect(async.nonPeriodicTimerCount, 1);
        channels.deliver({
          'done': true,
          'ai_topic_summary': {'summarized_text': 'The summary'},
        });
        async.flushMicrotasks();
        expect(result, 'The summary');
        expect(channels.cancellations, 1);
        expect(async.nonPeriodicTimerCount, 0);
        controller.dispose();
      });
    },
  );
}

const _site = 'https://meta.discourse.org';
AiSummaryController _controller(
  _FailingChannels channels, {
  FakeDiscourseApi? api,
}) => AiSummaryController(
  api: AiSummaryApi(
    api ??
        FakeDiscourseApi(
          pluginResponses: const {
            'POST /discourse-ai/summarization/t/7.json': {},
          },
        ),
  ),
  requests: FakePluginRequestHost(
    credentials: FakeApiCredentialReader()..keys[_site] = 'key',
  ),
  trackerFor: (_) => channels,
);

final class _FailingChannels implements PluginLiveChannelHandle {
  int cancellations = 0;
  final callbacks = <void Function(Object?, int)>[];

  void deliver(Object? data) {
    for (final callback in callbacks.toList()) {
      callback(data, 1);
    }
  }

  @override
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object?, int) onMessage, {
    int? lastId,
  }) {
    callbacks.add(onMessage);
    return _Subscription(() {
      callbacks.remove(onMessage);
      cancellations++;
      throw StateError('Cancellation failed');
    });
  }
}

final class _Subscription implements PluginLiveChannelSubscription {
  _Subscription(this.release);
  final void Function() release;
  @override
  void cancel() => release();
}

final class _HeldSummaryApi extends FakeDiscourseApi {
  final responses = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) {
    final response = Completer<Map<String, dynamic>>();
    responses.add(response);
    return response.future;
  }
}
