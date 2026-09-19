import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/cooking/cooking_module.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_widget.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_module.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_settings.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/media_pipeline.dart';

const _site = 'https://pipeline.example/forum';
const _firstComposer = ValueKey('pipeline-first-composer');
const _secondComposer = ValueKey('pipeline-second-composer');
const _user = DiscourseUser(id: 7, username: 'sam', timezone: 'Etc/UTC');

ChatApi _chatApi(PluginApiTransport transport) => transport as ChatApi;

/// These are diagnostic timings, not latency assertions. They include snapshot
/// selection, scheduling, worker startup when cold, row notification, and native
/// HTML layout. The test's real-event polling and frame overhead are included;
/// this is a repeatable desktop debug baseline, not a device release benchmark.
void main() {
  testWidgets('installed Chat cooks and renders locally while send is pending', (
    tester,
  ) async {
    final rig = await _Rig.create(tester);
    final rich = await rig.sendAndRender(
      tester,
      label: 'cold-rich',
      outgoing: OutgoingChatMessage.text(_richSource('Cold-marker')),
      marker: 'Cold-marker',
    );
    final document = html.parseFragment(rich.provisionalCooked!);
    expect(document.querySelector('strong')?.text, 'Cold-marker');
    expect(
      document.querySelector('a.mention')?.attributes['href'],
      '/forum/u/Alice',
    );
    expect(document.querySelector('img.emoji'), isNotNull);
    expect(document.querySelector('.discourse-local-date'), isNotNull);
    expect(document.querySelector('aside.quote'), isNotNull);
    expect(
      document.querySelector('pre code')?.text,
      contains('final answer = 42;'),
    );
    final external = document.querySelector(
      'a[href="https://external.test/path"]',
    )!;
    expect(external.attributes['rel'], contains('noopener'));
    expect(find.byType(LocalDateInline), findsOneWidget);

    await rig.sendAndRender(
      tester,
      label: 'warm-rich',
      outgoing: OutgoingChatMessage.text(_richSource('Warm-marker')),
      marker: 'Warm-marker',
      channelId: 10,
    );
    expect(find.byType(LocalDateInline), findsOneWidget);

    // Large unrelated enrichment is retained by the host but must not be
    // copied into a request. The long source remains below the chat limit.
    final unrelated = <String, String>{
      for (var i = 0; i < 150; i++)
        'https://unrelated.test/$i': '<p>${'unrelated ' * 100}</p>',
    };
    final lease = rig.shell.cooking.captureUploads(_site, '7');
    expect(
      rig.shell.cooking.ingestMetadata(
        lease,
        CookingCachedMetadata(oneboxes: unrelated),
      ),
      isTrue,
    );
    await tester.pump();
    final longSource =
        '${List.generate(75, (i) => '**Paragraph $i** ${'ordinary text ' * 12}').join('\n\n')}\n\nLarge-end-marker';
    expect(longSource.length, lessThan(20000));
    await rig.sendAndRender(
      tester,
      label: 'warm-long-source-large-unrelated-cache',
      outgoing: OutgoingChatMessage.text(longSource),
      marker: 'Large-end-marker',
      extra: {
        'retainedUnrelatedMetadataBytes': utf8
            .encode(jsonEncode(unrelated))
            .length,
      },
    );
    expect(rig.service.requests.last.snapshot.oneboxes, isEmpty);
    expect(
      utf8
          .encode(jsonEncode(rig.service.requests.last.snapshot.toJson()))
          .length,
      lessThan(16 * 1024),
      reason: 'Unrelated metadata must stay outside the selected work budget',
    );

    const gifUrl = 'https://media.test/cat.gif';
    final gif = await rig.sendAndRender(
      tester,
      label: 'warm-trusted-gif-source',
      outgoing: OutgoingChatMessage.trustedGif(
        raw:
            '![safe|20x20]($gifUrl)\n\n<kbd onclick="bad()">Gif-marker</kbd>\n<script>alert(1)</script>',
        url: gifUrl,
        title: 'safe',
        width: 20,
        height: 20,
      ),
      marker: 'Gif-marker',
    );
    final gifDocument = html.parseFragment(gif.provisionalCooked!);
    expect(gifDocument.querySelector('img')?.attributes['src'], gifUrl);
    expect(gifDocument.querySelector('script'), isNull);
    expect(
      gifDocument
          .querySelectorAll('*')
          .expand((node) => node.attributes.keys)
          .where((name) => name.toString().startsWith('on')),
      isEmpty,
    );

    final attachment = await rig.sendAndRender(
      tester,
      label: 'warm-separate-attachment',
      outgoing: OutgoingChatMessage.text(
        'Attachment-marker',
        uploads: const [
          ComposerUploadResult(
            id: 13,
            originalFilename: 'notes.pdf',
            shortUrl: 'upload://notes.pdf',
            url: 'https://pipeline.example/forum/uploads/notes.pdf',
          ),
        ],
      ),
      marker: 'Attachment-marker',
    );
    expect(attachment.uploads.single.originalFilename, 'notes.pdf');
    expect(attachment.provisionalCooked, isNot(contains('notes.pdf')));
    expect(find.byType(DAttachment), findsOneWidget);
    expect(rig.service.requests, hasLength(5));
    expect(rig.service.maxActive, 1);
    expect(rig.service.httpAttempts, 0);
    expect(rig.api.chatMessagesSent, hasLength(2));
    expect(rig.sendGate.isCompleted, isFalse);
    rig.emitSummary('installed-pipeline');
  });

  testWidgets('two composers coalesce rapid typing and reuse prepared HTML', (
    tester,
  ) async {
    final rig = await _Rig.create(tester);
    await tester.pumpWidget(_PipelineView(shell: rig.shell, composers: true));
    final field = find.descendant(
      of: find.byKey(_firstComposer),
      matching: find.byType(TextField),
    );
    const finalRaw = '**Prepared-marker** ready';
    final preparation = Stopwatch()..start();
    for (var i = 0; i < 40; i++) {
      await rig.service.withoutHttp(
        () => tester.enterText(field, 'revision $i'),
      );
    }
    await rig.service.withoutHttp(() => tester.enterText(field, finalRaw));
    final afterLastKeystroke = Stopwatch()..start();
    await tester.pump();
    expect(rig.service.requests, isEmpty);
    final otherField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(_secondComposer),
        matching: find.byType(TextField),
      ),
    );
    expect(otherField.controller!.text, finalRaw);
    await tester.pump(const Duration(milliseconds: 50));
    await _until(tester, () => rig.service.results.length == 1);
    await tester.pump();
    expect(rig.service.requests.single.raw, finalRaw);
    expect(rig.service.results.single.failure, isNull);
    _emit({
      'case': 'rapid-typing-two-composers',
      'revisions': 41,
      'mountedComposers': 2,
      'submittedCooks': rig.service.requests.length,
      'maxConcurrentCooks': rig.service.maxActive,
      'typingStartedToPreparedMicros': preparation.elapsedMicroseconds,
      'finalKeystrokeToPreparedMicros': afterLastKeystroke.elapsedMicroseconds,
      'widgetDebounceAdvanceMillis': 50,
    });

    // Removing one composer suspends pending preparation but preserves a ready
    // result and the source shared with the other mounted composer.
    await tester.pumpWidget(
      _PipelineView(shell: rig.shell, composers: true, firstComposer: false),
    );
    await rig.sendAndRender(
      tester,
      label: 'warm-prepared-submit',
      outgoing: OutgoingChatMessage.text(finalRaw),
      marker: 'Prepared-marker',
      expectPrepared: true,
      composers: true,
    );
    expect(rig.service.requests, hasLength(1));
    expect(rig.service.httpAttempts, 0);
    rig.emitSummary('prepared-two-composer-pipeline');
  });
}

