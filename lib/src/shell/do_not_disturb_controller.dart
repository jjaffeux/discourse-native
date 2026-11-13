import 'dart:async';
import 'dart:io';

import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/do_not_disturb_api.dart';
import '../data/site_lifecycle.dart';
import '../data/write_failure.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/do_not_disturb.dart';

typedef DoNotDisturbCommitted = void Function(String siteUrl, DateTime? until);

final class DoNotDisturbController extends FrameSafeNotifier {
  DoNotDisturbController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.onCommitted,
    this.onSnapshotInvalidated,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DoNotDisturbApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final DoNotDisturbCommitted onCommitted;
  final void Function(String siteUrl)? onSnapshotInvalidated;
  final DateTime Function() _clock;
  final Map<String, _PauseAccount> _accounts = {};

  _PauseAccount? _existingAccount(String siteUrl) {
    final account = _accounts[siteUrl];
    if (account == null || account.isCurrent) return account;
    _retireAccount(account);
    return _accounts[siteUrl];
  }

  _PauseAccount _accountFor(String siteUrl) {
    final held = _existingAccount(siteUrl);
    if (held != null) return held;
    final account = _PauseAccount(this, siteUrl, lifecycle.capture(siteUrl));
    _accounts[siteUrl] = account;
    account.observeRetirement();
    return account;
  }

  void _retireAccount(_PauseAccount account) {
    final changed =
        identical(_accounts[account.siteUrl], account) &&
        (account.snapshot?.until != null || account.request != null);
    account.retire();
    if (changed) notifySafely();
  }

  DoNotDisturbState stateFor(String siteUrl) {
    final account = _existingAccount(siteUrl);
    return DoNotDisturbState(
      until: account?.snapshot?.until,
      saving: account?.request != null,
    );
  }

  void restoreSnapshot(String siteUrl, DateTime? until) {
    if (isDisposed) return;
    final account = _accountFor(siteUrl);
    if (account.protectsRestoration) return;
    _replaceUntil(account, _activeUntil(until), notify: false);
  }

  DateTime? acceptSnapshot(
    String siteUrl,
    DateTime? until, {
    required bool isCurrent,
  }) {
    if (isDisposed) return null;
    final account = isCurrent
        ? _accountFor(siteUrl)
        : _existingAccount(siteUrl);
    if (isCurrent && account?.request == null && account != null) {
      _replaceUntil(account, _activeUntil(until));
    }
    return _existingAccount(siteUrl)?.snapshot?.until;
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
    if (isDisposed) return null;
    final account = _accountFor(siteUrl);
    if (account.request != null) {
      return appL10n.anotherNotificationChangeIsStillFinishing;
    }

    final request = Object();
    final revision = ++account.revision;
    final wasRestorationProtected = account.protectsRestoration;
    var confirmed = false;
    account.protectsRestoration = true;
    account.request = request;
    account.timer?.cancel();
    account.timer = null;
    bool isCurrent() =>
        account.isCurrent && identical(account.request, request);

    onSnapshotInvalidated?.call(siteUrl);
    if (!isCurrent()) return null;
    notifySafely();
    if (!isCurrent()) return null;
    try {
      final auth = await AccountRequestSession(
        siteUrl,
        account.lease,
      ).credentials(credentials);
      final apiKey = auth.apiKey;
      if (!isCurrent()) return null;
      if (apiKey == null) {
        return const WriteException(WriteFailure.forbidden).message;
      }
      final dispatchedRevision = account.revision;
      final until = await auth.run(() => send(apiKey, auth.clientId));
      if (!isCurrent()) return null;

      confirmed = true;
      // Live changes received after dispatch outrank the response snapshot.
      if (account.revision == dispatchedRevision) {
        _replaceUntil(account, _activeUntil(until), committed: true);
      }
      return null;
    } on WriteException catch (error) {
      return isCurrent() ? error.message : null;
    } catch (_) {
      return isCurrent()
          ? const WriteException(WriteFailure.unreachable).message
          : null;
    } finally {
      if (isCurrent()) {
        onSnapshotInvalidated?.call(siteUrl);
        // The hook may synchronously retire this account and start a successor.
        if (isCurrent()) {
          if (!confirmed &&
              !wasRestorationProtected &&
              account.revision == revision) {
            account.protectsRestoration = false;
          }
          account.request = null;
          _schedule(account);
          notifySafely();
        }
      }
    }
  }

