import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalender/kalender.dart' as kalender;

import 'support/event_fixtures.dart';

void main() {
  late EventTestPorts ports;
  late EventCalendarPage page;
  final opened = <int>[];
  setUp(() {
    ports = EventTestPorts();
    page = EventCalendarPage(EventCalendarView.month, DateTime.utc(2026, 9, 8));
    opened.clear();
  });
  tearDown(() => ports.close());

  EventCalendarEntry event(
    int id, {
    String? name,
    String? start,
    String? end,
    bool allDay = false,
  }) => EventCalendarEntry.decode(
    PostEvent.decode({
      'id': id,
      'name': name ?? 'Event $id',
      'recurrence': 'every_week',
      'starts_at': start ?? '2026-09-08T09:00:00+02:00',
      'ends_at': end ?? '2026-09-08T10:00:00+02:00',
      'all_day': allDay,
    })!,
    zones: ports.zones,
    timezone: 'Europe/Paris',
    settings: const EventSettings(),
  )!;

  Future<void> pump(
    WidgetTester tester,
    List<EventCalendarEntry> events, {
    Size size = const Size(1300, 900),
    double scale = 1,
  }) async {
    tester.view.reset();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: EventCalendar(
                page: page,
                events: events,
                location: ports.zones.location('Europe/Paris')!,
                onPageChanged: (value) => setState(() => page = value),
                onOpen: (event) => opened.add(event.event.id),
                mine: false,
                onMineChanged: (_) {},
                actions: const SizedBox(width: 40),
                clock: eventTestNow,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'month grid positions timed events and bars across their actual days',
    (tester) async {
      await pump(tester, [
        event(1, name: 'Morning call'),
        event(
          2,
          name: 'Launch',
          start: '2026-09-14',
          end: '2026-09-17',
          allDay: true,
        ),
      ]);
      expect(find.byType(kalender.KalenderView), findsOneWidget);
      expect(find.byType(DKalenderTheme), findsOneWidget);
      expect(find.byType(DCalendarDayButton), findsWidgets);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('MON'), findsOneWidget);
      final call = find.textContaining('Morning call', findRichText: true);
      final launch = find.textContaining('Launch', findRichText: true);
      expect(call, findsOneWidget);
      expect(launch, findsOneWidget);
      expect(
        tester.getSize(launch).width,
        greaterThan(tester.getSize(call).width * 3),
      );
      expect(
        tester.getTopLeft(launch).dy,
        greaterThan(tester.getTopLeft(call).dy),
      );
      await tester.tap(call);
      expect(opened, [1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'day week month and year controls navigate the matching periods',
    (tester) async {
      await pump(tester, [event(1)]);
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(find.text('Sep 7 – Sep 13, 2026'), findsOneWidget);
      expect(
        find.textContaining('09:00 – 10:00', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();
      expect(page.date, DateTime.utc(2026, 9, 15));
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(find.text('September 8, 2026'), findsOneWidget);
      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();
      expect(find.text('2026'), findsOneWidget);
      expect(find.textContaining('Morning', findRichText: true), findsNothing);
      await tester.tap(find.byTooltip('Next year'));
      await tester.pumpAndSettle();
      expect(find.text('2027'), findsOneWidget);
      expect(find.textContaining('Event 1', findRichText: true), findsNothing);
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      expect(find.text('January 2027'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'crowded months scroll and offer every hidden event in the day dialog',
    (tester) async {
      await pump(tester, [
        for (var id = 1; id <= 30; id++) event(id),
      ], size: const Size(800, 750));
      final day = find.bySemanticsLabel('Tuesday, September 8, 2026');
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Event 30'),
        300,
        scrollable: find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Event 30'));
      await tester.pumpAndSettle();
      expect(opened, [30]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a narrow window with large text keeps all navigation reachable',
    (tester) async {
      await pump(tester, [event(1)], size: const Size(320, 780), scale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(page.date, DateTime.utc(2026, 9, 9));
      expect(tester.takeException(), isNull);
    },
  );
}
