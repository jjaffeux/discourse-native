import 'dart:async';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';

import 'chat_message.dart';
import 'chat_stream_target.dart';

/// A chat message whose send failed in a way that left nothing on the site,
/// with everything needed to show it again as failed and to send it on request.
///
/// It is never sent without the reader asking: Discourse does not de-duplicate
/// on `staged_id`, so a resend that raced an accepted request would post twice.
@immutable
final class FailedChatSend {
  const FailedChatSend({
    required this.stagedId,
    required this.target,
    required this.raw,
    required this.createdAt,
    required this.failedAt,
    required this.rateLimited,
    this.replyTo,
    this.uploads = const [],
    this.contextTopicId,
    this.contextPostIds = const [],
  });

  final String stagedId;
  final ChatStreamTarget target;
  final String raw;

  /// Sent as `client_created_at`, so a retry keeps the message's place.
  final DateTime createdAt;
  final DateTime failedAt;

  /// The site refused the send for its rate; otherwise it never reached it.
  final bool rateLimited;
  final ChatReplyTo? replyTo;
  final List<ChatUpload> uploads;
  final int? contextTopicId;
  final List<int> contextPostIds;

  Map<String, Object?> toJson() => {
    'staged_id': stagedId,
    'channel_id': target.channelId,
    'thread_id': ?target.threadId,
    'raw': raw,
    'created_at': createdAt.toUtc().microsecondsSinceEpoch,
    'failed_at': failedAt.toUtc().millisecondsSinceEpoch,
    'rate_limited': rateLimited,
    if (replyTo case final reply?)
      'reply_to': {
        'id': reply.id,
        'user_id': reply.userId,
        'excerpt': reply.excerpt,
        'username': reply.username,
        'avatar_url': ?reply.avatarUrl,
      },
    if (uploads.isNotEmpty)
      'uploads': [
        for (final upload in uploads)
          {
            'id': upload.id,
            'url': upload.url,
            'original_filename': upload.originalFilename,
            'thumbnail_url': ?upload.thumbnailUrl,
            'width': ?upload.width,
            'height': ?upload.height,
          },
      ],
    'context_topic_id': ?contextTopicId,
    if (contextPostIds.isNotEmpty) 'context_post_ids': contextPostIds,
  };

  static FailedChatSend? fromJson(Object? json) {
    if (json is! Map) return null;
    final stagedId = json['staged_id'];
    final channelId = json['channel_id'];
    final threadId = json['thread_id'];
    final raw = json['raw'];
    final createdAt = json['created_at'];
    final failedAt = json['failed_at'];
    if (stagedId is! String ||
        stagedId.isEmpty ||
        channelId is! int ||
        channelId <= 0 ||
        threadId is! int? ||
        raw is! String ||
        raw.length > ChatMessage.maximumEditLength ||
        createdAt is! int ||
        failedAt is! int) {
      return null;
    }
    final uploads = <ChatUpload>[];
    if (json['uploads'] case final List<Object?> held) {
      for (final upload in held.take(ChatMessage.maximumUploadsPerMessage)) {
        if (upload case {
          'id': final int id,
          'url': final String url,
          'original_filename': final String filename,
        } when id > 0) {
          uploads.add(
            ChatUpload(
              id: id,
              url: url,
              originalFilename: filename,
              kind: ChatUploadKind.read(null, filename),
              thumbnailUrl: switch (upload['thumbnail_url']) {
                final String thumbnail => thumbnail,
                _ => null,
              },
              width: switch (upload['width']) {
                final int width => width,
                _ => null,
              },
              height: switch (upload['height']) {
                final int height => height,
                _ => null,
              },
            ),
          );
        } else {
          // A retry without one of its attachments would post another message
          // than the one written.
          return null;
        }
      }
    }
    if (raw.trim().isEmpty && uploads.isEmpty) return null;
    return FailedChatSend(
      stagedId: stagedId,
      target: threadId == null
          ? ChatChannelTarget(channelId)
          : ChatThreadTarget(channelId: channelId, threadId: threadId),
      raw: raw,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(createdAt, isUtc: true),
      failedAt: DateTime.fromMillisecondsSinceEpoch(failedAt, isUtc: true),
      rateLimited: json['rate_limited'] == true,
      replyTo: switch (json['reply_to']) {
        {
              'id': final int id,
              'user_id': final int userId,
              'excerpt': final String excerpt,
              'username': final String username,
            } &&
            final reply =>
          ChatReplyTo(
            id: id,
            userId: userId,
            excerpt: excerpt,
            username: username,
            avatarUrl: switch (reply['avatar_url']) {
              final String avatar => avatar,
              _ => null,
            },
          ),
        _ => null,
      },
      uploads: List.unmodifiable(uploads),
      contextTopicId: switch (json['context_topic_id']) {
        final int topicId when topicId > 0 => topicId,
        _ => null,
      },
      contextPostIds: switch (json['context_post_ids']) {
        final List<Object?> ids => List.unmodifiable(
          ids.whereType<int>().take(maximumContextPosts),
        ),
        _ => const [],
      },
    );
  }

  static const maximumContextPosts = 50;
}

typedef ChatSendOutbox = SiteOutbox<List<FailedChatSend>>;

/// The most failed messages one site keeps. Past it the oldest are let go.
const int maximumFailedChatSends = 50;

List<FailedChatSend> boundFailedChatSends(Iterable<FailedChatSend> sends) {
  final held = sends.toList();
  return List.unmodifiable(
    held.length > maximumFailedChatSends
        ? held.sublist(held.length - maximumFailedChatSends)
        : held,
  );
}

ChatSendOutbox createChatSendOutbox(FutureOr<File> Function() file) =>
    ChatSendOutbox(
      file: file,
      codec: SiteOutboxCodec(
        encode: (sends) => [for (final send in sends) send.toJson()],
        decode: (json) {
          if (json is! List) return null;
          final sends = boundFailedChatSends(
            json.map(FailedChatSend.fromJson).nonNulls,
          );
          return sends.isEmpty ? null : sends;
        },
      ),
    );
