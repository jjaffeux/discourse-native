import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';

final class DataExplorerReports implements DashboardReportSource {
  const DataExplorerReports();
  @override
  String get name => 'discourse-data-explorer';
  @override
  String get source => 'data_explorer_query';
  @override
  ReportApi createApi(PluginApiTransport transport) =>
      _DataExplorerReportApi(transport, this);

  @override
  DashboardReportResult decode(Map<String, dynamic> json) {
    final data = jsonObject(json['data']);
    if (data['columns'] is! List || data['rows'] is! List) {
      return DashboardReportResult(
        error: json['error'] == true || data['error'] != null,
        unsupported: true,
      );
    }
    final columns = (data['columns'] as List)
        .map((value) => value.toString())
        .toList();
    final rows = (data['rows'] as List).whereType<List<dynamic>>().toList();
    final render = jsonObject(data['colrender']);
    final relations = jsonObject(data['relations']);
    String cell(int column, Object? value) {
      final type = jsonString(render['$column']);
      final relation = jsonObjects(
        relations[type],
      ).where((item) => item['id'].toString() == value.toString()).firstOrNull;
      return _reportCell(
        relation?['username'] ??
            relation?['title'] ??
            relation?['name'] ??
            value,
      );
    }

    num? number(Object? value) =>
        _number(value) ??
        (value is String ? _number(num.tryParse(value)) : null);
    final chartable =
        columns.length == 2 &&
        rows.isNotEmpty &&
        rows.every(
          (row) =>
              row.length == 2 && (row[1] == null || number(row[1]) != null),
        );
    return DashboardReportResult(
      error:
          json['error'] == true ||
          data['success'] == false ||
          data['error'] != null && data['error'] != false,
      headings: columns.map(
        (name) =>
            (name.contains(r'$')
                    ? name.split(r'$').last
                    : name.endsWith('_id')
                    ? name.substring(0, name.length - 3)
                    : name)
                .replaceAll('_', ' '),
      ),
      rows: rows.map(
        (row) => [
          for (var i = 0; i < columns.length; i++)
            cell(i, i < row.length ? row[i] : null),
        ],
      ),
      points: chartable
          ? rows.map((row) => DashboardPoint(cell(0, row[0]), number(row[1])))
          : const [],
    );
  }

  static num? _number(Object? value) =>
      value is num && value.isFinite ? value : null;
  static String _reportCell(Object? value) => switch (value) {
    null => '—',
    String() || num() || bool() => value.toString(),
    _ => '—',
  };
}

final class _DataExplorerReportApi implements ReportApi {
  const _DataExplorerReportApi(this.transport, this.source);
  final PluginApiTransport transport;
  final DataExplorerReports source;

  @override
  Future<ReportDetails> load({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardReport report,
    required DashboardRange range,
    required Map<String, Object?> filters,
  }) async {
    if (!RegExp(r'^-?[1-9][0-9]*$').hasMatch(report.identifier)) {
      throw ArgumentError.value(report.identifier, 'identifier');
    }
    var result = await transport.pluginGetJson(
      siteUrl: siteUrl,
      path: Uri(
        path: '/data-explorer/queries/${report.identifier}/run.json',
        queryParameters: {'params': jsonEncode(range.query)},
      ).toString(),
      apiKey: apiKey,
      clientId: clientId,
    );
    final render = jsonObject(result['colrender']);
    if (render.values.any((type) => type == 'category' || type == 'group')) {
      final site = await transport.pluginGetJson(
        siteUrl: siteUrl,
        path: '/site.json',
        apiKey: apiKey,
        clientId: clientId,
      );
      result = {
        ...result,
        'relations': {
          ...jsonObject(result['relations']),
          'category': site['categories'],
          'group': site['groups'],
        },
      };
    }
    return ReportDetails(result: source.decode({'data': result}));
  }
}
