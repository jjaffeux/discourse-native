import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/src/plugins/local_dates/local_date.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_widget.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relative_time/relative_time.dart';

import '../../support/bundled_plugins.dart';

void main() {
  setUpAll(() {
    LocalDateEnvironment.instance.ensureDatabase();
  });

  setUp(() {
    LocalDateEnvironment.instance.setDeviceTimezone('Etc/UTC');
  });

  Future<void> pump(WidgetTester tester, String html) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates:
            RelativeTimeLocalizations.localizationsDelegates,
        supportedLocales: RelativeTimeLocalizations.supportedLocales,
        home: Scaffold(
          body: CookedHtml(html: html, registry: pluginRegistry),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'renders a cooked date without requiring a Post or site setting',
    (tester) async {
      await pump(
        tester,
        '<p>Starts <span class="discourse-local-date" '
        'data-date="2026-08-09" data-time="13:05:00" '
        'data-timezone="UTC" data-format="YYYY-MM-DD HH:mm" '
        'data-calendar="off">server value</span></p>',
      );

      expect(find.byType(LocalDateInline), findsOneWidget);
      expect(find.textContaining('2026-08-09 13:05'), findsOneWidget);
      expect(find.text('server value'), findsNothing);
    },
  );

  testWidgets('a date-only line stays compact and has no hover fill', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(
      tester,
      '<p><span class="discourse-local-date" data-date="2026-09-18" '
      'data-timezone="Australia/Brisbane">server value</span></p>',
    );

    final date = find.byType(LocalDateInline);
    final ink = find.descendant(of: date, matching: find.byType(InkWell));
    expect(date, findsOneWidget);
    expect(ink, findsOneWidget);
    expect(
      tester.getSize(ink).width,
      lessThan(tester.getSize(find.byType(CookedHtml)).width),
    );
    expect(tester.widget<InkWell>(ink).mouseCursor, SystemMouseCursors.click);
    expect(tester.widget<InkWell>(ink).hoverColor, Colors.transparent);
  });

  testWidgets('retains server-cooked text for invalid dates and zones', (
    tester,
  ) async {
    await pump(
      tester,
      '<p><span class="discourse-local-date" data-date="2024-03-10" '
      'data-time="02:30:00" data-timezone="America/New_York">'
      'server fallback</span> '
      '<span class="discourse-local-date" data-date="2026-08-09" '
      'data-timezone="Mars/Olympus">unknown zone</span></p>',
    );

    expect(find.text('server fallback'), findsOneWidget);
    expect(find.text('unknown zone'), findsOneWidget);
  });

  testWidgets('compacts a same-device-day range to the ending time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(
      tester,
      '<p><span class="discourse-local-date" data-range="from" '
      'data-date="2026-08-09" data-time="09:00:00" data-timezone="UTC" '
      'data-calendar="off">start</span> → '
      '<span class="discourse-local-date" data-range="to" '
      'data-date="2026-08-09" data-time="10:30:00" data-timezone="UTC" '
      'data-calendar="off">end</span></p>',
    );

    expect(find.byType(LocalDateInline), findsNWidgets(2));
    expect(find.textContaining('10:30'), findsOneWidget);
    expect(find.textContaining('(UTC)'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(LocalDateInline).first).dy,
      closeTo(tester.getTopLeft(find.byType(LocalDateInline).last).dy, 1),
      reason: 'range dates should remain on the same line when they fit',
    );
  });

  testWidgets('activation opens device, source, and extra zone previews', (
    tester,
  ) async {
    LocalDateEnvironment.instance.setDeviceTimezone('Europe/Paris');
    await pump(
      tester,
      '<p><span class="discourse-local-date" data-date="2026-08-09" '
      'data-time="13:05:00" data-timezone="America/New_York" '
      'data-timezones="Asia/Tokyo|Europe/Paris" data-calendar="off">'
      'server value</span></p>',
    );

    await tester.tap(find.bySemanticsLabel(RegExp('New York:')));
    await tester.pumpAndSettle();

    expect(find.text('Paris'), findsOneWidget);
    expect(find.text('New York'), findsOneWidget);
    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.textContaining('Device'), findsOneWidget);
    expect(find.textContaining('Source'), findsOneWidget);
  });

  testWidgets('is a named button that activates with Enter and Space', (
    tester,
  ) async {
    const html =
        '<p><span class="discourse-local-date" data-date="2026-08-09" '
        'data-time="13:05:00" data-timezone="America/New_York" '
        'data-timezones="Asia/Tokyo" data-calendar="off">server</span></p>';
    final semantics = tester.ensureSemantics();
    try {
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        await pump(tester, html);

        final target = find.bySemanticsLabel(RegExp('New York:'));
        final data = tester.getSemantics(target).getSemanticsData();
        expect(data.label, contains('New York:'));
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(target, findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, isNotNull);
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();

        expect(find.textContaining('Device'), findsOneWidget, reason: '$key');
        await tester.tapAt(const Offset(1, 1));
        await tester.pumpAndSettle();
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('nested cooked content uses the same date renderer', (
    tester,
  ) async {
    await pump(
      tester,
      '<blockquote><p><span class="discourse-local-date" '
      'data-date="2026-08-09" data-timezone="UTC" '
      'data-format="YYYY">server</span></p></blockquote>',
    );

    expect(find.byType(LocalDateInline), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
  });

  group('countdown refresh', () {
    const spec = LocalDateSpec(
      date: '2026-01-11',
      time: '12:00:00',
      timezone: 'UTC',
      countdown: true,
      fallbackText: 'server countdown',
    );

    testWidgets('an already elapsed countdown stays idle', (tester) async {
      final countdown = _CountdownHarness(tester, DateTime.utc(2026, 1, 12));
      await countdown.run(() async {
        await countdown.show(spec);

        expect(find.textContaining('now'), findsOneWidget);
        await countdown.expectIdle();
      });
    });

    testWidgets('stops at the exact deadline after its final tick', (
      tester,
    ) async {
      final countdown = _CountdownHarness(
        tester,
        DateTime.utc(2026, 1, 11, 11, 59, 59, 750),
      );
      await countdown.run(() async {
        await countdown.show(spec);
        expect(find.textContaining('a few seconds'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 249));
        expect(find.textContaining('a few seconds'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));

        expect(find.textContaining('now'), findsOneWidget);
        await countdown.expectIdle();
      });
    });

    testWidgets('a future countdown keeps ticking and cancels on disposal', (
      tester,
    ) async {
      final countdown = _CountdownHarness(
        tester,
        DateTime.utc(2026, 1, 11, 11, 59, 15),
      );
      await countdown.run(() async {
        await countdown.show(spec);
        expect(find.textContaining('a minute'), findsOneWidget);
        expect(countdown.activeTimers, hasLength(1));

        await tester.pump(const Duration(seconds: 1));
        expect(find.textContaining('a few seconds'), findsOneWidget);
        expect(countdown.activeTimers, hasLength(1));

        await tester.pumpWidget(const SizedBox.shrink());
        await countdown.expectIdle();
      });
    });

    testWidgets('an elapsed replacement cancels a future countdown', (
      tester,
    ) async {
      final countdown = _CountdownHarness(
        tester,
        DateTime.utc(2026, 1, 11, 11, 59, 15),
      );
      await countdown.run(() async {
        await countdown.show(spec);
        expect(countdown.activeTimers, hasLength(1));

        await countdown.show(
          const LocalDateSpec(
            date: '2026-01-10',
            countdown: true,
            fallbackText: '',
          ),
        );
        expect(find.textContaining('now'), findsOneWidget);
        await countdown.expectIdle();
      });
    });

    testWidgets('a recurring countdown advances after its exact deadline', (
      tester,
    ) async {
      final countdown = _CountdownHarness(
        tester,
        DateTime.utc(2026, 1, 11, 11, 59, 59, 750),
      );
      await countdown.run(() async {
        await countdown.show(
          const LocalDateSpec(
            date: '2026-01-11',
            time: '12:00:00',
            timezone: 'UTC',
            countdown: true,
            recurring: '1.minutes',
            fallbackText: '',
          ),
        );
        expect(find.textContaining('a few seconds'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 250));
        expect(find.textContaining('now'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        expect(find.textContaining('a minute'), findsOneWidget);

        await tester.pump(const Duration(seconds: 16));
        expect(find.textContaining('a few seconds'), findsOneWidget);
        expect(countdown.activeTimers, hasLength(1));
      });
    });

    for (final recurring in ['invalid', '0.seconds', '900000000000.days']) {
      testWidgets('an unadvanceable recurrence stays idle: $recurring', (
        tester,
      ) async {
        final countdown = _CountdownHarness(
          tester,
          DateTime.utc(2026, 1, 11, 11, 59, 59, 750),
        );
        await countdown.run(() async {
          await countdown.show(
            LocalDateSpec(
              date: spec.date,
              time: spec.time,
              timezone: spec.timezone,
              countdown: true,
              recurring: recurring,
              fallbackText: '',
            ),
          );

          await tester.pump(const Duration(milliseconds: 250));
          expect(find.textContaining('now'), findsOneWidget);
          await countdown.expectIdle();
        });
      });
    }

    for (final invalid in [
      const LocalDateSpec(
        date: 'invalid',
        countdown: true,
        fallbackText: 'invalid date',
      ),
      const LocalDateSpec(
        date: '2026-01-11',
        timezone: 'Mars/Olympus',
        countdown: true,
        fallbackText: 'invalid timezone',
      ),
    ]) {
      testWidgets(
        'cancels for ${invalid.fallbackText} and resumes a replacement',
        (tester) async {
          final countdown = _CountdownHarness(
            tester,
            DateTime.utc(2026, 1, 11, 11, 59, 15),
          );
          await countdown.run(() async {
            await countdown.show(spec);
            final state = tester.state(find.byType(LocalDateInline));
            expect(countdown.activeTimers, hasLength(1));

            await countdown.show(invalid);
            expect(tester.state(find.byType(LocalDateInline)), same(state));
            expect(find.text(invalid.fallbackText), findsOneWidget);
            await countdown.expectIdle();

            await countdown.show(
              const LocalDateSpec(
                date: '2026-01-12',
                time: '12:00:00',
                timezone: 'UTC',
                countdown: true,
                fallbackText: '',
              ),
            );
            expect(tester.state(find.byType(LocalDateInline)), same(state));
            expect(countdown.activeTimers, hasLength(1));
            expect(find.textContaining('a day'), findsOneWidget);

            await tester.pump(const Duration(days: 1));
            expect(find.textContaining('now'), findsOneWidget);
            await countdown.expectIdle();
          });
        },
      );
    }

    testWidgets(
      'an elapsed countdown responds to locale, zone and spec changes',
      (tester) async {
        final countdown = _CountdownHarness(tester, DateTime.utc(2026, 1, 12));
        await countdown.run(() async {
          await countdown.show(spec);
          final state = tester.state(find.byType(LocalDateInline));
          await countdown.expectIdle();

          await countdown.show(spec, locale: const Locale('fr'));
          expect(find.textContaining('maintenant'), findsOneWidget);
          await countdown.expectIdle();

          LocalDateEnvironment.instance.setDeviceTimezone('Europe/Paris');
          await tester.pump();
          expect(find.bySemanticsLabel(RegExp('Paris:')), findsOneWidget);
          await countdown.expectIdle();

          await countdown.show(
            const LocalDateSpec(
              date: '2026-01-13',
              time: '00:00:00',
              timezone: 'UTC',
              countdown: true,
              fallbackText: '',
            ),
          );
          expect(tester.state(find.byType(LocalDateInline)), same(state));
          expect(find.textContaining('a day'), findsOneWidget);
          expect(countdown.activeTimers, hasLength(1));
        });
      },
    );
  });
}

class _CountdownHarness {
  _CountdownHarness(this.tester, this.start)
    : clockStart = tester.binding.clock.now();

  final WidgetTester tester;
  final DateTime start;
  final DateTime clockStart;
  final List<Timer> _timers = [];
  int _clockReads = 0;

  Iterable<Timer> get activeTimers => _timers.where((timer) => timer.isActive);

  DateTime now() {
    _clockReads++;
    return start.add(tester.binding.clock.now().difference(clockStart));
  }

  Future<void> run(Future<void> Function() body) => runZoned(
    () async {
      try {
        await body();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createTimer(zone, duration, callback);
        _timers.add(timer);
        return timer;
      },
    ),
  );

  Future<void> show(LocalDateSpec spec, {Locale locale = const Locale('en')}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          themeAnimationDuration: Duration.zero,
          locale: locale,
          localizationsDelegates:
              RelativeTimeLocalizations.localizationsDelegates,
          supportedLocales: RelativeTimeLocalizations.supportedLocales,
          home: Scaffold(
            body: LocalDateInline(
              spec: spec,
              formatter: LocalDateFormatter(
                environment: LocalDateEnvironment.instance,
              ),
              now: now,
            ),
          ),
        ),
      );

  Future<void> expectIdle() async {
    // Bounded pumps expose immediate and delayed refreshes without letting a
    // zero-delay timer/rebuild loop hang pumpAndSettle or fakeAsync.
    final reads = _clockReads;
    expect(activeTimers, isEmpty);
    for (final duration in [
      Duration.zero,
      const Duration(milliseconds: 1),
      const Duration(seconds: 1),
      const Duration(minutes: 1),
    ]) {
      await tester.pump(duration);
      expect(activeTimers, isEmpty);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(_clockReads, reads, reason: 'idle values must not rebuild');
    }
  }
}
