// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../diagnostics/diagnostics_controller.dart';
import '../../foundation/frame_safe_notifier.dart';
import '../../models/discourse_user.dart';
import '../../models/json.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/live_channels.dart';
import 'chat_channel.dart';
import 'chat_message.dart';
import 'chat_plugin_data.dart';
import 'chat_stream_target.dart';
import 'chat_thread.dart';

/// The canonical-state seam used by [ChatLiveSyncCoordinator].
///
/// MessageBus ownership stays independent from the controller's HTTP and
/// paging orchestration. The host receives only validated current-generation
/// events and the lifecycle changes that affect canonical chat state.
@immutable
final class ChatLiveSyncHost {
  const ChatLiveSyncHost({
    required this.isDisposed,
    required this.clock,
    required this.currentUserFor,
    required this.channelFor,
    required this.messageFor,
    required this.threadFor,
    required this.hasThreads,
    required this.putChannel,
    required this.putMessage,
    required this.putLiveMessage,
    required this.putThread,
    required this.publishNotificationChange,
    required this.notifyCanonicalChange,
    required this.removeKickedChannelState,
    required this.isChannelListed,
    required this.resolvePartialChannel,
    required this.insertListedChannel,
    required this.advanceLastViewedAt,
    required this.beginChannelFollow,
    required this.ownsChannelFollow,
    required this.endChannelFollow,
    required this.followChannel,
    required this.revealThreads,
    required this.admitActivityMessage,
    required this.streamContainsMessage,
    required this.admitLiveMessage,
    required this.bumpStreamsHolding,
    required this.setLoadedThreadOriginalDeleted,
    required this.scheduleThreadDetailRefresh,
    required this.applyDeleteMutation,
    required this.applyBulkDeleteMutation,
    required this.applyReactionMutation,
    required this.applyPinMutation,
    required this.applySelfFlagMutation,
    required this.applyFlagMutation,
    required this.showStreamNotice,
    required this.reconcileSentEvent,
    required this.attachReconciliationTracker,
    required this.cancelReconciliationChannel,
    required this.forgetReconciliation,
    required this.disposeReconciliation,
    required this.report,
  });

  final bool Function() isDisposed;
  final DateTime Function() clock;
  final DiscourseUser? Function(String siteUrl) currentUserFor;
  final ChatChannel? Function(String siteUrl, int channelId) channelFor;
  final ChatMessage? Function(String siteUrl, int messageId) messageFor;
  final ChatThread? Function(String siteUrl, int threadId) threadFor;
  final bool Function(String siteUrl) hasThreads;
  final void Function(String siteUrl, ChatChannel channel) putChannel;
  final void Function(String siteUrl, ChatMessage message) putMessage;
  final void Function(
    String siteUrl,
    ChatMessage message,
    bool preservePersonalizedState,
  )
  putLiveMessage;
  final void Function(String siteUrl, ChatThread thread) putThread;
  final void Function(String siteUrl, ChatChannel before, ChatChannel after)
  publishNotificationChange;
  final VoidCallback notifyCanonicalChange;
  final void Function(String siteUrl, int channelId) removeKickedChannelState;
  final bool Function(String siteUrl, int channelId) isChannelListed;
  final void Function(String siteUrl, int channelId) resolvePartialChannel;
  final void Function(String siteUrl, ChatChannel channel) insertListedChannel;
  final void Function(String siteUrl, int channelId) advanceLastViewedAt;
  final Object? Function(String siteUrl, int channelId) beginChannelFollow;
  final bool Function(String siteUrl, int channelId, Object token)
  ownsChannelFollow;
  final void Function(String siteUrl, int channelId, Object token)
  endChannelFollow;
  final Future<ChatMembership> Function(
    String siteUrl,
    String apiKey,
    String clientId,
    int channelId,
  )
  followChannel;
  final void Function(String siteUrl) revealThreads;
  final void Function(String siteUrl, int channelId, ChatMessage message)
  admitActivityMessage;
  final bool Function(String siteUrl, ChatStreamTarget target, int messageId)
  streamContainsMessage;
  final void Function(
    String siteUrl,
    ChatStreamTarget target,
    ChatMessage message,
  )
  admitLiveMessage;
  final void Function(String siteUrl, int messageId) bumpStreamsHolding;
  final void Function(
    String siteUrl,
    int channelId,
    int originalMessageId,
    DateTime? deletedAt,
    bool clear,
  )
  setLoadedThreadOriginalDeleted;
  final void Function(String siteUrl, ChatThreadTarget target)
  scheduleThreadDetailRefresh;
  final void Function(
    String siteUrl,
    Map<String, dynamic> data,
    int? channelId,
    ChatThread? thread,
  )
  applyDeleteMutation;
  final void Function(
    String siteUrl,
    Map<String, dynamic> data,
    int? channelId,
    ChatThread? thread,
    int? skipMessageId,
  )
  applyBulkDeleteMutation;
  final void Function(String siteUrl, Map<String, dynamic> data)
  applyReactionMutation;
  final void Function(String siteUrl, Map<String, dynamic> data, int? channelId)
  applyPinMutation;
  final void Function(String siteUrl, Map<String, dynamic> data)
  applySelfFlagMutation;
  final void Function(String siteUrl, Map<String, dynamic> data)
  applyFlagMutation;
  final void Function(String siteUrl, ChatStreamTarget target, String notice)
  showStreamNotice;
  final void Function(String siteUrl, ChatStreamTarget target, Object? data)
  reconcileSentEvent;
  final void Function(String siteUrl, PluginLiveChannelHandle channels)
  attachReconciliationTracker;
  final void Function(String siteUrl, int channelId)
  cancelReconciliationChannel;
  final void Function(String siteUrl) forgetReconciliation;
  final VoidCallback disposeReconciliation;
  final void Function(
    Object error,
    StackTrace stackTrace,
    String operation,
    DiagnosticSeverity severity,
  )
  report;
}

/// Owns every persistent and view-scoped Chat MessageBus lifecycle.
///
/// Callbacks are guarded by both the plugin site lease and an exact site-state
/// generation. Cancellation additionally closes the individual callback slot,
/// so a transport delivery already queued before replacement cannot mutate the
/// next account session.
final class ChatLiveSyncCoordinator {
  ChatLiveSyncCoordinator({
    required PluginRequestHost requests,
    required ChatLiveSyncHost host,
  }) : _requests = requests,
       _host = host;

  final PluginRequestHost _requests;
  final ChatLiveSyncHost _host;
  final Map<String, _ChatLiveSite> _sites = {};
  final Map<String, FrameSafeValueNotifier<Set<int>>> _presenceRefs = {};
  bool _disposed = false;

  static int? _newerCursor(int? current, int? incoming) {
    if (incoming == null) return current;
    if (current == null || incoming > current) return incoming;
    return current;
  }

  _ChatLiveSite _siteFor(String siteUrl) => _sites.putIfAbsent(
    siteUrl,
    () => _ChatLiveSite(siteUrl, _requests.capture(siteUrl)),
  );

  bool _accepts(_ChatLiveSite site, _OwnedLiveSubscription subscription) =>
      !_disposed &&
      !_host.isDisposed() &&
      identical(_sites[site.siteUrl], site) &&
      site.lease.isCurrent &&
      subscription.isActive;

