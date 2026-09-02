import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../models/discourse_user.dart';
import '../models/json.dart';
import '../models/topic_tracking_state.dart';
import '../plugin_api/discourse_model_codec.dart';

/// The MessageBus snapshots and matching channel positions embedded by
/// Discourse in an authenticated application document.
final class SiteMessageBusBootstrap {
  SiteMessageBusBootstrap({
    required this.currentUser,
    required Map<String, dynamic>? currentUserState,
    required this.topicTrackingState,
    required Map<String, int> topicTrackingLastIds,
    required this.notificationChannelPosition,
  }) : currentUserState = currentUserState == null
           ? null
           : Map.unmodifiable(currentUserState),
       topicTrackingLastIds = Map.unmodifiable(topicTrackingLastIds);

  final DiscourseUser? currentUser;

  /// The current-user serializer is also the snapshot carried by the private
  /// notification and reviewable-count channels.
  final Map<String, dynamic>? currentUserState;

  final TopicTrackingState? topicTrackingState;
  final Map<String, int> topicTrackingLastIds;
  final int? notificationChannelPosition;

  bool hasCompleteTopicTrackingSnapshot(int userId) {
    if (topicTrackingState == null) return false;
    return [
      '/latest',
      '/new',
      '/unread',
      '/unread/$userId',
      '/delete',
      '/recover',
      '/destroy',
    ].every(topicTrackingLastIds.containsKey);
  }

  Map<String, int?> initialLastIds({int? userId}) {
    final positions = <String, int?>{...topicTrackingLastIds};
    final notificationPosition = notificationChannelPosition;
    if (userId != null && notificationPosition != null) {
      positions['/notification/$userId'] = notificationPosition;
    }
    final statusPosition = currentUser?.status?.messageBusLastId;
    if (statusPosition != null) positions['/user-status'] = statusPosition;
    final doNotDisturbPosition = currentUser?.doNotDisturbChannelPosition;
    if (userId != null && doNotDisturbPosition != null) {
      positions['/do-not-disturb/$userId'] = doNotDisturbPosition;
    }
    return positions;
  }

  /// Reads core's `PreloadStore` wire format: one outer JSON object whose
  /// values are themselves JSON strings.
  static SiteMessageBusBootstrap? fromHtml(
    String source, {
    required String siteUrl,
    required DiscourseModelCodec models,
  }) {
    final script = html
        .parse(source)
        .querySelector('script#data-preloaded[type="application/json"]');
    if (script == null) return null;

    final Map<String, dynamic> preloaded;
    try {
      preloaded = jsonObject(jsonDecode(script.text));
    } on Object {
      return null;
    }
    if (preloaded.isEmpty) return null;

    final currentUserState = _objectEntry(preloaded, 'currentUser');
    DiscourseUser? currentUser;
    if (currentUserState != null) {
      try {
        currentUser = models.currentUser(currentUserState, siteUrl);
      } on Object {
        // One plugin field or older serializer must not discard the independent
        // topic-tracking snapshot and positions.
      }
    }

    final trackingRows = _entry(preloaded, 'topicTrackingStates');
    final trackingState = trackingRows is List
        ? TopicTrackingState.fromJson(trackingRows)
        : null;
    final trackingMeta = _objectEntry(preloaded, 'topicTrackingStateMeta');
    final rawLastIds = jsonObject(trackingMeta?['message_bus_last_ids']);
    final lastIds = <String, int>{};
    for (final entry in rawLastIds.entries) {
      final lastId = jsonIntOrNull(entry.value);
      if (entry.key.startsWith('/') && lastId != null && lastId >= 0) {
        lastIds[entry.key] = lastId;
      }
    }

    final notificationPosition = jsonIntOrNull(
      currentUserState?['notification_channel_position'],
    );
    return SiteMessageBusBootstrap(
      currentUser: currentUser,
      currentUserState: currentUserState,
      topicTrackingState: trackingState,
      topicTrackingLastIds: lastIds,
      notificationChannelPosition:
          notificationPosition != null && notificationPosition >= 0
          ? notificationPosition
          : null,
    );
  }
}

Object? _entry(Map<String, dynamic> preloaded, String key) {
  final encoded = preloaded[key];
  if (encoded is! String) return null;
  try {
    return jsonDecode(encoded);
  } on Object {
    return null;
  }
}

Map<String, dynamic>? _objectEntry(Map<String, dynamic> preloaded, String key) {
  final value = _entry(preloaded, key);
  return value is Map<String, dynamic> ? value : null;
}
