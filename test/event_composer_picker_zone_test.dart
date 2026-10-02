import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer_parser.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_time.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

const _date = ValueKey('event-picker-date');
const _time = ValueKey('event-picker-time');
const _apply = ValueKey('event-picker-apply');
const _paris = '2026-10-02T09:00+02:00';
const _platforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.iOS,
});

void main() {
  for (final (source, hour, minute, second) in [
    (_paris, 9, 0, 0),
    ('2026-10-02T07:00:42.123456Z', 9, 0, 42),
    ('2026-10-02 09:00', 9, 0, 0),
    ('2026-10-01T23:30Z', 1, 30, 0),
    ('2026-10-25T02:30:41.123456+02:00', 2, 30, 41),
    ('2026-10-25T02:30:41.123456+01:00', 2, 30, 41),
  ]) {
    testWidgets('unchanged Native picker preserves $source exactly', (
      tester,
    ) async {
      final ports = await _open(tester, source);
      final local = eventDate(
        source,
        zones: ports.zones,
        timezone: 'Europe/Paris',
        showLocalTime: true,
      )!;
      final original = local.toUtc();
      await _choose(tester);
      expect(
        tester.widget<DDatePicker>(find.byKey(_date)).value,
        DCalendarDate.fromDateTime(local),
      );
      expect(
        tester.widget<DTimeInput>(find.byKey(_time)).initialValue,
        DTimeValue(hour: hour, minute: minute, second: second),
      );
      await _accept(tester);
      expect(_value(tester), source);
      expect(
        eventDate(
          _value(tester),
          zones: ports.zones,
          timezone: 'Europe/Paris',
        )!.toUtc(),
        original,
      );
      expect(tester.takeException(), isNull);
    }, variant: _platforms);
  }

  for (final (label, attribute) in [
    ('Ends (optional)', 'end'),
    ('Repeat until (optional)', 'recurrence-until'),
  ]) {
    testWidgets('Native $attribute picker uses the event timezone', (
      tester,
    ) async {
      await _open(
        tester,
        _paris,
        extra: '$attribute="$_paris" recurrence="every_week"',
      );
      await _choose(tester, label: label);
      expect(
        tester.widget<DTimeInput>(find.byKey(_time)).initialValue,
        const DTimeValue(hour: 9, minute: 0),
      );
      await _accept(tester);
      expect(_value(tester, label: label), _paris);
    }, variant: _platforms);
  }

  for (final (source, zone) in [
    ('2026-10-02T00:30+14:00', 'Pacific/Kiritimati'),
    ('2026-10-02T23:30-10:00', 'Pacific/Honolulu'),
  ]) {
    testWidgets('all-day $zone carrier retains its written calendar day', (
      tester,
    ) async {
      await _open(tester, source, zone: zone, extra: 'all-day="true"');
      await _choose(tester);
      expect(
        tester.widget<DDatePicker>(find.byKey(_date)).value,
        DCalendarDate(2026, 10, 2),
      );
      expect(find.byType(DTimeInput), findsNothing);
      await _accept(tester);
      expect(_value(tester), '2026-10-02');
    }, variant: _platforms);
  }

  testWidgets('a date-only recurrence limit retains its chosen day', (
    tester,
  ) async {
    await _open(
      tester,
      _paris,
      extra: 'recurrence="every_week" recurrence-until="2028-12-31"',
    );
    await _choose(tester, label: 'Repeat until (optional)');
    expect(
      tester.widget<DDatePicker>(find.byKey(_date)).value,
      DCalendarDate(2028, 12, 31),
    );
    await _accept(tester);
    expect(
      _value(tester, label: 'Repeat until (optional)'),
      '2028-12-31 00:00',
    );
  });

  testWidgets('changed Native day and time remain a Paris wall time', (
    tester,
  ) async {
    final ports = await _open(tester, _paris);
    await _choose(tester);
    await _openCalendar(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Saturday, October 3, 2026'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_time), '11:45:12');
    await tester.pump();
    await _accept(tester);
    expect(_value(tester), '2026-10-03 11:45:12');
    expect(
      eventDate(
        _value(tester),
        zones: ports.zones,
        timezone: 'Europe/Paris',
      )!.toUtc(),
      DateTime.utc(2026, 10, 3, 9, 45, 12),
    );
  }, variant: _platforms);

  testWidgets('invalid or empty time disables Native Apply', (tester) async {
    await _open(tester, _paris);
    await _choose(tester);
    for (final text in ['25:00:00', '09:61', '09:00:99', '']) {
      await tester.enterText(find.byKey(_time), text);
      await tester.pump();
      expect(tester.widget<DButton>(find.byKey(_apply)).onPressed, isNull);
      expect(_value(tester), _paris);
    }
    await tester.enterText(find.byKey(_time), '10:15');
    await tester.pump();
    expect(tester.widget<DButton>(find.byKey(_apply)).onPressed, isNotNull);
    await _accept(tester);
    expect(_value(tester), '2026-10-02 10:15');
  }, variant: _platforms);

  testWidgets('cancelling the Native picker leaves the source unchanged', (
    tester,
  ) async {
    await _open(tester, _paris);
    await _choose(tester);
    await tester.enterText(find.byKey(_time), '11:00');
    await tester.tap(
      find.descendant(
        of: find.byType(DDialogContent),
        matching: find.widgetWithText(DButton, 'Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_apply), findsNothing);
    expect(_value(tester), _paris);
  }, variant: _platforms);

  testWidgets('an expired composer cannot accept the picker result', (
    tester,
  ) async {
    var current = true;
    await _open(tester, _paris, isCurrent: () => current);
    await _choose(tester);
    await tester.enterText(find.byKey(_time), '11:00');
    current = false;
    await _accept(tester);
    expect(_value(tester), _paris);
  }, variant: _platforms);

  testWidgets('an empty picker starts from the declared timezone clock', (
    tester,
  ) async {
    final ports = await _open(tester, '', zone: 'Pacific/Kiritimati');
    final before = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    await _choose(tester);
    final after = DateTime.now().toUtc();
    final day = tester.widget<DDatePicker>(find.byKey(_date)).value!;
    final time = tester.widget<DTimeInput>(find.byKey(_time)).initialValue!;
    final instant = day
        .atTime(
          ports.zones.location('Pacific/Kiritimati')!,
          hour: time.hour,
          minute: time.minute,
          second: time.second,
        )
        .toUtc();
    expect(instant.isBefore(before), isFalse);
    expect(instant.isAfter(after), isFalse);
  });

  testWidgets('Native picker fits 320px, enlarged text and RTL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _open(tester, _paris, direction: TextDirection.rtl);
    await _choose(tester);
    for (final key in [_date, _time, _apply]) {
      final bounds = tester.getRect(find.byKey(key));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
    }
    expect(find.byKey(_apply).hitTestable(), findsOneWidget);
    await _openCalendar(tester);
    expect(find.byType(DCalendar), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a standalone picker also preserves written offset fields', (
    tester,
  ) async {
    await _open(tester, _paris, withController: false);
    await _choose(tester);
    expect(
      tester.widget<DTimeInput>(find.byKey(_time)).initialValue,
      const DTimeValue(hour: 9, minute: 0),
    );
    await _accept(tester);
    expect(_value(tester), _paris);
  });
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is DInput && widget.labelText == label,
);

String _value(WidgetTester tester, {String label = 'Starts'}) =>
    tester.widget<DInput>(_field(label)).controller!.text;

Future<void> _choose(WidgetTester tester, {String label = 'Starts'}) async {
  final field = _field(label);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: field, matching: find.byType(DButton)));
  await tester.pumpAndSettle();
  expect(find.byType(DDialogContent), findsOneWidget);
  expect(find.byType(CalendarDatePicker), findsNothing);
  expect(find.byType(TimePickerDialog), findsNothing);
}

Future<void> _accept(WidgetTester tester) async {
  await tester.tap(find.byKey(_apply));
  await tester.pumpAndSettle();
  expect(find.byKey(_apply), findsNothing);
}

Future<void> _openCalendar(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: find.byKey(_date), matching: find.byType(DButton)),
  );
  await tester.pumpAndSettle();
}

Future<EventTestPorts> _open(
  WidgetTester tester,
  String start, {
  String zone = 'Europe/Paris',
  String extra = '',
  TextDirection direction = TextDirection.ltr,
  bool withController = true,
  bool Function()? isCurrent,
}) async {
  final ports = EventTestPorts();
  ports.environment.setDeviceTimezone('America/Los_Angeles');
  addTearDown(ports.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: defaultTargetPlatform),
      builder: (context, child) =>
          Directionality(textDirection: direction, child: child!),
      home: Scaffold(
        body: EventComposerSheet(
          block: start.isEmpty
              ? null
              : parseEventBlocks(
                  '[event start="$start" timezone="$zone" $extra]x[/event]',
                ).single,
          settings: const EventSettings(enabled: true),
          timezone: zone,
          controller: withController ? ports.controller : null,
          isCurrent: isCurrent ?? () => true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ports;
}
