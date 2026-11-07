import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/report_api.dart';
import '../data/site_lifecycle.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/dashboard.dart';
import '../models/report.dart';
import '../plugin_api/preserved_json.dart';

final class _ReportQuery {
  _ReportQuery(this.range, Map<String, Object?> filters)
    : filters = _snapshotFilters(filters);

  final DashboardRange range;
  final Map<String, Object?> filters;

  static Map<String, Object?> _snapshotFilters(Map<String, Object?> filters) {
    final frozen = freezeJson(filters);
    if (!frozen.valid || frozen.value is! Map<String, Object?>) {
      throw ArgumentError('Report filters must contain JSON values.');
    }
    return frozen.value! as Map<String, Object?>;
  }
}

final class ReportController extends FrameSafeNotifier {
  ReportController({
    required this.api,
    required this.credentials,
    required this.lease,
    required this.siteUrl,
    required this.report,
    required DashboardRange range,
  }) : _query = _ReportQuery(range, const {}) {
    _detach = lease.onRetire(() {
      _generation++;
      details = null;
      loading = false;
      if (!isDisposed) notifySafely();
    });
  }

  final ReportApi api;
  final ApiCredentialReader credentials;
  final SiteLease lease;
  final String siteUrl;
  final DashboardReport report;
  _ReportQuery _query;
  DashboardRange get range => _query.range;
  ReportDetails? details;
  bool loading = false;
  bool error = false;
  int _generation = 0;
  void Function()? _detach;

  Future<void> selectRange(DashboardRange value) async {
    if (value.start.isAfter(value.end)) return;
    _query = _ReportQuery(value, _query.filters);
    details = null;
    await refresh();
  }

  Future<void> filter(String id, Object? value) async {
    _query = _ReportQuery(range, {..._query.filters, id: value});
    details = null;
    await refresh();
  }

  Future<void> refresh() async {
    if (isDisposed || !lease.isCurrent) return;
    final generation = ++_generation;
    final query = _query;
    bool owns() => !isDisposed && lease.isCurrent && generation == _generation;
    loading = true;
    error = false;
    notifySafely();
    if (!owns()) return;
    try {
      final auth = await AccountRequestSession(
        siteUrl,
        lease,
      ).credentials(credentials);
      if (!owns()) return;
      if (auth.apiKey == null) {
        throw StateError('Report requires a staff account.');
      }
      final loaded = await auth.run(
        () => api.load(
          siteUrl: siteUrl,
          apiKey: auth.apiKey!,
          clientId: auth.clientId,
          report: report,
          range: query.range,
          filters: query.filters,
        ),
      );
      if (!owns()) return;
      details = loaded;
      error = loaded.result.error;
    } catch (_) {
      if (!owns()) return;
      error = true;
    }
    if (!owns()) return;
    loading = false;
    notifySafely();
  }

  @override
  void dispose() {
    _generation++;
    _detach?.call();
    super.dispose();
  }
}