  void attachTracker(String siteUrl, PluginLiveChannelHandle channels) {
    if (_disposed || _host.isDisposed()) return;
    var site = _siteFor(siteUrl);
    if (!identical(site.tracker, channels) || !site.lease.isCurrent) {
      final replacement = site.copyForReplacement(
        lease: _requests.capture(siteUrl),
        tracker: channels,
      );
      _sites[siteUrl] = replacement;
      site.cancelAll(this);
      site = replacement;
    } else {
      site.tracker = channels;
    }

    _host.attachReconciliationTracker(siteUrl, channels);
    _syncPresence(site);
    _syncPersistentSubscriptions(site);
    for (final channelId in site.rootViewTokens.keys.toList()) {
      _ensureRootSubscription(site, channelId);
    }
    for (final target in site.threadViewTokens.keys.toList()) {
      _ensureThreadSubscription(site, target);
    }
  }

  /// Replaces the HTTP-owned channel snapshot while retaining later cursors.
  void replace(String siteUrl, ChatChannels channels) {
    if (_disposed || _host.isDisposed()) return;
    final site = _siteFor(siteUrl);
    site.cancelPersistent(this);
    site.cancelPresence(this);
    site.hasChannelSnapshot = true;

    final all = [...channels.public, ...channels.direct];
    site.newMessageCursors = {
      for (final channel in all)
        if (!channel.membership.muted)
          channel.id: _newerCursor(
            site.newMessageCursors[channel.id],
            channels.newMessageBusLastIds[channel.id] ??
                channel.messageBus.newMessages,
          ),
    };
    site.newMentionCursors = {
      for (final channel in all)
        if (!channel.membership.muted)
          channel.id: _newerCursor(
            site.newMentionCursors[channel.id],
            channels.newMentionMessageBusLastIds[channel.id] ??
                channel.messageBus.newMentions,
          ),
    };
    site.kickCursors = {
      for (final channel in channels.public)
        if (!channel.membership.muted)
          channel.id: _newerCursor(
            site.kickCursors[channel.id],
            channels.kickMessageBusLastIds[channel.id] ??
                channel.messageBus.kick,
          ),
    };
    site.rootMessageCursors = {
      for (final channel in all)
        channel.id: _newerCursor(
          site.rootMessageCursors[channel.id],
          channels.channelMessageBusLastIds[channel.id] ??
              channel.messageBus.channel,
        ),
    };
    site.newChannelCursor = _newerCursor(
      site.newChannelCursor,
      channels.newChannelBusLastId,
    );
    site.channelMetadataCursor = _newerCursor(
      site.channelMetadataCursor,
      channels.channelMetadataBusLastId,
    );
    site.channelEditCursor = _newerCursor(
      site.channelEditCursor,
      channels.channelEditsBusLastId,
    );
    site.channelStatusCursor = _newerCursor(
      site.channelStatusCursor,
      channels.channelStatusBusLastId,
    );
    site.userTrackingCursor = _newerCursor(
      site.userTrackingCursor,
      channels.userTrackingBusLastId,
    );
    site.userTrackingCursorSet = true;
    site.userHasThreadsCursor = _newerCursor(
      site.userHasThreadsCursor,
      channels.userHasThreadsBusLastId,
    );
    site.userHasThreadsCursorSet = true;
    site.awaitingFirstMessage.clear();
    site.presence = channels.presence;
    _presenceRefs[siteUrl]?.value = channels.presence.userIds;

    _syncPresence(site);
    _syncPersistentSubscriptions(site);
  }

  void adoptChannel(
    String siteUrl,
    ChatChannel channel, {
    required bool includeActivity,
    bool awaitFirstMessage = false,
  }) {
    if (_disposed || _host.isDisposed()) return;
    final site = _siteFor(siteUrl);
    site.rootMessageCursors[channel.id] = _newerCursor(
      site.rootMessageCursors[channel.id],
      channel.messageBus.channel,
    );
    if (includeActivity && !channel.membership.muted) {
      site.newMessageCursors[channel.id] = _newerCursor(
        site.newMessageCursors[channel.id],
        channel.messageBus.newMessages,
      );
      site.newMentionCursors[channel.id] = _newerCursor(
        site.newMentionCursors[channel.id],
        channel.messageBus.newMentions,
      );
      if (channel.isCategoryChannel) {
        site.kickCursors[channel.id] = _newerCursor(
          site.kickCursors[channel.id],
          channel.messageBus.kick,
        );
      }
      if (awaitFirstMessage) site.awaitingFirstMessage.add(channel.id);
      _syncPersistentSubscriptions(site);
    }
    _ensureRootSubscription(site, channel.id);
  }

  void stopFollowingChannel(String siteUrl, int channelId) {
    final site = _sites[siteUrl];
    if (site == null) return;
    site.newMessageCursors.remove(channelId);
    site.newMentionCursors.remove(channelId);
    site.kickCursors.remove(channelId);
    site.rootMessageCursors.remove(channelId);
    site.awaitingFirstMessage.remove(channelId);
    site.cancelActivity(channelId, this, operation: 'chat.channelFollow');
  }

  /// Removes every live owner for a channel after an authoritative kick.
  void removeChannel(String siteUrl, int channelId) {
    final site = _sites[siteUrl];
    if (site == null) return;
    site.newMessageCursors.remove(channelId);
    site.newMentionCursors.remove(channelId);
    site.kickCursors.remove(channelId);
    site.rootMessageCursors.remove(channelId);
    site.awaitingFirstMessage.remove(channelId);
    site.activeChannelViews.remove(channelId);
    site.rootViewTokens.remove(channelId);
    site.cancelActivity(channelId, this, operation: 'chat.kick');
    site.rootSubscriptions
        .remove(channelId)
        ?.cancel(this, 'chat.kick.unsubscribe');
    final targets = [
      for (final target in site.threadSubscriptions.keys)
        if (target.channelId == channelId) target,
    ];
    for (final target in targets) {
      site.threadSubscriptions
          .remove(target)
          ?.cancel(this, 'chat.kick.unsubscribe');
      site.threadViewTokens.remove(target);
      site.threadMessageCursors.remove(target);
    }
    _host.cancelReconciliationChannel(siteUrl, channelId);
  }

  bool consumeFirstMessageReplay(
    String siteUrl,
    int channelId,
    int messageId,
    int? snapshotMessageId,
  ) {
    final site = _sites[siteUrl];
    if (site == null || !site.awaitingFirstMessage.remove(channelId)) {
      return false;
    }
    return snapshotMessageId == messageId;
  }

  Object beginViewingChannel(String siteUrl, int channelId) {
    final token = Object();
    if (_disposed || _host.isDisposed()) return token;
    final site = _siteFor(siteUrl);
    (site.activeChannelViews[channelId] ??= {}).add(token);
    _retainRoot(site, channelId, token);
    return token;
  }

  void endViewingChannel(String siteUrl, int channelId, Object token) {
    final site = _sites[siteUrl];
    if (site == null) return;
    final tokens = site.activeChannelViews[channelId];
    tokens?.remove(token);
    if (tokens != null && tokens.isEmpty) {
      site.activeChannelViews.remove(channelId);
    }
    _releaseRoot(site, channelId, token);
  }

