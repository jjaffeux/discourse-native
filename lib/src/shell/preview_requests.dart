import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/user_card.dart';

part 'preview_loading.dart';

/// Which on-demand previews of one kind (a profile card, a post's likers) are
/// being fetched on each site, and why the last fetch of each failed.
///
/// Hovering a name or a like count starts one of these fetches, so this state
/// has its own notifier rather than the shell's: an open preview listens to
/// it beside its record's store ref, and nothing else on screen redraws.
final class PreviewRequests<K extends Object> extends FrameSafeNotifier {
  final Map<String, Set<K>> _pending = {};
  final Map<String, Map<K, String>> _errors = {};

  bool isPending(String siteUrl, K key) =>
      _pending[siteUrl]?.contains(key) ?? false;

  String? errorFor(String siteUrl, K key) => _errors[siteUrl]?[key];

  /// Marks [key] as fetching and drops its last failure. Answers false, and
  /// changes nothing, while a fetch of it is already running.
  bool begin(String siteUrl, K key) {
    if (isDisposed || isPending(siteUrl, key)) return false;
    _pending.putIfAbsent(siteUrl, () => {}).add(key);
    _removeError(siteUrl, key);
    notifySafely();
    return true;
  }

  /// Ends the fetch of [key], recording [error] as why it failed. A fetch
  /// whose site was forgotten meanwhile records nothing.
  void finish(String siteUrl, K key, {String? error}) {
    final pending = _pending[siteUrl];
    if (isDisposed || pending == null || !pending.remove(key)) return;
    if (pending.isEmpty) _pending.remove(siteUrl);
    if (error != null) _errors.putIfAbsent(siteUrl, () => {})[key] = error;
    notifySafely();
  }

  void forget(String siteUrl) {
    _clearSite(siteUrl)?.call();
  }

  void Function()? _clearSite(String siteUrl) {
    final hadPending = _pending.remove(siteUrl) != null;
    final hadErrors = _errors.remove(siteUrl) != null;
    return hadPending || hadErrors ? notifySafely : null;
  }

  void _removeError(String siteUrl, K key) {
    final errors = _errors[siteUrl];
    if (errors == null || errors.remove(key) == null) return;
    if (errors.isEmpty) _errors.remove(siteUrl);
  }

  @override
  void dispose() {
    _pending.clear();
    _errors.clear();
    super.dispose();
  }
}
