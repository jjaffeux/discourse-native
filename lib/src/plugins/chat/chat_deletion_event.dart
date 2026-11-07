import 'package:discourse_native/discourse_plugin_sdk.dart';

/// A deletion delivery parsed once before canonical and thread projections.
sealed class ChatDeletionEvent {
  const ChatDeletionEvent._(this.deletedAt, this.deletedById);

  final DateTime deletedAt;
  final int? deletedById;

  static ChatDeletionEvent? decode(
    Map<String, dynamic> data, {
    required DateTime Function() clock,
  }) {
    switch (data['type']) {
      case 'delete':
        final id = jsonIntOrNull(data['deleted_id']);
        if (id == null) return null;
        return ChatMessageDeleted._(
          id,
          jsonDate(data['deleted_at']) ?? clock().toUtc(),
          jsonIntOrNull(data['deleted_by_id']),
          jsonIntOrNull(data['latest_not_deleted_message_id']),
        );
      case 'bulk_delete':
        return ChatMessagesDeleted._(
          [
            for (final value in jsonArray(data['deleted_ids']))
              ?jsonIntOrNull(value),
          ],
          jsonDate(data['deleted_at']) ?? clock().toUtc(),
          jsonIntOrNull(data['deleted_by_id']),
        );
      default:
        return null;
    }
  }
}

final class ChatMessageDeleted extends ChatDeletionEvent {
  const ChatMessageDeleted._(
    this.messageId,
    super.deletedAt,
    super.deletedById,
    this.latestNotDeletedMessageId,
  ) : super._();

  final int messageId;
  final int? latestNotDeletedMessageId;
}

final class ChatMessagesDeleted extends ChatDeletionEvent {
  ChatMessagesDeleted._(
    Iterable<int> messageIds,
    super.deletedAt,
    super.deletedById,
  ) : messageIds = List.unmodifiable(messageIds),
      super._();

  final List<int> messageIds;
}