  bool isViewingChannel(String siteUrl, int channelId) =>
      _sites[siteUrl]?.activeChannelViews.containsKey(channelId) ?? false;

  Object beginViewingThread(String siteUrl, ChatThreadTarget target) {
    final token = Object();
    if (_disposed || _host.isDisposed()) return token;
    final site = _siteFor(siteUrl);
    _retainRoot(site, target.channelId, token);
    (site.threadViewTokens[target] ??= {}).add(token);
    _ensureThreadSubscription(site, target);
    return token;
  }

  void endViewingThread(String siteUrl, ChatThreadTarget target, Object token) {
    final site = _sites[siteUrl];
    if (site == null) return;
    _releaseRoot(site, target.channelId, token);
    final tokens = site.threadViewTokens[target];
    tokens?.remove(token);
    if (tokens != null && tokens.isEmpty) {
      site.threadViewTokens.remove(target);
      site.threadSubscriptions
          .remove(target)
          ?.cancel(this, 'chat.thread.unsubscribe');
    }
  }

  void adoptThreadCursor(String siteUrl, ChatThreadTarget target, int? cursor) {
    if (_disposed || _host.isDisposed()) return;
    final site = _siteFor(siteUrl);
    site.threadMessageCursors[target] = _newerCursor(
      site.threadMessageCursors[target],
      cursor,
    );
    _ensureThreadSubscription(site, target);
  }

  void ensureThreadSubscription(String siteUrl, ChatThreadTarget target) {
    final site = _sites[siteUrl];
    if (site != null) _ensureThreadSubscription(site, target);
  }

  bool isOnline(String siteUrl, int userId) =>
      _sites[siteUrl]?.presence?.contains(userId) ?? false;

  ValueListenable<Set<int>> onlineUserIdsListenable(String siteUrl) =>
      _presenceRefs.putIfAbsent(
        siteUrl,
        () => FrameSafeValueNotifier(
          _sites[siteUrl]?.presence?.userIds ?? const {},
        ),
      );

  void _retainRoot(_ChatLiveSite site, int channelId, Object token) {
    (site.rootViewTokens[channelId] ??= {}).add(token);
    _ensureRootSubscription(site, channelId);
  }

  void _releaseRoot(_ChatLiveSite site, int channelId, Object token) {
    final tokens = site.rootViewTokens[channelId];
    tokens?.remove(token);
    if (tokens != null && tokens.isEmpty) {
      site.rootViewTokens.remove(channelId);
      site.rootSubscriptions
          .remove(channelId)
          ?.cancel(this, 'chat.channel.unsubscribe');
    }
  }

  void _ensureRootSubscription(_ChatLiveSite site, int channelId) {
    if (site.rootSubscriptions.containsKey(channelId) ||
        !(site.rootViewTokens[channelId]?.isNotEmpty ?? false)) {
      return;
    }
    final tracker = site.tracker;
    if (tracker == null) return;
    _subscribe(
      site,
      tracker,
      '/chat/$channelId',
      lastId: site.rootMessageCursors[channelId],
      operation: 'chat.channel.subscribe',
      onMessage: (data, messageId) {
        _applyRootEvent(site.siteUrl, channelId, data);
      },
      onDelivered: (messageId) {
        site.rootMessageCursors[channelId] = _newerCursor(
          site.rootMessageCursors[channelId],
          messageId,
        );
      },
      install: (subscription) {
        site.rootSubscriptions[channelId] = subscription;
      },
    );
  }

  void _ensureThreadSubscription(_ChatLiveSite site, ChatThreadTarget target) {
    if (site.threadSubscriptions.containsKey(target) ||
        !(site.threadViewTokens[target]?.isNotEmpty ?? false)) {
      return;
    }
    final tracker = site.tracker;
    final detail = _host.threadFor(site.siteUrl, target.threadId);
    if (tracker == null || detail == null) return;
    final cursor = site.threadMessageCursors[target] = _newerCursor(
      site.threadMessageCursors[target],
      detail.messageBusLastId,
    );
    _subscribe(
      site,
      tracker,
      '/chat/${target.channelId}/thread/${target.threadId}',
      lastId: cursor,
      operation: 'chat.thread.subscribe',
      onMessage: (data, messageId) {
        _applyThreadEvent(site.siteUrl, target, data);
      },
      onDelivered: (messageId) {
        site.threadMessageCursors[target] = _newerCursor(
          site.threadMessageCursors[target],
          messageId,
        );
      },
      install: (subscription) {
        site.threadSubscriptions[target] = subscription;
      },
    );
  }

  void _applyRootEvent(String siteUrl, int channelId, Object? data) {
    if (data is! Map<String, dynamic>) return;
    switch (data['type']) {
      case 'sent' || 'processed' || 'edit' || 'refresh' || 'restore':
        final payload = data['chat_message'];
        if (payload is! Map<String, dynamic>) return;
        final message = ChatMessage.fromJson(payload, siteUrl);
        if (message.id <= 0 ||
            message.channelId != channelId ||
            message.threadId != null &&
                message.thread?.threadId != message.threadId) {
          return;
        }
        // Replies without their nested root preview belong only to the thread
        // stream even though core also publishes them on the root channel.
        if (message.threadId != null && message.thread == null) return;
        _host.putLiveMessage(siteUrl, message, true);
        final target = ChatChannelTarget(channelId);
        if (data['type'] == 'sent' &&
            !_host.streamContainsMessage(siteUrl, target, message.id)) {
          _host.admitLiveMessage(siteUrl, target, message);
        }
        if (data['staged_id'] is String) {
          _host.reconcileSentEvent(siteUrl, target, data);
        }
        if (data['type'] == 'restore') {
          _host.bumpStreamsHolding(siteUrl, message.id);
          _host.setLoadedThreadOriginalDeleted(
            siteUrl,
            channelId,
            message.id,
            null,
            true,
          );
        }
        break;
      case 'thread_created':
        final payload = data['chat_message'];
        if (payload is! Map<String, dynamic>) return;
        final message = ChatMessage.fromJson(payload, siteUrl);
        if (message.channelId == channelId && message.thread != null) {
          _host.putLiveMessage(siteUrl, message, true);
        }
        break;
      case 'update_thread_original_message':
        final originalId = jsonIntOrNull(data['original_message_id']);
        final threadId = jsonIntOrNull(data['thread_id']);
        final preview = data['preview'];
        if (originalId == null ||
            threadId == null ||
            preview is! Map<String, dynamic>) {
          return;
        }
        final current = _host.messageFor(siteUrl, originalId);
        final heldThread = _host.threadFor(siteUrl, threadId);
        if (current != null && current.channelId != channelId) return;
        if (heldThread != null && heldThread.channelId != channelId) return;
        if (current == null && heldThread == null) return;
        final parsed = ChatThreadPreview.fromJson({
          'id': threadId,
          'reply_count': jsonInt(preview['reply_count']),
          // Incremental events omit title; retain it until detail refreshes.
          'title': heldThread?.title ?? current?.thread?.title,
          'preview': preview,
        }, siteUrl);
        if (parsed == null) return;
        if (current != null) {
          _host.putMessage(siteUrl, current.withThreadPreview(parsed));
        }
        if (heldThread != null) {
          _host.putThread(
            siteUrl,
            heldThread.copyWith(
              replyCount: parsed.replyCount,
              preview: parsed,
              lastMessageId: parsed.lastReplyId,
            ),
          );
          _host.notifyCanonicalChange();
        }
        _host.scheduleThreadDetailRefresh(
          siteUrl,
          ChatThreadTarget(channelId: channelId, threadId: threadId),
        );
        break;
      case 'delete':
        _host.applyDeleteMutation(siteUrl, data, channelId, null);
        if (jsonIntOrNull(data['deleted_id']) case final originalId?) {
          _host.setLoadedThreadOriginalDeleted(
            siteUrl,
            channelId,
            originalId,
            jsonDate(data['deleted_at']) ?? _host.clock().toUtc(),
            false,
          );
        }
        break;
      case 'bulk_delete':
        _host.applyBulkDeleteMutation(siteUrl, data, channelId, null, null);
        final deletedAt = jsonDate(data['deleted_at']) ?? _host.clock().toUtc();
        for (final value
            in data['deleted_ids'] is List
                ? data['deleted_ids'] as List
                : const []) {
          if (jsonIntOrNull(value) case final originalId?) {
            _host.setLoadedThreadOriginalDeleted(
              siteUrl,
              channelId,
              originalId,
              deletedAt,
              false,
            );
          }
        }
        break;
      case 'reaction':
        _host.applyReactionMutation(siteUrl, data);
        break;
      case 'pin' || 'unpin':
        _host.applyPinMutation(siteUrl, data, channelId);
        break;
      case 'self_flagged':
        _host.applySelfFlagMutation(siteUrl, data);
        break;
      case 'flag':
        _host.applyFlagMutation(siteUrl, data);
        break;
      case 'notice':
        final notice =
            jsonText(data['text_content']) ??
            jsonText(jsonObject(data['data'])['text']);
        if (notice != null) {
          _host.showStreamNotice(siteUrl, ChatChannelTarget(channelId), notice);
        }
        break;
    }
  }

