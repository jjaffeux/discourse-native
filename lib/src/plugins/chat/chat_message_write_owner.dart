part of 'chat_controller.dart';

enum _MessageWriteKind { edit, deletion, pin, flag, rebake }

final class _PinWriteSettlement {
  _PinWriteSettlement({
    required this.channelId,
    required this.pinned,
    required this.actorId,
  });

  final int channelId;
  final bool pinned;
  final int? actorId;
  bool dispatched = false;
  bool confirmed = false;
  bool messageAuthority = false;
  bool countAuthority = false;
}

final class _MessageWrite {
  _MessageWrite(this.kind, Iterable<int> ids, {this.pin})
    : ids = List<int>.unmodifiable(ids);

  final _MessageWriteKind kind;
  final List<int> ids;
  final _PinWriteSettlement? pin;
}

final class _ChatSourceMessageMove {
  _ChatSourceMessageMove({
    required this.channelId,
    required Iterable<int> messageIds,
    required Iterable<int> threadIds,
    required this.deletedAt,
    required this.deletedById,
  }) : messageIds = Set.unmodifiable(messageIds),
       threadIds = Set.unmodifiable(threadIds);

  final int channelId;
  final Set<int> messageIds;
  final Set<int> threadIds;
  final DateTime deletedAt;
  final int? deletedById;

  bool contains(ChatMessage message) {
    final serverId = message.serverId ?? message.id;
    return serverId > 0 &&
        message.channelId == channelId &&
        (messageIds.contains(serverId) || threadIds.contains(message.threadId));
  }

  ChatMessage project(ChatMessage message) {
    if (!contains(message)) return message;
    final deleted = message.isDeleted
        ? message
        : message.withDeletedAt(deletedAt, deletedById: deletedById);
    return deleted.thread == null ? deleted : deleted.withThreadPreview(null);
  }
}

final class _AccountMessageWrites {
  _AccountMessageWrites(this.chat, this.siteUrl, this.lease);

  final ChatController chat;
  final String siteUrl;
  final PluginSiteLease lease;
  final Map<int, _MessageWrite> _active = {};
  bool _retired = false;

  bool get isCurrent => chat._requestIsCurrent(lease, () => !_retired);

  bool inFlight(int id, _MessageWriteKind kind) =>
      !_retired && _active[id]?.kind == kind;

  _MessageWrite? _admit(
    _MessageWriteKind kind,
    Iterable<int> ids, {
    _PinWriteSettlement? pin,
  }) {
    if (ids.any(_active.containsKey)) return null;
    final ticket = _MessageWrite(kind, ids, pin: pin);
    for (final id in ticket.ids) {
      _active[id] = ticket;
    }
    return ticket;
  }

  bool _owns(_MessageWrite ticket) =>
      isCurrent && ticket.ids.every((id) => identical(_active[id], ticket));

  void _release(_MessageWrite ticket) {
    for (final id in ticket.ids) {
      if (identical(_active[id], ticket)) _active.remove(id);
    }
  }

  void retire() {
    _retired = true;
    _active.clear();
  }

  void retireChannelPins(int channelId) {
    _active.removeWhere((_, ticket) => ticket.pin?.channelId == channelId);
  }

  void acceptPinCount(int channelId) {
    if (!isCurrent) return;
    for (final ticket in _active.values) {
      final pin = ticket.pin;
      if (pin != null && pin.channelId == channelId) pin.countAuthority = true;
    }
  }

  void acceptPinEvent(
    int channelId,
    int messageId, {
    required bool pinned,
    required int? actorId,
  }) {
    if (!isCurrent) return;
    final pin = _active[messageId]?.pin;
    if (pin == null || pin.channelId != channelId) return;
    pin.messageAuthority = true;
    if (pin.dispatched &&
        pin.pinned == pinned &&
        pin.actorId != null &&
        pin.actorId == actorId) {
      pin.confirmed = true;
    }
  }

