import 'package:discourse_native/l10n/strings.dart';
import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/invites_api.dart';
import '../data/site_lifecycle.dart';

import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/invite.dart';

final class InvitesController extends FrameSafeNotifier {
  InvitesController({
    required this.api,
    required this.credentials,
    required this.instance,
    required SiteLifecycle lifecycle,
  }) : _lease = lifecycle.capture(instance.url);

  final InvitesApi api;
  final ApiCredentialReader credentials;
  final DiscourseInstance instance;
  final SiteLease _lease;

  InviteFilter filter = InviteFilter.pending;
  String search = '';
  List<DiscourseInvite> invites = const [];
  Map<InviteFilter, int> counts = const {};
  bool canSeeDetails = false;
  bool loaded = false;
  bool loading = false;
  bool hasMore = false;
  bool writing = false;
  String? error;
  String? actionError;
  String? message;
  int _offset = 0;
  Object? _request;

  bool get isCurrent => !isDisposed && _lease.isCurrent;
  bool get canInvite => isCurrent && instance.user?.canInviteToForum == true;

  Future<AccountRequestCredentials?> _credentials() async {
    if (!canInvite) return null;
    final auth = await AccountRequestSession(
      instance.url,
      _lease,
    ).credentials(credentials);
    if (!canInvite) return null;
    if (auth.apiKey == null) throw const WriteException(WriteFailure.forbidden);
    return auth;
  }

  Future<void> load({
    InviteFilter? filter,
    String? search,
    bool more = false,
  }) async {
    if (!canInvite || (more && (loading || !hasMore))) return;
    this.filter = filter ?? this.filter;
    this.search = search?.trim() ?? this.search;
    final request = _request = Object();
    final offset = more ? _offset : 0;
    if (!more) {
      invites = const [];
      loaded = false;
      _offset = 0;
      hasMore = false;
    }
    loading = true;
    error = null;
    notifySafely();

    bool current() => isCurrent && identical(_request, request);
    try {
      final auth = await _credentials();
      if (!current() || auth == null) return;
      final page = await auth.run(
        () => api.list(
          siteUrl: instance.url,
          username: instance.user!.username,
          apiKey: auth.apiKey!,
          clientId: auth.clientId,
          filter: this.filter,
          search: this.search,
          offset: offset,
        ),
      );
      if (!current()) return;
      counts = page.counts;
      canSeeDetails = page.canSeeDetails;
      if (page.error != null) {
        error = page.error;
        return;
      } else if (!canSeeDetails && this.filter != InviteFilter.redeemed) {
        await load(filter: InviteFilter.redeemed);
        return;
      } else {
        // Pages are offset windows over recency-ordered rows, so an invite
        // created, resent or redeemed elsewhere between pages repeats a held
        // row. A redeemed row is one user's redemption, so a shared link
        // appears once per user. The held row keeps its place and identity:
        // removal and resend accept only an instance still in the list.
        final rows = more ? [...invites] : <DiscourseInvite>[];
        final seen = {for (final invite in rows) (invite.id, invite.userId)};
        for (final invite in page.invites) {
          if (seen.add((invite.id, invite.userId))) rows.add(invite);
        }
        invites = List.unmodifiable(rows);
        _offset = offset + page.rowCount;
        hasMore =
            page.rowCount > 0 &&
            (this.search.isNotEmpty || _offset < (counts[this.filter] ?? 0));
      }
      loaded = true;
    } catch (exception) {
      if (!current()) return;

      error = appL10n.couldnTLoadInvitesPleaseTryAgain;
    } finally {
      if (current()) {
        loading = false;
        notifySafely();
      }
    }
  }

  Future<DiscourseInvite?> create(InviteDraft draft) {
    if (draft.sendEmail && !instance.config.invites.allowEmail) {
      return Future.value();
    }
    return _write(
      draft.sendEmail ? appL10n.invitationEmailSent : appL10n.inviteLinkCreated,
      (auth) => api.create(
        siteUrl: instance.url,
        apiKey: auth.apiKey!,
        clientId: auth.clientId,
        draft: draft,
      ),
    );
  }

  Future<bool?> remove(DiscourseInvite invite) async {
    if (!invite.canDelete || !invites.contains(invite)) return false;
    return _write(appL10n.inviteRemoved, (auth) async {
      await api.remove(
        siteUrl: instance.url,
        apiKey: auth.apiKey!,
        clientId: auth.clientId,
        inviteId: invite.id,
      );
      return true;
    });
  }

  Future<bool?> resend(DiscourseInvite invite) async {
    if (!invite.canDelete ||
        !invites.contains(invite) ||
        invite.email == null ||
        !instance.config.invites.allowEmail) {
      return false;
    }
    return _write(appL10n.invitationEmailSent, (auth) async {
      await api.resend(
        siteUrl: instance.url,
        apiKey: auth.apiKey!,
        clientId: auth.clientId,
        email: invite.email!,
      );
      return true;
    });
  }

  Future<T?> _write<T>(
    String success,
    Future<T> Function(AccountRequestCredentials auth) action,
  ) async {
    if (!canInvite || writing) return null;
    writing = true;
    actionError = null;
    message = null;
    notifySafely();
    try {
      final auth = await _credentials();
      if (auth == null || !isCurrent) return null;
      final result = await auth.run(() => action(auth));
      if (!isCurrent) return null;
      message = success;
      await load();
      return isCurrent ? result : null;
    } catch (exception) {
      if (!isCurrent) return null;

      actionError = exception is WriteException
          ? exception.message
          : appL10n.couldnTSaveTheInvitePleaseTryAgain;
      return null;
    } finally {
      if (isCurrent) {
        writing = false;
        notifySafely();
      }
    }
  }
}
