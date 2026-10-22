import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

typedef ChatSearchRecord = ({
  int id,
  int channelId,
  Map<String, dynamic> message,
  Map<String, dynamic> channel,
});

@immutable
final class ChatSearchResponse {
  const ChatSearchResponse._({
    required this.records,
    required this.hasMore,
    required this.limit,
    required this.offset,
    required this.consumedCount,
  });

  static const int defaultPageSize = 20;
  static const int maximumPageSize = 40;

  factory ChatSearchResponse.fromJson(Map<String, dynamic> json) {
    final records = <ChatSearchRecord>[];
    final entries = jsonObjects(
      json['messages'],
    ).take(maximumPageSize).toList(growable: false);
    for (final entry in entries) {
      final channel = entry['channel'];
      if (channel is! Map<String, dynamic>) continue;
      final id = jsonInt(entry['id']);
      final channelId = jsonInt(entry['chat_channel_id']);
      if (id <= 0 || channelId <= 0 || jsonInt(channel['id']) != channelId) {
        continue;
      }
      records.add((
        id: id,
        channelId: channelId,
        message: entry,
        channel: channel,
      ));
    }

    final meta = jsonObject(json['meta']);
    return ChatSearchResponse._(
      records: List.unmodifiable(records),
      hasMore: meta['has_more'] == true,
      limit:
          jsonIntOrNull(meta['limit'])?.clamp(1, maximumPageSize) ??
          defaultPageSize,
      offset: switch (jsonIntOrNull(meta['offset'])) {
        final value? when value >= 0 => value,
        _ => 0,
      },
      consumedCount: entries.length,
    );
  }

  final List<ChatSearchRecord> records;
  final bool hasMore;
  final int limit;
  final int offset;

  /// Records consumed from the server window, including any rejected locally.
  final int consumedCount;
}
