part of 'chat_controller.dart';

enum _MessageWriteKind { edit, deletion, pin, flag, rebake }

final class _MessageWrite {
  _MessageWrite(this.kind, Iterable<int> ids)
    : ids = List<int>.unmodifiable(ids);

  final _MessageWriteKind kind;
  final List<int> ids;
}

final class _AccountMessageWrites {
  _AccountMessageWrites(this.chat, this.siteUrl, this.lease);

  final ChatController chat;
  final String siteUrl;
  final PluginSiteLease lease;
  final Map<int, _MessageWrite> _active = {};
  bool _retired = false;

  bool get isCurrent => !_retired && !chat.isDisposed && lease.isCurrent;

  bool inFlight(int id, _MessageWriteKind kind) =>
      !_retired && _active[id]?.kind == kind;

  _MessageWrite? _admit(_MessageWriteKind kind, Iterable<int> ids) {
    if (ids.any(_active.containsKey)) return null;
    final ticket = _MessageWrite(kind, ids);
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
    } catch (error, stackTrace) {
      if (ownsRequest()) chat._report(error, stackTrace, 'chat.flagMessage');
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

    final ticket = _admit(_MessageWriteKind.pin, [messageId]);
    if (ticket == null) return appL10n.anotherMessageChangeIsStillFinishing;

    bool ownsRequest() => _owns(ticket);

    void project(bool next) {
      lease.commit(() {
        final latest = chat._store.read<ChatMessage>(siteUrl, messageId);
        if (latest == null || latest.pinned == next) return;
        chat._store.put(siteUrl, latest.withPinned(next));
        chat._updateChannel(
          siteUrl,
          latest.channelId,
          (channel) => channel.withPinnedMessagesCount(
            channel.pinnedMessagesCount + (next ? 1 : -1),
          ),
        );
        // Pinning forces the message to begin a speaker run in core.
        chat._bumpStreamsHolding(siteUrl, messageId);
      });
    }

    try {
      project(pinned);
      try {
        final requestCredentials = await chat._requests.credentialsFor(siteUrl);
        final apiKey = requestCredentials.apiKey;
        if (!ownsRequest()) return null;
        if (apiKey == null) throw const WriteException(WriteFailure.forbidden);
        final clientId = requestCredentials.clientId;
        if (!ownsRequest()) return null;
        final current = chat._store.read<ChatMessage>(siteUrl, messageId);
        if (current == null || !chat.canPinMessage(siteUrl, current)) {
          project(held.pinned);
          return appL10n.thisMessageCanNoLongerBe((pinned).toString());
        }
        await requestCredentials.run(
          () => chat.api.updateChatMessagePinned(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: clientId,
            channelId: held.channelId,
            messageId: held.id,
            pinned: pinned,
          ),
        );
        return null;
      } on WriteException catch (error) {
        if (ownsRequest()) project(held.pinned);
        return error.message;
      } catch (error, stackTrace) {
        if (ownsRequest()) {
          chat._report(
            error,
            stackTrace,
            'chat.${pinned ? 'pin' : 'unpin'}Message',
          );
          project(held.pinned);
        }
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
    } catch (error, stackTrace) {
      if (ownsRequest()) {
        chat._report(error, stackTrace, 'chat.deleteMessages');
      }
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

      lease.commit(() => chat._markMessagesDeleted(siteUrl, channelId, ids));
      return (move: move, error: null);
    } on WriteException catch (error) {
      return (move: null, error: error.message);
    } catch (error, stackTrace) {
      if (ownsRequest()) chat._report(error, stackTrace, 'chat.moveMessages');
      return (
        move: null,
        error: const WriteException(WriteFailure.unreachable).message,
      );
    } finally {
      _release(ticket);
    }
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
    } catch (error, stackTrace) {
      if (ownsRequest()) {
        chat._report(
          error,
          stackTrace,
          'chat.${deleted ? 'delete' : 'restore'}Message',
        );
      }
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
    } catch (error, stackTrace) {
      if (ownsRequest()) chat._report(error, stackTrace, 'chat.rebakeMessage');
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
      } catch (error, stackTrace) {
        if (canonicalEditArrived()) return null;
        if (ownsRequest()) chat._report(error, stackTrace, 'chat.editMessage');
        rollback();
        return const WriteException(WriteFailure.unreachable).message;
      }
    } finally {
      _release(ticket);
    }
  }
}
