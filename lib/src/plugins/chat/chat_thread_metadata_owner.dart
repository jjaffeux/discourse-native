import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'chat_api.dart';
import 'chat_channel.dart';
import 'chat_stream_target.dart';
import 'chat_thread.dart';

/// Publishes metadata outcomes through the existing conversation and catalog owners.
abstract interface class ChatThreadMetadataEvents {
  void detailLoading(String siteUrl, ChatThreadTarget target);
  void detailStored(String siteUrl, ChatThreadTarget target, ChatThread detail);
  void detailFailed(
    String siteUrl,
    ChatThreadTarget target, {
    required bool terminal,
  });
  void ensureThreadSubscription(String siteUrl, ChatThreadTarget target);
  void threadCreated(String siteUrl, ChatThread created, int originalMessageId);
  void threadChanged(String siteUrl, ChatThread before, ChatThread after);
}

typedef _ChatThreadMetadataKey = ({String siteUrl, ChatThreadTarget target});

/// Owns coalesced detail and serialized metadata writes; records remain in Store.
final class ChatThreadMetadataOwner {
  ChatThreadMetadataOwner({
    required this.api,
    required this._requests,
    required this._store,
    required this._currentUserFor,
    required this._channelFor,
    required this._events,
  });

  final ChatApi api;
  final PluginRequestHost _requests;
  final Store _store;
  final DiscourseUser? Function(String siteUrl) _currentUserFor;
  final ChatChannel? Function(String siteUrl, int channelId) _channelFor;
  final ChatThreadMetadataEvents _events;
  bool _disposed = false;

  final Map<_ChatThreadMetadataKey, _ChatThreadMetadata> _metadata = {};

  _ChatThreadMetadata _metadataFor(String siteUrl, ChatThreadTarget target) =>
      _metadata.putIfAbsent((
        siteUrl: siteUrl,
        target: target,
      ), _ChatThreadMetadata.new);

  bool _ownsMetadata(
    String siteUrl,
    ChatThreadTarget target,
    _ChatThreadMetadata metadata,
  ) => identical(_metadata[(siteUrl: siteUrl, target: target)], metadata);

  void _releaseIdleMetadata(
    String siteUrl,
    ChatThreadTarget target,
    _ChatThreadMetadata metadata,
  ) {
    if (!metadata.preventsEviction &&
        _ownsMetadata(siteUrl, target, metadata)) {
      _metadata.remove((siteUrl: siteUrl, target: target));
    }
  }

  ChatThread? _thread(String siteUrl, int threadId) =>
      _store.read<ChatThread>(siteUrl, threadId);

  void _updateThread(
    String siteUrl,
    int threadId,
    ChatThread Function(ChatThread) change,
  ) {
    final before = _thread(siteUrl, threadId);
    if (before == null) return;
    _store.update<ChatThread>(siteUrl, threadId, change);
    if (_thread(siteUrl, threadId) case final after?) {
      _events.threadChanged(siteUrl, before, after);
    }
  }

  bool _requestIsCurrent(PluginSiteLease lease, bool Function() ownsRequest) =>
      !_disposed && lease.isCurrent && ownsRequest();

  bool preventsEviction(String siteUrl, ChatThreadTarget target) =>
      _metadata[(siteUrl: siteUrl, target: target)]?.preventsEviction ?? false;

  void revokeChannel(String siteUrl, int channelId) {
    _metadata.removeWhere((key, metadata) {
      if (key.siteUrl != siteUrl || key.target.channelId != channelId) {
        return false;
      }
      metadata.abandonDetail();
      return !metadata.preventsEviction;
    });
  }

  void forget(String siteUrl) =>
      _metadata.removeWhere((key, _) => key.siteUrl == siteUrl);

  void dispose() {
    _disposed = true;
    _metadata.clear();
  }

  bool _canCreateThread(String siteUrl, int channelId) {
    final held = _channelFor(siteUrl, channelId);
    return !_disposed &&
        held != null &&
        held.membership.following &&
        held.threadingEnabled &&
        held.canModifyMessages(
          isStaff: _currentUserFor(siteUrl)?.staff ?? false,
        );
  }

