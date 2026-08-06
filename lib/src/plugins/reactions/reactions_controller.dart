import 'package:flutter/foundation.dart';

import '../../data/authenticator.dart';
import '../../data/discourse_api.dart';
import '../../data/store.dart';
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
class ReactionsController extends ChangeNotifier {
  ReactionsController({
    required this.api,
    required this.authenticator,
    required this.store,
  });

  final DiscourseApi api;
  final Authenticator authenticator;
  final Store store;

  /// Kept outside the [Store] for the reason the likers' equivalents are: they
  /// are facts about a request, not about a post, and a record that has never
  /// been fetched has nowhere to hold them.
  final Set<String> _loading = {};
  final Map<String, String> _errors = {};

  /// Bumped per site on [forget], so a fetch in flight when a site was
  /// disconnected can tell on arrival that the store it fetched for has been
  /// emptied since, and put nothing back into it.
  final Map<String, int> _siteEpochs = {};

  int _siteEpoch(String siteUrl) => _siteEpochs[siteUrl] ?? 0;

  bool _disposed = false;

  static String _key(String siteUrl, int postId, String? filter) =>
      '$siteUrl~${PostReactors.key(postId, filter)}';

  /// Who reacted, as far as it has been fetched. Null before the first answer.
  PostReactors? reactors(String siteUrl, int postId, {String? filter}) =>
      store.read<PostReactors>(siteUrl, PostReactors.key(postId, filter));

  bool isLoading(String siteUrl, int postId, {String? filter}) =>
      _loading.contains(_key(siteUrl, postId, filter));

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
    final epoch = _siteEpoch(siteUrl);
    _notify();

    try {
      // Inside the guard, not before it: an unsigned macOS build's keychain can
      // throw rather than answer, and reading it outside would leave this key
      // stranded in `_loading` for the life of the app. The same reason
      // `loadLikers` reads it here.
      final fetched = await api.postReactors(
        siteUrl: siteUrl,
        postId: postId,
        reaction: filter,
        apiKey: await authenticator.apiKeyFor(siteUrl),
        clientId: await authenticator.clientId(),
      );
      // A disconnect in flight empties the store; the epoch says whether one
      // happened while this was away.
      if (_disposed || epoch != _siteEpoch(siteUrl)) return;
      store.put(siteUrl, fetched);
      _errors.remove(key);
    } catch (_) {
      if (_disposed || epoch != _siteEpoch(siteUrl)) return;
      // Names already on screen are better than an error where they were: they
      // were true a moment ago, and the next open asks again.
      if (reactors(siteUrl, postId, filter: filter) == null) {
        _errors[key] = 'Could not find out who reacted.';
      }
    } finally {
      _loading.remove(key);
      _notify();
    }
  }

  /// Forgets what was being asked for one site, for a disconnect.
  ///
  /// The lists themselves are the [Store]'s to forget; these are only the
  /// questions in flight. Bumping the epoch is what tells an answer still on
  /// its way that it arrives too late.
  void forget(String siteUrl) {
    _loading.removeWhere((key) => key.startsWith('$siteUrl~'));
    _errors.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _siteEpochs[siteUrl] = _siteEpoch(siteUrl) + 1;
  }

  /// No scheduler-phase guard, unlike `ShellController._notify`. Everything
  /// here is reached from a completed request or a hover timer, never from
  /// inside a layout pass — there is no scroll handler in this class to be
  /// dispatched from one.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
