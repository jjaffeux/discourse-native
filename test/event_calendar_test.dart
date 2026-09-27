import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/control_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalender/kalender.dart' as kalender;

import 'support/event_fixtures.dart';

void main() {
  late EventTestPorts ports;
  late EventCalendarPage page;
  late bool mine;
  final opened = <int>[];
  setUp(() {
    ports = EventTestPorts();
    page = EventCalendarPage(EventCalendarView.month, DateTime.utc(2026, 9, 8));
    opened.clear();
    mine = false;
  });
  tearDown(() => ports.close());

  EventCalendarEntry event(
    int id, {
    String? name,
    String? start,
    String? end,
    bool allDay = false,
    Map<String, Object?> metadata = const {},
  }) => EventCalendarEntry.decode(
    PostEvent.decode({
      'id': id,
      'name': name ?? 'Event $id',
      'recurrence': 'every_week',
      'starts_at': start ?? '2026-09-08T09:00:00+02:00',
      'ends_at': end ?? '2026-09-08T10:00:00+02:00',
      'all_day': allDay,
      ...metadata,
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
    TargetPlatform platform = TargetPlatform.macOS,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.reset();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Directionality(
                textDirection: direction,
                child: EventCalendar(
                  page: page,
                  events: events,
                  location: ports.zones.location('Europe/Paris')!,
                  onPageChanged: (value) => setState(() => page = value),
                  onOpen: (event) => opened.add(event.event.id),
                  mine: mine,
                  onMineChanged: (value) => setState(() => mine = value),
                  clock: eventTestNow,
                ),
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

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final width in [390.0, 800.0, 1300.0]) {
      testWidgets('$platform header matches mockup at $width', (tester) async {
        await pump(
          tester,
          [event(1)],
          size: Size(width, 844),
          platform: platform,
        );
        final header = find.byKey(const ValueKey('event-calendar-header'));
        Finder button(String label) =>
            find.ancestor(of: find.text(label), matching: find.byType(DButton));
        Rect surface(Finder control) => tester.getRect(
          find.descendant(of: control, matching: find.byType(DControlArtwork)),
        );
        final scope = surface(button('All events'));
        final view = surface(button('Month'));
        final today = surface(button('Today'));
        final previous = surface(find.byTooltip('Previous month'));
        final next = surface(find.byTooltip('Next month'));
        final title = tester.getRect(find.text('Events'));
        final period = tester.getRect(find.text('September 2026'));
        final separator = tester.getRect(
          find.descendant(of: header, matching: find.byType(DSeparator)),
        );
        expect(title.left, 16);
        expect(title.top, 16);
        expect(scope.left, 16);
        expect(scope.top - title.bottom, closeTo(16, .01));
        expect(view.left - scope.right, closeTo(8, .01));
        expect(view.top, scope.top);
        expect(today.center.dy, scope.center.dy);
        expect(today.right, closeTo(width - 16, .01));
        expect(previous.left, closeTo(16, .01));
        expect(next.right, closeTo(width - 16, .01));
        expect(previous.top - scope.bottom, closeTo(10, .01));
        expect(period.center.dx, closeTo(width / 2, .01));
        expect(period.center.dy, previous.center.dy);
        expect(separator.top - previous.bottom, closeTo(14, .01));
        expect(separator.left, 16);
        expect(separator.width, width - 32);
        expect(tester.getRect(header).bottom - separator.bottom, 16);
        final headingStyle = tester.widget<Text>(find.text('Events')).style!;
        expect(headingStyle.fontSize, 22);
        expect(headingStyle.fontWeight, FontWeight.w700);
        final periodStyle = tester
            .widget<Text>(find.text('September 2026'))
            .style!;
        expect(periodStyle.fontSize, 13.5);
        expect(periodStyle.fontWeight, FontWeight.w600);
        expect(
          tester.widget<Text>(find.text('All events')).style!.fontWeight,
          FontWeight.w600,
        );
        expect(
          tester.widget<Text>(find.text('Month')).style!.fontWeight,
          FontWeight.w400,
        );
        expect(find.byType(DToggleGroup<bool>), findsNothing);
        expect(find.byTooltip('Calendar actions'), findsNothing);
        await tester.tap(find.byType(DSelect<EventCalendarView>));
        await tester.pumpAndSettle();
        for (final label in ['Week', 'Day', 'Year']) {
          expect(find.text(label), findsNothing);
        }
        await tester.tap(find.text('Schedule'));
        await tester.pumpAndSettle();
        expect(page.view, EventCalendarView.schedule);
        await tester.tap(find.byTooltip('Next month'));
        await tester.pumpAndSettle();
        expect(find.text('October 2026'), findsOneWidget);
        await tester.tap(find.text('Today'));
        await tester.pumpAndSettle();
        expect(page.date, DateTime.utc(2026, 9, 8));
        expect(tester.takeException(), isNull);
      });
    }
  }

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
      expect(find.byType(DDialogContent), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Event 30'),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Event 30'));
      await tester.pumpAndSettle();
      expect(opened, [30]);
      expect(find.byType(DDialogContent), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a narrow window with large text keeps all navigation reachable',
    (tester) async {
      await pump(tester, [event(1)], size: const Size(320, 780), scale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(DSelect<EventCalendarView>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(page.date, DateTime.utc(2026, 10));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile month limits bars and opens every event from the whole day',
    (tester) async {
      await pump(
        tester,
        [for (var id = 1; id <= 7; id++) event(id)],
        size: const Size(390, 844),
        platform: TargetPlatform.iOS,
      );
      expect(find.byType(DKalenderCompactMonthBody), findsOneWidget);
      expect(find.text('+3'), findsOneWidget);
      expect(find.textContaining('Event 1', findRichText: true), findsNothing);
      final day = find.bySemanticsLabel(
        'Tuesday, September 8, 2026, Today, 7 events',
      );
      expect(tester.getSize(day).height, greaterThanOrEqualTo(48));
      await tester.tapAt(tester.getBottomLeft(day) + const Offset(12, -5));
      await tester.pumpAndSettle();
      expect(find.byType(DDialogContent), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Event 7'),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Event 7'));
      await tester.pumpAndSettle();
      expect(opened, [7]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile schedule groups dates, retains metadata and opens an occurrence',
    (tester) async {
      await pump(
        tester,
        [
          event(
            1,
            name: 'First event',
            metadata: {
              'creator': {'username': 'sam'},
              'post': {'id': 1, 'category_slug': 'books'},
            },
          ),
          event(
            2,
            name: 'Three day event',
            start: '2026-09-08T15:00:00+02:00',
            end: '2026-09-10T16:00:00+02:00',
          ),
          event(
            3,
            name: 'Later event',
            start: '2026-09-08T19:30:00+02:00',
            end: '2026-09-08T20:00:00+02:00',
          ),
          event(
            4,
            name: 'Next morning',
            start: '2026-09-09T10:00:00+02:00',
            end: '2026-09-09T11:00:00+02:00',
          ),
        ],
        size: const Size(390, 844),
        platform: TargetPlatform.iOS,
      );
      await tester.tap(find.byType(DSelect<EventCalendarView>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(page.view, EventCalendarView.schedule);
      await tester.tap(find.byType(DSelect<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My events'));
      await tester.pumpAndSettle();
      expect(mine, isTrue);
      expect(page.view, EventCalendarView.schedule);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('Tue 8'), findsOneWidget);
      expect(find.text('books · sam'), findsOneWidget);
      expect(find.text('9 am'), findsOneWidget);
      expect(find.text('day 1 of 3'), findsOneWidget);
      expect(find.text('day 2 of 3'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Next morning')).dy,
        lessThan(tester.getTopLeft(find.text('day 2 of 3')).dy),
      );
      expect(
        tester.getTopLeft(find.text('First event')).dy,
        lessThan(tester.getTopLeft(find.text('Later event')).dy),
      );
      await tester.tap(find.text('Later event'));
      expect(opened, [3]);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(page.date, DateTime.utc(2026, 10));
      expect(find.text('First event'), findsNothing);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(page.date, DateTime.utc(2026, 9, 8));
      expect(find.text('First event'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile schedule reflows at 200 percent in RTL', (tester) async {
    page = EventCalendarPage(
      EventCalendarView.schedule,
      DateTime.utc(2026, 9, 8),
    );
    await pump(
      tester,
      [event(1, name: 'A longer meeting title that wraps')],
      size: const Size(320, 780),
      scale: 2,
      platform: TargetPlatform.iOS,
      direction: TextDirection.rtl,
    );
    expect(find.text('A longer meeting title that wraps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today returns safely from an empty month to a long schedule', (
    tester,
  ) async {
    // Exercise intermediate animation frames: 100ms pumps skip Kalender's
    // overlapping page builds and can hide stale schedule item-map reads.
    Future<void> settle() =>
        tester.pumpAndSettle(const Duration(milliseconds: 16));
    await pump(
      tester,
      [
        for (var i = 1; i <= 10; i++)
          event(
            i,
            name: 'Earlier $i',
            start: '2026-09-01T09:00:00+02:00',
            end: '2026-09-01T10:00:00+02:00',
          ),
        event(11, name: 'Current event'),
        for (var i = 12; i <= 30; i++)
          event(
            i,
            name: 'Later $i',
            start: '2026-09-10T09:00:00+02:00',
            end: '2026-09-10T10:00:00+02:00',
          ),
      ],
      size: const Size(320, 844),
      platform: TargetPlatform.iOS,
    );
    await tester.tap(find.byType(DSelect<EventCalendarView>));
    await settle();
    await tester.tap(find.text('Schedule'));
    await settle();
    await tester.tap(find.byTooltip('Next month'));
    await settle();
    expect(page.date, DateTime.utc(2026, 10));
    await tester.tap(find.text('Today').hitTestable().first);
    await settle();
    expect(page.date, DateTime.utc(2026, 9, 8));
    expect(find.text('Current event').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('compact month splits bars across weeks in ${direction.name}', (
      tester,
    ) async {
      final spanning = event(
        1,
        name: 'Long event',
        start: '2026-09-04',
        end: '2026-09-07',
        allDay: true,
      );
      await pump(
        tester,
        [spanning],
        size: const Size(390, 844),
        platform: TargetPlatform.iOS,
        direction: direction,
      );
      final bars = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'calendar-bar-${spanning.id}-',
            ),
      );
      expect(bars, findsNWidgets(2));
      final friday = find.bySemanticsLabel(
        'Friday, September 4, 2026, 1 event',
      );
      final sunday = find.bySemanticsLabel(
        'Sunday, September 6, 2026, 1 event',
      );
      final monday = find.bySemanticsLabel(
        'Monday, September 7, 2026, 1 event',
      );
      final columnWidth = tester.getSize(friday).width;
      expect(
        tester.getSize(bars.first).width,
        closeTo(3 * columnWidth - 8, .01),
      );
      expect(tester.getSize(bars.last).width, closeTo(columnWidth - 8, .01));
      final firstDay = direction == TextDirection.ltr ? friday : sunday;
      expect(
        tester.getTopLeft(bars.first).dx,
        closeTo(tester.getTopLeft(firstDay).dx + 4, .01),
      );
      expect(
        tester.getTopLeft(bars.last).dx,
        closeTo(tester.getTopLeft(monday).dx + 4, .01),
      );
      await tester.drag(
        find.byType(DKalenderCompactMonthBody),
        Offset(direction == TextDirection.ltr ? -350 : 350, 0),
      );
      await tester.pumpAndSettle();
      expect(page.date, DateTime.utc(2026, 10));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('schedule reveals the requested day when fetched events arrive', (
    tester,
  ) async {
    var entries = <EventCalendarEntry>[];
    for (final month in ['09', '10']) {
      page = EventCalendarPage(
        EventCalendarView.schedule,
        DateTime.utc(2026, int.parse(month), 8),
      );
      // Navigation can keep the preceding month's events while loading.
      await pump(tester, entries, size: const Size(390, 844));
      entries = [
        event(
          100,
          name: 'Cross-month event',
          start: '2026-09-30',
          end: '2026-10-02',
          allDay: true,
        ),
        for (var i = 1; i <= 40; i++)
          event(
            i,
            name: 'Earlier $i',
            start: '2026-$month-01T09:00:00+02:00',
            end: '2026-$month-01T10:00:00+02:00',
          ),
        event(
          41,
          name: 'Requested day',
          start: '2026-$month-08T09:00:00+02:00',
          end: '2026-$month-08T10:00:00+02:00',
        ),
        for (var i = 42; i <= 61; i++)
          event(
            i,
            name: 'Following $i',
            start: '2026-$month-09T09:00:00+02:00',
            end: '2026-$month-09T10:00:00+02:00',
          ),
      ];
      await pump(tester, entries, size: const Size(390, 844));
      expect(find.text('Requested day').hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Requested day')).dy,
        lessThan(
          tester.getTopLeft(find.byType(DKalenderScheduleBody)).dy + 100,
        ),
      );
      expect(find.text('Earlier 1').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