  Future<ChatThread?> refreshThreadDetail(
    String siteUrl,
    ChatThreadTarget target,
  ) {
    if (_disposed || target.channelId <= 0 || target.threadId <= 0) {
      return Future.value();
    }
    final metadata = _metadataFor(siteUrl, target);
    metadata.detailDirty = true;
    final current = metadata.detail;
    if (current != null) return current.future;

    final run = _ThreadDetailRun();
    metadata.detail = run;
    run.result.complete(
      _drainThreadDetail(siteUrl, target, metadata, run).whenComplete(() {
        if (identical(metadata.detail, run)) {
          metadata.abandonDetail();
          _releaseIdleMetadata(siteUrl, target, metadata);
        }
      }),
    );
    return run.future;
  }

  Future<ChatThread?> _drainThreadDetail(
    String siteUrl,
    ChatThreadTarget target,
    _ChatThreadMetadata metadata,
    _ThreadDetailRun run,
  ) async {
    final lease = _requests.capture(siteUrl);
    bool ownsRequest() =>
        _ownsMetadata(siteUrl, target, metadata) &&
        identical(metadata.detail, run);
    _events.detailLoading(siteUrl, target);
    while (metadata.takeDetailDirty()) {
      try {
        final requestCredentials = await _requests.credentialsFor(siteUrl);
        final apiKey = requestCredentials.apiKey;
        if (!_requestIsCurrent(lease, ownsRequest)) return null;
        final clientId = requestCredentials.clientId;
        if (!_requestIsCurrent(lease, ownsRequest)) return null;
        final detail = await requestCredentials.run(
          () => api.chatThread(
            siteUrl: siteUrl,
            channelId: target.channelId,
            threadId: target.threadId,
            apiKey: apiKey,
            clientId: clientId,
          ),
        );
        if (!_requestIsCurrent(lease, ownsRequest)) return null;
        if (detail.id != target.threadId ||
            detail.channelId != target.channelId) {
          throw StateError('Thread detail did not match its requested target.');
        }
        if (metadata.detailDirty) continue;

        ChatThread? stored;
        lease.commit(() {
          final held = _thread(siteUrl, detail.id);
          if (held == null) {
            stored = _store.put(siteUrl, detail);
          } else {
            _store.update<ChatThread>(
              siteUrl,
              detail.id,
              (current) => current.withDetail(detail),
            );
            stored = _thread(siteUrl, detail.id);
          }
          final merged = stored!;
          _events.detailStored(siteUrl, target, merged);
        });
        _events.ensureThreadSubscription(siteUrl, target);
        return stored;
      } catch (error) {
        if (!_requestIsCurrent(lease, ownsRequest)) return null;
        if (metadata.detailDirty) continue;

        final terminal =
            error is SiteLookupException &&
            (error.statusCode == 403 || error.statusCode == 404);

        lease.commit(() {
          if (terminal) _store.remove<ChatThread>(siteUrl, target.threadId);
          _events.detailFailed(siteUrl, target, terminal: terminal);
        });
        return null;
      }
    }
    return _thread(siteUrl, target.threadId);
  }

