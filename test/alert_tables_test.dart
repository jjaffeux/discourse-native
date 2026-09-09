import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_widget.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_plugin.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_data.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_tables.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/alert_fixtures.dart';
import 'support/shell_test_harness.dart' show renderedText, watchBrowser;

void main() {
  testWidgets(
    'shows all status tables in order with descriptions and UTC dates',
    (tester) async {
      await _pump(tester, [
        alertJson(status: 'resolved', identifier: 'history'),
        alertJson(status: 'suppressed', identifier: 'silenced'),
        alertJson(status: 'stale', identifier: 'stale'),
        alertJson(identifier: 'active', description: 'High latency'),
      ], registry: _localDates());
      for (final name in [
        'history',
        'silenced',
        'stale',
        'active',
        'High latency',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.byType(LocalDateInline), findsNWidgets(5));
      expect(find.textContaining('17:35 (UTC)'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('🤫'), findsOneWidget);
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

  testWidgets('alert timestamps open Local Dates timezone previews', (
    tester,
  ) async {
    await _pump(tester, [alertJson()], registry: _localDates());
    expect(find.textContaining('2020-07-27 17:26 (UTC)'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('Paris:')));
    await tester.pumpAndSettle();
    expect(find.text('Paris'), findsOneWidget);
    expect(find.textContaining('Device'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\b7:26\s+PM')), findsOneWidget);
    expect(find.textContaining('Source'), findsOneWidget);
  });

  testWidgets(
    'date ranges keep a later end date and malformed times remain readable',
    (tester) async {
      await _pump(tester, [
        alertJson(status: 'resolved')..['ends_at'] = '2020-07-28T00:35:00Z',
        alertJson(identifier: 'invalid time')..['starts_at'] = 'invalid',
      ], registry: _localDates());
      expect(find.textContaining('2020-07-28 00:35 (UTC)'), findsOneWidget);
      expect(renderedText('Unknown time'), findsOneWidget);
      expect(find.text('invalid time'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dates retain readable UTC text when Local Dates is not installed',
    (tester) async {
      await _pump(tester, [alertJson(status: 'resolved')]);
      expect(
        renderedText('2020-07-27 17:26 (UTC) – 17:35 (UTC)'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'desktop tables give names most of the width and use compact controls',
    (tester) async {
      tester.view.physicalSize = const Size(880, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        [alertJson()],
        registry: _localDates(),
        onQuote: (_) {},
      );
      final table = find.byType(DTable);
      final date = find.byType(LocalDateInline);
      final nameWidth =
          tester.getTopLeft(date).dx -
          tester.getTopLeft(find.text('myalert')).dx;
      expect(nameWidth, greaterThan(tester.getSize(table).width * .65));
      expect(tester.getSize(_button('Quote Alert')).height, 28);
      expect(
        tester
            .getSize(find.widgetWithText(DCollapsibleTrigger, 'sjc1 (1)'))
            .height,
        28,
      );
      expect(
        tester.getSize(table).height,
        lessThanOrEqualTo(tester.getSize(date).height + 8),
      );
      expect(tester.takeException(), isNull);
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
        platform: TargetPlatform.iOS,
        registry: _localDates(),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(_button('Quote Alert')).height, 40);
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
      final offset = tester.getTopLeft(find.text(identifier)).dx;
      await tester.tap(find.text('sjc1 (1)'));
      await tester.pumpAndSettle();
      expect(find.text(identifier), findsNothing);
      await tester.tap(find.text('sjc1 (1)'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text(identifier)).dx, offset);
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
        tester.widget<DTable>(find.byType(DTable)).body.rows.single.cells,
        hasLength(3),
      );
    },
  );
}

Finder _button(String tooltip) => find.descendant(
  of: find.byTooltip(tooltip),
  matching: find.byType(IconButton),
);

PluginRegistry _localDates() {
  final environment = LocalDateEnvironment.forTesting(
    detectDeviceTimezone: () async => 'Europe/Paris',
  )..setDeviceTimezone('Europe/Paris');
  addTearDown(environment.dispose);
  return PluginRegistry([LocalDatesPlugin(environment: environment)]);
}

Future<void> _pump(
  WidgetTester tester,
  List<Object?> rows, {
  ValueChanged<PrometheusAlert>? onQuote,
  double scale = 1,
  TargetPlatform platform = TargetPlatform.macOS,
  PluginRegistry registry = PluginRegistry.empty,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light.copyWith(platform: platform),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: PluginRegistryScope(
          registry: registry,
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
  ),
);
