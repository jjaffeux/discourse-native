import 'discourse_user.dart';
import 'json.dart';
import 'live_refresh_id.dart';

/// Personalizes public topic events before they enter the counter snapshot or
/// announce themselves as arrivals on the reader's topic lists.
final class TopicTrackingMessageFilter {
  TopicTrackingMessageFilter({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const _hintLifetime = Duration(seconds: 60);
  static const _maxHintedTopics = 5000;

  final DateTime Function() _clock;
  final Map<int, DateTime> _unmutedUntil = {};
  final Map<int, DateTime> _mutedUntil = {};

  bool accepts(Object? value, {DiscourseUser? user}) {
    if (value is! Map) return false;
    final type = value['message_type'];
    final topicId = liveRefreshId(value['topic_id']);
    _recordHint(type, topicId);
    if (type == 'unmuted') return false;
    if (type != 'new_topic') return true;
    if (topicId == null) return false;
    return !_inMutedCategory(value, user) || _unmutedUntil.containsKey(topicId);
  }

  /// Whether a `/latest` or `/new` message may count as a topic arriving on
  /// the reader's Latest or New list. The server removes muted topics and
  /// muted categories from those lists, so an arrival it will not return
  /// must not be announced. Like core, this drops a topic named by a `muted`
  /// hint in the last minute, and one in a muted category unless an
  /// `unmuted` hint let it back in.
  ///
  /// Records hints exactly as [accepts] does, and recording the same message
  /// twice is harmless, so both paths may see every message.
  bool admitsIncoming(Object? value, {DiscourseUser? user}) {
    if (value is! Map) return false;
    final type = value['message_type'];
    final topicId = liveRefreshId(value['topic_id']);
    _recordHint(type, topicId);
    if (type != 'new_topic' && type != 'latest') return true;
    if (topicId == null) return false;
    if (_mutedUntil.containsKey(topicId)) return false;
    return !_inMutedCategory(value, user) || _unmutedUntil.containsKey(topicId);
  }

  void _recordHint(Object? type, int? topicId) {
    final now = _clock();
    _unmutedUntil.removeWhere((_, expiry) => !expiry.isAfter(now));
    _mutedUntil.removeWhere((_, expiry) => !expiry.isAfter(now));
    switch (type) {
      case 'unmuted':
        // Core targets this hint using topic, category and tag preferences.
        // A category's watched/tracked lists cannot reconstruct that decision.
        _refresh(_unmutedUntil, topicId, now);
      case 'muted':
        // A reader who muted the topic but follows its category or tags gets
        // both hints, in either order; core lets the muted one win.
        _unmutedUntil.remove(topicId);
        _refresh(_mutedUntil, topicId, now);
      case 'destroy':
        _unmutedUntil.remove(topicId);
    }
  }

  void _refresh(Map<int, DateTime> hints, int? topicId, DateTime now) {
    if (topicId == null) return;
    hints.remove(topicId);
    hints[topicId] = now.add(_hintLifetime);
    if (hints.length > _maxHintedTopics) hints.remove(hints.keys.first);
  }

  static bool _inMutedCategory(
    Map<Object?, Object?> value,
    DiscourseUser? user,
  ) {
    final categoryId = jsonIntOrNull(
      jsonObject(value['payload'])['category_id'],
    );
    return (user?.mutedCategoryIds?.contains(categoryId) ?? false) ||
        (user?.indirectlyMutedCategoryIds?.contains(categoryId) ?? false);
  }
}
