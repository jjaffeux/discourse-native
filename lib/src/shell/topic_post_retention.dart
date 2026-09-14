import '../foundation/frame_safe_notifier.dart';

/// Bounds recently viewed post trees kept alive by the topic's lazy sliver.
///
/// HTML length is a cost proxy, not a measurement of retained heap bytes.
/// Large posts have an additional row limit; a post exceeding the whole budget
/// remains recyclable. Small replies benefit from reuse on direction changes too.
final class TopicPostRetention extends FrameSafeNotifier {
  TopicPostRetention({
    this.maxPosts = 24,
    this.maxLargePosts = 3,
    this.maxCharacters = 256 * 1024,
  }) : assert(maxLargePosts >= 0);

  final int maxPosts;
  final int maxLargePosts;
  final int maxCharacters;
  final Map<Object, ({int characters, bool large})> _entries = {};
  int _characters = 0;
  int _largePosts = 0;

  bool contains(Object owner) => _entries.containsKey(owner);

  void retain(Object owner, int characters, {bool large = false}) {
    final entry = (characters: characters, large: large);
    if (isDisposed || _entries[owner] == entry) return;
    final wasRetained = contains(owner);
    release(owner);
    if (characters <= 0 ||
        characters > maxCharacters ||
        maxPosts <= 0 ||
        (large && maxLargePosts <= 0)) {
      if (wasRetained) notifySafely();
      return;
    }
    _entries[owner] = entry;
    _characters += characters;
    if (large) _largePosts++;
    while (_largePosts > maxLargePosts) {
      release(_entries.entries.firstWhere((entry) => entry.value.large).key);
    }
    while (_entries.length > maxPosts || _characters > maxCharacters) {
      release(_entries.keys.first);
    }
    // Admission can evict a sibling during sliver layout. Keep-alive listeners
    // must release that sibling after the frame, not dirty its tree mid-build.
    notifySafely();
  }

  void touch(Object owner) {
    final entry = _entries.remove(owner);
    if (entry != null) _entries[owner] = entry;
  }

  void release(Object owner) {
    final entry = _entries.remove(owner);
    if (entry == null) return;
    _characters -= entry.characters;
    if (entry.large) _largePosts--;
  }

  void clear() {
    _entries.clear();
    _characters = 0;
    _largePosts = 0;
    notifySafely();
  }
}