  void _applyThreadEvent(
    String siteUrl,
    ChatThreadTarget target,
    Object? data,
  ) {
    if (data is! Map<String, dynamic>) return;
    final heldThread = _host.threadFor(siteUrl, target.threadId);
    final originalId = heldThread?.originalMessage?.id;
    switch (data['type']) {
      case 'sent' || 'processed' || 'edit' || 'refresh' || 'restore':
        final payload = data['chat_message'];
        if (payload is! Map<String, dynamic>) return;
        final message = ChatMessage.fromJson(payload, siteUrl);
        if (message.id <= 0 ||
            message.channelId != target.channelId ||
            message.threadId != target.threadId && message.id != originalId) {
          return;
        }
        // The original is published to both streams; only the root path may
        // apply non-idempotent mutations for that record.
        if (message.id == originalId) return;
        _host.putLiveMessage(siteUrl, message, true);
        if (data['type'] == 'restore') {
          _host.bumpStreamsHolding(siteUrl, message.id);
        }
        if (data['type'] == 'sent' &&
            !_host.streamContainsMessage(siteUrl, target, message.id)) {
          _host.admitLiveMessage(siteUrl, target, message);
        }
        if (data['staged_id'] is String) {
          _host.reconcileSentEvent(siteUrl, target, data);
        }
        break;
      case 'delete':
        if (jsonIntOrNull(data['deleted_id']) == originalId) return;
        _host.applyDeleteMutation(siteUrl, data, target.channelId, heldThread);
        break;
      case 'bulk_delete':
        _host.applyBulkDeleteMutation(
          siteUrl,
          data,
          target.channelId,
          heldThread,
          originalId,
        );
        break;
      case 'reaction':
        if (jsonIntOrNull(data['chat_message_id']) == originalId) return;
        _host.applyReactionMutation(siteUrl, data);
        break;
      case 'pin' || 'unpin':
        if (jsonIntOrNull(data['chat_message_id']) == originalId) return;
        _host.applyPinMutation(siteUrl, data, target.channelId);
        break;
      case 'self_flagged':
        if (jsonIntOrNull(data['chat_message_id']) == originalId) return;
        _host.applySelfFlagMutation(siteUrl, data);
        break;
      case 'flag':
        if (jsonIntOrNull(data['chat_message_id']) == originalId) return;
        _host.applyFlagMutation(siteUrl, data);
        break;
    }
  }

  void _syncPresence(_ChatLiveSite site) {
    if (site.presenceSubscription != null) return;
    final tracker = site.tracker;
    final presence = site.presence;
    if (tracker == null || presence == null) return;
    _subscribe(
      site,
      tracker,
      '/presence/chat/online',
      lastId: presence.lastMessageId,
      operation: 'chat.presence.subscribe',
      onMessage: (data, messageId) {
        final held = site.presence;
        if (held == null) return;
        final updated = held.withMessage(data, lastMessageId: messageId);
        site.presence = updated;
        _presenceRefs[site.siteUrl]?.value = updated.userIds;
      },
      install: (subscription) {
        site.presenceSubscription = subscription;
      },
    );
  }

