import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_directory.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalender/kalender.dart' as kalender;

import 'support/event_fixtures.dart';

void main() {
  const read =
      'GET /discourse-post-event/events.json?include_ongoing=true&order=asc&limit=200&after=2026-08-30T22%3A00%3A00.000Z&before=2026-10-04T22%3A00%3A00.000Z';
  late EventTestPorts ports;
  late _CalendarTransport transport;
  late Map<String, dynamic> current;
  setUp(() {
    transport = _CalendarTransport();
    ports = EventTestPorts(transport: transport);
    current = eventJson();
    ports.transport.responders[read] = (request) => {
      'events': [current],
    };
  });
  tearDown(() => ports.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventDirectory(
            site: eventSite,
            mine: false,
            controller: ports.controller,
            navigation: EventNavigation(
              host: _Routes(),
              editor: PluginPostEditorHost(open: (_, _, {focusText}) => false),
              controller: ports.controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'directory repaints reader dates and refreshes on resume without mounted post cards',
    (tester) async {
      ports.user = null;
      ports.transport.responders[read
          .replaceAll('2026-08-30T22', '2026-08-31T00')
          .replaceAll('2026-10-04T22', '2026-10-05T00')] = (_) => {
        'events': [current],
      };
      await pump(tester);
      expect(find.textContaining('21:00', findRichText: true), findsOneWidget);
      ports.environment.setDeviceTimezone('Europe/Paris');
      await tester.pumpAndSettle();
      expect(find.textContaining('23:00', findRichText: true), findsOneWidget);
      ports.controller.setForeground(false);
      current = eventJson(overrides: {'name': 'Updated while away'});
      ports.controller.setForeground(true);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Updated while away', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Engineering Managers Call', findRichText: true),
        findsNothing,
      );
    },
  );

  testWidgets(
    'account refresh clears old directory data and drops a superseded response',
    (tester) async {
      await pump(tester);
      final stale = Completer<Map<String, dynamic>>();
      ports.transport.responders[read] = (_) => stale.future;
      await tester.tap(find.byTooltip('Calendar actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      final next = Completer<Map<String, dynamic>>();
      ports.transport.responders[read] = (_) => next.future;
      ports.controller.pluginCurrentUserRefreshed(eventSite);
      await tester.pump();
      expect(
        find.textContaining('Engineering Managers Call', findRichText: true),
        findsNothing,
      );
      next.complete({
        'events': [
          eventJson(overrides: {'name': 'Current account event'}),
        ],
      });
      await tester.pumpAndSettle();
      stale.complete({
        'events': [current],
      });
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Current account event', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Engineering Managers Call', findRichText: true),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'navigation requests visible periods with timezone-aware DST boundaries',
    (tester) async {
      transport.respond = (_) => {'events': <Object?>[]};
      await pump(tester);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(transport.queries.map((uri) => uri.queryParameters), [
        for (final (after, before) in [
          ('2026-08-30T22:00:00.000Z', '2026-10-04T22:00:00.000Z'),
          ('2026-09-27T22:00:00.000Z', '2026-11-01T23:00:00.000Z'),
          ('2026-08-30T22:00:00.000Z', '2026-10-04T22:00:00.000Z'),
          ('2026-09-07T22:00:00.000Z', '2026-09-08T22:00:00.000Z'),
        ])
          {
            'include_ongoing': 'true',
            'order': 'asc',
            'limit': '200',
            'after': after,
            'before': before,
          },
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a late response from another month cannot replace the current calendar',
    (tester) async {
      await pump(tester);
      final stale = Completer<Map<String, dynamic>>();
      transport.respond = (_) => stale.future;
      await tester.tap(find.byTooltip('Next month'));
      await tester.pump();
      transport.respond = (_) => {
        'events': [
          eventJson(overrides: {'name': 'Current month'}),
        ],
      };
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      stale.complete({
        'events': [
          eventJson(overrides: {'name': 'Stale month'}),
        ],
      });
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Current month', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Stale month', findRichText: true),
        findsNothing,
      );
    },
  );

  testWidgets(
    'year requests bounded quarters and retains every daily occurrence',
    (tester) async {
      transport.respond = (uri) {
        final after = DateTime.parse(uri.queryParameters['after']!);
        final before = DateTime.parse(uri.queryParameters['before']!);
        return {
          'events': [
            eventJson(
              overrides: {
                'occurrences': [
                  for (
                    var date = DateTime.utc(
                      after.year,
                      after.month,
                      after.day + 1,
                      9,
                    );
                    date.isBefore(before);
                    date = date.add(const Duration(days: 1))
                  )
                    {
                      'starts_at': date.toIso8601String(),
                      'ends_at': date
                          .add(const Duration(hours: 1))
                          .toIso8601String(),
                    },
                ],
              },
            ),
          ],
        };
      };
      await pump(tester);
      transport.queries.clear();
      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();
      expect(
        transport.queries.map(
          (uri) =>
              (uri.queryParameters['after'], uri.queryParameters['before']),
        ),
        [
          ('2025-12-31T23:00:00.000Z', '2026-03-31T22:00:00.000Z'),
          ('2026-03-31T22:00:00.000Z', '2026-06-30T22:00:00.000Z'),
          ('2026-06-30T22:00:00.000Z', '2026-09-30T22:00:00.000Z'),
          ('2026-09-30T22:00:00.000Z', '2026-12-31T23:00:00.000Z'),
        ],
      );
      final calendar = tester.widget<kalender.KalenderView>(
        find.byType(kalender.KalenderView),
      );
      final events = calendar.eventsController.events
          .whereType<EventCalendarEntry>();
      expect(events, hasLength(365));
      expect(events.last.localStart.month, 12);
      expect(
        tester.widget<EventCalendar>(find.byType(EventCalendar)).page.date.year,
        2026,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

final class _CalendarTransport extends RecordingPluginTransport {
  final queries = <Uri>[];
  FutureOr<Map<String, dynamic>> Function(Uri)? respond;
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    queries.add(uri);
    return respond != null
        ? await respond!(uri)
        : super.pluginGetJson(
            siteUrl: siteUrl,
            path: path,
            apiKey: apiKey,
            clientId: clientId,
          );
  }
}

final class _Routes implements PluginRouteNavigationHost {
  @override
  final sites = const [
    PluginRouteSite(url: eventSite, title: 'Forum', isConnected: true),
  ];
  @override
  PluginRouteSite get currentSite => sites.single;
  @override
  ContentRoute? currentContent;
  @override
  void selectInstance(int index) {}
  @override
  void pushContent(ContentRoute route) => currentContent = route;
  @override
  void replaceCurrentContent(ContentRoute route) => currentContent = route;
  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) {}
}
