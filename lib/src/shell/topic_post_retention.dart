import '../foundation/frame_safe_notifier.dart';

/// Bounds the long post trees kept alive by a topic's existing lazy sliver.
///
/// HTML length is a cost proxy, not a measurement of retained heap bytes.
/// Ordinary rows and posts exceeding the whole budget remain recyclable.
final class TopicPostRetention extends FrameSafeNotifier {
  TopicPostRetention({this.maxPosts = 3, this.maxCharacters = 256 * 1024});

  final int maxPosts;
  final int maxCharacters;
  final Map<Object, int> _entries = {};
  int _characters = 0;

  bool contains(Object owner) => _entries.containsKey(owner);

  void retain(Object owner, int characters) {
    if (isDisposed || _entries[owner] == characters) return;
    final wasRetained = contains(owner);
    release(owner);
    if (characters <= 0 || characters > maxCharacters || maxPosts <= 0) {
      if (wasRetained) notifySafely();
      return;
    }
    _entries[owner] = characters;
    _characters += characters;
    while (_entries.length > maxPosts || _characters > maxCharacters) {
      release(_entries.keys.first);
    }
    // Admission can evict a sibling during sliver layout. Keep-alive listeners
    // must release that sibling after the frame, not dirty its tree mid-build.
    notifySafely();
  }

  void touch(Object owner) {
    final characters = _entries.remove(owner);
    if (characters != null) _entries[owner] = characters;
  }

  void release(Object owner) {
    _characters -= _entries.remove(owner) ?? 0;
  }

  void clear() {
    _entries.clear();
    _characters = 0;
    notifySafely();
  }
}
