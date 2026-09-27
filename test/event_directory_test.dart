import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
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

  Future<void> pump(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.macOS,
    Brightness brightness = Brightness.light,
    EventCalendarPage? page,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform, brightness: brightness),
        home: Scaffold(
          body: EventDirectory(
            site: eventSite,
            mine: false,
            page: page,
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
    if (settle) await tester.pumpAndSettle();
  }

  for (final view in [EventCalendarView.schedule, EventCalendarView.month]) {
    testWidgets(
      '${view.name} uses skeletons until events load and on foreground resume',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        final request = Completer<Map<String, dynamic>>();
        transport.respond = (_) => request.future;
        await pump(
          tester,
          platform: TargetPlatform.iOS,
          page: EventCalendarPage(view, DateTime.utc(2026, 9, 8)),
          settle: false,
        );
        await tester.pump();
        expect(find.bySemanticsLabel('Loading events'), findsOneWidget);
        expect(find.byType(DSkeletonRegion), findsOneWidget);
        expect(find.byType(DProgress), findsNothing);
        expect(find.text('No events in this period.'), findsNothing);
        final calendar = tester.state(
          find.byType(kalender.KalenderView, skipOffstage: false),
        );

        request.complete({
          'events': [current],
        });
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        expect(find.byType(DSkeletonRegion), findsNothing);
        expect(find.byType(kalender.KalenderView), findsOneWidget);
        expect(
          tester.state(find.byType(kalender.KalenderView)),
          same(calendar),
        );
        if (view == EventCalendarView.schedule) {
          expect(
            find.text('Engineering Managers Call').hitTestable(),
            findsOneWidget,
          );
        }

        final refresh = Completer<Map<String, dynamic>>();
        transport.respond = (_) => refresh.future;
        expect(find.byTooltip('Calendar actions'), findsNothing);
        ports.controller.setForeground(false);
        ports.controller.setForeground(true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.bySemanticsLabel('Loading events'), findsOneWidget);
        expect(find.textContaining('Engineering Managers Call'), findsNothing);
        expect(find.byType(DProgress), findsNothing);
        expect(find.byTooltip('Next month').hitTestable(), findsOneWidget);

        refresh.complete({
          'events': [current],
        });
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        expect(find.byType(DSkeletonRegion), findsNothing);
        expect(
          tester.state(find.byType(kalender.KalenderView)),
          same(calendar),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('failed event loading removes the skeleton and offers retry', (
    tester,
  ) async {
    final request = Completer<Map<String, dynamic>>();
    transport.respond = (_) => request.future;
    await pump(tester, settle: false);
    await tester.pump();
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    request.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(
      find.text('Unable to load events. Try refreshing the calendar.'),
      findsOneWidget,
    );
    transport.respond = (_) => {
      'events': [current],
    };
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(
      find.textContaining('Engineering Managers Call', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '${platform.name} defaults to Schedule and retains a selected view',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        transport.respond = (_) => {
          'events': [current],
        };
        await pump(tester, platform: platform);
        EventCalendarPage currentPage() =>
            tester.widget<EventCalendar>(find.byType(EventCalendar)).page;
        expect(currentPage().view, EventCalendarView.schedule);
        expect(find.byType(DCalendarScheduleEntry), findsWidgets);
        expect(transport.queries, hasLength(1));
        expect(
          transport.queries.single.queryParameters['after'],
          '2026-08-31T22:00:00.000Z',
        );
        expect(
          transport.queries.single.queryParameters['before'],
          '2026-09-30T22:00:00.000Z',
        );

        await tester.tap(find.byType(DSelect<EventCalendarView>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Month'));
        await tester.pumpAndSettle();
        expect(currentPage().view, EventCalendarView.month);
        await pump(tester, platform: platform, brightness: Brightness.dark);
        expect(currentPage().view, EventCalendarView.month);
        expect(transport.queries, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('mobile preserves an explicit calendar route', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final page = EventCalendarPage(
      EventCalendarView.month,
      DateTime.utc(2026, 9, 8),
    );
    await pump(tester, platform: TargetPlatform.iOS, page: page);
    expect(tester.widget<EventCalendar>(find.byType(EventCalendar)).page, page);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop defaults to Month even with an old configured view', (
    tester,
  ) async {
    ports.settings = const EventSettings(
      enabled: true,
      calendarView: EventCalendarView.week,
    );
    transport.respond = (_) => {
      'events': [current],
    };
    await pump(tester);
    expect(
      tester.widget<EventCalendar>(find.byType(EventCalendar)).page.view,
      EventCalendarView.month,
    );
    expect(tester.takeException(), isNull);
  });

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
      ports.controller.setForeground(false);
      ports.controller.setForeground(true);
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
      await tester.tap(find.byType(DSelect<EventCalendarView>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(transport.queries.map((uri) => uri.queryParameters), [
        for (final (after, before) in [
          ('2026-08-30T22:00:00.000Z', '2026-10-04T22:00:00.000Z'),
          ('2026-09-27T22:00:00.000Z', '2026-11-01T23:00:00.000Z'),
          ('2026-08-30T22:00:00.000Z', '2026-10-04T22:00:00.000Z'),
          ('2026-08-31T22:00:00.000Z', '2026-09-30T22:00:00.000Z'),
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

  for (final view in [
    EventCalendarView.week,
    EventCalendarView.day,
    EventCalendarView.year,
  ]) {
    testWidgets('old ${view.name} links open the requested month', (
      tester,
    ) async {
      transport.respond = (_) => {'events': <Object?>[]};
      await pump(
        tester,
        page: EventCalendarPage(view, DateTime.utc(2026, 10, 8)),
      );
      final calendar = tester.widget<EventCalendar>(find.byType(EventCalendar));
      expect(calendar.page.view, EventCalendarView.month);
      expect(calendar.page.date, DateTime.utc(2026, 10, 8));
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.byTooltip('Calendar actions'), findsNothing);
      expect(find.byType(DDropdownMenu), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('default follows window width until a view is selected', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    transport.respond = (_) => {'events': <Object?>[]};
    await pump(tester);
    EventCalendarPage currentPage() =>
        tester.widget<EventCalendar>(find.byType(EventCalendar)).page;
    expect(currentPage().view, EventCalendarView.schedule);
    tester.view.physicalSize = const Size(1000, 844);
    await tester.pumpAndSettle();
    expect(currentPage().view, EventCalendarView.month);
    await tester.tap(find.byType(DSelect<EventCalendarView>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1000, 844);
    await tester.pumpAndSettle();
    expect(currentPage().view, EventCalendarView.schedule);
    expect(tester.takeException(), isNull);
  });
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
