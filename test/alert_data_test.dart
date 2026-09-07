import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_data.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_tables.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/alert_fixtures.dart';

void main() {
  test('groups statuses in priority order and datacenters alphabetically', () {
    final data = AlertData.decode({
      'alert_data': [
        alertJson(status: 'resolved'),
        alertJson(status: 'stale'),
        alertJson(status: 'suppressed'),
        alertJson(datacenter: 'sjc2', identifier: 'second'),
        alertJson(identifier: 'first'),
        alertJson(identifier: 'third', description: 'High latency'),
      ],
    })!;

    expect(data.groups.map((group) => (group.status.label, group.datacenter)), [
      ('Firing', 'sjc1'),
      ('Firing', 'sjc2'),
      ('Silenced', 'sjc1'),
      ('Stale', 'sjc1'),
      ('History', 'sjc1'),
    ]);
    expect(data.groups.first.alerts.map((alert) => alert.identifier), [
      'first',
      'third',
    ]);
    expect(data.groups.first.showDescription, isTrue);
    expect(data.groups[1].showDescription, isFalse);
  });

  test(
    'collapses large statuses and the lower priority statuses after them',
    () {
      final data = AlertData.decode({
        'alert_data': [
          alertJson(),
          for (var i = 0; i < 31; i++)
            alertJson(
              status: 'suppressed',
              datacenter: i.isEven ? 'ams1' : 'sjc1',
            ),
          alertJson(status: 'resolved'),
        ],
      })!;
      expect(data.groups.map((group) => group.defaultCollapsed), [
        false,
        true,
        true,
        true,
      ]);
      expect(
        AlertData.decode({
          'alert_data': List.generate(30, (_) => alertJson()),
        })!.groups.single.defaultCollapsed,
        isFalse,
      );
    },
  );

  test(
    'malformed rows and dates do not hide valid alerts or activate absent data',
    () {
      for (final value in [null, false, 3, 'alerts', <String, dynamic>{}]) {
        expect(AlertData.decode({'alert_data': value}), isNull);
      }
      expect(AlertData.decode({}), isNull);
      expect(AlertData.decode({'alert_data': <Object?>[]})!.alerts, isEmpty);
      final source = alertJson()
        ..addAll({
          'starts_at': 'invalid',
          'ends_at': 8,
          'last_suppressed_at': <Object?>[],
          'identifier': false,
          'datacenter': null,
          'description': <String, Object?>{},
        });
      final data = AlertData.decode({
        'alert_data': [
          null,
          <String, Object?>{},
          false,
          {'status': 'other'},
          source,
        ],
      })!;
      expect(data.alerts, hasLength(1));
      final alert = data.alerts.single;
      expect(
        (alert.identifier, alert.datacenter, alert.description),
        ('', '', ''),
      );
      expect(
        (alert.start, alert.end, alert.lastSuppressedAt),
        (null, null, null),
      );
      expect(alertDateRange(alert), 'Unknown time');
      source['identifier'] = 'mutated';
      expect(alert.identifier, '');
      expect(() => data.alerts.clear(), throwsUnsupportedError);
    },
  );

  test(
    'equivalent data compares equally and a changed alert invalidates it',
    () {
      AlertData data(String status) => AlertData.decode({
        'alert_data': [alertJson(status: status)],
      })!;
      expect(data('firing'), data('firing'));
      expect(data('firing').hashCode, data('firing').hashCode);
      expect(data('firing'), isNot(data('resolved')));
    },
  );

  test(
    'formats UTC ranges and quotes without losing the opening post timestamp',
    () {
      final alert = PrometheusAlert.decode(
        alertJson(status: 'resolved', description: 'High latency'),
      )!;
      expect(alertDateRange(alert), '2020-07-27 17:26 – 17:35 UTC');
      expect(
        alert.quoteContents,
        '**myalert** - sjc1 - [date=2020-07-27 time=17:26:49.526234Z displayedTimezone=UTC format="YYYY-MM-DD HH:mm"] - High latency',
      );
      final nextDay = PrometheusAlert.decode(
        alertJson()..['ends_at'] = '2020-07-28T00:35:00Z',
      )!;
      expect(
        alertDateRange(nextDay),
        '2020-07-27 17:26 – 2020-07-28 00:35 UTC',
      );
    },
  );

  test(
    'previously silenced applies only to firing alerts within ninety days',
    () {
      final now = DateTime.utc(2026, 9, 7);
      for (final status in AlertStatus.values) {
        for (final days in [-1, 0, 90, 91]) {
          final alert = PrometheusAlert.decode(
            alertJson(status: status.name)
              ..['last_suppressed_at'] = now
                  .subtract(Duration(days: days))
                  .toIso8601String(),
          )!;
          expect(
            alert.wasRecentlySilenced(now),
            status == AlertStatus.firing && days >= 0 && days <= 90,
            reason: '${status.name}, $days days',
          );
        }
      }
    },
  );
}
