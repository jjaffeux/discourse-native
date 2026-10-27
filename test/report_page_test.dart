import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/data/report_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/dashboard.dart';
import 'package:discourse_native/src/models/report.dart';
import 'package:discourse_native/src/shell/report_controller.dart';
import 'package:discourse_native/src/shell/report_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dashboard_test.dart' show FakeCredentials;
import 'report_test.dart' show report, range, reportPayload;

void main() {
  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });
  for (final size in [const Size(390, 844), const Size(1100, 900)]) {
    testWidgets('report charts, tables, dates and filters work at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _Api();
      final owner = ReportController(
        api: api,
        credentials: FakeCredentials(),
        lease: SiteLifecycle().capture('https://forum.example'),
        siteUrl: 'https://forum.example',
        report: report,
        range: range,
      );
      addTearDown(owner.dispose);
      await owner.refresh();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(
              textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Lato'),
            ),
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ReportPage(controller: owner, onBack: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(DCartesianChart<MapEntry<String, Map<String, num?>>>),
        findsOneWidget,
      );
      await _capture(tester, boundary, 'chart-${size.width.toInt()}');
      await tester.tap(find.text('Table'));
      await tester.pumpAndSettle();
      expect(find.text('2026-10-01'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      await _capture(tester, boundary, 'table-${size.width.toInt()}');
      await tester.tap(find.text('include subcategories'));
      await tester.pumpAndSettle();
      expect(api.filters, {'include_subcategories': true});
      final start = tester.widget<DDatePicker>(find.byType(DDatePicker).first);
      start.onChanged!(DCalendarDate(2026, 10, 2));
      await tester.pumpAndSettle();
      expect(api.range!.query, {
        'start_date': '2026-10-02',
        'end_date': '2026-10-03',
      });
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(api.requests, 4);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed report can retry and empty report is explicit', (
    tester,
  ) async {
    final api = _Api()..fail = true;
    final owner = ReportController(
      api: api,
      credentials: FakeCredentials(),
      lease: SiteLifecycle().capture('https://forum.example'),
      siteUrl: 'https://forum.example',
      report: report,
      range: range,
    );
    addTearDown(owner.dispose);
    await owner.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(
          textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Lato'),
        ),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ReportPage(controller: owner, onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load this report. Refresh to try again.'),
      findsOneWidget,
    );
    api.fail = false;
    api.empty = true;
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('No data for the selected period.'), findsOneWidget);
    expect(
      find.byType(DCartesianChart<MapEntry<String, Map<String, num?>>>),
      findsNothing,
    );
  });
}

class _Api implements ReportApi {
  int requests = 0;
  bool fail = false;
  bool empty = false;
  DashboardRange? range;
  Map<String, Object?> filters = {};
  @override
  Future<ReportDetails> load({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardReport report,
    required DashboardRange range,
    required Map<String, Object?> filters,
  }) async {
    requests++;
    this.range = range;
    this.filters = filters;
    if (fail) throw StateError('unavailable');
    return ReportDetails.fromJson({
      'data': {
        ...reportPayload,
        if (empty) 'data': <Object?>[],
        'available_filters': [
          {
            'id': 'include_subcategories',
            'type': 'bool',
            'default': filters['include_subcategories'] ?? false,
          },
        ],
      },
    });
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['REPORT_PREVIEW_DIR'];
  if (directory == null) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$directory/report-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
