import '../../data/api_credentials.dart';
import '../../data/discourse_api_contracts.dart';
import '../../data/site_lifecycle.dart';
import '../../data/store.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../../foundation/frame_safe_notifier.dart';
import 'post_reactors.dart';

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
  final Set<String> _loading = {};
  final Map<String, String> _errors = {};

  static String _key(String siteUrl, int postId, String? filter) =>
      '$siteUrl~${PostReactors.key(postId, filter)}';

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
    final key = _key(siteUrl, postId, filter);
    if (!_loading.add(key)) return;
    final lease = lifecycle.capture(siteUrl);
    notifySafely();

    try {
      // Inside the guard, not before it: an unsigned macOS build's keychain can
      // throw rather than answer, and reading it outside would leave this key
      // stranded in `_loading` for the life of the app. The same reason
      // `loadLikers` reads it here.
      final fetched = await api.postReactors(
        siteUrl: siteUrl,
        postId: postId,
        reaction: filter,
        apiKey: await credentials.apiKeyFor(siteUrl),
        clientId: await credentials.clientId(),
      );
      if (isDisposed) return;
      lease.commit(() {
        store.put(siteUrl, fetched);
        _errors.remove(key);
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
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
      if (!isDisposed) {
        lease.commit(() {
          _loading.remove(key);
          notifySafely();
        });
      }
    }
  }

  /// Forgets what was being asked for one site, for a disconnect.
  ///
  /// The lists themselves are the [Store]'s to forget; these are only the
  /// questions in flight. The shell invalidates the shared lifecycle first.
  void forget(String siteUrl) {
    final loadingBefore = _loading.length;
    final errorsBefore = _errors.length;
    _loading.removeWhere((key) => key.startsWith('$siteUrl~'));
    _errors.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    if (_loading.length != loadingBefore || _errors.length != errorsBefore) {
      notifySafely();
    }
  }
}
