import '../models/dashboard.dart';
import '../models/json.dart';
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
  const DiscourseDashboardApi(this.transport);
  final PluginApiTransport transport;

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
        jsonString(item['key']): DashboardReportResult.fromJson(item),
    });
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
