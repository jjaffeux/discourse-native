part of 'chat_controller.dart';

typedef _ChatReactionWriteKey = ({int messageId, String emoji});
typedef _ChatReactorsKey = ({int channelId, int messageId, String? filter});

final class _ChatReactionWrite {
  bool dispatched = false;
  bool? liveReacted;
}

final class _AccountChatReactions {
  _AccountChatReactions(
    this.chat,
    this.siteUrl,
    this.lease, {
    required this.onChanged,
  });

  final ChatController chat;
  final String siteUrl;
  final PluginSiteLease lease;
  final VoidCallback onChanged;
  final Map<_ChatReactionWriteKey, _ChatReactionWrite> _reactionWrites = {};
  final Map<_ChatReactorsKey, Object> _reactorRequests = {};
  final Map<_ChatReactorsKey, String> _reactorErrors = {};
  bool _retired = false;

  bool get isCurrent => chat._requestIsCurrent(lease, () => !_retired);

  String? reactorsError(int channelId, int messageId, {String? filter}) =>
      _reactorErrors[(
        channelId: channelId,
        messageId: messageId,
        filter: filter,
      )];

  void retire() {
    _retired = true;
    _reactionWrites.clear();
    _reactorRequests.clear();
    _reactorErrors.clear();
  }

  void _projectReader(
    int messageId,
    String emoji, {
    required bool reacted,
    int? userId,
  }) {
    lease.commit(() {
      final message = chat._store.read<ChatMessage>(siteUrl, messageId);
      if (message == null) return;
      final updated = message.withReaction(
        emoji,
        reacted: reacted,
        userId: userId,
      );
      if (!identical(message, updated)) chat._store.put(siteUrl, updated);
    });
  }

  Future<String?> set(int messageId, String emoji, {bool? reacted}) async {
    if (!isCurrent) return null;
    final message = chat._store.read<ChatMessage>(siteUrl, messageId);
    if (message == null ||
        message.id <= 0 ||
        message.isDeleted ||
        message.isOptimistic ||
        emoji.isEmpty) {
      return null;
    }
    final held = message.reactions
        .where((reaction) => reaction.emoji == emoji)
        .firstOrNull;
    final wasReacted = held?.reacted ?? false;
    final adding = reacted ?? !wasReacted;
    if (adding == wasReacted) return null;
    if (!(adding
        ? chat.canAddReactionToMessage(siteUrl, message)
        : chat.canRemoveReactionFromMessage(siteUrl, message))) {
      return null;
    }

    final key = (messageId: messageId, emoji: emoji);
    if (_reactionWrites.containsKey(key)) return null;
    final request = _ChatReactionWrite();
    _reactionWrites[key] = request;

    final readerId = chat._currentUserFor(siteUrl)?.id;
    _projectReader(messageId, emoji, reacted: adding, userId: readerId);

    bool ownsRequest() => isCurrent && identical(_reactionWrites[key], request);

    void rollback() {
      if (ownsRequest()) {
        _projectReader(
          messageId,
          emoji,
          reacted: request.liveReacted ?? !adding,
          userId: readerId,
        );
      }
    }

    try {
      final requestCredentials = await chat._requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return null;
      if (apiKey == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return null;
      final current = chat._store.read<ChatMessage>(siteUrl, messageId);
      if (current == null ||
          !(adding
              ? chat.canAddReactionToMessage(siteUrl, current)
              : chat.canRemoveReactionFromMessage(siteUrl, current))) {
        rollback();
        return null;
      }
      await requestCredentials.run(() {
        request.dispatched = true;
        return chat.api.setChatMessageReaction(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          channelId: message.channelId,
          messageId: message.id,
          emoji: emoji,
          action: adding ? ChatReactionAction.add : ChatReactionAction.remove,
        );
      });
      if (!ownsRequest()) return null;
      _projectReader(
        messageId,
        emoji,
        reacted: request.liveReacted ?? adding,
        userId: readerId,
      );
      return null;
    } on WriteException catch (error) {
      rollback();
      if (ownsRequest() &&
          request.dispatched &&
          !error.notSent &&
          error.failure == WriteFailure.unreachable &&
          request.liveReacted == adding) {
        return null;
      }
      return error.message;
    } catch (error) {
      rollback();
      if (ownsRequest() &&
          request.dispatched &&
          request.liveReacted == adding) {
        return null;
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_reactionWrites[key], request)) {
        _reactionWrites.remove(key);
      }
    }
  }

