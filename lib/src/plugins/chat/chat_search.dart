import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

import 'chat_channel.dart';
import 'chat_message.dart';
import 'chat_search_response.dart';

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

  static const int defaultPageSize = ChatSearchResponse.defaultPageSize;
  static const int maximumPageSize = ChatSearchResponse.maximumPageSize;

  factory ChatSearchPage.fromJson(Map<String, dynamic> json, String siteUrl) {
    final response = ChatSearchResponse.fromJson(json);
    final hits = <ChatSearchHit>[];
    for (final record in response.records) {
      final entry = record.message;
      final message = ChatMessage.fromJson(entry, siteUrl);
      final channel = ChatChannel.fromJson(record.channel, siteUrl);
      hits.add(
        ChatSearchHit(
          message: message,
          channel: channel,
          threadTitle: jsonText(entry['thread_title']) ?? message.thread?.title,
          excerpt: jsonText(entry['excerpt']),
        ),
      );
    }

    return ChatSearchPage(
      hits: List.unmodifiable(hits),
      hasMore: response.hasMore,
      limit: response.limit,
      offset: response.offset,
      consumedCount: response.consumedCount,
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
