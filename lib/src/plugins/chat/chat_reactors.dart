import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../../models/json.dart';
import '../reactions/post_reactors.dart';

/// Who reacted to one chat message, as returned by chat's own lazy endpoint.
///
/// The rows deliberately use [PostReactor]: despite its historical name, it
/// is exactly Discourse's basic-user-plus-reaction envelope on both routes.
/// [ReactorsPage] is the UI boundary; this record only owns chat identity and
/// storage.
@immutable
class ChatMessageReactors
    with Storable<ChatMessageReactors>
    implements ReactorsPage {
  const ChatMessageReactors({
    required this.channelId,
    required this.messageId,
    required this.reactors,
    required this.total,
    this.filter,
  });

  static const int maximumPageSize = 50;

  factory ChatMessageReactors.parse(
    Map<String, dynamic> json, {
    required int channelId,
    required int messageId,
    required String siteUrl,
    String? filter,
  }) => ChatMessageReactors(
    channelId: channelId,
    messageId: messageId,
    filter: filter,
    reactors: List.unmodifiable(
      jsonObjects(json['users'])
          .take(maximumPageSize)
          .map((entry) => PostReactor.fromJson(entry, siteUrl)),
    ),
    total: jsonInt(json['total_rows']),
  );

  final int channelId;
  final int messageId;
  final String? filter;

  @override
  final List<PostReactor> reactors;

  @override
  final int total;

  @override
  Object get storeId => key(channelId, messageId, filter);

  @override
  ChatMessageReactors merge(ChatMessageReactors incoming) =>
      this == incoming ? this : incoming;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageReactors &&
          other.channelId == channelId &&
          other.messageId == messageId &&
          other.filter == filter &&
          other.total == total &&
          listEquals(other.reactors, reactors);

  @override
  int get hashCode => Object.hash(
    channelId,
    messageId,
    filter,
    total,
    Object.hashAll(reactors),
  );

  static String key(int channelId, int messageId, String? filter) =>
      [channelId, messageId, ?filter].join(':');
}
