import 'package:flutter/foundation.dart';

import '../../models/json.dart';
import 'chat_channel.dart';
import 'chat_message.dart';

enum ChatSearchSort { relevance, latest }

@immutable
final class ChatSearchHit {
  const ChatSearchHit({
    required this.message,
    required this.channel,
    this.threadTitle,
    this.excerpt,
  });

  final ChatMessage message;
  final ChatChannel channel;
  final String? threadTitle;
  final String? excerpt;

  int get id => message.id;
}

@immutable
final class ChatSearchPage {
  const ChatSearchPage({
    this.hits = const [],
    this.hasMore = false,
    this.limit = defaultPageSize,
    this.offset = 0,
    this._consumedCount,
  });

  static const int defaultPageSize = 20;
  static const int maximumPageSize = 40;

  factory ChatSearchPage.fromJson(Map<String, dynamic> json, String siteUrl) {
    final hits = <ChatSearchHit>[];
    final records = jsonObjects(
      json['messages'],
    ).take(maximumPageSize).toList(growable: false);
    for (final entry in records) {
      final channelJson = entry['channel'];
      if (channelJson is! Map<String, dynamic>) continue;
      final message = ChatMessage.fromJson(entry, siteUrl);
      final channel = ChatChannel.fromJson(channelJson, siteUrl);
      if (message.id <= 0 ||
          message.channelId <= 0 ||
          channel.id <= 0 ||
          channel.id != message.channelId) {
        continue;
      }
      hits.add(
        ChatSearchHit(
          message: message,
          channel: channel,
          threadTitle: jsonText(entry['thread_title']) ?? message.thread?.title,
          excerpt: jsonText(entry['excerpt']),
        ),
      );
    }

    final meta = jsonObject(json['meta']);
    return ChatSearchPage(
      hits: List.unmodifiable(hits),
      hasMore: meta['has_more'] == true,
      limit:
          jsonIntOrNull(meta['limit'])?.clamp(1, maximumPageSize) ??
          defaultPageSize,
      offset: switch (jsonIntOrNull(meta['offset'])) {
        final value? when value >= 0 => value,
        _ => 0,
      },
      consumedCount: records.length,
    );
  }

  final List<ChatSearchHit> hits;
  final bool hasMore;
  final int limit;
  final int offset;
  final int? _consumedCount;

  /// Records consumed from the server window, including any rejected locally.
  int get consumedCount => _consumedCount ?? hits.length;
}
