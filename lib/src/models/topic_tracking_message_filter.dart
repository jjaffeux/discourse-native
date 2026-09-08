import 'discourse_user.dart';
import 'json.dart';
import 'live_refresh_id.dart';

/// Personalizes public new-topic events before they enter the counter snapshot.
final class TopicTrackingMessageFilter {
  TopicTrackingMessageFilter({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const _hintLifetime = Duration(seconds: 60);
  static const _maxUnmutedTopics = 5000;

  final DateTime Function() _clock;
  final Map<int, DateTime> _unmutedUntil = {};

  bool accepts(Object? value, {DiscourseUser? user}) {
    if (value is! Map) return false;
    final now = _clock();
    _unmutedUntil.removeWhere((_, expiry) => !expiry.isAfter(now));

    final type = value['message_type'];
    final topicId = liveRefreshId(value['topic_id']);
    if (type == 'unmuted') {
      if (topicId != null) {
        // Core targets this hint using topic, category and tag preferences.
        // A category's watched/tracked lists cannot reconstruct that decision.
        _unmutedUntil.remove(topicId);
        _unmutedUntil[topicId] = now.add(_hintLifetime);
        if (_unmutedUntil.length > _maxUnmutedTopics) {
          _unmutedUntil.remove(_unmutedUntil.keys.first);
        }
      }
      return false;
    }
    if (type == 'muted' || type == 'destroy') {
      _unmutedUntil.remove(topicId);
    }
    if (type != 'new_topic') return true;
    if (topicId == null) return false;

    final categoryId = jsonIntOrNull(
      jsonObject(value['payload'])['category_id'],
    );
    final muted =
        (user?.mutedCategoryIds?.contains(categoryId) ?? false) ||
        (user?.indirectlyMutedCategoryIds?.contains(categoryId) ?? false);
    return !muted || _unmutedUntil.containsKey(topicId);
  }
}
