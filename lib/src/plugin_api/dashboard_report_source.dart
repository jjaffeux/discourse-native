import '../models/dashboard.dart';
import '../models/report.dart';
import 'plugin_contracts.dart';

export '../models/dashboard.dart'
    show DashboardReport, DashboardRange, DashboardReportResult, DashboardPoint;
export '../models/report.dart' show ReportDetails;

/// A report provider owns its wire format and detail endpoint. Core only
/// dispatches by the source returned by the dashboard and presents shared data.
abstract interface class DashboardReportSource implements PluginCapability {
  String get source;
  DashboardReportResult decode(Map<String, dynamic> payload);
  ReportApi createApi(PluginApiTransport transport);
}

abstract interface class ReportApi {
  Future<ReportDetails> load({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardReport report,
    required DashboardRange range,
    required Map<String, Object?> filters,
  });
}
