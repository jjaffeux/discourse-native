import 'dart:io';

import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_module.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/plugins/discourse_events/topic_calendar_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_mermaid/discourse_mermaid_module.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_widget.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_module.dart';
import 'package:discourse_native/src/plugins/poll/poll_card.dart';
import 'package:discourse_native/src/plugins/poll/poll_module.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://example.test/forum';
const _poll =
    '''<div class="poll" data-poll-name="lunch"><div class="poll-title">Lunch</div><div class="poll-container"><ul><li data-poll-option-id="a">Soup</li><li data-poll-option-id="b">Salad</li></ul></div><div class="poll-info">0 voters</div></div>''';

Widget _body(String html, {PluginRegistry? registry, Post? post}) =>
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CookedHtml(
            html: html,
            registry: registry,
            post: post,
            siteUrl: _site,
            buildAsync: false,
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'installed owners render fragments without fetching or voting authority',
    (tester) async {
      final transport = RecordingPluginTransport();
      final host = await PluginHostHarness.open(
        transport: transport,
        manifest: const PluginManifest([pollModule, discourseEventsModule]),
        sites: const [
          PluginHostSite(
            url: _site,
            apiKey: 'key',
            user: PluginHostUser(id: 7, username: 'sam'),
          ),
        ],
      );
      addTearDown(host.close);
      final baseline = transport.requests.length;
      var attemptedHttp = 0;
      await HttpOverrides.runZoned(
        () => tester.pumpWidget(
          host.scope(
            child: _body('''$_poll
<div class="discourse-post-event" data-start="2026-09-19" data-name="Planning">Public description<span class="hidden">Secret event text</span></div>
<div class="discourse-calendar-wrap"><div class="calendar">Public calendar<span class="hidden">Secret calendar text</span></div></div>
<div class="group-timezones" data-group="staff" data-size="large"></div>
<div class="hidden"><div class="discourse-post-event" data-name="Secret nested event"></div><img src="https://private.test/hidden.png">Hidden body</div>
<span class="preview">Public preview</span>'''),
          ),
        ),
        createHttpClient: (_) {
          attemptedHttp++;
          throw StateError(
            'Provisional rendering must not acquire remote records',
          );
        },
      );
      await tester.pumpAndSettle();
      expect(find.byType(PollFallbackCard), findsOneWidget);
      expect(find.byType(PollCard), findsNothing);
      expect(find.byType(EventCookedFallback), findsOneWidget);
      expect(find.byType(PostEventCard), findsNothing);
      expect(find.byType(TopicCalendarFallback), findsOneWidget);
      expect(find.text('Soup', findRichText: true), findsOneWidget);
      expect(find.textContaining('0 voters', findRichText: true), findsNothing);
      expect(find.text('Timezones for staff'), findsOneWidget);
      expect(
        find.text('Group member timezones are not available here.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Public preview', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Secret', findRichText: true), findsNothing);
      expect(
        find.textContaining('Hidden body', findRichText: true),
        findsNothing,
      );
      expect(find.byType(DRadioGroup<String>), findsNothing);
      expect(find.byType(DCheckbox), findsNothing);
      expect(transport.requests.length, baseline);
      expect(attemptedHttp, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('canonical poll serializer still owns interactive presentation', (
    tester,
  ) async {
    final installed = PluginInstaller.install(
      const PluginManifest([pollModule]),
    );
    addTearDown(installed.close);
    final post = installed.models.post({
      'id': 11,
      'topic_id': 7,
      'post_number': 2,
      'username': 'sam',
      'cooked': _poll,
      'polls': [
        {
          'name': 'lunch',
          'type': 'regular',
          'status': 'open',
          'results': 'always',
          'public': true,
          'voters': 4,
          'options': [
            {'id': 'a', 'html': 'Soup', 'votes': 3},
            {'id': 'b', 'html': 'Salad', 'votes': 1},
          ],
        },
      ],
    }, _site);
    await tester.pumpWidget(
      _body(_poll, registry: installed.registry, post: post),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PollCard), findsOneWidget);
    expect(find.byType(PollFallbackCard), findsNothing);
    expect(tester.widget<PollCard>(find.byType(PollCard)).poll.voters, 4);
    await tester.pumpWidget(_body(_poll, registry: installed.registry));
    await tester.pumpAndSettle();
    expect(find.byType(PollCard), findsNothing);
    expect(find.byType(PollFallbackCard), findsOneWidget);
    expect(find.textContaining('4 voters', findRichText: true), findsNothing);
  });

  testWidgets('nested details and wraps retain owner renderers without a Post', (
    tester,
  ) async {
    LocalDateEnvironment.instance.ensureDatabase();
    final installed = PluginInstaller.install(
      PluginManifest([pollModule, localDatesModule, discourseMermaidModule]),
    );
    addTearDown(installed.close);
    await tester.pumpWidget(
      _body(
        '''<div class="d-wrap" data-wrap="custom"><details><summary>Rich details</summary>
$_poll
<span class="discourse-local-date" data-date="2026-09-19" data-timezone="Etc/UTC" data-format="YYYY-MM-DD" data-timezones="Europe/Paris|Asia/Tokyo">date fallback</span>
<pre data-code-wrap="mermaid"><code>flowchart TD; A --&gt; B;</code></pre>
</details></div>''',
        registry: installed.registry,
      ),
    );
    await tester.pump();
    expect(find.byType(PollFallbackCard), findsNothing);
    expect(find.byType(LocalDateInline), findsNothing);
    expect(find.byType(DMermaid), findsNothing);
    await tester.tap(find.text('Rich details'));
    await tester.pump();
    expect(find.byType(PollFallbackCard), findsOneWidget);
    expect(find.byType(LocalDateInline), findsOneWidget);
    expect(
      tester
          .widget<LocalDateInline>(find.byType(LocalDateInline))
          .spec
          .timezones,
      ['Europe/Paris', 'Asia/Tokyo'],
    );
    expect(find.byType(DMermaid), findsOneWidget);
    expect(
      tester.widget<DMermaid>(find.byType(DMermaid)).source,
      'flowchart TD; A --> B;',
    );
    // Diagram platform rendering has its own tested offline component. This
    // fixture verifies cooking-marker dispatch and bounded widget retirement.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'event and calendar fallbacks retain nested spoiler concealment',
    (tester) async {
      final installed = PluginInstaller.install(
        const PluginManifest([discourseEventsModule]),
      );
      addTearDown(installed.close);
      await tester.pumpWidget(
        _body('''
<div class="discourse-post-event" data-name="Event"><p>Event introduction</p><div class="spoiler"><p>Event spoiler body</p><a href="/forum/t/1">Nested link</a></div></div>
<div class="calendar"><p>Calendar introduction</p><div class="spoiler"><p>Calendar spoiler body</p></div></div>
''', registry: installed.registry),
      );
      await tester.pumpAndSettle();
      expect(find.text('Spoiler'), findsNWidgets(2));
      expect(
        find.textContaining('spoiler body', findRichText: true),
        findsNothing,
      );
      await tester.tap(find.text('Spoiler').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Event spoiler body', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('Calendar spoiler body', findRichText: true),
        findsNothing,
      );
      expect(
        tester
            .widgetList<CookedHtml>(find.byType(CookedHtml))
            .where((widget) => widget.html.contains('Nested link'))
            .every((widget) => widget.siteUrl == _site),
        isTrue,
      );
      expect(find.byType(PostEventCard), findsNothing);
      await tester.tap(find.text('Spoiler').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Calendar spoiler body', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
