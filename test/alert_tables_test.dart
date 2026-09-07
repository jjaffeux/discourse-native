import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_data.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_tables.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/alert_fixtures.dart';
import 'support/shell_test_harness.dart' show watchBrowser;

void main() {
  testWidgets(
    'shows all status tables in order with descriptions and UTC dates',
    (tester) async {
      await _pump(tester, [
        alertJson(status: 'resolved', identifier: 'history'),
        alertJson(status: 'suppressed', identifier: 'silenced'),
        alertJson(status: 'stale', identifier: 'stale'),
        alertJson(identifier: 'active', description: 'High latency'),
      ]);
      for (final name in [
        'history',
        'silenced',
        'stale',
        'active',
        'High latency',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('2020-07-27 17:26 – 17:35 UTC'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Firing')).dy,
        lessThan(tester.getTopLeft(find.text('Silenced')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Silenced')).dy,
        lessThan(tester.getTopLeft(find.text('Stale')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Stale')).dy,
        lessThan(tester.getTopLeft(find.text('History')).dy),
      );
    },
  );

  testWidgets(
    'a large group expands and keeps the user choice on data refresh',
    (tester) async {
      final rows = List.generate(
        31,
        (index) => alertJson(identifier: 'alert $index'),
      );
      await _pump(tester, rows);
      expect(find.text('sjc1 (31)'), findsOneWidget);
      expect(find.text('alert 0'), findsNothing);

      await tester.tap(find.text('sjc1 (31)'));
      await tester.pump();
      expect(find.text('alert 0'), findsOneWidget);

      await _pump(tester, [...rows, alertJson(identifier: 'new alert')]);
      expect(find.text('sjc1 (32)'), findsOneWidget);
      expect(find.text('new alert'), findsOneWidget);
      await tester.tap(find.text('sjc1 (32)'));
      await tester.pump();
      expect(find.text('alert 0'), findsNothing);
    },
  );

  testWidgets(
    'phone tables scroll horizontally and retain long selectable text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final quoted = <PrometheusAlert>[];
      final identifier = 'database-${'long-hostname-' * 8}';
      await _pump(
        tester,
        [
          alertJson(
            identifier: identifier,
            description: 'A detailed alert description ' * 15,
          ),
        ],
        onQuote: quoted.add,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      final before = tester.getTopLeft(find.text(identifier)).dx;
      final horizontal = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      await tester.dragFrom(
        tester.getTopLeft(horizontal) + const Offset(160, 40),
        const Offset(-650, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text(identifier)).dx, lessThan(before));
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'graph and manager links open the browser and quoting selects the row',
    (tester) async {
      final launched = watchBrowser(tester);
      final quoted = <PrometheusAlert>[];
      await _pump(tester, [alertJson(status: 'resolved')], onQuote: quoted.add);
      await tester.tap(find.text('myalert'));
      await tester.pump();
      expect(
        Uri.parse(launched.single).queryParameters['g0.range_input'],
        '1127s',
      );

      await tester.tap(_button('Open Alertmanager'));
      await tester.pump();
      expect(launched.last, 'https://alertmanager.example.com');
      await tester.tap(_button('Quote Alert'));
      await tester.pump();
      expect(quoted.single.identifier, 'myalert');
    },
  );

  testWidgets(
    'invalid links retain identifiers as text and empty descriptions add no column',
    (tester) async {
      await _pump(tester, [
        alertJson()..addAll({
          'generator_url': 'javascript:alert(1)',
          'link_url': 'file:///private/file',
          'external_url': null,
        }),
      ]);
      expect(find.text('myalert'), findsOneWidget);
      expect(_button('Open Link'), findsNothing);
      expect(_button('Open Alertmanager'), findsNothing);
      expect(_button('Quote Alert'), findsNothing);
      expect(
        tester.widget<Table>(find.byType(Table)).children.single.children,
        hasLength(3),
      );
    },
  );
}

Finder _button(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is DButton && widget.tooltip == tooltip,
);

Future<void> _pump(
  WidgetTester tester,
  List<Object?> rows, {
  ValueChanged<PrometheusAlert>? onQuote,
  double scale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: SingleChildScrollView(
          child: AlertTables(
            data: AlertData.decode({'alert_data': rows})!,
            siteUrl: 'https://meta.discourse.org',
            onQuote: onQuote,
          ),
        ),
      ),
    ),
  ),
);