String _richSource(String marker) => '''**$marker** @Alice :smile:

[date=2026-09-19 time=12:00:00 timezone="Etc/UTC" format="YYYY-MM-DD"]

[quote="Alice, post:1, topic:42"]
Quoted text
[/quote]

```dart
final answer = 42;
```

[external](https://external.test/path)''';

/// Real application host/runtime with observation only. Suppressing optional
/// prewarming deliberately makes the first submission pay for worker startup.
/// Each source is distinct and the host result cache is disabled so a warm
/// measurement still traverses the worker. HttpOverrides guards the Dart host
/// path; the real JS worker separately has no network capability installed.
final class _MeasuredCookingService implements CookingServicePort {
  final inner = CookingHostService(maxCacheEntries: 0);
  final requests = <CookingRequest>[];
  final results = <CookingResult>[];
  var httpAttempts = 0;
  var maxActive = 0;
  var _active = 0;

  T withoutHttp<T>(T Function() body) => HttpOverrides.runZoned(
    body,
    createHttpClient: (_) {
      httpAttempts++;
      throw StateError('Cooking must not create an HTTP client');
    },
  );

  @override
  Future<bool> start() async => true;

  @override
  Future<CookingResult> cook(CookingRequest request) => withoutHttp(() async {
    requests.add(request);
    _active++;
    if (_active > maxActive) maxActive = _active;
    try {
      final result = await inner.cook(request);
      results.add(result);
      return result;
    } finally {
      _active--;
    }
  });

