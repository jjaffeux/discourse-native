import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/user_ignores_api.dart';
import '../foundation/frame_safe_notifier.dart';
import '../foundation/site_scoped_state.dart';
import '../models/discourse_instance.dart';
import 'account_writes.dart';

/// How long an ignore lasts. Core stores one moment the ignore ends at and has
/// no open-ended ignore, so "forever" is the web client's thousand years.
enum IgnoreDuration {
  oneDay(Duration(days: 1)),
  oneWeek(Duration(days: 7)),
  twoWeeks(Duration(days: 14)),
  oneMonth(Duration(days: 30)),
  threeMonths(Duration(days: 91)),
  sixMonths(Duration(days: 182)),
  oneYear(Duration(days: 365)),
  forever(Duration(days: 365250));

  const IgnoreDuration(this.length);
  final Duration length;
}

/// Told once the site has started or stopped ignoring [username].
typedef IgnoredUserChanged =
    void Function(
      DiscourseInstance instance,
      String username, {
      required bool ignored,
    });

/// Starts and stops ignoring a person for the signed-in reader.
///
/// Ignoring is not part of the Users preference draft: core takes it one
/// person at a time, with an end date, on a route of its own. The state names
/// the person a request is about.
final class IgnoredUsersTransactions extends FrameSafeNotifier
    with AccountScopedState {
  IgnoredUsersTransactions({
    required this.api,
    required ApiCredentialReader credentials,
    required SiteLifecycle lifecycle,
    this.onChanged,
    this.clock = DateTime.now,
  }) {
    _writes = AccountWrites<String>(
      credentials: credentials,
      lifecycle: lifecycle,
      notify: notifySafely,
      isDisposed: () => isDisposed,
    );
  }

  final UserIgnoresApi api;
  final IgnoredUserChanged? onChanged;
  final DateTime Function() clock;
  late final AccountWrites<String> _writes;

  AccountWriteState<String> stateFor(String siteUrl) =>
      _writes.stateFor(siteUrl);

  /// Ignores [username] for [duration], counted from now.
  Future<bool> ignore(
    DiscourseInstance instance,
    String username,
    IgnoreDuration duration,
  ) {
    // Core refuses this as well; asking would only spend a request.
    if (_isReader(instance, username)) return Future.value(false);
    return _writes.run(
      instance,
      username,
      (request, apiKey) => api.ignoreUser(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: request.clientId,
        username: username,
        until: clock().add(duration.length),
      ),
      onAccepted: () => onChanged?.call(instance, username, ignored: true),
    );
  }

  Future<bool> stopIgnoring(DiscourseInstance instance, String username) =>
      _writes.run(
        instance,
        username,
        (request, apiKey) => api.stopIgnoringUser(
          siteUrl: instance.url,
          apiKey: apiKey,
          clientId: request.clientId,
          username: username,
        ),
        onAccepted: () => onChanged?.call(instance, username, ignored: false),
      );

  static bool _isReader(DiscourseInstance instance, String username) =>
      instance.user?.username.toLowerCase() == username.toLowerCase();

  @override
  void forget(String siteUrl) => _writes.retire(siteUrl);

  @override
  void dispose() {
    _writes.retireAll();
    super.dispose();
  }
}
