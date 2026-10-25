import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/dashboard_api.dart';
import '../data/site_lifecycle.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/dashboard.dart';

final class DashboardState {
  const DashboardState({
    this.period = DashboardPeriod.last30Days,
    this.snapshot,
    this.reports = const {},
    this.loading = false,
    this.mutating = false,
    this.error = false,
    this.mutationError = false,
  });
  final DashboardPeriod period;
  final DashboardSnapshot? snapshot;
  final Map<String, DashboardReportResult> reports;
  final bool loading;
  final bool mutating;
  final bool error;
  final bool mutationError;
}

/// Owns one mounted dashboard's account, selected period, and confirmed writes.
final class DashboardController extends FrameSafeNotifier {
  DashboardController({
    required this.api,
    required this.credentials,
    required this.lease,
    required this.siteUrl,
    required this.staff,
    required this.admin,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _detach = lease.onRetire(() {
      _generation++;
      _state = const DashboardState();
      if (!isDisposed) notifySafely();
    });
  }
  final DashboardApi api;
  final ApiCredentialReader credentials;
  final SiteLease lease;
  final String siteUrl;
  final bool staff;
  final bool admin;
  final DateTime Function() _now;
  void Function()? _detach;
  int _generation = 0;
  int _problemRevision = 0;
  List<DashboardProblem>? _latestProblems;
  final Set<int> _dismissed = {};
  DashboardState _state = const DashboardState();
  DashboardState get state => _state;
  bool get _current => !isDisposed && lease.isCurrent && staff;

  void _publish(DashboardState value) {
    if (!_current) return;
    lease.commit(() {
      _state = value;
      notifySafely();
    });
  }

  DashboardSnapshot _confirmedSnapshot(
    DashboardSnapshot snapshot,
    int revision,
  ) {
    final problems = revision != _problemRevision && _latestProblems != null
        ? _latestProblems!
        : snapshot.problems;
    return snapshot.withProblems(
      problems.where((problem) => !_dismissed.contains(problem.id)),
    );
  }

  Future<AccountRequestCredentials> _auth() async {
    final auth = await AccountRequestSession(
      siteUrl,
      lease,
    ).credentials(credentials);
    if (auth.apiKey == null) {
      throw StateError('Dashboard requires a connected staff account.');
    }
    return auth;
  }

  Future<void> selectPeriod(DashboardPeriod period) async {
    if (period == state.period || !_current) return;
    _publish(DashboardState(period: period, mutating: state.mutating));
    await refresh();
  }

  Future<void> refresh() async {
    if (!_current) return;
    final generation = ++_generation;
    final held = state;
    final problemRevision = _problemRevision;
    final range = held.period.rangeAt(_now());
    bool owns() => _current && generation == _generation;
    _publish(
      DashboardState(
        period: held.period,
        snapshot: held.snapshot,
        reports: held.reports,
        loading: true,
        mutating: held.mutating,
      ),
    );
    if (!owns()) return;
    try {
      final auth = await _auth();
      if (!owns()) return;
      var snapshot = await auth.run(
        () => api.load(
          siteUrl: siteUrl,
          apiKey: auth.apiKey!,
          clientId: auth.clientId,
          range: range,
        ),
      );
      if (!owns()) return;
      final items = snapshot.sections
          .whereType<DashboardReports>()
          .expand((section) => section.items)
          .toList();
      Map<String, DashboardReportResult> reports;
      try {
        reports = await auth.run(
          () => api.reports(
            siteUrl: siteUrl,
            apiKey: auth.apiKey!,
            clientId: auth.clientId,
            range: range,
            items: items,
          ),
        );
      } catch (_) {
        reports = {
          for (final item in items)
            item.key: DashboardReportResult(error: true),
        };
      }
      if (!owns()) return;
      snapshot = _confirmedSnapshot(snapshot, problemRevision);
      _publish(
        DashboardState(
          period: held.period,
          snapshot: snapshot,
          reports: reports,
          mutating: state.mutating,
        ),
      );
    } catch (_) {
      if (owns()) {
        _publish(
          DashboardState(
            period: held.period,
            snapshot: held.snapshot == null
                ? null
                : _confirmedSnapshot(held.snapshot!, problemRevision),
            reports: held.reports,
            error: true,
            mutating: state.mutating,
          ),
        );
      }
    }
  }

  Future<void> configure(List<DashboardConfiguration> sections) {
    final configuration = state.snapshot?.configuration;
    if (!_current || !admin || configuration == null) return Future.value();
    final supplied = {
      for (final section in sections) section.id: section.visible,
    };
    final preserved = [
      for (final section in configuration)
        DashboardConfiguration(
          section.id,
          supplied[section.id] ?? section.visible,
        ),
    ];
    return _mutate((auth) async {
      await auth.run(
        () => api.configure(
          siteUrl: siteUrl,
          apiKey: auth.apiKey!,
          clientId: auth.clientId,
          sections: preserved,
        ),
      );
      if (_current) await refresh();
    }, adminOnly: true);
  }

  Future<void> refreshProblems() => _mutate((auth) async {
    final problems = await auth.run(
      () => api.refreshProblems(
        siteUrl: siteUrl,
        apiKey: auth.apiKey!,
        clientId: auth.clientId,
      ),
    );
    if (_current) {
      _problemRevision++;
      _latestProblems = problems;
      _replaceProblems(problems);
    }
  });

  Future<void> dismissProblem(DashboardProblem problem) =>
      _mutate((auth) async {
        await auth.run(
          () => api.dismissProblem(
            siteUrl: siteUrl,
            apiKey: auth.apiKey!,
            clientId: auth.clientId,
            id: problem.id,
          ),
        );
        if (_current) {
          _problemRevision++;
          _dismissed.add(problem.id);
          _replaceProblems(state.snapshot?.problems ?? const []);
        }
      }, adminOnly: true);

  void _replaceProblems(Iterable<DashboardProblem> problems) {
    _publish(
      DashboardState(
        period: state.period,
        snapshot: state.snapshot?.withProblems(
          problems.where((problem) => !_dismissed.contains(problem.id)),
        ),
        reports: state.reports,
        loading: state.loading,
        error: state.error,
        mutating: state.mutating,
      ),
    );
  }

  Future<void> _mutate(
    Future<void> Function(AccountRequestCredentials) operation, {
    bool adminOnly = false,
  }) async {
    if (!_current || state.mutating || adminOnly && !admin) return;
    _publish(
      DashboardState(
        period: state.period,
        snapshot: state.snapshot,
        reports: state.reports,
        loading: state.loading,
        mutating: true,
        error: state.error,
      ),
    );
    if (!_current) return;
    var failed = false;
    try {
      final auth = await _auth();
      if (!_current) return;
      await operation(auth);
    } catch (_) {
      failed = true;
    }
    if (_current) {
      _publish(
        DashboardState(
          period: state.period,
          snapshot: state.snapshot,
          reports: state.reports,
          loading: state.loading,
          error: state.error,
          mutationError: failed,
        ),
      );
    }
  }

  @override
  void dispose() {
    _generation++;
    _detach?.call();
    _detach = null;
    super.dispose();
  }
}