  Future<ChatThread?> createThread(
    String siteUrl, {
    required int channelId,
    required int originalMessageId,
  }) async {
    if (originalMessageId <= 0 || !_canCreateThread(siteUrl, channelId)) {
      return null;
    }
    final lease = _requests.capture(siteUrl);
    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!lease.isCurrent || _disposed || apiKey == null) return null;
      final clientId = requestCredentials.clientId;
      if (!lease.isCurrent || !_canCreateThread(siteUrl, channelId)) {
        return null;
      }
      final created = await requestCredentials.run(
        () => api.createChatThread(
          siteUrl: siteUrl,
          apiKey: apiKey,
          channelId: channelId,
          originalMessageId: originalMessageId,
          clientId: clientId,
        ),
      );
      if (!lease.isCurrent || !_canCreateThread(siteUrl, channelId)) {
        return null;
      }
      lease.commit(() {
        _store.put(siteUrl, created);
        _events.threadCreated(siteUrl, created, originalMessageId);
      });
      return created;
    } catch (error) {
      return null;
    }
  }

  /// Mirrors core's silence and staff-or-original-author presentation gates;
  /// the server remains authoritative.
  bool canEditThreadTitle(String siteUrl, ChatThread? thread) {
    final user = _currentUserFor(siteUrl);
    final authorId = thread?.originalMessage?.author.id;
    return thread != null &&
        _channelFor(siteUrl, thread.channelId)?.userSilenced != true &&
        user != null &&
        (user.staff || (user.id != null && user.id == authorId));
  }

  /// The write returns no thread record, so project the title and dirty detail
  /// to defeat an older concurrent refresh.
  Future<bool> updateThreadTitle(
    String siteUrl,
    ChatThreadTarget target,
    String title,
  ) async {
    if (_disposed ||
        target.channelId <= 0 ||
        target.threadId <= 0 ||
        title.runes.length > 100) {
      return false;
    }
    final held = _thread(siteUrl, target.threadId);
    if (held?.channelId != target.channelId ||
        !canEditThreadTitle(siteUrl, held)) {
      return false;
    }
    final metadata = _metadataFor(siteUrl, target);
    if (metadata.titleWrite != null) return false;
    final token = Object();
    final lease = _requests.capture(siteUrl);
    metadata.titleWrite = token;

    bool isCurrent() =>
        _ownsMetadata(siteUrl, target, metadata) &&
        identical(metadata.titleWrite, token) &&
        lease.isCurrent &&
        !_disposed;

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isCurrent() || apiKey == null) return false;
      final clientId = requestCredentials.clientId;
      if (!isCurrent() ||
          !canEditThreadTitle(siteUrl, _thread(siteUrl, target.threadId))) {
        return false;
      }
      await requestCredentials.run(
        () => api.updateChatThreadTitle(
          siteUrl: siteUrl,
          apiKey: apiKey,
          channelId: target.channelId,
          threadId: target.threadId,
          title: title,
          clientId: clientId,
        ),
      );
      if (!isCurrent()) return false;
      lease.commit(() {
        _store.update<ChatThread>(
          siteUrl,
          target.threadId,
          (current) => current.copyWith(title: title),
        );
        metadata.detailDirty = true;
      });
      return true;
    } catch (error) {
      return false;
    } finally {
      if (identical(metadata.titleWrite, token)) {
        metadata.titleWrite = null;
        _releaseIdleMetadata(siteUrl, target, metadata);
      }
    }
  }

  Future<bool> updateThreadNotificationLevel(
    String siteUrl,
    ChatThreadTarget target,
    ChatThreadNotificationLevel level,
  ) {
    if (_disposed || target.channelId <= 0 || target.threadId <= 0) {
      return Future.value(false);
    }
    final held = _thread(siteUrl, target.threadId);
    if (held == null || held.channelId != target.channelId) {
      return Future.value(false);
    }
    final metadata = _metadataFor(siteUrl, target);
    final queue = metadata.notifications ??= _ThreadNotificationQueue(
      held.membership,
    );

    final write = _QueuedThreadNotification(
      siteUrl: siteUrl,
      target: target,
      level: level,
      lease: _requests.capture(siteUrl),
    );
    queue.latest = write;
    final previous = held.membership;
    final optimistic =
        (previous ?? ChatThreadMembership(threadId: target.threadId))
            .withNotificationLevel(level);
    _updateThread(
      siteUrl,
      target.threadId,
      (current) => current.copyWith(membership: optimistic),
    );

    final previousTail = queue.tail;
    late final Future<void> tail;
    tail = previousTail
        .catchError((_) {})
        .then((_) => _performThreadNotificationWrite(metadata, queue, write))
        .whenComplete(() {
          if (!identical(metadata.notifications, queue) ||
              !identical(queue.tail, tail)) {
            return;
          }
          metadata.notifications = null;
          _releaseIdleMetadata(siteUrl, target, metadata);
        });
    queue.tail = tail;
    unawaited(tail);
    return write.result.future;
  }

  Future<void> _performThreadNotificationWrite(
    _ChatThreadMetadata metadata,
    _ThreadNotificationQueue queue,
    _QueuedThreadNotification write,
  ) async {
    bool isCurrent() =>
        _ownsMetadata(write.siteUrl, write.target, metadata) &&
        identical(metadata.notifications, queue) &&
        write.lease.isCurrent &&
        !_disposed;
    bool isLatest() => identical(queue.latest, write) && isCurrent();

    if (!isLatest()) {
      write.complete(false);
      return;
    }

    try {
      final requestCredentials = await _requests.credentialsFor(write.siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      if (apiKey == null) {
        _rollbackThreadNotification(queue, write);
        write.complete(false);
        return;
      }
      final clientId = requestCredentials.clientId;
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      final membership = await requestCredentials.run(
        () => api.updateChatThreadNotificationLevel(
          siteUrl: write.siteUrl,
          apiKey: apiKey,
          channelId: write.target.channelId,
          threadId: write.target.threadId,
          notificationLevel: write.level,
          clientId: clientId,
        ),
      );
      if (!isCurrent()) {
        write.complete(false);
        return;
      }
      final currentRead = _thread(
        write.siteUrl,
        write.target.threadId,
      )?.membership?.lastReadMessageId;
      final responseRead = membership.lastReadMessageId;
      final confirmed = membership.copyWith(
        lastReadMessageId:
            currentRead != null &&
                (responseRead == null || currentRead > responseRead)
            ? currentRead
            : responseRead,
      );
      queue.confirmed = confirmed;
      if (isLatest()) {
        write.lease.commit(() {
          final current = _thread(write.siteUrl, write.target.threadId);
          if (current != null) {
            _updateThread(
              write.siteUrl,
              current.id,
              (held) => held.copyWith(membership: confirmed),
            );
          }
        });
      }
      write.complete(true);
    } catch (error) {
      if (isCurrent()) {
        if (isLatest()) _rollbackThreadNotification(queue, write);
      }
      write.complete(false);
    }
  }

  void _rollbackThreadNotification(
    _ThreadNotificationQueue queue,
    _QueuedThreadNotification write,
  ) {
    if (!write.lease.isCurrent || _disposed) return;
    final previous = queue.confirmed;
    write.lease.commit(() {
      final current = _thread(write.siteUrl, write.target.threadId);
      if (current != null) {
        _updateThread(write.siteUrl, current.id, (held) {
          final membership = held.membership;
          if (previous == null || membership == null) {
            return held.copyWith(
              membership: previous,
              clearMembership: previous == null,
            );
          }
          return held.copyWith(
            membership: membership.withNotificationLevel(
              previous.notificationLevel,
            ),
          );
        });
      }
    });
  }
}

