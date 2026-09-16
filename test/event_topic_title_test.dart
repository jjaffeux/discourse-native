import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

const _timed = EventTopicData(
  startsAt: '2026-10-14T20:00:00+02:00',
  endsAt: '2026-10-14T21:00:00+02:00',
  timezone: 'Europe/Paris',
);
const _title = 'Sales Stage Cross Functional';

void main() {
  testWidgets(
    'stamp identifies the event and opens an accessible full schedule',
    (tester) async {
      final ports = EventTestPorts();
      addTearDown(ports.close);
      var opened = 0;
      await _pump(tester, ports, onOpen: () => opened++);
      expect(find.text('OCT'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('Event · Wed · 20:00'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('OCT')).dx,
        lessThan(tester.getTopLeft(find.text(_title)).dx),
      );
      expect(
        find.bySemanticsLabel(
          RegExp('View event schedule:.*2026.*Europe/Paris'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('event-schedule-trigger')));
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(find.text('Event schedule'), findsOneWidget);
      expect(find.text('Starts'), findsOneWidget);
      expect(find.text('Ends'), findsOneWidget);
      expect(find.text('Wednesday, October 14, 2026 · 21:00'), findsOneWidget);
      expect(find.text('Europe/Paris'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Event schedule'), findsNothing);
      await tester.tap(find.text(_title));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reader timezone updates both calendar day and an open schedule',
    (tester) async {
      final ports = EventTestPorts();
      addTearDown(ports.close);
      await _pump(tester, ports);
      await tester.tap(find.byKey(const ValueKey('event-schedule-trigger')));
      await tester.pumpAndSettle();
      ports.user = const DiscourseUser(username: 'lee', timezone: 'Asia/Tokyo');
      ports.controller.pluginCurrentUserRefreshed(eventSite);
      await tester.pumpAndSettle();
      expect(find.text('Asia/Tokyo'), findsOneWidget);
      expect(find.text('Thursday, October 15, 2026 · 03:00'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('15'), findsOneWidget);
      expect(find.text('Event · Thu · 03:00'), findsOneWidget);
    },
  );

  testWidgets(
    'all-day dates stay calendar days and do not suggest a timezone',
    (tester) async {
      final ports = EventTestPorts();
      addTearDown(ports.close);
      ports.user = const DiscourseUser(
        username: 'lee',
        timezone: 'America/Los_Angeles',
      );
      await _pump(
        tester,
        ports,
        event: const EventTopicData(startsAt: '2026-10-16', allDay: true),
      );
      expect(find.text('16'), findsOneWidget);
      expect(find.text('Event · Fri · All day'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-schedule-trigger')));
      await tester.pumpAndSettle();
      expect(find.text('Friday, October 16, 2026 · All day'), findsOneWidget);
      expect(find.text('Timezone'), findsNothing);
      expect(find.text('Ends'), findsNothing);
    },
  );

  testWidgets('event-local time takes precedence when requested', (
    tester,
  ) async {
    final ports = EventTestPorts();
    addTearDown(ports.close);
    ports.user = const DiscourseUser(username: 'lee', timezone: 'Asia/Tokyo');
    await _pump(
      tester,
      ports,
      event: const EventTopicData(
        startsAt: '2026-10-14T20:00:00+02:00',
        timezone: 'Europe/Paris',
        showLocalTime: true,
      ),
    );
    expect(find.text('14'), findsOneWidget);
    expect(find.text('Event · Wed · 20:00'), findsOneWidget);
  });

  testWidgets('multi-day ranges count calendar days across daylight saving', (
    tester,
  ) async {
    final ports = EventTestPorts();
    addTearDown(ports.close);
    await _pump(
      tester,
      ports,
      event: const EventTopicData(
        startsAt: '2026-10-24T09:00:00+02:00',
        endsAt: '2026-10-26T17:00:00+01:00',
        timezone: 'Europe/Paris',
      ),
    );
    expect(find.text('Event · Oct 24 – Oct 26 · 3 days'), findsOneWidget);
  });

  testWidgets('cross-year and future dates keep their year visible', (
    tester,
  ) async {
    final ports = EventTestPorts();
    addTearDown(ports.close);
    await _pump(
      tester,
      ports,
      event: const EventTopicData(
        startsAt: '2026-12-31',
        endsAt: '2027-01-02',
        allDay: true,
      ),
    );
    expect(
      find.text('Event · Dec 31, 2026 – Jan 2, 2027 · All day'),
      findsOneWidget,
    );
    await _pump(
      tester,
      ports,
      event: const EventTopicData(startsAt: '2027-10-16', allDay: true),
    );
    expect(find.text('Event · Sat, Oct 16, 2027 · All day'), findsOneWidget);
  });

  testWidgets('hidden or invalid event dates leave the original title alone', (
    tester,
  ) async {
    final ports = EventTestPorts();
    addTearDown(ports.close);
    await _pump(tester, ports);
    ports.settings = const EventSettings(
      enabled: true,
      displayTopicDate: false,
    );
    ports.controller.pluginCurrentUserRefreshed(eventSite);
    await tester.pumpAndSettle();
    expect(find.byType(DCard), findsNothing);
    expect(find.text(_title), findsOneWidget);
    ports.settings = const EventSettings(enabled: true);
    ports.controller.pluginCurrentUserRefreshed(eventSite);
    await tester.pumpAndSettle();
    expect(find.text('14'), findsOneWidget);
    await _pump(
      tester,
      ports,
      event: const EventTopicData(startsAt: 'invalid'),
    );
    expect(find.byType(DCard), findsNothing);
    expect(find.text(_title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final rtl in [false, true]) {
      testWidgets('320px large-text range wraps, dark=$dark rtl=$rtl', (
        tester,
      ) async {
        final ports = EventTestPorts();
        addTearDown(ports.close);
        await tester.binding.setSurfaceSize(const Size(320, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pump(
          tester,
          ports,
          dark: dark,
          rtl: rtl,
          scale: 2,
          event: const EventTopicData(
            startsAt: '2026-12-31',
            endsAt: '2027-01-02',
            allDay: true,
          ),
        );
        expect(
          find.text('Event · Dec 31, 2026 – Jan 2, 2027 · All day'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('event-schedule-trigger')));
        await tester.pumpAndSettle();
        expect(find.text('Starts'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<void> _pump(
  WidgetTester tester,
  EventTestPorts ports, {
  EventTopicData event = _timed,
  VoidCallback? onOpen,
  bool dark = false,
  bool rtl = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: DItem(
            onPressed: onOpen ?? () {},
            children: [
              DItemContent(
                children: [
                  EventTopicTitle(
                    site: eventSite,
                    topicTitle: _title,
                    event: event,
                    controller: ports.controller,
                    child: const Text(_title),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
