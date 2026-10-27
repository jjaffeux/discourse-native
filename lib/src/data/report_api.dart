import '../models/json.dart';
import '../plugin_api/dashboard_report_source.dart';
import 'plugin_transport.dart';

export '../plugin_api/dashboard_report_source.dart' show ReportApi;

final class DiscourseReportApi implements ReportApi {
  const DiscourseReportApi(this.transport, {this.sources = const []});
  final PluginApiTransport transport;
  final Iterable<DashboardReportSource> sources;

  @override
  Future<ReportDetails> load({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardReport report,
    required DashboardRange range,
    required Map<String, Object?> filters,
  }) async {
    Future<Map<String, dynamic>> get(String path) => transport.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
    if (report.source != 'core_report') {
      final source = sources
          .where((source) => source.source == report.source)
          .firstOrNull;
      if (source == null) {
        return ReportDetails(result: DashboardReportResult(unsupported: true));
      }
      return source
          .createApi(transport)
          .load(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: clientId,
            report: report,
            range: range,
            filters: filters,
          );
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(report.identifier)) {
      throw ArgumentError.value(report.identifier, 'identifier');
    }
    final response = await get(
      Uri(
        path: '/admin/reports/${report.identifier}.json',
        queryParameters: {
          ...range.query,
          'limit': '50',
          for (final entry in filters.entries)
            if (entry.value is List)
              'filters[${entry.key}][]': (entry.value as List)
                  .map((value) => value.toString())
                  .toList()
            else if (entry.value != null)
              'filters[${entry.key}]': entry.value.toString(),
        },
      ).toString(),
    );
    final payload = <String, dynamic>{'data': jsonObject(response['report'])};
    final data = jsonObject(payload['data']);
    final filtersNeedSite = jsonObjects(data['available_filters']).any(
      (filter) => const {
        'category',
        'category_list',
        'group',
        'groups',
      }.contains(filter['type']),
    );
    final site = filtersNeedSite
        ? await get('/site.json')
        : <String, dynamic>{};
    return ReportDetails.fromJson(payload, site: site);
  }
}
