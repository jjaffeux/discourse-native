import '../../data/api_credentials.dart';
import '../../data/discourse_api_contracts.dart';
import '../../data/site_lifecycle.dart';
import '../../data/store.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../../foundation/frame_safe_notifier.dart';
import 'post_reactors.dart';

typedef _ReactionRequestKey = ({String siteUrl, int postId, String? filter});

/// Who reacted to what, and whether we are still finding out.
///
/// Its own notifier rather than more state on `ShellController`, the way
/// `UpdateController` and `ComposerController` are: opening one reactor list
/// should redraw that list, not every post in the topic and every badge in the
/// rail. Reached through a `ListenableBuilder`.
///
/// Only the *asking* lives here. The lists themselves go in the [Store] under
/// their own ids, so the panel and the sheet are drawing the same record and
/// one being dismissed does not cost the other its names.
class ReactionsController extends FrameSafeNotifier {
  ReactionsController({
    required this.api,
    required this.credentials,
    required this.store,
    SiteLifecycle? lifecycle,
  }) : lifecycle = lifecycle ?? SiteLifecycle();

  final ReactionsApi api;
  final ApiCredentialReader credentials;
  final Store store;
  final SiteLifecycle lifecycle;

  /// Kept outside the [Store] for the reason the likers' equivalents are: they
  /// are facts about a request, not about a post, and a record that has never
  /// been fetched has nowhere to hold them.
  final Map<_ReactionRequestKey, Object> _requests = {};
  final Map<_ReactionRequestKey, String> _errors = {};

  static _ReactionRequestKey _key(String siteUrl, int postId, String? filter) =>
      (siteUrl: siteUrl, postId: postId, filter: filter);

  /// Who reacted, as far as it has been fetched. Null before the first answer.
  PostReactors? reactors(String siteUrl, int postId, {String? filter}) =>
      store.read<PostReactors>(siteUrl, PostReactors.key(postId, filter));

  String? error(String siteUrl, int postId, {String? filter}) =>
      _errors[_key(siteUrl, postId, filter)];

  /// Fetches who reacted to a post, or who gave it one particular emoji.
  ///
  /// Called on every open rather than once: this is a list of what other people
  /// have just done, and it is cheap to ask again. Whatever was fetched last
  /// time stays on screen while the answer is on its way.
  Future<void> load({
    required String siteUrl,
    required int postId,
    String? filter,
  }) async {
    if (isDisposed) return;
    final key = _key(siteUrl, postId, filter);
    if (_requests.containsKey(key)) return;
    final request = Object();
    final lease = lifecycle.capture(siteUrl);
    _requests[key] = request;
    notifySafely();

    try {
      // Inside the guard, not before it: an unsigned macOS build's keychain can
      // throw rather than answer, and reading it outside would leave this key
      // stranded in `_requests` for the life of the app. The same reason
      // `loadLikers` reads it here.
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (!_canSend(lease, key, request)) return;

      final clientId = await credentials.clientId();
      if (!_canSend(lease, key, request)) return;

      final fetched = await api.postReactors(
        siteUrl: siteUrl,
        postId: postId,
        reaction: filter,
        apiKey: apiKey,
        clientId: clientId,
      );
      if (!_canSend(lease, key, request)) return;
      lease.commit(() {
        store.put(siteUrl, fetched);
        _errors.remove(key);
      });
    } catch (error, stackTrace) {
      if (!_canSend(lease, key, request)) return;
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'reactions.loadUsers',
        source: 'reactions',
        handled: true,
        degraded: true,
      );
      lease.commit(() {
        if (reactors(siteUrl, postId, filter: filter) == null) {
          _errors[key] = 'Could not find out who reacted.';
        }
      });
    } finally {
      if (_isCurrentRequest(key, request)) {
        _requests.remove(key);
        notifySafely();
      }
    }
  }

  /// Forgets what was being asked for one site, for a disconnect.
  ///
  /// The lists themselves are the [Store]'s to forget; these are only the
  /// questions in flight. The shell invalidates the shared lifecycle first.
  void forget(String siteUrl) {
    final requestsBefore = _requests.length;
    final errorsBefore = _errors.length;
    _requests.removeWhere((key, _) => key.siteUrl == siteUrl);
    _errors.removeWhere((key, _) => key.siteUrl == siteUrl);
    if (_requests.length != requestsBefore || _errors.length != errorsBefore) {
      notifySafely();
    }
  }

  bool _canSend(SiteLease lease, _ReactionRequestKey key, Object request) =>
      lease.isCurrent && _isCurrentRequest(key, request);

  bool _isCurrentRequest(_ReactionRequestKey key, Object request) =>
      !isDisposed && identical(_requests[key], request);

  @override
  void dispose() {
    _requests.clear();
    _errors.clear();
    super.dispose();
  }
}