  Future<String?> flag(
    int messageId,
    PostFlagType flagType, {
    String? message,
  }) async {
    final held = chat._store.read<ChatMessage>(siteUrl, messageId);
    if (held == null || !chat.canFlagMessage(siteUrl, held)) {
      return appL10n.thisMessageCanNoLongerBeFlagged;
    }
    if (!flagType.enabled ||
        !flagType.appliesToTarget(chatMessageWireType) ||
        !held.availableFlags.contains(flagType.nameKey)) {
      return appL10n.thisFlagReasonIsNoLongerAvailable;
    }
    final submittedMessage = flagType.requireMessage ? message ?? '' : null;
    final minimum = chat.flagMessageMinimumLength(siteUrl);
    final length = submittedMessage?.length ?? 0;
    if (flagType.requireMessage &&
        (length < minimum || length > PostFlagType.maximumMessageLength)) {
      return appL10n.yourMessageMustBeBetweenAndCharacters(
        (minimum).toString(),
        (PostFlagType.maximumMessageLength).toString(),
      );
    }

    final ticket = _admit(_MessageWriteKind.flag, [messageId]);
    if (ticket == null) return appL10n.anotherMessageChangeIsStillFinishing;

    bool ownsRequest() => _owns(ticket);

    try {
      final requestCredentials = await chat._requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return null;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return null;
      final current = chat._store.read<ChatMessage>(siteUrl, messageId);
      if (current == null ||
          !chat.canFlagMessage(siteUrl, current) ||
          !current.availableFlags.contains(flagType.nameKey)) {
        return appL10n.thisMessageCanNoLongerBeFlagged;
      }
      await requestCredentials.run(
        () => chat.api.flagChatMessage(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          channelId: current.channelId,
          messageId: current.id,
          flagTypeId: flagType.id,
          message: submittedMessage,
        ),
      );
      if (!ownsRequest()) return null;
      lease.commit(() {
        chat._store.update<ChatMessage>(
          siteUrl,
          messageId,
          (message) => message.withUserFlagStatus(0),
        );
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error) {
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      _release(ticket);
    }
  }

  Future<String?> pin(int messageId, {required bool pinned}) async {
    final held = chat._store.read<ChatMessage>(siteUrl, messageId);
    if (held == null || !chat.canPinMessage(siteUrl, held)) {
      return appL10n.thisMessageCanNoLongerBe((pinned).toString());
    }
    if (held.pinned == pinned) return null;

    final settlement = _PinWriteSettlement(
      channelId: held.channelId,
      pinned: pinned,
      actorId: chat._currentUserFor(siteUrl)?.id,
    );
    final ticket = _admit(_MessageWriteKind.pin, [messageId], pin: settlement);
    if (ticket == null) return appL10n.anotherMessageChangeIsStillFinishing;

    bool ownsRequest() => _owns(ticket);

    void project(bool next) {
      if (!ownsRequest()) return;
      lease.commit(() {
        final latest = chat._store.read<ChatMessage>(siteUrl, messageId);
        if (latest == null || latest.pinned == next) return;
        chat._store.put(siteUrl, latest.withPinned(next));
        if (!ownsRequest()) return;
        if (!settlement.countAuthority) {
          chat._updateChannel(
            siteUrl,
            latest.channelId,
            (channel) => channel.withPinnedMessagesCount(
              channel.pinnedMessagesCount + (next ? 1 : -1),
            ),
          );
        }
        if (!ownsRequest()) return;
        // Pinning forces the message to begin a speaker run in core.
        chat._bumpStreamsHolding(siteUrl, messageId);
      });
    }

    void rollback() {
      if (!settlement.messageAuthority) project(held.pinned);
    }

    try {
      project(pinned);
      if (!ownsRequest()) return null;
      try {
        final requestCredentials = await chat._requests.credentialsFor(siteUrl);
        final apiKey = requestCredentials.apiKey;
        if (!ownsRequest()) return null;
        if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
        final clientId = requestCredentials.clientId;
        if (!ownsRequest()) return null;
        final current = chat._store.read<ChatMessage>(siteUrl, messageId);
        if (current == null || !chat.canPinMessage(siteUrl, current)) {
          rollback();
          return appL10n.thisMessageCanNoLongerBe((pinned).toString());
        }
        await requestCredentials.run(() {
          settlement.dispatched = true;
          return chat.api.updateChatMessagePinned(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: clientId,
            channelId: held.channelId,
            messageId: held.id,
            pinned: pinned,
          );
        });
        return null;
      } on WriteException catch (error) {
        rollback();
        if (ownsRequest() &&
            settlement.confirmed &&
            error.failure == WriteFailure.unreachable &&
            !error.notSent) {
          return null;
        }
        return error.message;
      } catch (error) {
        rollback();
        if (ownsRequest() && settlement.confirmed) return null;
        return const WriteException(WriteFailure.unreachable).message;
      }
    } finally {
      _release(ticket);
    }
  }

  Future<String?> deleteMany(int channelId, Iterable<int> messageIds) async {
    final ids = messageIds.toSet().toList()..sort();
    if (ids.isEmpty) return appL10n.selectAtLeastOneMessage;
    if (ids.length > ChatController.maximumBulkDeleteMessages) {
      return appL10n.selectNoMoreThanMessagesToDelete(
        (ChatController.maximumBulkDeleteMessages).toString(),
      );
    }
    if (!chat.canDeleteMessages(siteUrl, channelId, ids)) {
      return appL10n.oneOrMoreMessagesCanNoLongerBeDeleted;
    }

    final ticket = _admit(_MessageWriteKind.deletion, ids);
    if (ticket == null) return appL10n.anotherMessageChangeIsStillFinishing;

    bool ownsRequest() => _owns(ticket);

    try {
      final requestCredentials = await chat._requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return null;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return null;
      if (!chat.canDeleteMessages(siteUrl, channelId, ids)) {
        return appL10n.oneOrMoreMessagesCanNoLongerBeDeleted;
      }

      await requestCredentials.run(
        () => chat.api.deleteChatMessages(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          channelId: channelId,
          messageIds: ids,
        ),
      );
      if (!ownsRequest()) return null;

      lease.commit(() => chat._markMessagesDeleted(siteUrl, channelId, ids));
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error) {
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      _release(ticket);
    }
  }

  Future<({ChatMessageMove? move, String? error})> move(
    int channelId,
    int destinationChannelId,
    Iterable<int> messageIds,
  ) async {
    final ids = messageIds.toSet().toList()..sort();
    if (!chat.canMoveMessages(siteUrl, channelId, ids)) {
      return (move: null, error: appL10n.oneOrMoreMessagesCanNoLongerBeMoved);
    }
    final destinations = chat.messageMoveDestinations(siteUrl, channelId);
    if (!destinations.any((channel) => channel.id == destinationChannelId)) {
      return (move: null, error: appL10n.chooseAnotherPublicChannel);
    }

    final ticket = _admit(_MessageWriteKind.deletion, ids);
    if (ticket == null) {
      return (move: null, error: appL10n.anotherMessageChangeIsStillFinishing);
    }

    bool ownsRequest() => _owns(ticket);

    try {
      final requestCredentials = await chat._requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return (move: null, error: null);
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return (move: null, error: null);
      if (!chat.canMoveMessages(siteUrl, channelId, ids) ||
          !chat
              .messageMoveDestinations(siteUrl, channelId)
              .any((channel) => channel.id == destinationChannelId)) {
        return (
          move: null,
          error: appL10n.theSelectedMessagesOrDestinationChanged,
        );
      }

      final threadIds = <int>{
        for (final id in ids)
          if (chat._store.read<ChatMessage>(siteUrl, id)?.threadId
              case final threadId?)
            threadId,
      };

      final move = await requestCredentials.run(
        () => chat.api.moveChatMessages(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          channelId: channelId,
          destinationChannelId: destinationChannelId,
          messageIds: ids,
        ),
      );
      if (!ownsRequest()) return (move: null, error: null);

      lease.commit(() => _markMessagesMoved(ticket, channelId, ids, threadIds));
      if (!ownsRequest()) return (move: null, error: null);
      return (move: move, error: null);
    } on WriteException catch (error) {
      return (move: null, error: error.message);
    } catch (error) {
      return (
        move: null,
        error: const WriteException(WriteFailure.unreachable).message,
      );
    } finally {
      _release(ticket);
    }
  }

  void _markMessagesMoved(
    _MessageWrite ticket,
    int channelId,
    List<int> ids,
    Set<int> threadIds,
  ) {
    final move = _ChatSourceMessageMove(
      channelId: channelId,
      messageIds: ids,
      threadIds: threadIds,
      deletedAt: chat._clock().toUtc(),
      deletedById: chat._currentUserFor(siteUrl)?.id,
    );
    final messages = chat._store.readMatching<ChatMessage>(
      siteUrl,
      move.contains,
    );
    for (final owner in chat._conversations.values) {
      if (owner.siteUrl == siteUrl &&
          owner.target.channelId == channelId &&
          (owner.target.threadId == null ||
              threadIds.contains(owner.target.threadId))) {
        owner.recordSourceMoved(move);
      }
    }
    chat
        ._heldThreadCatalog(siteUrl)
        ?.recordSourceMoved(channelId, threadIds, move.deletedAt);
    chat._clearDeletedChannelPreview(siteUrl, channelId, {
      ...ids,
      ...messages.map((message) => message.id),
    });
    for (final threadId in threadIds) {
      if (!_owns(ticket)) return;
      chat._threadMetadata.recordSourceMoved(
        siteUrl,
        ChatThreadTarget(channelId: channelId, threadId: threadId),
        move.deletedAt,
      );
    }
    for (final message in messages) {
      if (!_owns(ticket)) return;
      final latest = chat._store.read<ChatMessage>(siteUrl, message.id);
      if (latest == null) continue;
      final next = move.project(latest);
      if (identical(latest, next)) continue;
      chat._store.update<ChatMessage>(siteUrl, message.id, (_) => next);
      if (!_owns(ticket)) return;
      chat._bumpStreamsHolding(siteUrl, message.id);
    }
    for (final thread in chat._store.readMatching<ChatThread>(
      siteUrl,
      (thread) =>
          thread.channelId == channelId && threadIds.contains(thread.id),
    )) {
      if (!_owns(ticket)) return;
      final before = chat.thread(siteUrl, thread.id);
      if (before == null || before.channelId != channelId) continue;
      chat._store.update<ChatThread>(siteUrl, thread.id, (current) {
        if (current.channelId != channelId) return current;
        return current.withSourceMoved(move.deletedAt);
      });
      if (!_owns(ticket)) return;
      if (chat.thread(siteUrl, thread.id) case final after?) {
        chat._recordThreadChange(siteUrl, before, after);
      }
    }
    if (_owns(ticket)) chat.notifySafely();
  }

  Future<String?> setDeleted(int messageId, {required bool deleted}) async {
    final held = chat._store.read<ChatMessage>(siteUrl, messageId);
    final allowed =
        held != null &&
        (deleted
            ? chat.canDeleteMessage(siteUrl, held)
            : chat.canRestoreMessage(siteUrl, held));
    if (!allowed) {
      return deleted
          ? appL10n.thisMessageCanNoLongerBeDeleted
          : appL10n.thisMessageCanNoLongerBeRestored;
    }

    final ticket = _admit(_MessageWriteKind.deletion, [messageId]);
    if (ticket == null) return appL10n.anotherMessageChangeIsStillFinishing;

    bool ownsRequest() => _owns(ticket);

    try {
      final requestCredentials = await chat._requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return null;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return null;
      final current = chat._store.read<ChatMessage>(siteUrl, messageId);
      if (current == null ||
          !(deleted
              ? chat.canDeleteMessage(siteUrl, current)
              : chat.canRestoreMessage(siteUrl, current))) {
        return deleted
            ? appL10n.thisMessageCanNoLongerBeDeleted
            : appL10n.thisMessageCanNoLongerBeRestored;
      }
      if (deleted) {
        await requestCredentials.run(
          () => chat.api.deleteChatMessage(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: clientId,
            channelId: held.channelId,
            messageId: held.id,
          ),
        );
      } else {
        await requestCredentials.run(
          () => chat.api.restoreChatMessage(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: clientId,
            channelId: held.channelId,
            messageId: held.id,
          ),
        );
      }
      if (!ownsRequest()) return null;
      lease.commit(() {
        final latest = chat._store.read<ChatMessage>(siteUrl, messageId);
        if (latest == null || latest.isDeleted == deleted) return;
        final deletedAt = deleted ? chat._clock().toUtc() : null;
        final updated = latest.withDeletedAt(
          deletedAt,
          deletedById: deleted ? chat._currentUserFor(siteUrl)?.id : null,
          clearDeletedById: !deleted,
        );
        chat._store.put(siteUrl, updated);
        chat._updateChannelMessagePreview(siteUrl, updated);
        chat._bumpStreamsHolding(siteUrl, messageId);
        chat._setLoadedThreadOriginalDeleted(
          siteUrl,
          latest.channelId,
          messageId,
          deletedAt: deletedAt,
          clear: !deleted,
        );
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error) {
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      _release(ticket);
    }
  }

  Future<String?> rebake(int messageId) async {
    final held = chat._store.read<ChatMessage>(siteUrl, messageId);
    if (held == null || !chat.canRebakeMessage(siteUrl, held)) {
      return appL10n.thisMessageCanNoLongerBeRebuilt;
    }

    final ticket = _admit(_MessageWriteKind.rebake, [messageId]);
    if (ticket == null) return appL10n.anotherMessageChangeIsStillFinishing;

    bool ownsRequest() => _owns(ticket);

    try {
      final requestCredentials = await chat._requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!ownsRequest()) return null;
      if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
      final clientId = requestCredentials.clientId;
      if (!ownsRequest()) return null;
      final current = chat._store.read<ChatMessage>(siteUrl, messageId);
      if (current == null || !chat.canRebakeMessage(siteUrl, current)) {
        return appL10n.thisMessageCanNoLongerBeRebuilt;
      }
      await requestCredentials.run(
        () => chat.api.rebakeChatMessage(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          channelId: current.channelId,
          messageId: current.id,
        ),
      );
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error) {
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      _release(ticket);
    }
  }

  Future<String?> edit(
    int messageId,
    String raw, {
    List<ChatUpload>? uploads,
    Object? cookingOwner,
  }) async {
    final held = chat._store.read<ChatMessage>(siteUrl, messageId);
    if (held == null || !chat.canEditMessage(siteUrl, held)) {
      return appL10n.thisMessageCanNoLongerBeEdited;
    }
    if (raw.length > ChatMessage.maximumEditLength) {
      return appL10n.messagesCanBeAtMostCharacters(
        (ChatMessage.maximumEditLength).toString(),
      );
    }
    final editedUploads = List<ChatUpload>.unmodifiable(
      (uploads ?? held.uploads).take(ChatMessage.maximumUploadsPerMessage),
    );
    final uploadIds = [
      for (final upload in editedUploads)
        if (upload.id > 0) upload.id,
    ];
    if (raw.trim().isEmpty && uploadIds.isEmpty) {
      return appL10n.aMessageCannotBeEmpty;
    }
    bool hasUploadIds(List<ChatUpload> candidate) => listEquals([
      for (final upload in candidate)
        if (upload.id > 0) upload.id,
    ], uploadIds);
    if (raw == held.raw && hasUploadIds(held.uploads)) return null;

    final ticket = _admit(_MessageWriteKind.edit, [messageId]);
    if (ticket == null) return appL10n.anotherEditIsStillFinishing;

    bool ownsRequest() => _owns(ticket);

    try {
      chat._cancelMessageCooking(siteUrl, messageId);
      final preview = chat._projectPreview(
        siteUrl,
        OutgoingChatMessage.text(raw),
      );
      var pending = held.withPendingEdit(raw, preview, uploads: editedUploads);
      final ready = chat._preparedCooking?.takeReady(
        key: ('editDraft', siteUrl, messageId, cookingOwner),
        raw: raw,
      );
      if (ready != null) pending = pending.withProvisionalCooked(ready);
      chat._store.put(siteUrl, pending);
      chat._updateChannelMessagePreview(siteUrl, pending);
      if (ready == null) chat._cookMessage(siteUrl, pending, author: held);

      bool canonicalEditArrived() {
        final current = chat._store.read<ChatMessage>(siteUrl, messageId);
        return current?.canonicalReceived == true &&
            current?.raw == raw &&
            hasUploadIds(current!.uploads);
      }

      void rollback() {
        if (!ownsRequest()) return;
        chat._cancelMessageCooking(siteUrl, messageId);
        lease.commit(() {
          final latest = chat._store.read<ChatMessage>(siteUrl, messageId);
          if (latest == null || latest.canonicalReceived || latest.raw != raw) {
            return;
          }
          final restored = latest.withContentOf(held);
          chat._store.put(siteUrl, restored);
          chat._updateChannelMessagePreview(siteUrl, restored);
        });
      }

      try {
        final requestCredentials = await chat._requests.credentialsFor(siteUrl);
        final apiKey = requestCredentials.apiKey;
        if (!ownsRequest()) return null;
        if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
        final clientId = requestCredentials.clientId;
        if (!ownsRequest()) return null;
        final current = chat._store.read<ChatMessage>(siteUrl, messageId);
        if (current == null ||
            current.raw != raw ||
            !hasUploadIds(current.uploads)) {
          rollback();
          return appL10n.thisMessageChangedBeforeTheEditCouldBeSaved;
        }
        await requestCredentials.run(
          () => chat.api.editChatMessage(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: clientId,
            channelId: held.channelId,
            messageId: held.id,
            message: raw,
            uploadIds: uploadIds,
          ),
        );
        return null;
      } on WriteException catch (error) {
        if (canonicalEditArrived()) return null;
        rollback();
        return error.message;
      } catch (error) {
        if (canonicalEditArrived()) return null;

        rollback();
        return const WriteException(WriteFailure.unreachable).message;
      }
    } finally {
      _release(ticket);
    }
  }
}
