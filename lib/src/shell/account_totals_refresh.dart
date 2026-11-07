part of 'account_activity_controller.dart';

/// Owns refresh sequencing and cooldown for one captured account.
final class _AccountTotalsRefresh {
  _AccountTotalsRefresh(this.controller, this.siteUrl, this.lease);

  final AccountActivityController controller;
  final String siteUrl;
  final SiteLease lease;
  _TotalsRefreshJob? _active;
  _TotalsRefreshJob? _pending;
  DateTime? _attemptedAt;
  void Function()? _detach;
  bool _retired = false;

  bool get isCurrent =>
      !_retired &&
      lease.isCurrent &&
      identical(controller._totalsRefreshes[siteUrl], this);

  void observeRetirement() {
    _detach = lease.onRetire(retire);
  }

  Future<NotificationTotals?> refresh(
    DiscourseInstance instance, {
    required bool force,
  }) {
    if (!isCurrent) return Future.value();
    final active = _active;
    if (active != null) {
      if (!force) return active.result.future;
      final pending = _pending ??= _TotalsRefreshJob(instance);
      pending.instance = instance;
      return pending.result.future;
    }
    final attemptedAt = _attemptedAt;
    if (!force &&
        attemptedAt != null &&
        controller._clock().difference(attemptedAt) <
            controller.minimumRefreshInterval) {
      return Future.value(controller.totalsFor(siteUrl));
    }
    final job = _TotalsRefreshJob(instance);
    _start(job);
    return job.result.future;
  }

  bool _owns(_TotalsRefreshJob job) => isCurrent && identical(_active, job);

  void _start(_TotalsRefreshJob job) {
    _active = job;
    _attemptedAt = controller._clock();
    unawaited(_run(job));
  }

  Future<void> _run(_TotalsRefreshJob job) async {
    NotificationTotals? applied;
    try {
      final owner = controller._reconciliationFor(siteUrl, lease: lease);
      final ticket = owner.beginTotalsRefresh();
      final auth = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(controller.credentials);
      if (!_owns(job) || auth.apiKey == null) return;
      final totals = await auth.run(
        () => controller.api.notificationTotals(
          siteUrl: siteUrl,
          apiKey: auth.apiKey!,
        ),
      );
      if (!_owns(job)) return;
      // Publication may retire the account synchronously. Preserve the accepted
      // result for this caller while suppressing any subsequent account hook.
      job.publishing = true;
      try {
        applied = owner.acceptTotalsRefresh(ticket, totals);
        if (applied != null && _owns(job)) {
          controller.onTotalsLoaded?.call(job.instance, applied);
        }
      } finally {
        job.publishing = false;
      }
    } catch (_) {
      applied = null;
    } finally {
      if (_owns(job)) {
        _active = null;
        final pending = _pending;
        _pending = null;
        if (pending != null) _start(pending);
      }
      if (!job.result.isCompleted) job.result.complete(applied);
    }
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _detach?.call();
    _detach = null;
    if (identical(controller._totalsRefreshes[siteUrl], this)) {
      controller._totalsRefreshes.remove(siteUrl);
    }
    final active = _active;
    final pending = _pending;
    _active = null;
    _pending = null;
    if (active != null && !active.publishing && !active.result.isCompleted) {
      active.result.complete(null);
    }
    if (pending != null && !pending.result.isCompleted) {
      pending.result.complete(null);
    }
  }
}

final class _TotalsRefreshJob {
  _TotalsRefreshJob(this.instance);

  DiscourseInstance instance;
  final result = Completer<NotificationTotals?>();
  bool publishing = false;
}
