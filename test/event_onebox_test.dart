import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_module.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_controller.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_onebox.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_onebox_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import 'support/event_fixtures.dart';
import 'support/native_ui_evidence.dart';

const _topicPath =
    '/discourse-post-event/events.json?topic_id=700&include_details=true&include_closed=true&limit=1';
const _quote =
    '<aside class="quote" data-topic="700" data-post="1"><a href="/t/team/700/1">Published event fallback</a><p>Published description</p></aside>';
String _external({String url = 'https://other.example/t/team/700'}) =>
    '''
<aside class="onebox"><div class="discourse-event-onebox"
data-event-starts-at="2026-11-01T01:00:00Z"
data-event-ends-at="2026-11-01T02:00:00Z" data-event-timezone="Etc/UTC">
<h3><a href="$url">Community gathering</a></h3>
<div class="discourse-event-onebox__description">Published invitation</div>
</div></aside>''';

void main() {
  test('onebox parsing scopes local lookups and external image origins', () {
    EventOneboxData? read(String markup, {String site = eventSite}) =>
        EventOneboxData.from(html.parseFragment(markup).children.single, site);
    expect(read(_quote)!.topicId, 700);
    expect(read(_external())!.topicId, isNull);
    expect(read(_external(url: '$eventSite/t/team/700'))!.topicId, 700);
    expect(read(_external(url: '$eventSite/t/700/1'))!.topicId, 700);
    final laterPost = read(_external(url: '$eventSite/t/123/4'))!.topicId;
    // ignore: avoid_print
    print('PERF_PROOF topic-link-owner onebox_later_post_topic=$laterPost');
    expect(laterPost, isNull, reason: 'the event lives on post 1');
    expect(
      read(
        _external(url: '$eventSite/forum/t/team/700'),
        site: '$eventSite/forum',
      )!.topicId,
      700,
    );
    expect(
      read(
        _external(url: '$eventSite/t/team/700'),
        site: '$eventSite/forum',
      )!.topicId,
      isNull,
    );
    expect(read(_external(url: 'javascript:alert(1)')), isNull);
    expect(read('<div>${_external()}</div>'), isNull);
    final image = read(
      _external().replaceFirst(
        '<h3>',
        '<img class="discourse-event-onebox__image" src="/banner.png"><h3>',
      ),
    )!;
    expect(image.image, 'https://other.example/banner.png');
    expect(
      read(
        _quote.replaceFirst(
          'data-post="1"',
          'data-post="1" data-username="sam"',
        ),
      ),
      isNull,
    );
  });

  test('blank onebox images do not resolve to the event topic page', () {
    for (final source in ['', '   ']) {
      final markup = _external().replaceFirst(
        '<h3>',
        '<img class="discourse-event-onebox__image" src="$source"><h3>',
      );
      final element = html.parseFragment(markup).children.single;
      final event = EventOneboxData.from(element, eventSite)!;
      expect(event.image, isNull, reason: 'src="$source"');
    }
  });

  test(
    'topic lookups keep active admission separate from cached answers',
    () async {
      final ports = EventTestPorts();
      addTearDown(ports.close);
      final responses = <Completer<Map<String, dynamic>>>[];
      final lookups = <Future<PostEvent?>>[];
      for (var topic = 1; topic <= 65; topic++) {
        final response = Completer<Map<String, dynamic>>();
        responses.add(response);
        ports
                .transport
                .responders['GET /discourse-post-event/events.json?topic_id=$topic&include_details=true&include_closed=true&limit=1'] =
            (_) => response.future;
        lookups.add(ports.controller.eventForTopic(eventSite, topic));
      }
      final joined = ports.controller.eventForTopic(eventSite, 1);
      await Future<void>.delayed(Duration.zero);
      expect(ports.transport.reads, hasLength(65));
      expect(joined, same(lookups.first));
      for (var i = 0; i < responses.length; i++) {
        responses[i].complete({
          'events': [
            eventJson(
              overrides: {
                'post': {
                  'id': 42,
                  'topic': {'id': i + 1},
                },
              },
            ),
          ],
        });
      }
      await Future.wait(lookups);
      await ports.controller.eventForTopic(eventSite, 65);
      expect(ports.transport.reads, hasLength(65));
      await ports.controller.eventForTopic(eventSite, 1);
      expect(
        ports.transport.reads,
        hasLength(66),
        reason: 'Completed answers stay bounded at 64',
      );
    },
  );

  test('retired topic completion cannot cache over a successor', () async {
    final ports = EventTestPorts();
    addTearDown(ports.close);
    final oldResponse = Completer<Map<String, dynamic>>();
    final newResponse = Completer<Map<String, dynamic>>();
    ports.transport.responders['GET $_topicPath'] = (_) => oldResponse.future;
    final old = ports.controller.eventForTopic(eventSite, 700);
    await Future<void>.delayed(Duration.zero);
    ports.controller.pluginCurrentUserRefreshed(eventSite);
    ports.transport.responders['GET $_topicPath'] = (_) => newResponse.future;
    final successor = ports.controller.eventForTopic(eventSite, 700);
    await Future<void>.delayed(Duration.zero);
    oldResponse.complete({
      'events': [
        eventJson(overrides: {'name': 'Old'}),
      ],
    });
    expect(await old, isNull);
    expect(ports.controller.eventForTopic(eventSite, 700), same(successor));
    newResponse.complete({
      'events': [
        eventJson(overrides: {'name': 'Current'}),
      ],
    });
    expect((await successor)!.title, 'Current');
    expect(
      (await ports.controller.eventForTopic(eventSite, 700))!.title,
      'Current',
    );
    expect(ports.transport.reads, hasLength(2));
  });

  test(
    'topic lookup joins requests and retires personalized responses',
    () async {
      final ports = EventTestPorts();
      addTearDown(ports.close);
      final completion = Completer<Map<String, dynamic>>();
      ports.transport.responders['GET $_topicPath'] = (_) => completion.future;
      final first = ports.controller.eventForTopic(eventSite, 700);
      expect(ports.controller.eventForTopic(eventSite, 700), same(first));
      await Future<void>.delayed(Duration.zero);
      ports.requests.forget(eventSite);
      ports.controller.forget(eventSite);
      completion.complete({
        'events': [eventJson()],
      });
      expect(await first, isNull);
      ports.transport.responders['GET $_topicPath'] = (_) => {
        'events': [
          eventJson(overrides: {'name': 'Current account event'}),
        ],
      };
      expect(
        (await ports.controller.eventForTopic(eventSite, 700))!.title,
        'Current account event',
      );
      expect(ports.transport.reads, hasLength(2));
      ports.controller.pluginCurrentUserRefreshed(eventSite);
      await ports.controller.eventForTopic(eventSite, 700);
      expect(ports.transport.reads, hasLength(3));
    },
  );

  test(
    'topic lookup rejects another topic and retries failed lookups',
    () async {
      final ports = EventTestPorts();
      addTearDown(ports.close);
      ports.transport.responses['GET $_topicPath'] = {
        'events': [
          eventJson(
            overrides: {
              'post': {
                'id': 42,
                'topic': {'id': 701},
              },
            },
          ),
        ],
      };
      expect(await ports.controller.eventForTopic(eventSite, 700), isNull);
      ports.transport.responses['GET $_topicPath'] = {
        'events': [eventJson()],
      };
      expect((await ports.controller.eventForTopic(eventSite, 700))!.id, 42);
    },
  );

  test(
    'a resolved topic preview follows canonical live recording updates',
    () async {
      final ports = EventTestPorts();
      addTearDown(ports.close);
      var current = eventJson(
        overrides: {'livestream': true, 'is_expired': true},
      );
      ports.transport.responders['GET $_topicPath'] = (_) => {
        'events': [current],
      };
      ports.transport.responders['GET /discourse-post-event/events/42.json'] =
          (_) => {'event': current};
      final seed = (await ports.controller.eventForTopic(eventSite, 700))!;
      final handle = ports.controller.acquire(eventSite, seed);
      await handle.refresh();
      expect(handle.event!.recordingUrl, isNull);
      current = eventJson(
        overrides: {'recording_url': 'https://video.example/replay'},
      );
      ports.channels.deliver('/discourse-post-event/700', {'id': 42});
      await Future<void>.delayed(Duration.zero);
      expect(handle.event!.recordingUrl, 'https://video.example/replay');
      handle.dispose();
    },
  );

  Future<(PluginHostHarness, InstalledPlugins)> host(
    RecordingPluginTransport transport,
  ) async {
    final host = await PluginHostHarness.open(
      transport: transport,
      manifest: const PluginManifest([discourseEventsModule]),
      sites: [
        PluginHostSite(
          url: eventSite,
          apiKey: 'key',
          user: const PluginHostUser(username: 'lee', id: 2),
          config: SiteConfig(
            plugins: PluginData.none.withValue(
              eventSettingsKey,
              const EventSettings(enabled: true),
            ),
          ),
        ),
      ],
    );
    final plugins = PluginInstaller.install(
      const PluginManifest([discourseEventsModule]),
    );
    addTearDown(host.close);
    addTearDown(plugins.close);
    return (host, plugins);
  }

  Future<void> pump(
    WidgetTester tester,
    PluginHostHarness host,
    InstalledPlugins plugins,
    String markup,
  ) async {
    await tester.pumpWidget(
      host.scope(
        child: MaterialApp(
          builder: nativeUiEvidenceBuilder,
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: plugins.registry.cookedElement(
                eventSite,
                html.parseFragment(markup).children.single,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'local cooked preview hydrates and receives a recording live update',
    (tester) async {
      var current = eventJson(
        overrides: {'livestream': true, 'is_expired': true},
      );
      final transport = RecordingPluginTransport(
        responses: {
          'GET $_topicPath': {
            'events': [current],
          },
        },
      );
      transport.responders['GET /discourse-post-event/events/42.json'] = (_) =>
          {'event': current};
      final (session, plugins) = await host(transport);
      await pump(tester, session, plugins, _quote);
      expect(find.byType(PostEventCard), findsOneWidget);
      expect(find.text('Engineering Managers Call'), findsOneWidget);
      expect(find.text('Watch recording'), findsNothing);
      current = eventJson(
        overrides: {
          'livestream': true,
          'is_expired': true,
          'recording_url': 'video.example/replay',
        },
      );
      final controller = session.require(eventControllerKey);
      final handle = controller.acquire(eventSite, PostEvent.decode(current)!);
      await handle.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Watch recording'), findsOneWidget);
      expect(find.byType(EventOnebox), findsOneWidget);
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('denied lookup keeps original published quote body and links', (
    tester,
  ) async {
    final transport = RecordingPluginTransport();
    final (session, plugins) = await host(transport);
    await pump(tester, session, plugins, _quote);
    expect(find.byType(PostEventCard), findsNothing);
    expect(
      find.text('Published description', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Published event fallback', findRichText: true),
      findsOneWidget,
    );
    expect(
      transport.reads.where((request) => request.path == _topicPath),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a published quote discovers a new event on foreground resume', (
    tester,
  ) async {
    final transport = RecordingPluginTransport(
      responses: {
        'GET $_topicPath': {'events': <Object?>[]},
      },
    );
    final (session, plugins) = await host(transport);
    await pump(tester, session, plugins, _quote);
    expect(find.byType(PostEventCard), findsNothing);
    expect(
      find.text('Published description', findRichText: true),
      findsOneWidget,
    );

    final controller = session.require(eventControllerKey);
    controller.setForeground(false);
    transport.responses['GET $_topicPath'] = {
      'events': [eventJson()],
    };
    transport.responses['GET /discourse-post-event/events/42.json'] = {
      'event': eventJson(),
    };
    controller.setForeground(true);
    await tester.pumpAndSettle();

    expect(find.byType(PostEventCard), findsOneWidget);
    expect(find.text('Engineering Managers Call'), findsOneWidget);
    expect(
      transport.reads.where((request) => request.path == _topicPath),
      hasLength(2),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [390.0, 1100.0]) {
    testWidgets('foreign event preview stays informational at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 750));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await prepareNativeUiEvidence(tester);
      final transport = RecordingPluginTransport();
      final (session, plugins) = await host(transport);
      await pump(tester, session, plugins, _external());
      expect(find.text('Community gathering'), findsOneWidget);
      expect(find.text('Published invitation'), findsOneWidget);
      expect(find.byType(PostEventCard), findsNothing);
      expect(
        transport.reads.where(
          (request) => request.path.startsWith('/discourse-post-event/'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await captureNativeUi(tester, 'event-onebox-${width.toInt()}');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test(
    'recordings accept only browser URLs and retain cached onebox fields',
    () {
      for (final source in [
        'javascript:alert(1)',
        'mailto:me@example.org',
        'https://user:pass@example.org/video',
        'https://example.org/a\nb',
      ]) {
        expect(eventRecordingUrl(source), isNull);
      }
      expect(
        eventRecordingUrl('video.example/replay'),
        'https://video.example/replay',
      );
      final event = PostEvent.decode(
        eventJson(
          overrides: {
            'recording_url': 'https://video.example/replay',
            'recording_onebox': '<p>Replay preview</p>',
          },
        ),
      )!;
      expect(event.recordingOnebox, '<p>Replay preview</p>');
      expect(
        PostEvent.decode(
          eventJson(
            overrides: {
              'recording_url': 'javascript:alert(1)',
              'recording_onebox': '<p>Replay preview</p>',
            },
          ),
        )!.recordingOnebox,
        isNull,
      );
    },
  );

  testWidgets(
    'recording menu reuses event authoring and cached recording renders',
    (tester) async {
      final ports = EventTestPorts();
      addTearDown(ports.close);
      var edits = 0;
      Widget card(Map<String, Object?> fields) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EventCard(
              event: PostEvent.decode(eventJson(overrides: fields))!,
              siteUrl: eventSite,
              zones: ports.zones,
              onEdit: () => edits++,
            ),
          ),
        ),
      );
      await tester.pumpWidget(card({'livestream': true, 'is_expired': true}));
      await tester.tap(find.byTooltip('Event actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add recording'));
      await tester.pumpAndSettle();
      expect(edits, 1);
      await tester.pumpWidget(
        card({
          'recording_url': 'https://video.example/replay',
          'recording_onebox': '<p>Published replay</p>',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Published replay', findRichText: true), findsOneWidget);
      expect(find.text('Watch recording'), findsNothing);
    },
  );
}
