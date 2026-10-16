import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalender/kalender.dart' as kalender;

import 'support/event_fixtures.dart';

void main() {
  late EventTestPorts ports;
  late EventCalendarPage page;
  late List<EventCalendarEntry> entries;
  late StateSetter update;
  var mine = false;
  var loading = false;
  final opened = <int>[];
  final imageKey = GlobalKey();

  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });

  setUp(() {
    ports = EventTestPorts();
    page = EventCalendarPage(EventCalendarView.schedule, DateTime.utc(2026, 9));
    mine = false;
    loading = false;
    opened.clear();
    entries = [
      for (var day = 1; day <= 15; day++)
        for (var item = 0; item < 4; item++)
          EventCalendarEntry.decode(
            PostEvent.decode({
              'id': day * 10 + item,
              'name': 'Day $day event $item',
              'starts_at':
                  '2026-09-${day.toString().padLeft(2, '0')}T09:00:00+02:00',
              'ends_at':
                  '2026-09-${day.toString().padLeft(2, '0')}T10:00:00+02:00',
            })!,
            zones: ports.zones,
            timezone: 'Europe/Paris',
            settings: const EventSettings(),
          )!,
    ];
  });
  tearDown(() => ports.close());

  Future<void> pump(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool reducedMotion = false,
    TextDirection direction = TextDirection.ltr,
    EdgeInsets padding = EdgeInsets.zero,
    bool dock = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.reset);
    final calendar = StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        return EventCalendar(
          page: page,
          events: entries,
          location: ports.zones.location('Europe/Paris')!,
          onPageChanged: (value) => setState(() => page = value),
          onOpen: (entry) => opened.add(entry.event.id),
          mine: mine,
          onMineChanged: (value) => setState(() {
            mine = value;
            entries = [];
          }),
          loading: loading,
          clock: eventTestNow,
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: RepaintBoundary(
          key: imageKey,
          child: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 844),
                textScaler: TextScaler.linear(scale),
                disableAnimations: reducedMotion,
                padding: padding,
              ),
              child: Directionality(
                textDirection: direction,
                child: ForumWindowBackground(
                  child: ForumMobileSurface(
                    child: DScrollChrome(
                      identity: 'schedule-fixture',
                      keepFooterVisible: dock,
                      floatingFooter: true,
                      footerBuilder: (_) => dock
                          ? SizedBox(
                              key: const ValueKey('schedule-dock'),
                              height: 80,
                              child: DCard(
                                child: Center(
                                  child: DButton(
                                    label: const Text('Home'),
                                    onPressed: () {},
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                      child: calendar,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
  }

  Finder pinned() => find.ancestor(
    of: find.byElementPredicate((element) {
      final node = element.renderObject?.debugSemantics;
      return node != null &&
          node.attached &&
          RegExp(r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) \d+$').hasMatch(node.label);
    }),
    matching: find.byWidgetPredicate(
      (widget) => widget is DCalendarScheduleDay && widget.pinned,
    ),
  );
  Finder call(String way) =>
      find.byKey(ValueKey('schedule-today-$way')).hitTestable();
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Rect visibleInk(WidgetTester tester, Finder finder) {
    final render = tester.renderObject<RenderBox>(finder);
    var visible = tester.getRect(finder);
    RenderObject child = render;
    for (var parent = child.parent; parent != null; parent = child.parent) {
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        visible = visible.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
      }
      child = parent;
    }
    return visible;
  }

  Future<void> export(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('EXPORT_SCHEDULE_RENDER')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(imageKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/private/tmp/discourse-events-schedule-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'date pins below the retracting header and yields to the next date',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      final body = find.byType(kalender.ScheduleBody);
      expect(call('after'), findsOneWidget);
      expect(tester.getCenter(call('after')).dy, greaterThan(700));
      final gesture = await tester.startGesture(tester.getCenter(body));
      await gesture.moveBy(const Offset(0, -80));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(tester.widget<DCalendarScheduleDay>(pinned()).label, 'Tue 1');
      final top = tester.getTopLeft(body).dy;
      expect(tester.getTopLeft(pinned()).dy, closeTo(top, 1));
      expect(find.bySemanticsLabel('Tue 1'), findsOneWidget);
      await export(tester, 'pinned');
      var sawPush = false;
      var sawHandoff = false;
      for (var i = 0; i < 70; i++) {
        await gesture.moveBy(const Offset(0, -8));
        await tester.pump(const Duration(milliseconds: 16));
        if (pinned().evaluate().isEmpty) continue;
        final header = tester.widget<DCalendarScheduleDay>(pinned());
        if (header.label == 'Tue 1') {
          final incoming = find.descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is DCalendarScheduleDay &&
                  !widget.pinned &&
                  widget.label == 'Wed 2',
            ),
            matching: find.text('Wed 2'),
          );
          if (incoming.evaluate().isNotEmpty &&
              tester.getTopLeft(pinned()).dy < top - 1) {
            sawPush = true;
            final nextDay = find.ancestor(
              of: incoming,
              matching: find.byType(DCalendarScheduleDay),
            );
            expect(
              tester.getRect(pinned()).bottom,
              closeTo(tester.getRect(nextDay).top, 1),
            );
            if (tester.getRect(pinned()).top > top - 15) {
              await export(tester, 'handoff');
            }
          }
        } else if (header.label == 'Wed 2') {
          sawHandoff = true;
          expect(
            tester.getTopLeft(pinned()).dy,
            closeTo(tester.getTopLeft(body).dy, 1),
          );
          expect(find.bySemanticsLabel('Wed 2'), findsOneWidget);
          await export(tester, 'after-handoff');
          break;
        }
        expect(tester.takeException(), isNull);
      }
      await gesture.up();
      expect(sawPush, isTrue);
      expect(sawHandoff, isTrue);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'a single large scroll hands off the date in its first rendered frame',
    (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(kalender.ScheduleBody)),
      );
      await gesture.moveBy(const Offset(0, -240));
      await tester.pump(const Duration(milliseconds: 16));
      await export(tester, 'large-delta-first-frame');
      expect(pinned(), findsOneWidget);
      expect(tester.widget<DCalendarScheduleDay>(pinned()).label, 'Wed 2');
      await gesture.up();
    },
  );

  testWidgets('reverse scroll restores the source date in the first frame', (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(kalender.ScheduleBody)),
    );
    await gesture.moveBy(const Offset(0, -240));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.widget<DCalendarScheduleDay>(pinned()).label, 'Wed 2');
    await gesture.moveBy(const Offset(0, 240));
    await tester.pump(const Duration(milliseconds: 16));
    expect(pinned(), findsNothing);
    expect(find.bySemanticsLabel('Tue 1'), findsOneWidget);
    await export(tester, 'reverse-first-frame');
    await gesture.up();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Today calls point toward the offscreen day and land clear of controls',
    (tester) async {
      await pump(tester);
      await tester.tap(call('after'));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(find.text('Day 8 event 0').hitTestable(), findsOneWidget);
      expect(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is DButton &&
                  widget.density == DButtonDensity.floatingCall,
            )
            .hitTestable(),
        findsNothing,
      );
      expect(
        tester
            .getTopLeft(
              find.byWidgetPredicate(
                (widget) =>
                    widget is DCalendarScheduleDay &&
                    widget.label == 'Tue 8' &&
                    !widget.pinned,
              ),
            )
            .dy,
        greaterThanOrEqualTo(
          tester.getTopLeft(find.byType(kalender.ScheduleBody)).dy,
        ),
      );
      await tester.dragUntilVisible(
        find.text('Day 12 event 0'),
        find.byType(kalender.ScheduleBody),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(call('before'), findsOneWidget);
      expect(
        tester.getCenter(call('before')).dy,
        lessThan(tester.getTopLeft(find.byType(kalender.ScheduleBody)).dy + 60),
      );
      await export(tester, 'today-above');
      await tester.tap(call('before'));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(find.text('Day 8 event 0').hitTestable(), findsOneWidget);
      expect(call('before'), findsNothing);
      await tester.tap(find.text('Day 8 event 0'));
      expect(opened, [80]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty Today survives filtering and loading with narrow scaled RTL safe areas',
    (tester) async {
      entries = [];
      await pump(
        tester,
        width: 320,
        scale: 2,
        reducedMotion: true,
        direction: TextDirection.rtl,
        padding: const EdgeInsets.only(top: 24, bottom: 34),
      );
      expect(find.text('Nothing planned'), findsOneWidget);
      expect(find.bySemanticsLabel('Tue 8\nToday'), findsOneWidget);
      expect(call('before'), findsNothing);
      expect(call('after'), findsNothing);
      await export(tester, 'empty-scaled-rtl');
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(find.text('Nothing planned'), findsNothing);
      expect(call('before'), findsOneWidget);
      await tester.tap(call('before'));
      await tester.pump();
      await frames(tester);
      expect(find.text('Nothing planned').hitTestable(), findsOneWidget);
      await tester.tap(find.byType(DSelect<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My events'));
      await tester.pumpAndSettle();
      expect(mine, isTrue);
      expect(find.text('Nothing planned'), findsOneWidget);
      update(() => loading = true);
      await tester.pump();
      expect(find.text('Nothing planned'), findsNothing);
      update(() => loading = false);
      await tester.pumpAndSettle();
      expect(find.text('Nothing planned'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scaled RTL scrolling keeps event titles clear of the pinned date',
    (tester) async {
      await pump(tester, width: 320, scale: 2, direction: TextDirection.rtl);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(kalender.ScheduleBody)),
      );
      for (var step = 0; step < 180; step++) {
        await gesture.moveBy(const Offset(0, -8));
        await tester.pump(const Duration(milliseconds: 16));
        if (pinned().evaluate().isEmpty) continue;
        final label = tester.widget<DCalendarScheduleDay>(pinned()).label;
        final dateInk = tester.getRect(
          find.descendant(of: pinned(), matching: find.text(label)),
        );
        final titles = find
            .byWidgetPredicate(
              (widget) =>
                  widget is Text && widget.data?.startsWith('Day ') == true,
            )
            .hitTestable();
        for (final title in titles.evaluate()) {
          expect(
            dateInk.overlaps(visibleInk(tester, find.byWidget(title.widget))),
            isFalse,
            reason: 'title clear of pinned date at scroll step $step',
          );
        }
      }
      await export(tester, 'scaled-rtl-scrolling');
      await gesture.up();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clipped date ink rejects event taps while preserving scroll drags',
    (tester) async {
      await pump(tester);
      final body = find.byType(kalender.ScheduleBody);
      await tester.drag(body, const Offset(0, -80));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      final point = tester.getTopLeft(body) + const Offset(40, 24);
      await tester.tapAt(point);
      expect(opened, isEmpty);
      final before = tester.getTopLeft(find.text('Day 2 event 0')).dy;
      final gesture = await tester.startGesture(point);
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getTopLeft(find.text('Day 2 event 0')).dy,
        lessThan(before - 40),
      );
      await gesture.up();
      expect(opened, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard navigation skips hidden Today calls', (tester) async {
    await pump(tester);
    final before = tester
        .widget<DButton>(find.byKey(const ValueKey('schedule-today-before')))
        .focusNode!;
    final after = tester
        .widget<DButton>(find.byKey(const ValueKey('schedule-today-after')))
        .focusNode!;
    before.requestFocus();
    await tester.pump();
    expect(before.hasFocus, isFalse);
    after.requestFocus();
    await tester.pump();
    expect(after.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(find.text('Day 8 event 0').hitTestable(), findsOneWidget);
    expect(after.hasFocus, isFalse);
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(before.hasFocus || after.hasFocus, isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Paris midnight rows retain their local date while navigating Today',
    (tester) async {
      entries = [
        ...entries.where((entry) => entry.firstDay.day != 8),
        for (var id = 100; id < 109; id++)
          EventCalendarEntry.decode(
            PostEvent.decode({
              'id': id,
              'name': 'Paris night $id',
              'starts_at': '2026-09-08T00:30:00+02:00',
              'ends_at': '2026-09-08T01:30:00+02:00',
            })!,
            zones: ports.zones,
            timezone: 'Europe/Paris',
            settings: const EventSettings(),
          )!,
      ];
      await pump(tester);
      expect(call('after'), findsOneWidget);
      await tester.tap(call('after'));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(find.text('Paris night 100').hitTestable(), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(kalender.ScheduleBody)),
      );
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump(const Duration(milliseconds: 16));
      expect(pinned(), findsOneWidget);
      expect(tester.widget<DCalendarScheduleDay>(pinned()).label, 'Tue 8');
      expect(call('before'), findsNothing);
      await gesture.up();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'filter replacement clears pinned geometry without another scroll',
    (tester) async {
      await pump(tester);
      await tester.dragUntilVisible(
        find.text('Day 12 event 0'),
        find.byType(kalender.ScheduleBody),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(call('before'), findsOneWidget);
      update(() => loading = true);
      await tester.pump();
      expect(call('before'), findsNothing);
      update(() {
        entries = [];
        mine = true;
        loading = false;
      });
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(find.text('Nothing planned').hitTestable(), findsOneWidget);
      expect(call('before'), findsNothing);
      expect(call('after'), findsNothing);
      expect(find.bySemanticsLabel('Sat 12'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('floating Today clears the actual mobile footer', (tester) async {
    await pump(tester, dock: true, padding: const EdgeInsets.only(bottom: 34));
    final footer = tester.getRect(find.byKey(const ValueKey('schedule-dock')));
    expect(
      tester.getRect(call('after')).bottom,
      lessThanOrEqualTo(footer.top - 12),
    );
    await export(tester, 'dock-offscreen');
    await tester.tap(call('after'));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(find.text('Day 8 event 0').hitTestable(), findsOneWidget);
    expect(call('after'), findsNothing);
    await export(tester, 'dock-today');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion returns Today immediately during an existing schedule',
    (tester) async {
      await pump(tester, reducedMotion: true);
      expect(call('after'), findsOneWidget);
      await tester.tap(call('after'));
      await tester.pump();
      await frames(tester);
      expect(find.text('Day 8 event 0').hitTestable(), findsOneWidget);
      expect(call('after'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
