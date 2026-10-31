import '../models/dashboard.dart';
import '../models/json.dart';
import '../plugin_api/dashboard_report_source.dart';
import 'plugin_transport.dart';

abstract interface class DashboardApi {
  Future<DashboardSnapshot> load({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardRange range,
  });
  Future<Map<String, DashboardReportResult>> reports({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardRange range,
    required List<DashboardReport> items,
  });
  Future<void> configure({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required List<DashboardConfiguration> sections,
  });
  Future<List<DashboardProblem>> refreshProblems({
    required String siteUrl,
    required String apiKey,
    required String clientId,
  });
  Future<void> dismissProblem({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int id,
  });
}

final class DiscourseDashboardApi implements DashboardApi {
  const DiscourseDashboardApi(this.transport, {this.sources = const []});
  final PluginApiTransport transport;
  final Iterable<DashboardReportSource> sources;

  @override
  Future<DashboardSnapshot> load({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardRange range,
  }) async => DashboardSnapshot.fromJson(
    await transport.pluginGetJson(
      siteUrl: siteUrl,
      path: Uri(
        path: '/admin/dashboard.json',
        queryParameters: range.query,
      ).toString(),
      apiKey: apiKey,
      clientId: clientId,
    ),
  );

  @override
  Future<Map<String, DashboardReportResult>> reports({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardRange range,
    required List<DashboardReport> items,
  }) async {
    if (items.isEmpty) return const {};
    final current = await _reports(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      range: range,
      items: items,
    );
    final comparable = items.where((item) {
      final result = current[item.key];
      return result != null &&
          !result.error &&
          !result.unsupported &&
          result.points.isNotEmpty &&
          result.points.every(
            (point) => DateTime.tryParse(point.label) != null,
          );
    }).toList();
    if (comparable.isEmpty) return current;
    try {
      final previous = await _reports(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        range: range.previous,
        items: comparable,
      );
      return Map.unmodifiable({
        for (final entry in current.entries)
          entry.key: previous[entry.key] == null
              ? entry.value
              : entry.value.withPrevious(previous[entry.key]!),
      });
    } catch (_) {
      // A comparison failure must not discard the current period's report.
      return current;
    }
  }

  Future<Map<String, DashboardReportResult>> _reports({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardRange range,
    required List<DashboardReport> items,
  }) async {
    final body = <String, Object?>{
      'items': items.map((item) => item.toJson()).toList(),
      'filters': range.query,
    };
    final query = transport;
    final response = query is PluginJsonQueryTransport
        ? await (query as PluginJsonQueryTransport).pluginQueryJson(
            siteUrl: siteUrl,
            path: '/admin/dashboard/reports/bulk.json',
            apiKey: apiKey,
            clientId: clientId,
            body: body,
          )
        : await transport.pluginWriteJson(
            siteUrl: siteUrl,
            path: '/admin/dashboard/reports/bulk.json',
            method: 'POST',
            apiKey: apiKey,
            clientId: clientId,
            body: body,
          );
    return Map.unmodifiable({
      for (final item in jsonObjects(response['items']))
        jsonString(item['key']): _decode(item, items),
    });
  }

  DashboardReportResult _decode(
    Map<String, dynamic> payload,
    List<DashboardReport> items,
  ) {
    final source = items
        .where((item) => item.key == payload['key'])
        .firstOrNull
        ?.source;
    if (source == 'core_report') return DashboardReportResult.fromJson(payload);
    final extension = sources
        .where((extension) => extension.source == source)
        .firstOrNull;
    return extension?.decode(payload) ??
        DashboardReportResult(
          unsupported: true,
          error: payload['error'] == true,
        );
  }

  @override
  Future<void> configure({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required List<DashboardConfiguration> sections,
  }) async {
    await transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/admin/dashboard/configuration.json',
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'sections': sections.map((section) => section.toJson()).toList()},
    );
  }

  @override
  Future<List<DashboardProblem>> refreshProblems({
    required String siteUrl,
    required String apiKey,
    required String clientId,
  }) async {
    final response = await transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/admin/dashboard/problems.json',
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
    return List.unmodifiable(
      jsonObjects(response['problems']).map(DashboardProblem.fromJson),
    );
  }

  @override
  Future<void> dismissProblem({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required int id,
  }) async {
    if (id <= 0) throw ArgumentError.value(id, 'id');
    await transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/admin/admin_notices/$id.json',
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }
}