  void _syncPersistentSubscriptions(_ChatLiveSite site) {
    final tracker = site.tracker;
    if (tracker == null || !site.hasChannelSnapshot) return;
    final userId = _host.currentUserFor(site.siteUrl)?.id;

    if (userId != null && site.newChannelSubscription == null) {
      _subscribe(
        site,
        tracker,
        '/chat/new-channel',
        lastId: site.newChannelCursor,
        operation: 'chat.newChannel.subscribe',
        onMessage: (data, messageId) {
          _applyNewChannel(site, data);
        },
        onDelivered: (messageId) {
          site.newChannelCursor = _newerCursor(
            site.newChannelCursor,
            messageId,
          );
        },
        install: (subscription) {
          site.newChannelSubscription = subscription;
        },
      );
    }

    if (userId != null && site.channelStateSubscriptions.isEmpty) {
      final subscriptions = <_OwnedLiveSubscription>[];
      bool add(
        String channel,
        int? lastId,
        String operation,
        void Function(Object? data) apply,
        void Function(int messageId) advance,
      ) {
        return _subscribe(
          site,
          tracker,
          channel,
          lastId: lastId,
          operation: operation,
          onMessage: (data, messageId) {
            apply(data);
          },
          onDelivered: advance,
          install: subscriptions.add,
        );
      }

      var complete = add(
        '/chat/channel-metadata',
        site.channelMetadataCursor,
        'chat.channelMetadata.subscribe',
        (data) => _applyChannelMetadata(site.siteUrl, data),
        (messageId) => site.channelMetadataCursor = _newerCursor(
          site.channelMetadataCursor,
          messageId,
        ),
      );
      complete =
          add(
            '/chat/channel-edits',
            site.channelEditCursor,
            'chat.channelEdits.subscribe',
            (data) => _applyChannelEdit(site.siteUrl, data),
            (messageId) => site.channelEditCursor = _newerCursor(
              site.channelEditCursor,
              messageId,
            ),
          ) &&
          complete;
      complete =
          add(
            '/chat/channel-status',
            site.channelStatusCursor,
            'chat.channelStatus.subscribe',
            (data) => _applyChannelStatus(site.siteUrl, data),
            (messageId) => site.channelStatusCursor = _newerCursor(
              site.channelStatusCursor,
              messageId,
            ),
          ) &&
          complete;
      if (complete) {
        site.channelStateSubscriptions.addAll(subscriptions);
      } else {
        for (final subscription in subscriptions) {
          subscription.cancel(this, 'chat.channelState.unsubscribe');
        }
      }
    }

    if (userId != null &&
        site.userTrackingCursorSet &&
        site.userTrackingSubscriptions.isEmpty) {
      var complete = true;
      final subscriptions = <_OwnedLiveSubscription>[];
      for (final channel in [
        '/chat/user-tracking-state/$userId',
        '/chat/bulk-user-tracking-state/$userId',
      ]) {
        complete =
            _subscribe(
              site,
              tracker,
              channel,
              lastId: site.userTrackingCursor,
              operation: 'chat.userTracking.subscribe',
              onMessage: (data, messageId) {
                if (channel.contains('/bulk-')) {
                  _applyBulkUserTrackingState(site.siteUrl, data);
                } else {
                  _applyUserTrackingState(site.siteUrl, data);
                }
              },
              onDelivered: (messageId) {
                site.userTrackingCursor = _newerCursor(
                  site.userTrackingCursor,
                  messageId,
                );
              },
              install: subscriptions.add,
            ) &&
            complete;
      }
      if (complete) {
        site.userTrackingSubscriptions.addAll(subscriptions);
      } else {
        for (final subscription in subscriptions) {
          subscription.cancel(this, 'chat.userTracking.unsubscribe');
        }
      }
    }

    if (userId != null &&
        site.userHasThreadsCursorSet &&
        site.userHasThreadsSubscription == null) {
      _subscribe(
        site,
        tracker,
        '/chat/user-has-threads/$userId',
        lastId: site.userHasThreadsCursor,
        operation: 'chat.userHasThreads.subscribe',
        onMessage: (data, messageId) {
          if (data is Map<String, dynamic> &&
              data['has_threads'] == true &&
              !_host.hasThreads(site.siteUrl)) {
            _host.revealThreads(site.siteUrl);
          }
        },
        onDelivered: (messageId) {
          site.userHasThreadsCursor = _newerCursor(
            site.userHasThreadsCursor,
            messageId,
          );
        },
        install: (subscription) {
          site.userHasThreadsSubscription = subscription;
        },
      );
    }

    for (final entry in site.newMessageCursors.entries.toList()) {
      if (site.newMessageSubscriptions.containsKey(entry.key)) continue;
      final channelId = entry.key;
      _subscribe(
        site,
        tracker,
        '/chat/$channelId/new-messages',
        lastId: entry.value,
        operation: 'chat.newMessages.subscribe',
        onMessage: (data, messageId) {
          _applyNewMessage(site.siteUrl, channelId, data);
        },
        onDelivered: (messageId) {
          if (site.newMessageCursors.containsKey(channelId)) {
            site.newMessageCursors[channelId] = _newerCursor(
              site.newMessageCursors[channelId],
              messageId,
            );
          }
        },
        install: (subscription) {
          site.newMessageSubscriptions[channelId] = subscription;
        },
      );
    }

    if (userId == null) return;
    for (final entry in site.newMentionCursors.entries.toList()) {
      if (site.newMentionSubscriptions.containsKey(entry.key)) continue;
      final channelId = entry.key;
      _subscribe(
        site,
        tracker,
        '/chat/$channelId/new-mentions',
        lastId: entry.value,
        operation: 'chat.newMentions.subscribe',
        onMessage: (data, messageId) {
          _applyNewMention(site.siteUrl, channelId, data);
        },
        onDelivered: (messageId) {
          if (site.newMentionCursors.containsKey(channelId)) {
            site.newMentionCursors[channelId] = _newerCursor(
              site.newMentionCursors[channelId],
              messageId,
            );
          }
        },
        install: (subscription) {
          site.newMentionSubscriptions[channelId] = subscription;
        },
      );
    }

    for (final entry in site.kickCursors.entries.toList()) {
      if (site.kickSubscriptions.containsKey(entry.key)) continue;
      final channelId = entry.key;
      _subscribe(
        site,
        tracker,
        '/chat/$channelId/kick',
        lastId: entry.value,
        operation: 'chat.kick.subscribe',
        onMessage: (data, messageId) {
          if (data is Map<String, dynamic> &&
              jsonIntOrNull(data['channel_id']) == channelId &&
              _host.channelFor(site.siteUrl, channelId) != null) {
            removeChannel(site.siteUrl, channelId);
            _host.removeKickedChannelState(site.siteUrl, channelId);
          }
        },
        onDelivered: (messageId) {
          if (site.kickCursors.containsKey(channelId)) {
            site.kickCursors[channelId] = _newerCursor(
              site.kickCursors[channelId],
              messageId,
            );
          }
        },
        install: (subscription) {
          site.kickSubscriptions[channelId] = subscription;
        },
      );
    }
  }

  void _applyNewChannel(_ChatLiveSite site, Object? data) {
    if (data is! Map<String, dynamic>) return;
    final payload = data['channel'];
    if (payload is! Map<String, dynamic>) return;

    var incoming = ChatChannel.fromJson(payload, site.siteUrl);
    final reopensDirectMessage =
        incoming.isDirectMessage && !incoming.membership.following;
    if (incoming.id <= 0 ||
        !incoming.membership.following && !reopensDirectMessage ||
        !incoming.isDirectMessage && !incoming.isCategoryChannel) {
      return;
    }
    if (reopensDirectMessage) {
      incoming = incoming.withTrackingState(
        tracking: ChatTracking(
          unreadCount: 1,
          mentionCount: incoming.tracking.mentionCount,
          watchedThreadsUnreadCount:
              incoming.tracking.watchedThreadsUnreadCount,
        ),
      );
    }

    if (_host.isChannelListed(site.siteUrl, incoming.id)) return;
    _host.putChannel(site.siteUrl, incoming);
    _host.resolvePartialChannel(site.siteUrl, incoming.id);
    if (isViewingChannel(site.siteUrl, incoming.id)) {
      _host.advanceLastViewedAt(site.siteUrl, incoming.id);
    }
    _host.insertListedChannel(site.siteUrl, incoming);

    if (!incoming.membership.muted) {
      adoptChannel(
        site.siteUrl,
        incoming,
        includeActivity: true,
        awaitFirstMessage:
            incoming.lastMessageId != null && !reopensDirectMessage,
      );
    } else {
      adoptChannel(site.siteUrl, incoming, includeActivity: false);
    }
    if (reopensDirectMessage) {
      unawaited(_followNewDirectChannel(site, incoming));
    }
    _host.notifyCanonicalChange();
  }

