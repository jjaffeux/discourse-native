import 'discourse_user.dart';
import 'json.dart';
import 'live_refresh_id.dart';
import 'site_config.dart';

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

  bool accepts(
    Object? value, {
    DiscourseUser? user,
    SiteConfig config = const SiteConfig.unknown(),
  }) {
    if (value is! Map) return false;
    final type = value['message_type'];
    final topicId = liveRefreshId(value['topic_id']);
    _recordHint(type, topicId);
    if (type == 'unmuted') return false;
    if (type != 'new_topic') return true;
    if (topicId == null) return false;
    return _admitsPublicTopic(value, topicId, user, config);
  }

  /// Whether a `/latest` or `/new` message may count as a topic arriving on
  /// the reader's Latest or New list. The server removes muted topics and
  /// muted categories and tags from those lists, so an arrival it will not
  /// return must not be announced. Like core, this drops a topic named by a `muted`
  /// hint in the last minute, and one in a muted category unless an
  /// `unmuted` hint let it back in.
  ///
  /// Records hints exactly as [accepts] does, and recording the same message
  /// twice is harmless, so both paths may see every message.
  bool admitsIncoming(
    Object? value, {
    DiscourseUser? user,
    SiteConfig config = const SiteConfig.unknown(),
  }) {
    if (value is! Map) return false;
    final type = value['message_type'];
    final topicId = liveRefreshId(value['topic_id']);
    _recordHint(type, topicId);
    if (type != 'new_topic' && type != 'latest') return true;
    if (topicId == null) return false;
    return _admitsPublicTopic(value, topicId, user, config);
  }

  bool _admitsPublicTopic(
    Map<Object?, Object?> value,
    int topicId,
    DiscourseUser? user,
    SiteConfig config,
  ) {
    if (_mutedUntil.containsKey(topicId)) return false;
    if (!_unmutedUntil.containsKey(topicId) &&
        (config.muteAllCategoriesByDefault || _inMutedCategory(value, user))) {
      return false;
    }
    final mutedTags = user?.mutedTagIds;
    if (!config.taggingEnabled || mutedTags == null || mutedTags.isEmpty) {
      return true;
    }
    final tagIds = [
      for (final tag in jsonArray(jsonObject(value['payload'])['tags']))
        ?liveRefreshId(jsonObject(tag)['id']),
    ];
    // Like the server's topic query, an untagged topic is not tag-muted.
    // Older reports that omit tags cannot establish a tag mute either.
    if (tagIds.isEmpty) return true;
    return switch (config.removeMutedTagsFromLatest) {
      'always' => !tagIds.any(mutedTags.contains),
      'only_muted' => !tagIds.every(mutedTags.contains),
      _ => true,
    };
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
