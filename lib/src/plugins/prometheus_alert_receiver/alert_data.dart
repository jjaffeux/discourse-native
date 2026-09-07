import 'package:flutter/foundation.dart';

import '../../models/json.dart';
import '../../plugin_api/site_plugin_api.dart';

const prometheusAlertReceiverPluginId = PluginId(
  'discourse-prometheus-alert-receiver',
);
const alertDataKey = PluginDataKey<AlertData>(
  owner: 'discourse-prometheus-alert-receiver',
  name: 'alerts',
);

enum AlertStatus {
  firing('Firing'),
  suppressed('Silenced'),
  stale('Stale'),
  resolved('History');

  const AlertStatus(this.label);
  final String label;
}

@immutable
final class PrometheusAlert {
  const PrometheusAlert._({
    required this.status,
    required this.identifier,
    required this.datacenter,
    required this.description,
    required this.startsAt,
    required this.endsAt,
    required this.externalUrl,
    required this.generatorUrl,
    required this.linkUrl,
    required this.linkText,
    required this.lastSuppressedAt,
  });

  static PrometheusAlert? decode(Object? value) {
    final json = jsonObject(value);
    final status = AlertStatus.values
        .where((status) => status.name == json['status'])
        .firstOrNull;
    if (status == null) return null;
    return PrometheusAlert._(
      status: status,
      identifier: jsonString(json['identifier']),
      datacenter: jsonString(json['datacenter']),
      description: jsonString(json['description']),
      startsAt: _timestamp(json['starts_at']),
      endsAt: _timestamp(json['ends_at']),
      externalUrl: jsonText(json['external_url']),
      generatorUrl: jsonText(json['generator_url']),
      linkUrl: jsonText(json['link_url']),
      linkText: jsonText(json['link_text']) ?? 'Open Link',
      lastSuppressedAt: jsonDate(json['last_suppressed_at'])?.toUtc(),
    );
  }

  // Keep the wire precision for Kibana's absolute time range.
  static String? _timestamp(Object? value) =>
      jsonDate(value) == null ? null : value as String;

  final AlertStatus status;
  final String identifier;
  final String datacenter;
  final String description;
  final String? startsAt;
  final String? endsAt;
  final String? externalUrl;
  final String? generatorUrl;
  final String? linkUrl;
  final String linkText;
  final DateTime? lastSuppressedAt;

  DateTime? get start => jsonDate(startsAt)?.toUtc();
  DateTime? get end => jsonDate(endsAt)?.toUtc();

  bool wasRecentlySilenced(DateTime now) {
    final suppressed = lastSuppressedAt;
    if (status != AlertStatus.firing || suppressed == null) return false;
    final age = now.difference(suppressed);
    return !age.isNegative && age <= const Duration(days: 90);
  }

  String get quoteContents {
    final date = start?.toIso8601String().split('T');
    return '**$identifier** - $datacenter'
        '${date == null ? '' : ' - [date=${date[0]} time=${date[1]} displayedTimezone=UTC format="YYYY-MM-DD HH:mm"]'}'
        '${description.isEmpty ? '' : ' - $description'}';
  }

  @override
  bool operator ==(Object other) =>
      other is PrometheusAlert &&
      status == other.status &&
      identifier == other.identifier &&
      datacenter == other.datacenter &&
      description == other.description &&
      startsAt == other.startsAt &&
      endsAt == other.endsAt &&
      externalUrl == other.externalUrl &&
      generatorUrl == other.generatorUrl &&
      linkUrl == other.linkUrl &&
      linkText == other.linkText &&
      lastSuppressedAt == other.lastSuppressedAt;

  @override
  int get hashCode => Object.hash(
    status,
    identifier,
    datacenter,
    description,
    startsAt,
    endsAt,
    externalUrl,
    generatorUrl,
    linkUrl,
    linkText,
    lastSuppressedAt,
  );
}

@immutable
final class AlertData {
  AlertData._(List<PrometheusAlert> alerts)
    : alerts = List.unmodifiable(alerts),
      groups = List.unmodifiable(_group(alerts));

  static AlertData? decode(Map<String, dynamic> json) {
    final rows = json['alert_data'];
    if (rows is! List) return null;
    return AlertData._([for (final row in rows) ?PrometheusAlert.decode(row)]);
  }

  final List<PrometheusAlert> alerts;
  final List<AlertGroup> groups;

  static Iterable<AlertGroup> _group(List<PrometheusAlert> alerts) sync* {
    var collapsed = false;
    for (final status in AlertStatus.values) {
      final byDatacenter = <String, List<PrometheusAlert>>{};
      var count = 0;
      for (final alert in alerts.where((alert) => alert.status == status)) {
        (byDatacenter[alert.datacenter] ??= []).add(alert);
        count++;
      }
      // Upstream collapses this and all subsequent status groups once any
      // status exceeds thirty alerts, even when spread across datacenters.
      collapsed = collapsed || count > 30;
      for (final datacenter in byDatacenter.keys.toList()..sort()) {
        yield AlertGroup(
          status: status,
          datacenter: datacenter,
          alerts: List.unmodifiable(byDatacenter[datacenter]!),
          defaultCollapsed: collapsed,
        );
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AlertData && listEquals(alerts, other.alerts);

  @override
  int get hashCode => Object.hashAll(alerts);
}

@immutable
final class AlertGroup {
  const AlertGroup({
    required this.status,
    required this.datacenter,
    required this.alerts,
    required this.defaultCollapsed,
  });

  final AlertStatus status;
  final String datacenter;
  final List<PrometheusAlert> alerts;
  final bool defaultCollapsed;

  String get heading => datacenter.isEmpty ? 'Alerts' : datacenter;
  bool get showDescription =>
      alerts.any((alert) => alert.description.isNotEmpty);
}