  @override
  void invalidate() => inner.invalidate();

  @override
  Future<void> dispose() => inner.dispose();
}

final class _Rig {
  _Rig(this.shell, this.api, this.plugins, this.service, this.sendGate);

  final ShellController shell;
  final FakeDiscourseApi api;
  final InstalledPlugins plugins;
  final _MeasuredCookingService service;
  final Completer<void> sendGate;
  var mediaRequests = 0;
  var disposed = false;

  static Future<_Rig> create(WidgetTester tester) async {
    final plugins = PluginInstaller.install(
      PluginManifest([
        cookingModule,
        const ChatModule(apiFactory: _chatApi),
        localDatesModule,
      ]),
    );
    final service = _MeasuredCookingService();
    final gate = Completer<void>();
    final config = SiteConfig(
      plugins: PluginData.none
          .withValue(chatSettingsDataKey, const ChatSettings())
          .withValue(
            localDatesSettingsDataKey,
            const LocalDatesSettings(enabled: true),
          ),
    );
    final api = FakeDiscourseApi(user: _user, chatSendGate: gate);
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        DiscourseInstance(
          url: _site,
          title: 'Pipeline',
          apiVersion: 4,
          user: _user,
          config: config,
        ),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
      plugins: plugins,
      cookingService: service,
    );
    final rig = _Rig(shell, api, plugins, service, gate);
    installTestMediaPipeline(
      client: MockClient((request) async {
        rig.mediaRequests++;
        return http.Response.bytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
          ),
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!rig.disposed) {
        shell.dispose();
        rig.disposed = true;
      }
      if (!gate.isCompleted) gate.complete();
      var stopped = false;
      unawaited(shell.cooking.dispose().then((_) => stopped = true));
      await _until(tester, () => stopped);
      await plugins.close();
    });
    await tester.runAsync(shell.load);
    for (final id in [9, 10]) {
      shell.chatRecords.put(
        _site,
        ChatChannel(
          id: id,
          title: 'Pipeline $id',
          kind: id == 9
              ? ChatChannelKind.category
              : ChatChannelKind.directMessage,
          membership: const ChatMembership(following: true),
        ),
      );
    }
    shell.store.put(_site, const UserCard(username: 'Alice', id: 8));
    await tester.pump();
    return rig;
  }

  Future<ChatMessage> sendAndRender(
    WidgetTester tester, {
    required String label,
    required OutgoingChatMessage outgoing,
    required String marker,
    int channelId = 9,
    bool expectPrepared = false,
    bool composers = false,
    Map<String, Object?> extra = const {},
  }) async {
    final previousCooks = service.requests.length;
    final watch = Stopwatch()..start();
    final handle = service.withoutHttp(
      () => shell.chat.sendMessage(_site, channelId, outgoing),
    );
    final stageMicros = watch.elapsedMicroseconds;
    expect(handle, isNotNull);
    final id = handle!.localId;
    final staged = shell.chat.message(_site, id)!;
    expect(staged.raw, outgoing.raw);
    expect(staged.canonicalReceived, isFalse);
    expect(staged.cooked, isEmpty);
    expect(
      service.requests.length,
      previousCooks,
      reason: 'Staging must not start snapshot assembly or cooking',
    );
    expect(staged.provisionalCooked != null, expectPrepared);
    int? rowMicros = expectPrepared ? stageMicros : null;
    final ref = shell.chat.messageRef(_site, id);
    void onRow() {
      if (shell.chat.message(_site, id)?.provisionalCooked != null) {
        rowMicros ??= watch.elapsedMicroseconds;
      }
    }

    ref.addListener(onRow);
    try {
      await tester.pumpWidget(
        _PipelineView(
          shell: shell,
          messageId: id,
          composers: composers,
          firstComposer: false,
        ),
      );
      await _until(
        tester,
        () =>
            rowMicros != null &&
            find.byType(CookedHtml).evaluate().isNotEmpty &&
            find
                .textContaining(marker, findRichText: true)
                .evaluate()
                .isNotEmpty,
      );
      final renderedMicros = watch.elapsedMicroseconds;
      final row = shell.chat.message(_site, id)!;
      expect(row.canonicalReceived, isFalse);
      expect(sendGate.isCompleted, isFalse);
      expect(
        tester
            .widgetList<CookedHtml>(find.byType(CookedHtml))
            .map((widget) => widget.html),
        contains(row.provisionalCooked),
      );
      final request = service.requests.last;
      final result = service.results.last;
      expect(result.failure, isNull, reason: '$label: ${result.toJson()}');
      _emit({
        'case': label,
        'clock': 'Stopwatch.wall',
        'mode': 'desktop-debug-widget-test',
        'optionalPrewarmDeferred': true,
        'hostResultCacheEntries': service.inner.cachedResultCount,
        'sourceUtf8Bytes': utf8.encode(outgoing.raw).length,
        'snapshotUtf8Bytes': utf8
            .encode(jsonEncode(request.snapshot.toJson()))
            .length,
        'resultUtf8Bytes': utf8.encode(row.provisionalCooked!).length,
        'stageMicros': stageMicros,
        'submittedToProvisionalHtmlMicros': rowMicros,
        'submittedToNativeRenderedMicros': renderedMicros,
        'workerReportedMicros': result.elapsedMicroseconds,
        'cooksOnSubmit': service.requests.length - previousCooks,
        'maxConcurrentCooks': service.maxActive,
        ...extra,
      });
      return row;
    } finally {
      ref.removeListener(onRow);
    }
  }

  void emitSummary(String label) => _emit({
    'case': label,
    'compilerHttpClientAttempts': service.httpAttempts,
    'mockedRendererMediaRequests': mediaRequests,
    'submittedCooks': service.requests.length,
    'completedCooks': service.results.length,
    'maxConcurrentCooks': service.maxActive,
    'normalSendRequestsAwaitingResponse': api.chatMessagesSent.length,
  });
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final timeout = Stopwatch()..start();
  while (!ready() && timeout.elapsed < const Duration(seconds: 15)) {
    // Worker events need real time; pump then delivers their widget-zone
    // continuations. Advancing fake time would expire unrelated watchdogs.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'Real worker/rendering failed to settle');
}

void _emit(Map<String, Object?> value) {
  // ignore: avoid_print
  print('COOKING_PIPELINE_METRIC ${jsonEncode(value)}');
}

final class _PipelineView extends StatelessWidget {
  const _PipelineView({
    required this.shell,
    this.messageId,
    this.composers = false,
    this.firstComposer = true,
  });

  final ShellController shell;
  final int? messageId;
  final bool composers, firstComposer;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: shell,
    child: PluginUiScope.own(
      chatPluginId,
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              if (messageId case final id?)
                Expanded(
                  child: SingleChildScrollView(
                    child: ChatMessageTile(
                      siteUrl: _site,
                      messageId: id,
                      chained: false,
                    ),
                  ),
                ),
              if (composers)
                Row(
                  children: [
                    if (firstComposer)
                      const Expanded(
                        child: ChatComposer(
                          key: _firstComposer,
                          siteUrl: _site,
                          channelId: 9,
                        ),
                      ),
                    const Expanded(
                      child: ChatComposer(
                        key: _secondComposer,
                        siteUrl: _site,
                        channelId: 9,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
