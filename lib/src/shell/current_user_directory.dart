import '../data/current_user_reconciler.dart';
import '../data/current_user_refresh.dart';
import '../data/site_lifecycle.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import 'user_status_overrides.dart';

final class CurrentUserDirectory {
  CurrentUserDirectory({
    required this.lifecycle,
    required this.statuses,
    required this._canAcceptCurrentUser,
    required this._instanceAt,
    required this._readSessionUser,
    required this._acceptDoNotDisturbSnapshot,
    required this._publishFreshCurrentUser,
  });

  final SiteLifecycle lifecycle;
  final UserStatusOverrides statuses;
  final bool Function(String siteUrl) _canAcceptCurrentUser;
  final DiscourseInstance? Function(String siteUrl) _instanceAt;
  final Future<DiscourseUser?> Function(
    String siteUrl,
    String apiKey,
    SiteLease lease,
  )
  _readSessionUser;
  final DiscourseUser Function(
    String siteUrl,
    DiscourseUser user, {
    required bool isCurrent,
  })
  _acceptDoNotDisturbSnapshot;
  final bool Function(
    String siteUrl,
    SiteLease lease,
    DiscourseInstance previous,
    CurrentUserReconciliation accepted,
  )
  _publishFreshCurrentUser;
  final Map<String, _CurrentUserAccount> _accounts = {};
  bool _disposed = false;

  _CurrentUserAccount _accountFor(String siteUrl, [SiteLease? lease]) {
    final held = _accounts[siteUrl];
    if (held != null && held.isCurrent) return held;
    held?.retire();
    final session = lease ?? lifecycle.capture(siteUrl);
    final account = _CurrentUserAccount(
      session,
      CurrentUserReconciler(
        lease: session,
        statuses: statuses.reconcilerFor(siteUrl),
      ),
    );
    _accounts[siteUrl] = account;
    account.detach = session.onRetire(() {
      account.retire();
      if (identical(_accounts[siteUrl], account)) {
        _accounts.remove(siteUrl);
        statuses.forget(siteUrl);
      }
    });
    return account;
  }

  CurrentUserReconciler reconcilerFor(String siteUrl) =>
      _accountFor(siteUrl).reconciler;

  bool isFresh(String siteUrl) {
    final account = _accounts[siteUrl];
    return !_disposed && account != null && account.isCurrent && account.fresh;
  }

  DiscourseUser? freshUserFor(String siteUrl) =>
      isFresh(siteUrl) ? _instanceAt(siteUrl)?.user : null;

  void markConnectedUserFresh(String siteUrl, SiteLease lease) {
    if (_disposed || !lifecycle.owns(siteUrl, lease)) return;
    _accountFor(siteUrl, lease).confirmation = Object();
  }

  Future<DiscourseUser?> refresh(
    String siteUrl,
    String apiKey, {
    SiteLease? lease,
    bool force = false,
  }) {
    if (_disposed || _instanceAt(siteUrl) == null) return Future.value();
    final session = lease ?? lifecycle.capture(siteUrl);
    if (!lifecycle.owns(siteUrl, session)) return Future.value();
    final account = _accountFor(siteUrl, session);
    if (!force && account.fresh) {
      return Future.value(_instanceAt(siteUrl)?.user);
    }
    final refresh = account.refresh ??= CurrentUserRefresh(
      lease: account.lease,
      read: () async {
        final ticket = account.reconciler.beginSnapshot();
        final user = await _readSessionUser(siteUrl, apiKey, account.lease);
        return user == null
            ? null
            : acceptSnapshot(siteUrl, user, account.lease, ticket);
      },
    );
    return refresh.request(force: force);
  }

  DiscourseUser? acceptSnapshot(
    String siteUrl,
    DiscourseUser response,
    SiteLease lease,
    CurrentUserSnapshot ticket,
  ) {
    final account = _accounts[siteUrl];
    bool ownsAcceptance() =>
        !_disposed &&
        account != null &&
        account.isCurrent &&
        lease.isCurrent &&
        identical(account.lease.session, lease.session) &&
        identical(_accounts[siteUrl], account) &&
        _canAcceptCurrentUser(siteUrl);

    if (!ownsAcceptance()) return null;
    final user = _acceptDoNotDisturbSnapshot(
      siteUrl,
      response,
      isCurrent: account!.reconciler.doNotDisturbIsCurrent(ticket),
    );
    if (!ownsAcceptance()) return null;
    DiscourseUser? committed;
    lease.commit(() {
      final previous = _instanceAt(siteUrl);
      if (!ownsAcceptance() || previous == null) return;
      final accepted = account.reconciler.reconcile(
        ticket,
        previous: previous.user,
        incoming: user,
      );
      if (accepted == null || !ownsAcceptance()) return;
      final previousConfirmation = account.confirmation;
      final confirmation = Object();
      account.confirmation = confirmation;
      var published = false;
      try {
        published = _publishFreshCurrentUser(
          siteUrl,
          lease,
          previous,
          accepted,
        );
        if (published) {
          committed = accepted.user;
          if (accepted.statusChanged && ownsAcceptance()) {
            statuses.snapshotAccepted();
          }
        }
      } finally {
        if (!published &&
            account.isCurrent &&
            identical(account.confirmation, confirmation)) {
          account.confirmation = previousConfirmation;
        }
      }
    });
    return committed;
  }

  void forget(String siteUrl) => _accounts.remove(siteUrl)?.retire();

  void dispose() {
    _disposed = true;
    for (final account in _accounts.values.toList()) {
      account.retire();
    }
    _accounts.clear();
  }
}

final class _CurrentUserAccount {
  _CurrentUserAccount(this.lease, this.reconciler);

  final SiteLease lease;
  final CurrentUserReconciler reconciler;
  CurrentUserRefresh? refresh;
  Object? confirmation;
  bool get fresh => confirmation != null;
  bool _retired = false;
  void Function()? detach;

  bool get isCurrent => !_retired && lease.isCurrent;

  void retire() {
    if (_retired) return;
    _retired = true;
    detach?.call();
    detach = null;
    refresh?.retire();
    reconciler.retire();
    confirmation = null;
  }
}
