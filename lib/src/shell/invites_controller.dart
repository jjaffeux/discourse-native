import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/invites_api.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/invite.dart';

typedef _InviteCredentials = ({String apiKey, String clientId});

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

  Future<_InviteCredentials?> _credentials() async {
    if (!canInvite) return null;
    final key = await credentials.apiKeyFor(instance.url);
    if (!canInvite) return null;
    if (key == null) throw const WriteException(WriteFailure.forbidden);
    final clientId = await credentials.clientId();
    if (!canInvite) return null;
    return (apiKey: key, clientId: clientId);
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
      final page = await api.list(
        siteUrl: instance.url,
        username: instance.user!.username,
        apiKey: auth.apiKey,
        clientId: auth.clientId,
        filter: this.filter,
        search: this.search,
        offset: offset,
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
        invites = List.unmodifiable([if (more) ...invites, ...page.invites]);
        _offset = offset + page.rowCount;
        hasMore =
            page.rowCount > 0 &&
            (this.search.isNotEmpty || _offset < (counts[this.filter] ?? 0));
      }
      loaded = true;
    } catch (exception, stackTrace) {
      if (!current()) return;
      _report(exception, stackTrace, 'invites.load');
      error = "Couldn't load invites. Please try again.";
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
      'invites.create',
      draft.sendEmail ? 'Invitation email sent.' : 'Invite link created.',
      (auth) => api.create(
        siteUrl: instance.url,
        apiKey: auth.apiKey,
        clientId: auth.clientId,
        draft: draft,
      ),
    );
  }

  Future<bool?> remove(DiscourseInvite invite) async {
    if (!invite.canDelete || !invites.contains(invite)) return false;
    return _write('invites.remove', 'Invite removed.', (auth) async {
      await api.remove(
        siteUrl: instance.url,
        apiKey: auth.apiKey,
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
    return _write('invites.resend', 'Invitation email sent.', (auth) async {
      await api.resend(
        siteUrl: instance.url,
        apiKey: auth.apiKey,
        clientId: auth.clientId,
        email: invite.email!,
      );
      return true;
    });
  }

  Future<T?> _write<T>(
    String operation,
    String success,
    Future<T> Function(_InviteCredentials auth) action,
  ) async {
    if (!canInvite || writing) return null;
    writing = true;
    actionError = null;
    message = null;
    notifySafely();
    try {
      final auth = await _credentials();
      if (auth == null || !isCurrent) return null;
      final result = await action(auth);
      if (!isCurrent) return null;
      message = success;
      await load();
      return isCurrent ? result : null;
    } catch (exception, stackTrace) {
      if (!isCurrent) return null;
      _report(exception, stackTrace, operation);
      actionError = exception is WriteException
          ? exception.message
          : "Couldn't save the invite. Please try again.";
      return null;
    } finally {
      if (isCurrent) {
        writing = false;
        notifySafely();
      }
    }
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'network',
      handled: true,
      degraded: true,
    );
  }
}
