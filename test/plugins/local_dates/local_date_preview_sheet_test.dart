import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_preview_sheet.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_widget.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _spec = LocalDateSpec(
  date: '2026-09-14',
  time: '00:00:00',
  timezone: 'America/New_York',
  timezones: ['America/Los_Angeles', 'UTC'],
  fallbackText: 'September 14',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = LocalDateEnvironment.instance;
  final formatter = LocalDateFormatter(environment: environment);

  setUpAll(() async {
    final font = FontLoader('Lato')
      ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf'));
    await font.load();
  });

  setUp(() {
    environment.ensureDatabase();
    environment.setDeviceTimezone('Europe/Paris');
  });
  tearDown(() => environment.setDeviceTimezone('Etc/UTC'));

  Future<GlobalKey> open(
    WidgetTester tester, {
    LocalDateSpec spec = _spec,
    LocalDateSpec? end,
    double width = 390,
    double scale = 17 / 14,
    bool dark = true,
    bool hour24 = false,
    bool rtl = false,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [locale],
          theme: AppTheme.forBrightness(
            dark ? Brightness.dark : Brightness.light,
            fontFamily: 'Lato',
          ).copyWith(platform: TargetPlatform.iOS),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              alwaysUse24HourFormat: hour24,
              textScaler: TextScaler.linear(scale),
            ),
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: child!,
            ),
          ),
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: LocalDateInline(
                  spec: spec,
                  to: end,
                  formatter: formatter,
                  now: () => DateTime.utc(2026, 9, 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(LocalDateInline));
    await tester.pumpAndSettle();
    expect(find.byType(LocalDatePreviewSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    return capture;
  }

  Finder sheetText(String text) => find.descendant(
    of: find.byType(LocalDatePreviewSheet),
    matching: find.text(text, findRichText: true),
  );

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final path = Platform.environment['LOCAL_DATE_PREVIEW_RENDER_DIR'];
    if (path == null) return;
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(path).create(recursive: true);
        await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  for (final dark in [true, false]) {
    testWidgets(
      'local-first preview fits 320px in ${dark ? 'dark' : 'light'}',
      (tester) async {
        final key = await open(tester, width: 320, dark: dark);
        final hero = find.byKey(const ValueKey('local-date-your-time'));
        expect(
          find.descendant(of: hero, matching: find.text('Paris')),
          findsOneWidget,
        );
        expect(sheetText('6:00 AM'), findsOneWidget);
        expect(sheetText('12:00 AM'), findsOneWidget);
        expect(sheetText('9:00 PM'), findsOneWidget);
        expect(sheetText('4:00 AM'), findsOneWidget);
        expect(sheetText('Source · EDT'), findsOneWidget);
        expect(sheetText('Previous day'), findsOneWidget);
        expect(sheetText('Sun, Sep 13'), findsOneWidget);
        expect(find.textContaining('Your time'), findsNothing);
        expect(find.text('The same moment elsewhere'), findsNothing);
        expect(
          tester.getRect(hero).bottom,
          lessThan(tester.getRect(sheetText('New York')).top),
        );
        await capture(tester, key, dark ? 'dark-320' : 'light-320');

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(LocalDatePreviewSheet), findsNothing);
        await tester.tap(find.byType(LocalDateInline));
        await tester.pumpAndSettle();
        expect(find.byType(LocalDatePreviewSheet), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(LocalDatePreviewSheet), findsNothing);
      },
    );
  }

  testWidgets('24-hour device setting formats midnight and evening correctly', (
    tester,
  ) async {
    final key = await open(tester, hour24: true);
    expect(sheetText('06:00'), findsOneWidget);
    expect(sheetText('00:00'), findsOneWidget);
    expect(sheetText('21:00'), findsOneWidget);
    expect(sheetText('04:00'), findsOneWidget);
    await capture(tester, key, 'dark-390-24h');
    await tester.drag(find.byType(DDrawerSwipeHandle), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.byType(LocalDatePreviewSheet), findsNothing);
  });

  testWidgets(
    'pulling the date preview content past its edge dismisses the sheet',
    (tester) async {
      await open(tester, width: 320, scale: 2);
      final drawer = find.byType(DDrawerContent);
      final bounds = tester.getRect(drawer);
      final area = find.byType(DDrawerScrollArea);
      final scrollable = find.descendant(
        of: area,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(60);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getTopLeft(area) + const Offset(100, 30),
      );
      final distance = bounds.height * .6 + 90;
      for (var step = 0; step < 30; step++) {
        await gesture.moveBy(Offset(0, distance / 30));
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(tester.getTopLeft(drawer).dy, greaterThan(bounds.top));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(LocalDatePreviewSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large RTL text remains scrollable with an accessible close action',
    (tester) async {
      final key = await open(tester, width: 320, scale: 2, rtl: true);
      await tester.ensureVisible(sheetText('UTC'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(sheetText('UTC').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
      await capture(tester, key, 'dark-rtl-large');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(LocalDatePreviewSheet), findsNothing);
    },
  );

  testWidgets('same-day ranges show both times in each time zone', (
    tester,
  ) async {
    await open(
      tester,
      end: const LocalDateSpec(
        date: '2026-09-14',
        time: '01:30:00',
        timezone: 'America/New_York',
        fallbackText: '',
      ),
      hour24: true,
    );
    expect(sheetText('06:00'), findsOneWidget);
    expect(sheetText('07:30'), findsOneWidget);
    expect(sheetText('00:00'), findsOneWidget);
    expect(sheetText('01:30'), findsOneWidget);
    expect(sheetText('22:30'), findsOneWidget);
    expect(sheetText('→'), findsNWidgets(4));
  });

  testWidgets('cross-day ranges retain their ending date', (tester) async {
    await open(
      tester,
      end: const LocalDateSpec(
        date: '2026-09-15',
        time: '01:30:00',
        timezone: 'America/New_York',
        fallbackText: '',
      ),
    );
    expect(sheetText('Tuesday, September 15, 2026'), findsOneWidget);
    expect(sheetText('Tue, Sep 15'), findsNWidgets(2));
    expect(sheetText('Mon, Sep 14'), findsNWidgets(3));
    expect(sheetText('End'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('date-only entries do not invent a midnight time', (
    tester,
  ) async {
    await open(
      tester,
      spec: const LocalDateSpec(
        date: '2026-09-14',
        timezone: 'Europe/Paris',
        fallbackText: '',
      ),
    );
    expect(sheetText('Monday, September 14, 2026'), findsOneWidget);
    expect(sheetText('Source'), findsOneWidget);
    expect(sheetText('Paris'), findsOneWidget);
    expect(find.textContaining('AM', findRichText: true), findsNothing);
  });

  testWidgets('day changes use calendar dates across DST and year boundaries', (
    tester,
  ) async {
    await open(
      tester,
      spec: const LocalDateSpec(
        date: '2026-12-31',
        time: '23:30:00',
        timezone: 'Europe/Paris',
        timezones: ['Asia/Tokyo'],
        fallbackText: '',
      ),
    );
    expect(sheetText('Next day'), findsOneWidget);
    expect(sheetText('Fri, Jan 1, 2027'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await open(
      tester,
      spec: const LocalDateSpec(
        date: '2026-03-29',
        time: '00:30:00',
        timezone: 'Europe/Paris',
        timezones: ['America/Los_Angeles'],
        fallbackText: '',
      ),
    );
    expect(sheetText('Previous day'), findsOneWidget);
    expect(sheetText('Sat, Mar 28'), findsOneWidget);
  });
}