final class _QueuedThreadNotification {
  _QueuedThreadNotification({
    required this.siteUrl,
    required this.target,
    required this.level,
    required this.lease,
  });

  final String siteUrl;
  final ChatThreadTarget target;
  final ChatThreadNotificationLevel level;
  final PluginSiteLease lease;
  final Completer<bool> result = Completer<bool>();

  void complete(bool succeeded) {
    if (!result.isCompleted) result.complete(succeeded);
  }
}

final class _ChatThreadMetadata {
  bool detailDirty = false;
  _ThreadDetailRun? detail;
  Object? titleWrite;
  _ThreadNotificationQueue? notifications;

  bool get preventsEviction =>
      detailDirty ||
      detail != null ||
      titleWrite != null ||
      notifications != null;

  bool takeDetailDirty() {
    final dirty = detailDirty;
    detailDirty = false;
    return dirty;
  }

  void abandonDetail() {
    detail = null;
    detailDirty = false;
  }
}

final class _ThreadDetailRun {
  final Completer<ChatThread?> result = Completer();

  Future<ChatThread?> get future => result.future;
}

final class _ThreadNotificationQueue {
  _ThreadNotificationQueue(this.confirmed);

  ChatThreadMembership? confirmed;
  late _QueuedThreadNotification latest;
  Future<void> tail = Future.value();
}
