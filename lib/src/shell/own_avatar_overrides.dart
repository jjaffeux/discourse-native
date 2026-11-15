import '../data/site_lifecycle.dart';
import '../foundation/frame_safe_notifier.dart';
import '../foundation/site_scoped_state.dart';
import '../models/json.dart';

/// The pictures the signed-in account has replaced from this app, so a row
/// read before the change draws the current one.
///
/// Every loaded post, card and message keeps the avatar URL it was read
/// with. Only a URL resolved from a template this account replaced is
/// redrawn, at the size it was read at: a row read after the change, or a
/// picture changed somewhere else since, is left as the site sent it. The
/// name is checked as well, because a letter avatar's template is shared by
/// everyone with that letter and colour.
///
/// It has its own notifier so a change redraws avatars and nothing else.
final class OwnAvatarOverrides extends FrameSafeNotifier
    with AccountScopedState {
  final Map<String, _ReplacedPictures> _bySite = {};

  /// Records that [username] now draws from the template [current] where it
  /// drew from [previous]. A change accepted for a retired [lease] belongs
  /// to an account that has left, and is dropped.
  void record(
    String siteUrl,
    SiteLease lease, {
    required String username,
    required String? previous,
    required String? current,
  }) {
    if (isDisposed || !lease.isCurrent) return;
    if (previous == null || current == null || previous == current) return;
    final name = username.toLowerCase();
    final held = _bySite[siteUrl];
    final superseded = {
      if (held != null && held.username == name) ...held.superseded,
      previous,
    }..remove(current);
    _bySite[siteUrl] = _ReplacedPictures(name, current, superseded);
    notifySafely();
  }

  /// The URL to draw for [url], read as [username]'s picture on [siteUrl].
  String? urlFor(String siteUrl, String? username, String? url) {
    final held = _bySite[siteUrl];
    if (held == null || url == null || username == null) return url;
    if (username.toLowerCase() != held.username) return url;
    for (final template in held.superseded) {
      final size = _sizeResolvedFrom(template, siteUrl, url);
      if (size != null) {
        return resolveAvatarUrl(held.current, siteUrl, size: size);
      }
    }
    return url;
  }

  @override
  void forget(String siteUrl) {
    if (_bySite.remove(siteUrl) != null && !isDisposed) notifySafely();
  }

  @override
  void dispose() {
    _bySite.clear();
    super.dispose();
  }
}

final class _ReplacedPictures {
  const _ReplacedPictures(this.username, this.current, this.superseded);

  final String username;
  final String current;
  final Set<String> superseded;
}

const _placeholder = '{size}';
final _digits = RegExp(r'^[0-9]+$');

/// The size [url] was resolved at when it came from [template], otherwise
/// null. Resolution only prefixes a template, so what follows the
/// placeholder is unchanged and what precedes it is the same at every size.
int? _sizeResolvedFrom(String template, String siteUrl, String url) {
  final cut = template.indexOf(_placeholder);
  if (cut < 0 || template.indexOf(_placeholder, cut + 1) >= 0) return null;
  final tail = template.substring(cut + _placeholder.length);
  final probe = resolveAvatarUrl(template, siteUrl, size: 0);
  if (probe == null) return null;
  final head = probe.substring(0, probe.length - tail.length - 1);
  if (url.length <= head.length + tail.length ||
      !url.startsWith(head) ||
      !url.endsWith(tail)) {
    return null;
  }
  final size = url.substring(head.length, url.length - tail.length);
  return _digits.hasMatch(size) ? int.tryParse(size) : null;
}
