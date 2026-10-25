import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/models/dashboard.dart';
import 'package:discourse_native/src/shell/dashboard_controller.dart';
import 'package:discourse_native/src/shell/dashboard_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dashboard_fixture.dart';

final snapshot = DashboardSnapshot.fromJson(dashboardFixture);
final reports = {
  for (final item in dashboardReportsFixture['items'] as List<dynamic>)
    (item as Map<String, dynamic>)['key'] as String:
        DashboardReportResult.fromJson(item),
};

Widget dashboard({
  DashboardState? state,
  bool staff = true,
  bool admin = true,
  ValueChanged<DashboardPeriod>? onPeriod,
  ValueChanged<List<DashboardConfiguration>>? onConfigure,
  VoidCallback? onRefresh,
  ValueChanged<String>? onOpen,
  ValueChanged<DashboardProblem>? onDismiss,
}) => MaterialApp(
  theme: AppTheme.light.copyWith(
    textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Lato'),
  ),
  debugShowCheckedModeBanner: false,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: DashboardPage(
      state: state ?? DashboardState(snapshot: snapshot, reports: reports),
      staff: staff,
      admin: admin,
      onRefresh: () async {
        onRefresh?.call();
      },
      onPeriodChanged: onPeriod ?? (_) {},
      onConfigure: onConfigure ?? (_) {},
      onRefreshProblems: () {},
      onDismissProblem: onDismiss ?? (_) {},
      onOpenUrl: onOpen ?? (_) {},
    ),
  ),
);

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
    testWidgets('six dashboard sections render and scroll at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: dashboard()));
      await tester.pumpAndSettle();
      expect(find.text('Highlights'), findsOneWidget);
      expect(find.text('128'), findsOneWidget);
      expect(find.text('24.5%'), findsOneWidget);
      await capture(tester, key, size.width < 600 ? 'phone' : 'desktop');
      for (final id in [
        'reports',
        'traffic',
        'engagement',
        'search',
        'system',
      ]) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('dashboard-section-$id')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (id == 'reports') {
          await tester.ensureVisible(find.text('3.0 h'));
          expect(find.text('3.0 h'), findsOneWidget);
        }
        if (id == 'traffic') {
          expect(find.text('285'), findsOneWidget);
          await Scrollable.ensureVisible(
            tester.element(find.text('Crawlers')),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          expect(find.text('Crawlers').hitTestable(), findsOneWidget);
          await tester.tap(find.text('Crawlers'));
          await tester.pumpAndSettle();
          expect(find.text('560'), findsOneWidget);
          await Scrollable.ensureVisible(
            tester.element(find.text('Selected pageviews')),
            alignment: .2,
          );
          await tester.pumpAndSettle();
          await capture(
            tester,
            key,
            size.width < 600 ? 'phone-traffic' : 'desktop-traffic',
          );
        }
        if (id == 'system') {
          expect(find.text('200.0 MB used'), findsOneWidget);
          expect(find.text('300.0 MB free'), findsOneWidget);
        }
      }
      expect(find.text('System'), findsOneWidget);
    });
  }
  testWidgets('member page denies data and controls', (tester) async {
    await tester.pumpWidget(dashboard(staff: false, admin: false));
    await tester.pumpAndSettle();
    expect(find.text('Only staff can see the dashboard.'), findsOneWidget);
    expect(find.text('128'), findsNothing);
    expect(find.byType(DSelect<DashboardPeriod>), findsNothing);
  });
  testWidgets(
    'moderator hides admin configuration, dismissal, rankings, backups',
    (tester) async {
      await tester.pumpWidget(dashboard(admin: false));
      await tester.pumpAndSettle();
      expect(find.text('Configure'), findsNothing);
      expect(find.text('Dismiss notice'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('dashboard-section-traffic')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Top referrers'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('dashboard-section-system')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Backups'), findsNothing);
      expect(find.text('100.0 MB used'), findsOneWidget);
    },
  );
  testWidgets(
    'presets, confirmed configuration, advice, and refresh call their owners',
    (tester) async {
      DashboardPeriod? period;
      List<DashboardConfiguration>? configured;
      var refreshes = 0;
      DashboardProblem? dismissed;
      await tester.pumpWidget(
        dashboard(
          onPeriod: (value) => period = value,
          onConfigure: (value) => configured = value,
          onRefresh: () => refreshes++,
          onDismiss: (value) => dismissed = value,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 7 days').last);
      await tester.pumpAndSettle();
      expect(period, DashboardPeriod.last7Days);
      await tester.tap(find.text('Configure'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Site traffic').last);
      await tester.pumpAndSettle();
      expect(
        configured!.firstWhere((item) => item.id == 'traffic').visible,
        isFalse,
      );
      expect(configured!.last.id, 'plugin_health');
      await tester.tapAt(const Offset(10, 250));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dismiss notice'));
      await tester.pumpAndSettle();
      expect(dismissed!.id, 1);
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
    },
  );
  testWidgets('legacy and partial failures provide truthful browser actions', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      dashboard(
        state: DashboardState(snapshot: DashboardSnapshot(supported: false)),
        onOpen: (url) => opened = url,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('This forum does not provide the redesigned dashboard yet.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Open dashboard in browser'));
    expect(opened, '/admin/dashboard');
    await tester.pumpWidget(
      dashboard(
        state: DashboardState(
          snapshot: DashboardSnapshot(
            supported: true,
            sections: const [
              DashboardUnavailableSection('traffic', failed: true),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('This section could not be loaded. Refresh to try again.'),
      findsOneWidget,
    );
  });
  testWidgets('remote storage never invents free capacity', (tester) async {
    await tester.pumpWidget(
      dashboard(
        state: DashboardState(
          snapshot: DashboardSnapshot(
            supported: true,
            sections: [
              DashboardSystem.fromJson({
                'version': <String, dynamic>{},
                'storage': {
                  'uploads': {'used_bytes': 104857600, 'remote': true},
                },
              }),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Remote storage'), findsOneWidget);
    expect(find.textContaining('free'), findsNothing);
    expect(find.byType(DProgress), findsNothing);
  });
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['DASHBOARD_PREVIEW_DIR'];
  if (directory == null) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$directory/dashboard-port-preview-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
