import 'dart:async';
import 'dart:convert';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/application_cooking.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/cooking_plugin.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_generation_write.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_api.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_controller.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_ai/discourse_ai_module.dart';
import 'package:discourse_native/src/plugins/discourse_ai/discourse_ai_services.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

/// What upstream's stream job publishes on the summary channel once the site's
/// LLM credit allocation is spent (`stream_topic_ai_summary.rb`).
Map<String, dynamic> creditLimitPayload({
  Map<String, dynamic> details = const {
    'reset_time_relative': 'about 5 hours',
    'reset_time_absolute': 'September 28, 2026 00:00',
  },
}) => {
  'error': true,
  'error_type': 'credit_limit_exceeded',
  'message': 'Credit limit exceeded',
  'details': details,
  'done': true,
};

const _creditLimitCopy =
    'This community has reached its AI credit limit for today. Please try '
    'again after September 28, 2026 00:00 or contact your site administrator '
    'for more information.';

void main() {
  test('cooks summary Markdown with the Discourse runtime', () async {
    final service = OfflineCookingService();
    addTearDown(service.dispose);
    final controller = AiSummaryController(
      api: AiSummaryApi(FakeDiscourseApi()),
      requests: FakePluginRequestHost(),
      trackerFor: (_) => null,
      cooking: PluginCookingHost(
        request:
            ({
              required siteUrl,
              required raw,
              profile = CookingProfile.post,
              context = const CookingContext(),
              cachedMetadata,
            }) => CookingRequest(
              raw: raw,
              profile: profile,
              snapshot: CookingSnapshot(
                siteId: siteUrl,
                accountId: 'test',
                baseUrl: siteUrl,
              ),
            ),
        cook: service.cook,
      ),
    );
    addTearDown(controller.dispose);
    final html = await controller.cook(
      siteUrl: _siteUrl,
      raw: '[Aimee](/t/-/755/1) shares **Team Time**.\n\n- Walk\n- Lunch',
    );
    expect(html, contains('<strong>Team Time</strong>'));
    expect(html, contains('href="/t/-/755/1"'));
    expect(html, contains('<li>Walk</li>'));
    expect(html, contains('<li>Lunch</li>'));
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('renders cooked summary on $platform', (tester) async {
      tester.view.physicalSize = platform == TargetPlatform.iOS
          ? const Size(390, 844)
          : const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const raw = '[Aimee](/t/-/755/1) shares **Team Time**.';
      const html =
          '<p><a href="/t/-/755/1">Aimee</a> shares '
          '<strong>Team Time</strong>.</p>';
      final fixture = _SummaryFixture(
        api: FakeDiscourseApi(
          pluginResponses: {'GET $_summaryPath': summaryResponse(text: raw)},
        ),
        cookedHtml: List.filled(30, html).join(),
      );
      await fixture.openDialog(
        tester,
        hasCachedSummary: true,
        platform: platform,
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(DSheetContent),
        platform == TargetPlatform.iOS ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(DDialogContent),
        platform == TargetPlatform.macOS ? findsOneWidget : findsNothing,
      );
      final rendered = tester.widget<CookedHtml>(find.byType(CookedHtml));
      expect(rendered.html, contains('<strong>Team Time</strong>'));
      expect(rendered.siteUrl, _siteUrl);
      expect(find.text(raw), findsNothing);
      expect(
        find.textContaining('Aimee shares Team Time.', findRichText: true),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Close'));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(CookedHtml), findsNothing);
    });
  }

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
      expect(find.text('Fresh summary', findRichText: true), findsOneWidget);
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

  testWidgets('a summary generated without streaming may outlast a write', (
    tester,
  ) async {
    final site = _HeldSite();
    final request = _Settled(
      _heldSummaries(
        site,
      ).load(siteUrl: _siteUrl, topicId: 7, hasCachedSummary: false).result,
    );
    await tester.pump();
    expect(site.requests.single.url.path, _summaryPath);
    expect(jsonDecode(site.requests.single.body), isEmpty);
    await tester.pump(const Duration(seconds: 30));
    expect(request.done, isFalse);

    site.reply(summaryResponse());
    await tester.pump();

    expect(request.error, isNull);
    expect(request.value?.text, 'The important parts of the discussion.');
  });

  testWidgets('a summary generated without streaming stops at its deadline', (
    tester,
  ) async {
    final site = _HeldSite();
    final request = _Settled(
      _heldSummaries(
        site,
      ).load(siteUrl: _siteUrl, topicId: 7, hasCachedSummary: false).result,
    );
    await tester.pump();
    await tester.pump(aiGenerationTimeout - const Duration(seconds: 1));
    expect(request.done, isFalse);

    await tester.pump(const Duration(seconds: 1));

    expect(request.error, _timedOut);
  });

  testWidgets('a streamed summary request keeps the ordinary write deadline', (
    tester,
  ) async {
    final site = _HeldSite();
    final tracker = FakeSiteTracker(
      siteUrl: _siteUrl,
      onIncomingTopics: () {},
      onNotifications: (_) {},
      onReviewableCounts: (_) {},
      apiKey: 'api-key',
    );
    final request = _Settled(
      _heldSummaries(
        site,
        tracker: tracker,
      ).load(siteUrl: _siteUrl, topicId: 7, hasCachedSummary: false).result,
    );
    await tester.pump();
    expect(jsonDecode(site.requests.single.body), {'stream': true});
    await tester.pump(const Duration(seconds: 9));
    expect(request.done, isFalse);

    await tester.pump(const Duration(seconds: 1));

    expect(request.error, _timedOut);
    expect(tracker.pluginChannelCallbacks[_summaryChannel], isEmpty);
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
        // The summary controller compares `skip_age_check == "true"`, so a
        // JSON boolean would hand back the same outdated cached summary.
        'skip_age_check': 'true',
      });
      expect(fixture.callbacks, hasLength(1));

      fixture.deliver(summaryResponse(done: true, text: 'Regenerated summary'));
      await tester.pumpAndSettle();
      expect(
        find.text('Regenerated summary', findRichText: true),
        findsOneWidget,
      );
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
        find.text('The important parts of the discussion.', findRichText: true),
        findsOneWidget,
      );
      expect(fixture.callbacks, isEmpty);
    },
  );

  test('a stream failure reads the reset time upstream would show', () {
    expect(AiSummaryStreamFailure.fromJson(const {'done': true}), isNull);
    expect(
      AiSummaryStreamFailure.fromJson(summaryResponse(done: true)),
      isNull,
    );

    final credit = AiSummaryStreamFailure.fromJson(creditLimitPayload())!;
    expect(credit.creditLimitExceeded, isTrue);
    expect(credit.resetTime, 'September 28, 2026 00:00');
    expect(
      AiSummaryStreamFailure.fromJson(
        creditLimitPayload(
          details: const {
            'reset_time_relative': 'about 5 hours',
            'reset_time_absolute': '',
          },
        ),
      )!.resetTime,
      'about 5 hours',
    );
    // An allocation with no next reset sends both times blank.
    expect(
      AiSummaryStreamFailure.fromJson(
        creditLimitPayload(
          details: const {'reset_time_relative': '', 'reset_time_absolute': ''},
        ),
      )!.resetTime,
      isNull,
    );
    expect(
      AiSummaryStreamFailure.fromJson({
        ...creditLimitPayload(),
        'details': 'malformed',
      })!.resetTime,
      isNull,
    );

    final other = AiSummaryStreamFailure.fromJson(const {
      'error': true,
      'done': true,
    })!;
    expect(other.creditLimitExceeded, isFalse);
  });

  testWidgets('a stream failure after HTTP settles without the deadline', (
    tester,
  ) async {
    final fixture = _SummaryFixture();
    final request = _Settled(fixture.load().result);
    await tester.pump();
    expect(fixture.api.pluginWrites, hasLength(1));

    fixture.deliver({'done': true});
    await tester.pump();
    expect(request.done, isFalse);
    expect(fixture.callbacks, hasLength(1));

    fixture.deliver(creditLimitPayload());
    await tester.pump();

    expect(
      request.error,
      isA<AiSummaryStreamFailure>().having(
        (failure) => failure.resetTime,
        'resetTime',
        'September 28, 2026 00:00',
      ),
    );
    expect(fixture.callbacks, isEmpty);
    // Widget tests also fail if a settled request leaves its timer pending.
  });

  testWidgets('a stream failure during HTTP settles before HTTP returns', (
    tester,
  ) async {
    final api = _DelayedSummaryApi();
    final fixture = _SummaryFixture(api: api);
    final request = _Settled(fixture.load().result);
    await tester.pump();
    expect(api.started, isTrue);

    fixture.deliver(creditLimitPayload());
    await tester.pump();
    expect(request.error, isA<AiSummaryStreamFailure>());
    expect(fixture.callbacks, isEmpty);

    // The sent POST cannot be aborted; its late answer must not reopen it.
    api.response.complete(summaryResponse());
    await tester.pump();
    expect(request.value, isNull);
    expect(request.error, isA<AiSummaryStreamFailure>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a credit-limit failure explains itself and can be retried', (
    tester,
  ) async {
    final fixture = _SummaryFixture();
    await fixture.openDialog(tester);
    expect(find.text('Generating summary…'), findsOneWidget);

    fixture.deliver(creditLimitPayload());
    // One frame: settling would also run out the stream deadline.
    await tester.pump();
    expect(find.text(_creditLimitCopy), findsOneWidget);
    expect(find.text('Generating summary…'), findsNothing);
    expect(fixture.callbacks, isEmpty);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(fixture.api.pluginWrites, hasLength(2));
    expect(fixture.callbacks, hasLength(1));
    fixture.deliver(summaryResponse(done: true));
    await tester.pumpAndSettle();
    expect(
      find.text('The important parts of the discussion.', findRichText: true),
      findsOneWidget,
    );
    expect(find.text(_creditLimitCopy), findsNothing);
  });

  for (final (label, payload, copy) in [
    (
      'a credit limit without a reset time',
      creditLimitPayload(
        details: const {'reset_time_relative': '', 'reset_time_absolute': ''},
      ),
      'This community has reached its AI credit limit for today. Responses '
          'will be unavailable until your limit resets. Please contact your '
          'site administrator for more information.',
    ),
    (
      'another stream failure',
      <String, dynamic>{
        'error': true,
        'error_type': 'provider_unavailable',
        'message': 'Faraday::TimeoutError',
        'done': true,
      },
      "Couldn't generate this summary.",
    ),
  ]) {
    testWidgets('the dialog reports $label', (tester) async {
      final fixture = _SummaryFixture();
      await fixture.openDialog(tester);

      fixture.deliver(payload);
      // One frame: the deadline's own failure shows the generic copy too.
      await tester.pump();

      expect(find.text(copy), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(fixture.callbacks, isEmpty);
    });
  }

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

final _timedOut = isA<WriteException>().having(
  (error) => error.cause,
  'cause',
  isA<TimeoutException>(),
);

/// The production transport against a site whose one request is answered
/// only when the test says so, so the deadline it applies is the real one.
final class _HeldSite {
  _HeldSite() {
    api = DiscourseApi(
      client: MockClient((request) {
        requests.add(request);
        return _reply.future;
      }),
    );
    addTearDown(api.close);
  }

  late final DiscourseApi api;
  final requests = <http.Request>[];
  final _reply = Completer<http.Response>();

  void reply(Map<String, Object?> body) => _reply.complete(
    http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    ),
  );
}

AiSummaryController _heldSummaries(_HeldSite site, {FakeSiteTracker? tracker}) {
  final controller = AiSummaryController(
    api: AiSummaryApi(site.api),
    requests: FakePluginRequestHost(
      credentials: FakeApiCredentialReader()..keys[_siteUrl] = 'api-key',
    ),
    trackerFor: (_) => tracker,
  );
  addTearDown(controller.dispose);
  return controller;
}

final class _Settled<T> {
  _Settled(Future<T> future) {
    unawaited(
      future.then<void>(
        (result) {
          value = result;
          done = true;
        },
        onError: (Object failure) {
          error = failure;
          done = true;
        },
      ),
    );
  }

  T? value;
  Object? error;
  bool done = false;
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
    String? cookedHtml,
  }) : api =
           api ??
           FakeDiscourseApi(pluginResponses: const {'POST $_summaryPath': {}}),
       requests = FakePluginRequestHost(
         credentials:
             credentials ??
             (FakeApiCredentialReader()..keys[_siteUrl] = 'api-key'),
       ) {
    final cooking = ApplicationCooking(plugins: plugins);
    addTearDown(cooking.dispose);
    session = plugins.openSession(
      PluginHostBindings([
        PluginHostPort<Object>(
          corePluginCookingPort,
          PluginCookingHost(
            request:
                ({
                  required siteUrl,
                  required raw,
                  profile = CookingProfile.post,
                  context = const CookingContext(),
                  cachedMetadata,
                }) => cooking.request(
                  siteUrl: siteUrl,
                  accountId: 'test',
                  raw: raw,
                  config: const SiteConfig(),
                  profile: profile,
                  context: context,
                  cachedMetadata: cachedMetadata,
                ),
            cook: (request) async => CookingResult(
              html:
                  cookedHtml ??
                  '<p>${const HtmlEscape().convert(request.raw)}</p>',
            ),
          ),
        ),
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
        PluginHostPort<PluginUserIdReader>(corePluginUserPort, (_) => null),
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
    TargetPlatform platform = TargetPlatform.macOS,
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
          theme: ThemeData(platform: platform),
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
