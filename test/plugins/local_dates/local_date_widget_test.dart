import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_widget.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relative_time/relative_time.dart';

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
        home: Scaffold(body: CookedHtml(html: html)),
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
    expect(find.textContaining('(UTC)'), findsWidgets);
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

    await tester.tap(find.byType(LocalDateInline));
    await tester.pumpAndSettle();

    expect(find.textContaining('Paris'), findsWidgets);
    expect(find.textContaining('New York'), findsWidgets);
    expect(find.textContaining('Tokyo'), findsWidgets);
    expect(find.textContaining('Device'), findsOneWidget);
    expect(find.textContaining('Source'), findsOneWidget);
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
}
