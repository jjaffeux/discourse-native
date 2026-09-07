import '../../models/json.dart';
import '../../plugin_api/site_plugin_api.dart';
import 'alert_data.dart';

const alertLinkSettingsKey = PluginDataKey<AlertLinkSettings>(
  owner: 'discourse-prometheus-alert-receiver',
  name: 'link-settings',
);

final class AlertLinkSettings {
  const AlertLinkSettings({
    this.prometheus = r'\/graph\?g0\.expr=',
    this.grafana = '',
    this.kibana = r'\/app\/kibana',
  });

  static AlertLinkSettings decode(Map<String, dynamic> json) =>
      AlertLinkSettings(
        prometheus: jsonString(
          json['prometheus_alert_receiver_prometheus_regex'],
          fallback: r'\/graph\?g0\.expr=',
        ),
        grafana: jsonString(json['prometheus_alert_receiver_grafana_regex']),
        kibana: jsonString(
          json['prometheus_alert_receiver_kibana_regex'],
          fallback: r'\/app\/kibana',
        ),
      );

  final String prometheus;
  final String grafana;
  final String kibana;

  Uri? process(String? value, PrometheusAlert alert, {required DateTime now}) {
    final uri = alertWebUri(value);
    if (uri == null) return null;
    try {
      return _withTimeRange(uri, alert, now);
    } on FormatException {
      return uri;
    }
  }

  Uri _withTimeRange(Uri uri, PrometheusAlert alert, DateTime now) {
    final start = alert.start;
    if (start == null) return uri;
    final end = alert.end ?? now.toUtc();
    if (end.isBefore(start)) return uri;
    final query = <String, dynamic>{...uri.queryParametersAll};
    if (_matches(uri, prometheus)) {
      final duration =
          end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
      return uri.replace(
        queryParameters: query
          ..['g0.range_input'] = '${(duration / 1000 + 600).ceil()}s'
          ..['g0.end_input'] = _javascriptTimestamp(
            end.add(const Duration(minutes: 5)),
          )
          ..['g0.tab'] = '0',
      );
    }
    if (_matches(uri, grafana)) {
      return uri.replace(
        queryParameters: query
          ..['from'] = '${start.millisecondsSinceEpoch}'
          ..['to'] = '${end.millisecondsSinceEpoch}',
      );
    }
    if (_matches(uri, kibana)) {
      final separator = uri.fragment.indexOf('?');
      final path = separator < 0
          ? uri.fragment
          : uri.fragment.substring(0, separator);
      final fragmentQuery = separator < 0
          ? <String, String>{}
          : Uri.splitQueryString(uri.fragment.substring(separator + 1));
      fragmentQuery['_g'] =
          "(time:(from:'${alert.startsAt}',mode:absolute,to:'${alert.endsAt ?? _javascriptTimestamp(end)}'))";
      return uri.replace(
        fragment: '$path?${Uri(queryParameters: fragmentQuery).query}',
      );
    }
    return uri;
  }

  static bool _matches(Uri uri, String pattern) {
    if (pattern.isEmpty) return false;
    try {
      return RegExp(pattern).hasMatch(uri.toString());
    } on FormatException {
      return false;
    }
  }

  static String _javascriptTimestamp(DateTime value) =>
      DateTime.fromMillisecondsSinceEpoch(
        value.millisecondsSinceEpoch,
        isUtc: true,
      ).toIso8601String();

  @override
  bool operator ==(Object other) =>
      other is AlertLinkSettings &&
      prometheus == other.prometheus &&
      grafana == other.grafana &&
      kibana == other.kibana;

  @override
  int get hashCode => Object.hash(prometheus, grafana, kibana);
}

Uri? alertWebUri(String? value) {
  final uri = value == null ? null : Uri.tryParse(value);
  return uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.hasAuthority &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

final class AlertLinkSettingsCodec
    extends PluginDataPersistenceCodec<AlertLinkSettings> {
  const AlertLinkSettingsCodec();

  @override
  PluginDataKey<AlertLinkSettings> get key => alertLinkSettingsKey;

  @override
  AlertLinkSettings? decode(Object? value) {
    final fields = jsonObjectFields(value);
    return fields == null ? null : AlertLinkSettings.decode(fields);
  }

  @override
  Map<String, Object?> encode(AlertLinkSettings value) => {
    'prometheus_alert_receiver_prometheus_regex': value.prometheus,
    'prometheus_alert_receiver_grafana_regex': value.grafana,
    'prometheus_alert_receiver_kibana_regex': value.kibana,
  };
}