  Future<void> _followNewDirectChannel(
    _ChatLiveSite site,
    ChatChannel incoming,
  ) async {
    final token = _host.beginChannelFollow(site.siteUrl, incoming.id);
    if (token == null) return;
    final lease = _requests.capture(site.siteUrl);

    bool isCurrent() =>
        !_disposed &&
        !_host.isDisposed() &&
        identical(_sites[site.siteUrl], site) &&
        site.lease.isCurrent &&
        lease.isCurrent &&
        _host.ownsChannelFollow(site.siteUrl, incoming.id, token);

    try {
      final credentials = await _requests.credentialsFor(site.siteUrl);
      final apiKey = credentials.apiKey;
      if (!isCurrent() || apiKey == null) return;
      final membership = await _host.followChannel(
        site.siteUrl,
        apiKey,
        credentials.clientId,
        incoming.id,
      );
      if (!isCurrent()) return;
      lease.commit(() {
        final held = _host.channelFor(site.siteUrl, incoming.id) ?? incoming;
        final followed = held.withMembership(membership);
        _host.putChannel(site.siteUrl, followed);
        if (membership.following) {
          _host.insertListedChannel(site.siteUrl, followed);
          adoptChannel(site.siteUrl, followed, includeActivity: true);
        }
        _host.notifyCanonicalChange();
      });
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _report(error, stackTrace, 'chat.followNewDirectChannel');
      }
    } finally {
      final notify = isCurrent();
      _host.endChannelFollow(site.siteUrl, incoming.id, token);
      if (notify) _host.notifyCanonicalChange();
    }
  }

  void _applyChannelEdit(String siteUrl, Object? data) {
    if (data is! Map<String, dynamic>) return;
    final channelId = jsonIntOrNull(data['chat_channel_id']);
    final title = jsonText(data['name']);
    final slug = jsonText(data['slug']);
    final held = channelId == null
        ? null
        : _host.channelFor(siteUrl, channelId);
    if (held == null || title == null || slug == null) return;
    _host.putChannel(
      siteUrl,
      held.withRemoteMetadata(
        title: title,
        slug: slug,
        description: jsonText(data['description']),
      ),
    );
    _host.notifyCanonicalChange();
  }

  void _applyChannelStatus(String siteUrl, Object? data) {
    if (data is! Map<String, dynamic>) return;
    final channelId = jsonIntOrNull(data['chat_channel_id']);
    final rawStatus = data['status'];
    if (channelId == null ||
        rawStatus != 'open' &&
            rawStatus != 'read_only' &&
            rawStatus != 'closed' &&
            rawStatus != 'archived') {
      return;
    }
    final held = _host.channelFor(siteUrl, channelId);
    if (held == null) return;
    _host.putChannel(
      siteUrl,
      held.withRemoteStatus(ChatChannelStatus.read(rawStatus)),
    );
    _host.notifyCanonicalChange();
  }

  void _applyChannelMetadata(String siteUrl, Object? data) {
    if (data is! Map<String, dynamic>) return;
    final channelId = jsonIntOrNull(data['chat_channel_id']);
    final membershipsCount = jsonIntOrNull(data['memberships_count']);
    final held = channelId == null
        ? null
        : _host.channelFor(siteUrl, channelId);
    if (held == null || membershipsCount == null || membershipsCount < 0) {
      return;
    }
    _host.putChannel(siteUrl, held.withMembershipsCount(membershipsCount));
    _host.notifyCanonicalChange();
  }

  void _applyNewMention(String siteUrl, int channelId, Object? data) {
    if (data is! Map<String, dynamic> ||
        jsonIntOrNull(data['channel_id']) != channelId) {
      return;
    }
    final messageId = jsonIntOrNull(data['message_id']);
    final held = _host.channelFor(siteUrl, channelId);
    if (messageId == null ||
        held == null ||
        messageId <= (held.membership.lastReadMessageId ?? 0)) {
      return;
    }
    final updated = held.withTrackingState(
      tracking: ChatTracking(
        unreadCount: held.tracking.unreadCount,
        mentionCount: held.tracking.mentionCount + 1,
        watchedThreadsUnreadCount: held.tracking.watchedThreadsUnreadCount,
      ),
    );
    _host.putChannel(siteUrl, updated);
    _host.publishNotificationChange(siteUrl, held, updated);
    _host.notifyCanonicalChange();
  }

  void _applyUserTrackingState(String siteUrl, Object? data) {
    if (data is! Map<String, dynamic>) return;
    final channelId = jsonIntOrNull(data['channel_id']);
    if (channelId == null) return;
    // Nested channel and thread reports reuse field names; only the outer map
    // may update the sidebar aggregate.
    _applyTrackingState(siteUrl, channelId, data);
    final threadId = jsonIntOrNull(data['thread_id']);
    final threadTracking = data['thread_tracking'];
    if (threadId != null && threadTracking is Map<String, dynamic>) {
      final heldThread = _host.threadFor(siteUrl, threadId);
      if (heldThread != null && _threadReceivesTracking(heldThread)) {
        _host.putThread(
          siteUrl,
          heldThread.copyWith(tracking: ChatTracking.fromJson(threadTracking)),
        );
      }
      _host.notifyCanonicalChange();
    }
  }

  void _applyBulkUserTrackingState(String siteUrl, Object? data) {
    if (data is! Map<String, dynamic>) return;
    for (final entry in data.entries) {
      final channelId = int.tryParse(entry.key);
      final tracking = entry.value;
      if (channelId != null && tracking is Map<String, dynamic>) {
        _applyTrackingState(siteUrl, channelId, tracking, notify: false);
      }
    }
    _host.notifyCanonicalChange();
  }

  void _applyTrackingState(
    String siteUrl,
    int channelId,
    Map<String, dynamic> data, {
    bool notify = true,
  }) {
    final held = _host.channelFor(siteUrl, channelId);
    if (held == null) return;
    final threadId = jsonIntOrNull(data['thread_id']);

    final isChannelState = threadId == null;
    final hasLastRead = data.containsKey('last_read_message_id');
    final incomingLastRead = jsonIntOrNull(data['last_read_message_id']) ?? 0;
    final heldLastRead = held.membership.lastReadMessageId ?? 0;
    if (isChannelState && hasLastRead && incomingLastRead < heldLastRead) {
      return;
    }

    Map<int, DateTime>? threadOverview;
    if (data.containsKey('unread_thread_overview')) {
      threadOverview = {};
      for (final entry in jsonObject(data['unread_thread_overview']).entries) {
        final id = int.tryParse(entry.key);
        final createdAt = jsonDate(entry.value);
        if (id != null && id > 0 && createdAt != null) {
          threadOverview[id] = createdAt;
        }
      }
      threadOverview = Map.unmodifiable(threadOverview);
    }

    final updated = held.withTrackingState(
      tracking: ChatTracking(
        unreadCount: jsonInt(data['unread_count']),
        mentionCount: jsonInt(data['mention_count']),
        watchedThreadsUnreadCount: jsonInt(
          data['watched_threads_unread_count'],
        ),
      ),
      lastReadMessageId: isChannelState
          ? jsonIntOrNull(data['last_read_message_id'])
          : null,
      unreadThreadOverview: threadOverview,
    );
    var changed = updated != held;
    if (changed) {
      _host.putChannel(siteUrl, updated);
      _host.publishNotificationChange(siteUrl, held, updated);
    }
    if (threadId != null) {
      final heldThread = _host.threadFor(siteUrl, threadId);
      final membership = heldThread?.membership;
      final lastReadMessageId = jsonIntOrNull(data['last_read_message_id']);
      if (heldThread != null &&
          membership != null &&
          _threadReceivesTracking(heldThread) &&
          lastReadMessageId != null &&
          lastReadMessageId > (membership.lastReadMessageId ?? 0)) {
        _host.putThread(
          siteUrl,
          heldThread.copyWith(
            membership: membership.withLastReadMessageId(lastReadMessageId),
          ),
        );
        changed = true;
      }
    }
    if (changed && notify) _host.notifyCanonicalChange();
  }

  static bool _threadReceivesTracking(ChatThread thread) {
    final level = thread.membership?.notificationLevel;
    return level != null &&
        level != ChatThreadNotificationLevel.normal &&
        level != ChatThreadNotificationLevel.muted;
  }

  void _applyNewMessage(String siteUrl, int channelId, Object? data) {
    if (data is! Map<String, dynamic>) return;
    if (data['type'] != 'channel' && data['type'] != 'thread') return;
    if (jsonIntOrNull(data['channel_id']) != channelId) return;
    final payload = data['message'];
    if (payload is! Map<String, dynamic>) return;

    final messageId = jsonIntOrNull(payload['id']);
    final payloadChannelId = jsonIntOrNull(payload['chat_channel_id']);
    final createdAt = jsonDate(payload['created_at']);
    if (messageId == null ||
        messageId <= 0 ||
        payloadChannelId != channelId ||
        createdAt == null) {
      return;
    }

    final held = _host.channelFor(siteUrl, channelId);
    if (held == null) return;
    if (data['type'] == 'thread' &&
        !held.threadingEnabled &&
        data['force_thread'] != true) {
      return;
    }
    final repeatsSnapshot = consumeFirstMessageReplay(
      siteUrl,
      channelId,
      messageId,
      held.lastMessageId,
    );
    if (!repeatsSnapshot &&
        held.lastMessageId != null &&
        messageId <= held.lastMessageId!) {
      return;
    }

    final currentUser = _host.currentUserFor(siteUrl);
    final author = jsonObject(payload['user']);
    final authorId = jsonIntOrNull(author['id']);
    final authorUsername = jsonText(author['username']);
    final fromSelf = currentUser?.id != null && authorId == currentUser?.id;
    final fromIgnored =
        authorUsername != null &&
        currentUser?.ignoredUsernames.contains(authorUsername) == true;
    var markRead = false;
    var incrementUnread = false;
    if (data['type'] == 'channel') {
      if (fromSelf || fromIgnored) {
        markRead = true;
      } else if (currentUser?.id != null &&
          messageId > (held.membership.lastReadMessageId ?? 0)) {
        incrementUnread = true;
      }
    }

    final threadId = jsonIntOrNull(data['thread_id']);
    final foundThread = threadId == null
        ? null
        : _host.threadFor(siteUrl, threadId);
    final heldThread = foundThread?.channelId == channelId ? foundThread : null;
    final threadMembership = heldThread?.membership;
    final notificationLevel = threadMembership?.notificationLevel;
    final threadIsQuiet =
        notificationLevel == ChatThreadNotificationLevel.normal ||
        notificationLevel == ChatThreadNotificationLevel.muted;
    final canProjectWithoutHeldDetail =
        heldThread == null &&
        threadId != null &&
        (held.isDirectMessage ||
            held.unreadThreadOverview.containsKey(threadId));
    final markThreadUnread =
        threadId != null &&
        currentUser?.id != null &&
        !fromSelf &&
        !fromIgnored &&
        (canProjectWithoutHeldDetail ||
            threadMembership != null &&
                messageId > (threadMembership.lastReadMessageId ?? 0) &&
                !threadIsQuiet);
    final markThreadRead =
        threadId != null &&
        (threadMembership != null || canProjectWithoutHeldDetail) &&
        (fromSelf || fromIgnored);
    final watchedThreadUnread =
        markThreadUnread &&
        notificationLevel == ChatThreadNotificationLevel.watching;

    if (heldThread != null) {
      var membership = heldThread.membership;
      if (markThreadRead && membership != null) {
        membership = membership.withLastReadMessageId(messageId);
      }
      var tracking = heldThread.tracking;
      if (markThreadUnread) {
        tracking = ChatTracking(
          unreadCount: tracking.unreadCount + (watchedThreadUnread ? 0 : 1),
          mentionCount: tracking.mentionCount,
          watchedThreadsUnreadCount:
              tracking.watchedThreadsUnreadCount +
              (watchedThreadUnread ? 1 : 0),
        );
      }
      _host.putThread(
        siteUrl,
        heldThread.copyWith(
          lastMessageId: messageId,
          membership: membership,
          tracking: tracking,
        ),
      );
    }

    var updated = held.withNewMessage(
      messageId,
      createdAt,
      markRead: markRead,
      incrementUnread: incrementUnread,
      threadId: threadId,
      markThreadUnread: markThreadUnread,
      markThreadRead: markThreadRead,
      threadMembershipKnown: threadMembership != null,
      forceThread: data['force_thread'] == true,
      incrementWatchedThreadUnread: watchedThreadUnread,
    );
    if (markThreadUnread && isViewingChannel(siteUrl, channelId)) {
      final viewedAt = _host.clock().toUtc();
      final previous = updated.membership.lastViewedAt;
      if (previous == null || viewedAt.isAfter(previous)) {
        updated = updated.withLastViewedAt(viewedAt);
      }
    }

    _host.putChannel(siteUrl, updated);
    _host.publishNotificationChange(siteUrl, held, updated);
    if (data['type'] == 'channel') {
      _host.admitActivityMessage(
        siteUrl,
        channelId,
        ChatMessage.fromJson(payload, siteUrl),
      );
    }
    _host.notifyCanonicalChange();
  }

  bool _subscribe(
    _ChatLiveSite site,
    PluginLiveChannelHandle tracker,
    String channel, {
    required int? lastId,
    required String operation,
    required void Function(Object? data, int messageId) onMessage,
    void Function(int messageId)? onDelivered,
    required void Function(_OwnedLiveSubscription subscription) install,
  }) {
    final owned = _OwnedLiveSubscription();
    try {
      final subscription = tracker.subscribe(channel, (data, messageId) {
        if (!_accepts(site, owned)) return;
        try {
          onMessage(data, messageId);
        } catch (error, stackTrace) {
          _report(error, stackTrace, '$operation.apply');
        } finally {
          if (_accepts(site, owned)) onDelivered?.call(messageId);
        }
      }, lastId: lastId);
      owned.bind(subscription);
      if (owned.isActive && identical(_sites[site.siteUrl], site)) {
        install(owned);
        return true;
      } else {
        owned.cancel(this, '$operation.unsubscribe');
        return false;
      }
    } catch (error, stackTrace) {
      owned.cancel(this, '$operation.unsubscribe');
      _report(error, stackTrace, operation);
      return false;
    }
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    try {
      _host.report(error, stackTrace, operation, DiagnosticSeverity.warning);
    } catch (_) {
      // Diagnostics cannot become a second MessageBus failure.
    }
  }

  void forget(String siteUrl) {
    final site = _sites.remove(siteUrl);
    site?.cancelAll(this);
    _host.forgetReconciliation(siteUrl);
    final ref = _presenceRefs.remove(siteUrl);
    if (ref != null) ref.value = const {};
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final sites = _sites.values.toList(growable: false);
    _sites.clear();
    for (final site in sites) {
      site.cancelAll(this);
    }
    _host.disposeReconciliation();
    for (final ref in _presenceRefs.values) {
      ref.dispose();
    }
    _presenceRefs.clear();
  }
}

