import 'dart:convert';

import 'package:discourse_native/src/plugins/local_dates/local_date.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_widget.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relative_time/relative_time.dart';

void main() {
  for (final count in [1, 20]) {
    for (final countdown in [false, true]) {
      testWidgets('$count dates, countdown=$countdown, 60 ticks', (
        tester,
      ) async {
        final environment = LocalDateEnvironment.forTesting(
          detectDeviceTimezone: () async => 'Etc/UTC',
        );
        environment.setDeviceTimezone('Etc/UTC');
        final formatter = _CountingFormatter(environment: environment);
        final start = tester.binding.clock.now();
        DateTime now() => DateTime.utc(
          2026,
          1,
          11,
          11,
          55,
        ).add(tester.binding.clock.now().difference(start));
        final samples = <Map<String, Object>>[];
        for (var sample = 0; sample < 5; sample++) {
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(sample),
              theme: AppTheme.dark,
              localizationsDelegates:
                  RelativeTimeLocalizations.localizationsDelegates,
              supportedLocales: RelativeTimeLocalizations.supportedLocales,
              home: Scaffold(
                body: Column(
                  children: [
                    for (var index = 0; index < count; index++)
                      LocalDateInline(
                        spec: LocalDateSpec(
                          date: '2026-01-12',
                          time: '12:00:00',
                          timezone: 'UTC',
                          countdown: countdown,
                          timezones: const ['Asia/Tokyo', 'America/New_York'],
                          fallbackText: 'fallback',
                        ),
                        formatter: formatter,
                        now: now,
                      ),
                  ],
                ),
              ),
            ),
          );
          expect(find.byType(LocalDateInline), findsNWidgets(count));
          final before = formatter.previewCalls;
          final resolutions = formatter.resolutions;
          final rows = formatter.previewRows;
          final watch = Stopwatch()..start();
          for (var tick = 0; tick < 60; tick++) {
            await tester.pump(const Duration(seconds: 1));
          }
          watch.stop();
          expect(find.text('fallback'), findsNothing);
          expect(find.bySemanticsLabel(RegExp('Tokyo:')), findsNWidgets(count));
          expect(tester.takeException(), isNull);
          samples.add({
            'previewCalls': formatter.previewCalls - before,
            'resolutions': formatter.resolutions - resolutions,
            'formattedPreviewRows': formatter.previewRows - rows,
            'pumpMicroseconds': watch.elapsedMicroseconds,
          });
          await tester.pumpWidget(const SizedBox.shrink());
        }
        debugPrint(
          'COUNTDOWN_MEASUREMENT ${jsonEncode({'count': count, 'countdown': countdown, 'ticks': 60, 'samples': samples})}',
        );
        environment.dispose();
      });
    }
  }
}

class _CountingFormatter extends LocalDateFormatter {
  _CountingFormatter({required super.environment});
  int previewCalls = 0;
  int previewRows = 0;
  int resolutions = 0;

  @override
  LocalDateResolved? resolve(
    LocalDateSpec spec, {
    required Locale locale,
    String? accountTimezone,
    DateTime? now,
    bool sameLocalDayAsFrom = false,
  }) {
    resolutions++;
    return super.resolve(
      spec,
      locale: locale,
      accountTimezone: accountTimezone,
      now: now,
      sameLocalDayAsFrom: sameLocalDayAsFrom,
    );
  }

  @override
  List<LocalDatePreview> previews(
    LocalDateSpec spec, {
    required Locale locale,
    String? accountTimezone,
    Iterable<String> defaultTimezones = const [],
    DateTime? now,
  }) {
    previewCalls++;
    final result = super.previews(
      spec,
      locale: locale,
      accountTimezone: accountTimezone,
      defaultTimezones: defaultTimezones,
      now: now,
    );
    previewRows += result.length;
    return result;
  }
}