  void applyMessage(String siteUrl, Object? data) {
    if (isDisposed ||
        data is! Map<Object?, Object?> ||
        !data.containsKey('ends_at')) {
      return;
    }
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

    final account = _accountFor(siteUrl);
    account.protectsRestoration = true;
    final revision = ++account.revision;
    onSnapshotInvalidated?.call(siteUrl);
    if (account.revision == revision) {
      _replaceUntil(account, _activeUntil(until), committed: true);
    }
  }

  void checkExpirations() {
    for (final account in _accounts.values.toList()) {
      _expireOrTick(account);
    }
  }

  void forget(String siteUrl) {
    final account = _accounts[siteUrl];
    if (account != null) _retireAccount(account);
  }

  DateTime? _activeUntil(DateTime? until) =>
      until?.isAfter(_clock()) == true ? until!.toUtc() : null;

  void _replaceUntil(
    _PauseAccount account,
    DateTime? until, {
    bool committed = false,
    bool notify = true,
  }) {
    if (!account.isCurrent) return;
    final normalized = until?.toUtc();
    final changed =
        account.snapshot == null || account.snapshot?.until != normalized;
    account.snapshot = (until: normalized);
    _schedule(account);
    if (committed && changed) onCommitted(account.siteUrl, normalized);
    if (notify && changed && account.isCurrent) notifySafely();
  }

  void _schedule(_PauseAccount account) {
    if (!account.isCurrent) return;
    account.timer?.cancel();
    account.timer = null;
    if (account.request != null) return;
    final until = account.snapshot?.until;
    if (until == null || isEternalDoNotDisturb(until)) return;
    final remaining = until.difference(_clock());
    if (remaining <= Duration.zero) {
      late final Timer timer;
      timer = Timer(Duration.zero, () {
        if (!account.isCurrent || !identical(account.timer, timer)) return;
        account.timer = null;
        _expireOrTick(account);
      });
      account.timer = timer;
      return;
    }
    final wait = remaining < const Duration(minutes: 1)
        ? remaining
        : const Duration(minutes: 1);
    final expiresOnFire = wait == remaining;
    late final Timer timer;
    timer = Timer(wait, () {
      if (!account.isCurrent || !identical(account.timer, timer)) return;
      account.timer = null;
      if (expiresOnFire &&
          account.request == null &&
          account.snapshot?.until == until) {
        // Timers are monotonic; wall clocks and background suspension are not.
        _expire(account);
      } else {
        _expireOrTick(account);
      }
    });
    account.timer = timer;
  }

  void _expireOrTick(_PauseAccount account) {
    if (!account.isCurrent || account.request != null) return;
    final until = account.snapshot?.until;
    if (until == null || isEternalDoNotDisturb(until)) return;
    if (!until.isAfter(_clock())) {
      _expire(account);
      return;
    }
    notifySafely();
    _schedule(account);
  }

  void _expire(_PauseAccount account) {
    account.protectsRestoration = true;
    final revision = ++account.revision;
    onSnapshotInvalidated?.call(account.siteUrl);
    if (account.revision == revision) {
      _replaceUntil(account, null, committed: true);
    }
  }

  DateTime? _parseDate(String value) {
    if (value.length > 64) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso.toUtc();
    try {
      return HttpDate.parse(value).toUtc();
    } on HttpException {
      return null;
    }
  }

  @override
  void dispose() {
    final accounts = _accounts.values.toList();
    _accounts.clear();
    for (final account in accounts) {
      account.retire();
    }
    super.dispose();
  }
}

final class _PauseAccount {
  _PauseAccount(this.controller, this.siteUrl, this.lease);

  final DoNotDisturbController controller;
  final String siteUrl;
  final SiteLease lease;
  ({DateTime? until})? snapshot;
  Object? request;
  int revision = 0;
  bool protectsRestoration = false;
  Timer? timer;
  void Function()? _detach;
  bool _retired = false;

  bool get isCurrent =>
      !_retired &&
      lease.isCurrent &&
      identical(controller._accounts[siteUrl], this);

  void observeRetirement() =>
      _detach = lease.onRetire(() => controller._retireAccount(this));

  void retire() {
    if (_retired) return;
    _retired = true;
    _detach?.call();
    _detach = null;
    if (identical(controller._accounts[siteUrl], this)) {
      controller._accounts.remove(siteUrl);
    }
    timer?.cancel();
    timer = null;
    request = null;
    snapshot = null;
  }
}
