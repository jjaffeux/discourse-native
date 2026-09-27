import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_date_stamp.dart';
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
      expect(find.text('Wed · 20:00'), findsOneWidget);
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
      expect(find.text('Thu · 03:00'), findsOneWidget);
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
      expect(find.text('Fri · All day'), findsOneWidget);
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
    expect(find.text('Wed · 20:00'), findsOneWidget);
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
    expect(find.text('Oct 24 – Oct 26 · 3 days'), findsOneWidget);
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
    expect(find.text('Dec 31, 2026 – Jan 2, 2027 · All day'), findsOneWidget);
    await _pump(
      tester,
      ports,
      event: const EventTopicData(startsAt: '2027-10-16', allDay: true),
    );
    expect(find.text('Sat, Oct 16, 2027 · All day'), findsOneWidget);
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
          find.text('Dec 31, 2026 – Jan 2, 2027 · All day'),
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

  group('rebuild isolation', () {
    final titles = [for (var index = 0; index < 10; index++) 'Topic $index'];
    final ids = [for (var id = 100; id < 110; id++) id];
    Map<String, dynamic> eventFor(int id) => eventJson(
      overrides: {
        'id': id,
        'watching_invitee': watching(),
        'post': {
          'id': id,
          'post_number': 1,
          'topic': {'id': 1000 + id, 'title': 'Event topic $id'},
        },
      },
    );

    Future<void> pumpTitles(WidgetTester tester, EventTestPorts ports) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final title in titles)
                    EventTopicTitle(
                      site: eventSite,
                      topicTitle: title,
                      event: _timed,
                      controller: ports.controller,
                      child: Text(title),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Builds of each mounted title's date stamp from now on, keyed by topic
    /// title: the stamp is rebuilt whenever its title's listener fires.
    Map<String, int> countRebuilds() {
      final rebuilds = <String, int>{};
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is EventDateStamp) {
          rebuilds.update(
            element
                .findAncestorWidgetOfExactType<EventTopicTitle>()!
                .topicTitle,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      return rebuilds;
    }

    testWidgets(
      'events loading and answered elsewhere leave every title alone, and a timezone change redraws each once',
      (tester) async {
        final ports = EventTestPorts();
        addTearDown(ports.close);
        // Without an account timezone the reader's is the device's.
        ports.user = null;
        final loads = {for (final id in ids) id: Completer<Object?>()};
        for (final id in ids) {
          ports
              .transport
              .responders['GET /discourse-post-event/events/$id.json'] = (_) =>
              loads[id]!.future;
        }
        await pumpTitles(tester, ports);
        expect(find.text('Wed · 18:00'), findsNWidgets(titles.length));
        // What each card beside the list holds: one handle per event.
        final handles = [
          for (final id in ids)
            ports.controller.acquire(
              eventSite,
              PostEvent.decode(eventFor(id))!,
            ),
        ];
        addTearDown(() {
          for (final handle in handles) {
            handle.dispose();
          }
        });
        await tester.pumpAndSettle();
        final rebuilds = countRebuilds();

        for (final id in ids) {
          loads[id]!.complete({'event': eventFor(id)});
          await tester.pumpAndSettle();
        }
        expect(handles.every((handle) => handle.authoritative), isTrue);
        const path = '/discourse-post-event/events/100/invitees/83.json';
        ports.transport.responders['PUT $path'] = (_) => {};
        final write = handles.first.respond('interested');
        await tester.pumpAndSettle();
        await write;
        expect(ports.transport.writes.single.path, path);
        expect(rebuilds, isEmpty);

        ports.environment.setDeviceTimezone('Asia/Tokyo');
        await tester.pumpAndSettle();
        expect(find.text('Thu · 03:00'), findsNWidgets(titles.length));
        expect(rebuilds, {for (final title in titles) title: 1});
        expect(tester.takeException(), isNull);
      },
    );
  });
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