final class _ChatLiveSite {
  _ChatLiveSite(this.siteUrl, this.lease);

  final String siteUrl;
  final PluginSiteLease lease;
  PluginLiveChannelHandle? tracker;
  ChatPresence? presence;
  _OwnedLiveSubscription? presenceSubscription;

  Map<int, int?> newMessageCursors = {};
  Map<int, int?> newMentionCursors = {};
  Map<int, int?> kickCursors = {};
  Map<int, int?> rootMessageCursors = {};
  int? newChannelCursor;
  int? channelMetadataCursor;
  int? channelEditCursor;
  int? channelStatusCursor;
  int? userTrackingCursor;
  bool userTrackingCursorSet = false;
  int? userHasThreadsCursor;
  bool userHasThreadsCursorSet = false;
  bool hasChannelSnapshot = false;
  final Set<int> awaitingFirstMessage = {};

  _OwnedLiveSubscription? newChannelSubscription;
  final List<_OwnedLiveSubscription> channelStateSubscriptions = [];
  final List<_OwnedLiveSubscription> userTrackingSubscriptions = [];
  _OwnedLiveSubscription? userHasThreadsSubscription;
  final Map<int, _OwnedLiveSubscription> newMessageSubscriptions = {};
  final Map<int, _OwnedLiveSubscription> newMentionSubscriptions = {};
  final Map<int, _OwnedLiveSubscription> kickSubscriptions = {};

