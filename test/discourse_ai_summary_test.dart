import 'dart:async';

import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_api.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_controller.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_ai/discourse_ai_module.dart';
import 'package:discourse_native/src/plugins/discourse_ai/discourse_ai_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _summaryPath = '/discourse-ai/summarization/t/7.json';
const _summaryChannel = '/discourse-ai/summaries/topic/7';

Map<String, dynamic> summaryResponse({
  bool done = false,
  bool outdated = false,
  String text = 'The important parts of the discussion.',
}) => {
  if (done) 'done': true,
  'ai_topic_summary': {
    'summarized_text': text,
    'algorithm': 'test-model',
    'updated_at': '2026-08-24T12:00:00Z',
    'outdated': outdated,
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
        requests: FakePluginRequestHost(),
        trackerFor: (_) => null,
      );

      final summary = await controller
          .load(siteUrl: _siteUrl, topicId: 7, hasCachedSummary: true)
          .result;

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
      requests: FakePluginRequestHost(credentials: credentials),
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

    expect(
      (await pending.result).text,
      'The important parts of the discussion.',
    );
    expect(transport.pluginWrites.single.method, 'POST');
    expect(transport.pluginWrites.single.body, {'stream': true});
    expect(tracker.pluginChannelCallbacks.values.single, isEmpty);
  });

  testWidgets('closing during credentials prevents generation', (tester) async {
    final credentials = _DelayedCredentials();
    final fixture = _SummaryFixture(credentials: credentials);
    await fixture.openDialog(tester);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    credentials.key.complete('api-key');
    await tester.pump();

    expect(fixture.api.pluginWrites, isEmpty);
    expect(fixture.callbacks, isEmpty);
  });

  testWidgets('closing during HTTP generation releases the subscription', (
    tester,
  ) async {
    final api = _DelayedSummaryApi();
    final fixture = _SummaryFixture(api: api);
    await fixture.openDialog(tester);
    expect(api.started, isTrue);
    expect(fixture.callbacks, hasLength(1));

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(fixture.callbacks, isEmpty);
    api.response.completeError(StateError('Late network failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing during streaming releases the subscription and deadline',
    (tester) async {
      final fixture = _SummaryFixture();
      await fixture.openDialog(tester);
      expect(fixture.callbacks, hasLength(1));

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(fixture.callbacks, isEmpty);
    },
  );

  testWidgets('barrier dismissal cancels before the exit animation finishes', (
    tester,
  ) async {
    final credentials = _DelayedCredentials();
    final fixture = _SummaryFixture(credentials: credentials);
    await fixture.openDialog(tester);

    await tester.tapAt(const Offset(5, 5));
    credentials.key.complete('api-key');
    await tester.pump();

    expect(fixture.api.pluginWrites, isEmpty);
    expect(fixture.callbacks, isEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('disposing the dialog releases its stream wait', (tester) async {
    final fixture = _SummaryFixture();
    await fixture.openDialog(tester);
    expect(fixture.callbacks, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(fixture.callbacks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reopening owns a fresh request despite late HTTP and stream data',
    (tester) async {
      final api = _DelayedSummaryApi();
      final fixture = _SummaryFixture(api: api);
      await fixture.openDialog(tester);
      final oldCallback = fixture.callbacks.single;
      await tester.tap(find.text('Close'));
      expect(fixture.callbacks, isEmpty);
      await tester.pumpAndSettle();

      await fixture.openDialog(tester);
      expect(fixture.callbacks, hasLength(1));
      expect(api.responses, hasLength(2));
      api.responses.first.complete(summaryResponse(text: 'Abandoned summary'));
      oldCallback(summaryResponse(done: true, text: 'Abandoned stream'));
      api.responses.last.complete({});
      await tester.pump();
      expect(find.text('Generating summary…'), findsOneWidget);
      expect(find.textContaining('Abandoned'), findsNothing);
      expect(fixture.callbacks, hasLength(1));

      fixture.deliver(summaryResponse(done: true, text: 'Fresh summary'));
      await tester.pumpAndSettle();
      expect(find.text('Fresh summary'), findsOneWidget);
      expect(fixture.callbacks, isEmpty);
    },
  );

  testWidgets(
    'cancellation settles before credentials and handles a late error',
    (tester) async {
      final credentials = _DelayedCredentials();
      final fixture = _SummaryFixture(credentials: credentials);
      final request = fixture.load();
      final cancelled = expectLater(
        request.result,
        throwsA(isA<AiSummaryCancelled>()),
      );

      request.cancel();
      request.cancel();
      await tester.pump();
      await cancelled;
      expect(credentials.key.isCompleted, isFalse);
      expect(fixture.api.pluginWrites, isEmpty);

      credentials.key.completeError(StateError('Late keychain failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(fixture.callbacks, isEmpty);
    },
  );

  for (final streaming in [true, false]) {
    testWidgets('cancellation settles during HTTP with streaming=$streaming', (
      tester,
    ) async {
      final api = _DelayedSummaryApi();
      final fixture = _SummaryFixture(api: api, streaming: streaming);
      final request = fixture.load();
      final cancelled = expectLater(
        request.result,
        throwsA(isA<AiSummaryCancelled>()),
      );
      await tester.pump();
      expect(api.started, isTrue);

      request.cancel();
      expect(fixture.callbacks, isEmpty);
      await tester.pump();
      await cancelled;
      expect(api.response.isCompleted, isFalse);

      api.response.completeError(StateError('Late network failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'cancelling the streaming wait settles without reaching its deadline',
    (tester) async {
      final fixture = _SummaryFixture();
      final request = fixture.load();
      final cancelled = expectLater(
        request.result,
        throwsA(isA<AiSummaryCancelled>()),
      );
      await tester.pump();
      expect(fixture.callbacks, hasLength(1));

      request.cancel();
      expect(fixture.callbacks, isEmpty);
      await tester.pump();
      await cancelled;
      // Widget tests also fail if a cancelled request leaves its timer pending.
    },
  );

  testWidgets(
    'a completed stream arriving during HTTP is retained until HTTP succeeds',
    (tester) async {
      final api = _DelayedSummaryApi();
      final fixture = _SummaryFixture(api: api);
      final request = fixture.load();
      var settled = false;
      final result = request.result.then((summary) {
        settled = true;
        return summary;
      });
      await tester.pump();

      fixture.deliver(summaryResponse(done: true, text: 'First completion'));
      fixture.deliver(
        summaryResponse(done: true, text: 'Duplicate completion'),
      );
      await tester.pump();
      expect(settled, isFalse);
      api.response.complete({});
      await tester.pump();

      expect((await result).text, 'First completion');
      expect(fixture.callbacks, isEmpty);
      request.cancel();
      await fixture.session.forget(_siteUrl);
      expect((await request.result).text, 'First completion');
    },
  );

  testWidgets(
    'HTTP can return a cached summary while streaming is subscribed',
    (tester) async {
      final fixture = _SummaryFixture(
        api: FakeDiscourseApi(
          pluginResponses: {'POST $_summaryPath': summaryResponse()},
        ),
      );
      final request = fixture.load();
      await tester.pump();

      expect(
        (await request.result).text,
        'The important parts of the discussion.',
      );
      expect(fixture.callbacks, isEmpty);
    },
  );

  testWidgets('without a tracker generation uses the non-streaming response', (
    tester,
  ) async {
    final fixture = _SummaryFixture(
      streaming: false,
      api: FakeDiscourseApi(
        pluginResponses: {'POST $_summaryPath': summaryResponse()},
      ),
    );
    final request = fixture.load();
    await tester.pump();

    expect(
      (await request.result).text,
      'The important parts of the discussion.',
    );
    expect(fixture.api.pluginWrites.single.body, isEmpty);
    expect(fixture.callbacks, isEmpty);
  });

  testWidgets(
    'regenerate starts a new request after a cached outdated summary',
    (tester) async {
      final fixture = _SummaryFixture(
        api: FakeDiscourseApi(
          pluginResponses: {
            'GET $_summaryPath': summaryResponse(outdated: true),
            'POST $_summaryPath': <String, dynamic>{},
          },
        ),
      );
      await fixture.openDialog(tester, hasCachedSummary: true);
      await tester.pumpAndSettle();
      expect(find.text('Regenerate'), findsOneWidget);
      expect(fixture.api.pluginWrites, isEmpty);

      await tester.tap(find.text('Regenerate'));
      await tester.pump();
      expect(find.text('Regenerating summary…'), findsOneWidget);
      expect(fixture.api.pluginReadPaths, [_summaryPath]);
      expect(fixture.api.pluginWrites.single.body, {
        'stream': true,
        'skip_age_check': true,
      });
      expect(fixture.callbacks, hasLength(1));

      fixture.deliver(summaryResponse(done: true, text: 'Regenerated summary'));
      await tester.pumpAndSettle();
      expect(find.text('Regenerated summary'), findsOneWidget);
      expect(fixture.callbacks, isEmpty);
    },
  );

  testWidgets('the three-minute stream timeout begins after HTTP completes', (
    tester,
  ) async {
    final api = _DelayedSummaryApi();
    final fixture = _SummaryFixture(api: api);
    final request = fixture.load();
    var timedOut = false;
    final failure = expectLater(
      request.result,
      throwsA(isA<TimeoutException>()),
    );
    unawaited(failure.then((_) => timedOut = true));
    await tester.pump();
    await tester.pump(const Duration(minutes: 4));
    expect(timedOut, isFalse);

    api.response.complete({});
    await tester.pump();
    fixture.deliver('malformed');
    fixture.deliver({'done': true});
    fixture.deliver(summaryResponse());
    await tester.pump(const Duration(minutes: 2, seconds: 59));
    expect(timedOut, isFalse);
    expect(fixture.callbacks, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    await failure;
    expect(timedOut, isTrue);
    expect(fixture.callbacks, isEmpty);
  });

  testWidgets(
    'HTTP failure releases its subscription and the dialog can retry',
    (tester) async {
      final api = _DelayedSummaryApi();
      final fixture = _SummaryFixture(api: api);
      await fixture.openDialog(tester);
      fixture.deliver(summaryResponse(done: true));
      api.response.completeError(StateError('Network failure'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't generate this summary."), findsOneWidget);
      expect(fixture.callbacks, isEmpty);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(api.responses, hasLength(2));
      expect(fixture.callbacks, hasLength(1));
      api.responses.last.complete(summaryResponse());
      await tester.pumpAndSettle();
      expect(
        find.text('The important parts of the discussion.'),
        findsOneWidget,
      );
      expect(fixture.callbacks, isEmpty);
    },
  );

  testWidgets('forgetting an account promptly retires its stream wait', (
    tester,
  ) async {
    final fixture = _SummaryFixture();
    final request = fixture.load();
    final stale = expectLater(request.result, throwsStateError);
    await tester.pump();
    await fixture.session.forget('https://another.discourse.org');
    expect(fixture.callbacks, hasLength(1));

    fixture.requests.lifecycle.invalidate(_siteUrl);
    await fixture.session.forget(_siteUrl);
    await stale;
    expect(fixture.callbacks, isEmpty);

    final fresh = fixture.load();
    await tester.pump();
    fixture.deliver(summaryResponse(done: true));
    await tester.pump();
    expect((await fresh.result).text, 'The important parts of the discussion.');
  });

  testWidgets(
    'forgetting during credentials prevents sending for the old account',
    (tester) async {
      final credentials = _DelayedCredentials();
      final fixture = _SummaryFixture(credentials: credentials);
      final request = fixture.load();
      final stale = expectLater(request.result, throwsStateError);

      fixture.requests.lifecycle.invalidate(_siteUrl);
      await fixture.session.forget(_siteUrl);
      await stale;
      expect(credentials.key.isCompleted, isFalse);
      credentials.key.complete('api-key');
      await tester.pump();
      expect(fixture.api.pluginWrites, isEmpty);
      expect(fixture.callbacks, isEmpty);
    },
  );

  testWidgets('session close retires HTTP work and prevents subsequent loads', (
    tester,
  ) async {
    final api = _DelayedSummaryApi();
    final fixture = _SummaryFixture(api: api);
    final request = fixture.load();
    final cancelled = expectLater(
      request.result,
      throwsA(isA<AiSummaryCancelled>()),
    );
    await tester.pump();

    await fixture.session.close();
    await cancelled;
    expect(fixture.callbacks, isEmpty);
    api.response.complete({});
    await tester.pump();
    await expectLater(
      fixture.load().result,
      throwsA(isA<AiSummaryCancelled>()),
    );
    expect(api.responses, hasLength(1));
  });
}

final class _DelayedCredentials extends FakeApiCredentialReader {
  final key = Completer<String?>();

  @override
  Future<String?> apiKeyFor(String siteUrl) => key.future;
}

final class _DelayedSummaryApi extends FakeDiscourseApi {
  final responses = <Completer<Map<String, dynamic>>>[];
  Completer<Map<String, dynamic>> get response => responses.first;
  bool get started => responses.isNotEmpty;

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) {
    pluginWrites.add((
      siteUrl: siteUrl,
      method: method,
      path: path,
      body: body,
    ));
    final pending = Completer<Map<String, dynamic>>();
    responses.add(pending);
    return pending.future;
  }
}

final class _EmptyFreshAccount implements PluginFreshAccountHost {
  const _EmptyFreshAccount();

  @override
  PluginFreshAccountProfile? profileFor(String siteUrl) => null;

  @override
  T? recordFor<T extends Object>(String siteUrl, PluginDataKey<T> key) => null;
}

final class _SummaryFixture {
  _SummaryFixture({
    FakeDiscourseApi? api,
    FakeApiCredentialReader? credentials,
    bool streaming = true,
  }) : api =
           api ??
           FakeDiscourseApi(pluginResponses: const {'POST $_summaryPath': {}}),
       requests = FakePluginRequestHost(
         credentials:
             credentials ??
             (FakeApiCredentialReader()..keys[_siteUrl] = 'api-key'),
       ) {
    session = plugins.openSession(
      PluginHostBindings([
        PluginHostPort<Object>(corePluginTransportPort, this.api),
        PluginHostPort<Object>(corePluginRequestPort, requests),
        PluginHostPort<Object>(
          corePluginTrackerPort,
          (String _) => streaming ? tracker : null,
        ),
        PluginHostPort<Object>(
          corePluginSiteStatePort,
          PluginSiteStateHost(
            currentUserFor: (_) => null,
            siteConfigFor: (_) => const SiteConfig(),
          ),
        ),
        const PluginHostPort<Object>(
          corePluginFreshAccountPort,
          _EmptyFreshAccount(),
        ),
        const PluginHostPort<Object>(
          pluginDiagnosticsReporterPort,
          PluginDiagnosticsReporter.noop(),
        ),
      ]),
    );
    addTearDown(session.close);
  }

  final FakeDiscourseApi api;
  final FakePluginRequestHost requests;
  final plugins = PluginInstaller.install(
    const PluginManifest([discourseAiModule]),
  );
  late final PluginSession session;
  final tracker = FakeSiteTracker(
    siteUrl: _siteUrl,
    onIncomingTopics: () {},
    onNotifications: (_) {},
    onReviewableCounts: (_) {},
    apiKey: 'api-key',
  );

  AiSummaryController get controller =>
      session.require(aiSummaryControllerService);
  List<void Function(Object?)> get callbacks =>
      tracker.pluginChannelCallbacks[_summaryChannel] ?? [];

  AiSummaryRequest load() =>
      controller.load(siteUrl: _siteUrl, topicId: 7, hasCachedSummary: false);

  void deliver(Object? payload) =>
      tracker.deliverPluginMessage(_summaryChannel, payload);

  Future<void> openDialog(
    WidgetTester tester, {
    bool hasCachedSummary = false,
  }) async {
    final topic = TopicDetail(
      id: 7,
      title: 'A discussion',
      stream: const [],
      plugins: PluginData.none.withValue(
        aiSummaryAvailabilityDataKey,
        AiSummaryAvailability(
          summarizable: true,
          hasCachedSummary: hasCachedSummary,
        ),
      ),
    );
    await tester.pumpWidget(
      PluginScope(
        session: session,
        registry: plugins.registry,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: plugins.registry
                    .topicMapActions(context, _siteUrl, topic)
                    .actions,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ai-topic-summary-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}
