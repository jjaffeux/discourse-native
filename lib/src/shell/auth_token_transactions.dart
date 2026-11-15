import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/user_auth_tokens_api.dart';
import '../foundation/frame_safe_notifier.dart';
import '../foundation/site_scoped_state.dart';
import '../models/discourse_instance.dart';
import 'account_writes.dart';

/// Told once the site has ended the browser session [tokenId].
typedef AuthTokenRevoked =
    void Function(DiscourseInstance instance, int tokenId);

/// Signs one of the signed-in reader's browser sessions out.
///
/// The state names the session a request is about. This app's own access is a
/// user API key, which is revoked by disconnecting the site and never here.
final class AuthTokenTransactions extends FrameSafeNotifier
    with AccountScopedState {
  AuthTokenTransactions({
    required this.api,
    required ApiCredentialReader credentials,
    required SiteLifecycle lifecycle,
    this.onRevoked,
  }) {
    _writes = AccountWrites<int>(
      credentials: credentials,
      lifecycle: lifecycle,
      notify: notifySafely,
      isDisposed: () => isDisposed,
    );
  }

  final UserAuthTokensApi api;
  final AuthTokenRevoked? onRevoked;
  late final AccountWrites<int> _writes;

  AccountWriteState<int> stateFor(String siteUrl) => _writes.stateFor(siteUrl);

  Future<bool> revoke(DiscourseInstance instance, int tokenId) {
    final username = instance.user?.username;
    if (username == null) return Future.value(false);
    return _writes.run(
      instance,
      tokenId,
      (request, apiKey) => api.revokeAuthToken(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: request.clientId,
        username: username,
        tokenId: tokenId,
      ),
      onAccepted: () => onRevoked?.call(instance, tokenId),
    );
  }

  @override
  void forget(String siteUrl) => _writes.retire(siteUrl);

  @override
  void dispose() {
    _writes.retireAll();
    super.dispose();
  }
}
