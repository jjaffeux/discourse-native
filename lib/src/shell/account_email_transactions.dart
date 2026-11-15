import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/user_email_api.dart';
import '../foundation/frame_safe_notifier.dart';
import '../foundation/site_scoped_state.dart';
import '../models/discourse_instance.dart';
import 'account_writes.dart';

/// Told once the site has mailed a confirmation link for [email].
typedef EmailChangeRequested =
    void Function(DiscourseInstance instance, String email);

/// Asks the site to change the signed-in reader's address.
///
/// The state names the address a request is about and holds it in memory
/// only. An accepted request changes nothing the app shows as the primary
/// address: the site keeps the old one until its confirmation link is
/// followed.
final class AccountEmailTransactions extends FrameSafeNotifier
    with AccountScopedState {
  AccountEmailTransactions({
    required this.api,
    required ApiCredentialReader credentials,
    required SiteLifecycle lifecycle,
    this.onRequested,
  }) {
    _writes = AccountWrites<String>(
      credentials: credentials,
      lifecycle: lifecycle,
      notify: notifySafely,
      isDisposed: () => isDisposed,
    );
  }

  final UserEmailApi api;
  final EmailChangeRequested? onRequested;
  late final AccountWrites<String> _writes;

  AccountWriteState<String> stateFor(String siteUrl) =>
      _writes.stateFor(siteUrl);

  Future<bool> requestChange(DiscourseInstance instance, String email) {
    final address = email.trim();
    final username = instance.user?.username;
    if (address.isEmpty || username == null) return Future.value(false);
    return _writes.run(
      instance,
      address,
      (request, apiKey) => api.requestEmailChange(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: request.clientId,
        username: username,
        email: address,
      ),
      onAccepted: () => onRequested?.call(instance, address),
    );
  }

  /// Clears a finished request's outcome once the reader edits the address.
  void settle(String siteUrl) => _writes.settle(siteUrl);

  @override
  void forget(String siteUrl) => _writes.retire(siteUrl);

  @override
  void dispose() {
    _writes.retireAll();
    super.dispose();
  }
}
