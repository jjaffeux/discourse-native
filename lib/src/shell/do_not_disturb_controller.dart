import 'dart:async';
import 'dart:io';

import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/do_not_disturb.dart';

typedef DoNotDisturbCommitted = void Function(String siteUrl, DateTime? until);

final class DoNotDisturbController extends FrameSafeNotifier {
  DoNotDisturbController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.onCommitted,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DoNotDisturbApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final DoNotDisturbCommitted onCommitted;
  final DateTime Function() _clock;

  final Map<String, DateTime?> _untilBySite = {};
  final Map<String, Object> _requests = {};
  final Map<String, int> _revisions = {};
  final Set<String> _locallyAuthoritative = {};
  final Map<String, Timer> _expiryTimers = {};

  DoNotDisturbState stateFor(String siteUrl) => DoNotDisturbState(
    until: _untilBySite[siteUrl],
    saving: _requests.containsKey(siteUrl),
  );

  void restoreSnapshot(String siteUrl, DateTime? until) {
    if (_locallyAuthoritative.contains(siteUrl)) return;
    _replaceUntil(siteUrl, _activeUntil(until), notify: false);
  }

  DateTime? acceptSnapshot(String siteUrl, DateTime? until) {
    if (!_locallyAuthoritative.contains(siteUrl)) {
      _replaceUntil(siteUrl, _activeUntil(until));
    }
    return _untilBySite[siteUrl];
  }

  Future<String?> pause(String siteUrl, DoNotDisturbDuration duration) =>
      _write(siteUrl, (apiKey, clientId) {
        return api.enterDoNotDisturb(
          siteUrl: siteUrl,
          apiKey: apiKey,
          duration: duration,
          clientId: clientId,
        );
      });

  Future<String?> resume(String siteUrl) async {
    if (!stateFor(siteUrl).isActiveAt(_clock())) return null;
    return _write(siteUrl, (apiKey, clientId) async {
      await api.leaveDoNotDisturb(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
      );
      return null;
    });
  }

  Future<String?> _write(
    String siteUrl,
    Future<DateTime?> Function(String apiKey, String clientId) send,
  ) async {
    if (_requests.containsKey(siteUrl)) {
      return 'Another notification change is still finishing.';
    }

    final request = Object();
    final lease = lifecycle.capture(siteUrl);
    final revision = _bumpRevision(siteUrl);
    _locallyAuthoritative.add(siteUrl);
    _requests[siteUrl] = request;
    _expiryTimers.remove(siteUrl)?.cancel();
    notifySafely();

    bool isCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_requests[siteUrl], request);

    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (!isCurrent()) return null;
      if (apiKey == null) {
        return const WriteException(WriteFailure.forbidden).message;
      }
      final clientId = await credentials.clientId();
      if (!isCurrent()) return null;
      final until = await send(apiKey, clientId);
      if (!isCurrent()) return null;

      // A MessageBus delivery received after this write began is newer than
      // the response snapshot, including one produced by another session.
      if (_revisions[siteUrl] == revision) {
        _replaceUntil(siteUrl, _activeUntil(until), committed: true);
      }
      return null;
    } on WriteException catch (error) {
      return isCurrent() ? error.message : null;
    } catch (error, stackTrace) {
      if (!isCurrent()) return null;
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'doNotDisturb.write',
        source: 'shell',
        handled: true,
        degraded: true,
      );
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_requests[siteUrl], request)) {
        _requests.remove(siteUrl);
        _schedule(siteUrl);
        if (!isDisposed) notifySafely();
      }
    }
  }

  void applyMessage(String siteUrl, Object? data) {
    if (data is! Map<Object?, Object?> || !data.containsKey('ends_at')) return;
    final rawUntil = data['ends_at'];
    final DateTime? until;
    if (rawUntil == null) {
      until = null;
    } else if (rawUntil case final String value) {
      until = _parseDate(value);
      if (until == null) return;
    } else {
      return;
    }

    _locallyAuthoritative.add(siteUrl);
    _bumpRevision(siteUrl);
    _replaceUntil(siteUrl, _activeUntil(until), committed: true);
  }

  void checkExpirations() {
    for (final siteUrl in List<String>.of(_untilBySite.keys)) {
      _expireOrTick(siteUrl);
    }
  }

  void forget(String siteUrl) {
    final changed =
        _untilBySite.remove(siteUrl) != null ||
        _requests.remove(siteUrl) != null;
    _locallyAuthoritative.remove(siteUrl);
    _revisions.remove(siteUrl);
    _expiryTimers.remove(siteUrl)?.cancel();
    if (changed && !isDisposed) notifySafely();
  }

  int _bumpRevision(String siteUrl) =>
      _revisions.update(siteUrl, (revision) => revision + 1, ifAbsent: () => 1);

  DateTime? _activeUntil(DateTime? until) =>
      until?.isAfter(_clock()) == true ? until!.toUtc() : null;

  void _replaceUntil(
    String siteUrl,
    DateTime? until, {
    bool committed = false,
    bool notify = true,
  }) {
    final normalized = until?.toUtc();
    final present = _untilBySite.containsKey(siteUrl);
    final changed = !present || _untilBySite[siteUrl] != normalized;
    _untilBySite[siteUrl] = normalized;
    _schedule(siteUrl);
    if (committed && changed) onCommitted(siteUrl, normalized);
    if (notify && changed && !isDisposed) notifySafely();
  }

  void _schedule(String siteUrl) {
    _expiryTimers.remove(siteUrl)?.cancel();
    if (_requests.containsKey(siteUrl)) return;
    final until = _untilBySite[siteUrl];
    if (until == null || isEternalDoNotDisturb(until)) return;
    final remaining = until.difference(_clock());
    if (remaining <= Duration.zero) {
      _expiryTimers[siteUrl] = Timer(Duration.zero, () {
        _expiryTimers.remove(siteUrl);
        _expireOrTick(siteUrl);
      });
      return;
    }
    final wait = remaining < const Duration(minutes: 1)
        ? remaining
        : const Duration(minutes: 1);
    final scheduledUntil = until;
    final expiresOnFire = wait == remaining;
    _expiryTimers[siteUrl] = Timer(wait, () {
      _expiryTimers.remove(siteUrl);
      if (expiresOnFire &&
          !isDisposed &&
          !_requests.containsKey(siteUrl) &&
          _untilBySite[siteUrl] == scheduledUntil) {
        // A Timer is monotonic while DateTime is wall-clock based. Clearing at
        // the exact scheduled boundary also keeps expiry deterministic under
        // Flutter's fake clock; foreground reconciliation still handles clock
        // changes and timers suspended by the operating system.
        _expire(siteUrl);
      } else {
        _expireOrTick(siteUrl);
      }
    });
  }

  void _expireOrTick(String siteUrl) {
    if (isDisposed || _requests.containsKey(siteUrl)) return;
    final until = _untilBySite[siteUrl];
    if (until == null || isEternalDoNotDisturb(until)) return;
    if (!until.isAfter(_clock())) {
      _expire(siteUrl);
      return;
    }
    notifySafely();
    _schedule(siteUrl);
  }

  void _expire(String siteUrl) {
    _locallyAuthoritative.add(siteUrl);
    _bumpRevision(siteUrl);
    _replaceUntil(siteUrl, null, committed: true);
  }

  DateTime? _parseDate(String value) {
    if (value.length > 64) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso.toUtc();
    try {
      return HttpDate.parse(value).toUtc();
    } on FormatException {
      return null;
    }
  }

  @override
  void dispose() {
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    _expiryTimers.clear();
    _requests.clear();
    super.dispose();
  }
}
