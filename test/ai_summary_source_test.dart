import 'dart:convert';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary.dart';
import 'package:discourse_native/src/plugins/discourse_ai/discourse_ai_module.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _site = 'https://forum.example';
const _path = '/discourse-ai/summarization/t/7.json';
const _channel = '/discourse-ai/summaries/topic/7';
const _raw = '    code\n\nParagraph hard break  \nnext line  \n';
const _user = DiscourseUser(id: 7, username: 'reader');
const _topic = Topic(id: 7, title: 'A real topic', slug: 'a-real-topic');

Map<String, dynamic> _response() => {
  'done': true,
  'ai_topic_summary': {'summarized_text': _raw},
};

final class _Api extends FakeDiscourseApi {
  _Api(this.reader, {required bool cached})
    : super(
        user: _user,
        feeds: const {
          '/latest.json': [_topic],
        },
        topics: {
          7: topicPayload(
            id: 7,
            title: _topic.title,
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'author',
                cooked: '<p>Post body</p>',
              ),
            ],
            plugins: PluginData.none.withValue(
              aiSummaryAvailabilityDataKey,
              AiSummaryAvailability(
                summarizable: true,
                hasCachedSummary: cached,
              ),
            ),
          ),
        },
      );

  final DiscourseApi reader;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) => path == _path
      ? reader.pluginGetJson(
          siteUrl: siteUrl,
          path: path,
          apiKey: apiKey,
          clientId: clientId,
        )
      : super.pluginGetJson(
          siteUrl: siteUrl,
          path: path,
          apiKey: apiKey,
          clientId: clientId,
        );

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => reader.pluginWriteJson(
    siteUrl: siteUrl,
    path: path,
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );
}

final class _Cooking implements CookingServicePort {
  final service = CookingHostService();
  final requests = <CookingRequest>[];

  @override
  Future<bool> start() => service.start();
  @override
  Future<CookingResult> cook(CookingRequest request) {
    requests.add(request);
    return service.cook(request);
  }

  @override
  void invalidate() => service.invalidate();
  @override
  Future<void> dispose() => service.dispose();
}

void main() {
  test('summary decoder preserves nonblank plain text', () {
    const raw = '  The important parts of the discussion.  \n';
    expect(
      AiTopicSummary.fromJson({
        'ai_topic_summary': {'summarized_text': raw},
      })?.text,
      raw,
    );
  });

  for (final value in [
    null,
    '',
    ' \n\t ',
    17,
    true,
    ['text'],
    {'text': 'body'},
  ]) {
    test('summary decoder rejects blank or nonstring value $value', () {
      expect(
        AiTopicSummary.fromJson({
          'ai_topic_summary': {'summarized_text': value},
        }),
        isNull,
      );
    });
  }

  for (final (source, platform) in [
    ('cached', TargetPlatform.android),
    ('generated', TargetPlatform.android),
    ('streamed', TargetPlatform.android),
    ('cached', TargetPlatform.macOS),
  ]) {
    testWidgets('Native $source summary preserves Markdown on $platform', (
      tester,
    ) async {
      tester.view.physicalSize = platform == TargetPlatform.android
          ? const Size(390, 844)
          : const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final plugins = PluginInstaller.install(
        const PluginManifest([discourseAiModule]),
      );
      addTearDown(plugins.close);
      final sent = <http.Request>[];
      final client = MockClient((request) async {
        sent.add(request);
        return http.Response(
          jsonEncode(source == 'streamed' ? {} : _response()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      final cooking = _Cooking();
      expect(await tester.runAsync(cooking.start), isTrue);
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('forum.example').copyWith(user: _user),
        ]),
        api: _Api(DiscourseApi(client: client), cached: source == 'cached'),
        authenticator: FakeAuthenticator()..keys[_site] = 'secret',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: plugins,
        cookingService: cooking,
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) shell.dispose();
      });
      await shell.load();
      shell.openTopic(_topic);
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            builder: (context, child) => DToaster(child: child!),
            home: const Scaffold(body: MainContent(layout: ShellLayout.medium)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final trigger = find.byKey(const ValueKey('ai-topic-summary-button'));
      await tester.ensureVisible(trigger);
      await tester.tap(trigger);
      await tester.pump();
      expect(sent.single.method, source == 'cached' ? 'GET' : 'POST');
      expect(sent.single.url.path, _path);
      expect(sent.single.headers['user-api-key'], 'secret');
      if (source == 'streamed') {
        expect(jsonDecode(sent.single.body), {'stream': true});
        final tracker = FakeSiteTracker.built.single;
        expect(tracker.pluginChannelCallbacks[_channel], hasLength(1));
        tracker.deliverPluginMessage(_channel, _response());
        await tester.pump();
      }
      final summary = find.descendant(
        of: find.byType(
          platform == TargetPlatform.android ? DSheetContent : DDialogContent,
        ),
        matching: find.byType(CookedHtml),
      );
      for (
        var attempt = 0;
        attempt < 100 && summary.evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(summary, findsOneWidget);
      final rendered = tester.widget<CookedHtml>(summary);
      expect(rendered.html, contains('<pre><code>code\n</code></pre>'));
      expect(rendered.html, contains('Paragraph hard break<br>'));
      expect(cooking.requests.single.raw, _raw);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        disposed = true;
        shell.dispose();
        await shell.pluginTeardown;
        await shell.cooking.dispose();
      });
    });
  }
}
