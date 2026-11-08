import 'package:discourse_plugin_api/discourse_plugin_api.dart';

import '../models/dashboard.dart';
import '../models/report.dart';

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

/// One admitted owner for each optional report wire format and detail API.
final class DashboardReportSources {
  factory DashboardReportSources(Iterable<DashboardReportSource> sources) {
    final admitted = <String, DashboardReportSource>{};
    for (final source in sources) {
      final name = source.source;
      if (name.isEmpty || name == coreSource || admitted.containsKey(name)) {
        throw ArgumentError.value(
          name,
          'source',
          'Report source is reserved or already owned.',
        );
      }
      admitted[name] = source;
    }
    return DashboardReportSources._(Map.unmodifiable(admitted));
  }

  const DashboardReportSources.empty() : _sources = const {};
  const DashboardReportSources._(this._sources);

  static const coreSource = 'core_report';
  final Map<String, DashboardReportSource> _sources;

  DashboardReportSource? operator [](String? source) => _sources[source];
}
