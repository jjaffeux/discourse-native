import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_data.dart';
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

  test('quotes the alert with its precise opening timestamp and description', () {
    final alert = PrometheusAlert.decode(
      alertJson(status: 'resolved', description: 'High latency'),
    )!;
    expect(
      alert.quoteContents,
      '**myalert** - sjc1 - [date=2020-07-27 time=17:26:49.526234Z displayedTimezone=UTC format="YYYY-MM-DD HH:mm"] - High latency',
    );
  });

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