  Future<void> loadReactors(
    int channelId,
    int messageId, {
    String? filter,
  }) async {
    if (!isCurrent) return;
    final key = (channelId: channelId, messageId: messageId, filter: filter);
    if (_reactorRequests.containsKey(key)) return;
    final request = Object();
    _reactorRequests[key] = request;
    onChanged();

    bool ownsRequest() =>
        isCurrent && identical(_reactorRequests[key], request);

    try {
      final requestCredentials = await chat._requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return;
      if (apiKey == null) {
        throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
      }

      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return;
      final fetched = await requestCredentials.run(
        () => chat.api.chatMessageReactors(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          channelId: channelId,
          messageId: messageId,
          reaction: filter,
        ),
      );
      if (!ownsRequest()) return;
      lease.commit(() {
        chat._store.put(siteUrl, fetched);
        _reactorErrors.remove(key);
      });
    } catch (error) {
      if (!ownsRequest()) return;

      lease.commit(() {
        if (chat.messageReactors(
              siteUrl,
              channelId,
              messageId,
              filter: filter,
            ) ==
            null) {
          _reactorErrors[key] = appL10n.couldNotFindOutWhoReacted;
        }
      });
    } finally {
      if (ownsRequest()) {
        _reactorRequests.remove(key);
        onChanged();
      }
    }
  }

  /// Applies non-idempotent reaction deltas. HTTP pages expose no MessageBus
  /// cursor, so remount replay can leave truncated reactions off until refresh.
  void applyEvent(Map<String, dynamic> data) {
    if (!isCurrent) return;
    final messageId = jsonIntOrNull(data['chat_message_id']);
    final emoji = jsonText(data['emoji']);
    final action = jsonText(data['action']);
    if (messageId == null || emoji == null || action == null) return;
    if (action != 'add' && action != 'remove') return;
    final message = chat._store.read<ChatMessage>(siteUrl, messageId);
    if (message == null) return;

    final reactions = message.reactions.toList();
    final index = reactions.indexWhere((reaction) => reaction.emoji == emoji);
    final existing = index < 0 ? null : reactions[index];
    final actorId = jsonIntOrNull(jsonObject(data['user'])['id']);
    final isCurrentUser =
        actorId != null && actorId == chat._currentUserFor(siteUrl)?.id;
    if (isCurrentUser) {
      if (action == 'add' &&
          existing == null &&
          reactions.length >= ChatMessage.maximumReactionsPerMessage) {
        return;
      }
      _reactionWrites[(messageId: messageId, emoji: emoji)]?.liveReacted =
          action == 'add';
      _projectReader(
        messageId,
        emoji,
        reacted: action == 'add',
        userId: actorId,
      );
      return;
    }
    // Pages have no bus cursor, so actor identity deduplicates replay. The site
    // names only five reactors; once truncated, ambiguous events must still
    // advance the live count.
    if (actorId != null && existing != null) {
      if (action == 'add' && existing.hasReactor(actorId)) return;
      if (action == 'remove' &&
          !existing.hasReactor(actorId) &&
          existing.namesEveryReactor) {
        return;
      }
    }
    if (action == 'add') {
      final next = ChatReaction(
        emoji: emoji,
        count: (existing?.count ?? 0) + 1,
        reacted: existing?.reacted ?? false,
        reactorIds:
            existing?.reactorIdsWith(actorId, reacted: true) ?? [?actorId],
      );
      if (index < 0) {
        if (reactions.length >= ChatMessage.maximumReactionsPerMessage) return;
        reactions.add(next);
      } else {
        reactions[index] = next;
      }
    } else if (existing != null) {
      if (existing.count <= 1) {
        reactions.removeAt(index);
      } else {
        reactions[index] = ChatReaction(
          emoji: emoji,
          count: existing.count - 1,
          reacted: existing.reacted,
          reactorIds: existing.reactorIdsWith(actorId, reacted: false),
        );
      }
    } else {
      return;
    }
    chat._store.put(siteUrl, message.withReactions(reactions));
  }
}