  final Map<int, Set<Object>> activeChannelViews = {};
  final Map<int, Set<Object>> rootViewTokens = {};
  final Map<int, _OwnedLiveSubscription> rootSubscriptions = {};
  final Map<ChatThreadTarget, Set<Object>> threadViewTokens = {};
  final Map<ChatThreadTarget, int?> threadMessageCursors = {};
  final Map<ChatThreadTarget, _OwnedLiveSubscription> threadSubscriptions = {};

  _ChatLiveSite copyForReplacement({
    required PluginSiteLease lease,
    required PluginLiveChannelHandle tracker,
  }) {
    final replacement = _ChatLiveSite(siteUrl, lease)
      ..tracker = tracker
      ..presence = presence
      ..newMessageCursors = Map.of(newMessageCursors)
      ..newMentionCursors = Map.of(newMentionCursors)
      ..kickCursors = Map.of(kickCursors)
      ..rootMessageCursors = Map.of(rootMessageCursors)
      ..newChannelCursor = newChannelCursor
      ..channelMetadataCursor = channelMetadataCursor
      ..channelEditCursor = channelEditCursor
      ..channelStatusCursor = channelStatusCursor
      ..userTrackingCursor = userTrackingCursor
      ..userTrackingCursorSet = userTrackingCursorSet
      ..userHasThreadsCursor = userHasThreadsCursor
      ..userHasThreadsCursorSet = userHasThreadsCursorSet
      ..hasChannelSnapshot = hasChannelSnapshot;
    replacement.awaitingFirstMessage.addAll(awaitingFirstMessage);
    for (final entry in activeChannelViews.entries) {
      replacement.activeChannelViews[entry.key] = {...entry.value};
    }
    for (final entry in rootViewTokens.entries) {
      replacement.rootViewTokens[entry.key] = Set.of(entry.value);
    }
    for (final entry in threadViewTokens.entries) {
      replacement.threadViewTokens[entry.key] = Set.of(entry.value);
    }
    replacement.threadMessageCursors.addAll(threadMessageCursors);
    return replacement;
  }

  void cancelActivity(
    int channelId,
    ChatLiveSyncCoordinator owner, {
    required String operation,
  }) {
    newMessageSubscriptions
        .remove(channelId)
        ?.cancel(owner, '$operation.unsubscribe');
    newMentionSubscriptions
        .remove(channelId)
        ?.cancel(owner, '$operation.unsubscribe');
    kickSubscriptions
        .remove(channelId)
        ?.cancel(owner, '$operation.unsubscribe');
  }

  void cancelPresence(ChatLiveSyncCoordinator owner) {
    presenceSubscription?.cancel(owner, 'chat.presence.unsubscribe');
    presenceSubscription = null;
  }

  void cancelPersistent(ChatLiveSyncCoordinator owner) {
    for (final subscription in newMessageSubscriptions.values) {
      subscription.cancel(owner, 'chat.live.unsubscribe');
    }
    newMessageSubscriptions.clear();
    for (final subscription in newMentionSubscriptions.values) {
      subscription.cancel(owner, 'chat.live.unsubscribe');
    }
    newMentionSubscriptions.clear();
    for (final subscription in kickSubscriptions.values) {
      subscription.cancel(owner, 'chat.live.unsubscribe');
    }
    kickSubscriptions.clear();
    newChannelSubscription?.cancel(owner, 'chat.live.unsubscribe');
    newChannelSubscription = null;
    for (final subscription in channelStateSubscriptions) {
      subscription.cancel(owner, 'chat.live.unsubscribe');
    }
    channelStateSubscriptions.clear();
    for (final subscription in userTrackingSubscriptions) {
      subscription.cancel(owner, 'chat.live.unsubscribe');
    }
    userTrackingSubscriptions.clear();
    userHasThreadsSubscription?.cancel(owner, 'chat.live.unsubscribe');
    userHasThreadsSubscription = null;
  }

  void cancelAll(ChatLiveSyncCoordinator owner) {
    cancelPresence(owner);
    cancelPersistent(owner);
    for (final subscription in rootSubscriptions.values) {
      subscription.cancel(owner, 'chat.stream.unsubscribe');
    }
    rootSubscriptions.clear();
    for (final subscription in threadSubscriptions.values) {
      subscription.cancel(owner, 'chat.stream.unsubscribe');
    }
    threadSubscriptions.clear();
  }
}

final class _OwnedLiveSubscription {
  PluginLiveChannelSubscription? _subscription;
  bool _active = true;
  bool _underlyingCancelled = false;

  bool get isActive => _active;

  void bind(PluginLiveChannelSubscription subscription) {
    assert(_subscription == null);
    _subscription = subscription;
    if (!_active) _cancelUnderlying();
  }

  void cancel(ChatLiveSyncCoordinator owner, String operation) {
    if (!_active) return;
    _active = false;
    try {
      _cancelUnderlying();
    } catch (error, stackTrace) {
      owner._report(error, stackTrace, operation);
    }
  }

  void _cancelUnderlying() {
    if (_underlyingCancelled || _subscription == null) return;
    _underlyingCancelled = true;
    _subscription!.cancel();
  }
}
