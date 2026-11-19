import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart' show listEquals, setEquals;

import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_thread.dart';

/// Browses threads in the reader's joined channels. Reuse the controller's
/// cached per-channel pages and load more as the reader scrolls.
final class ChatThreadDirectory extends FrameSafeNotifier {
  ChatThreadDirectory(this.chat, this.siteUrl)
    : _session = chat.captureSession(siteUrl),
      _selectedId = chat.inboxFilters.browseFor(siteUrl).threadChannelId {
    chat.addListener(_chatChanged);
  }

  static const _channelsPerLoad = 25;
  static const _concurrentChannelLoads = 4;

  final ChatController chat;
  final String siteUrl;
  final PluginSiteLease _session;
  bool get isCurrent => !isDisposed && !chat.isDisposed && _session.isCurrent;
  int? _selectedId;
  Set<int> _joinedIds = {};
  final Set<int> _started = {};
  final Map<int, ChatChannel> _discovered = {};
  int _discoveryOffset = 0;
  bool _canDiscoverMore = true;
  String? _discoveryError;
  List<List<ChatThread>> _channelThreads = const [];
  List<ChatThread> _threads = const [];
  int _nextChannel = 0;
  bool loading = false;
  bool loaded = false;

  List<ChatChannel> get joinedChannels {
    if (!isCurrent) return const [];
    final channels = {
      for (final channel in chat.publicChannels(siteUrl)) channel.id: channel,
    };
    for (final channel in _discovered.values) {
      channels.putIfAbsent(
        channel.id,
        () => chat.channel(siteUrl, channel.id) ?? channel,
      );
    }
    return [
      for (final channel in channels.values)
        if (channel.membership.following && channel.threadingEnabled) channel,
    ];
  }

  ChatChannel? get selectedChannel {
    final id = _selectedId;
    return isCurrent && id != null && _joinedIds.contains(id)
        ? chat.channel(siteUrl, id) ?? _discovered[id]
        : null;
  }

  bool select(int? id) {
    if (id == _selectedId || (id != null && !_joinedIds.contains(id))) {
      return false;
    }
    _selectedId = id;
    chat.inboxFilters.browseFor(siteUrl).threadChannelId = id;
    _started.clear();
    _nextChannel = 0;
    notifySafely();
    unawaited(load());
    return true;
  }

  Iterable<int> get _visibleIds => _selectedId == null
      ? _joinedIds
      : _joinedIds.where((id) => id == _selectedId);

  Iterable<int> get _unstarted =>
      _visibleIds.where((id) => !_started.contains(id));

  List<ChatThread> get threads {
    if (!isCurrent) return const [];
    final channelThreads = [
      for (final id in _visibleIds) chat.channelThreads(siteUrl, id),
    ];
    if (!listEquals(channelThreads, _channelThreads)) {
      final rows = [for (final threads in channelThreads) ...threads]
        ..sort(_compareThreads);
      _threads = List.unmodifiable(rows);
      _channelThreads = channelThreads;
    }
    return _threads;
  }

  static int _compareThreads(ChatThread a, ChatThread b) {
    if (a.hasNewReplies != b.hasNewReplies) return a.hasNewReplies ? -1 : 1;

    final aAt = a.preview?.lastReplyAt ?? a.originalMessage?.createdAt;
    final bAt = b.preview?.lastReplyAt ?? b.originalMessage?.createdAt;
    if (aAt != null && bAt != null) {
      final byReplyTime = bAt.compareTo(aAt);
      if (byReplyTime != 0) return byReplyTime;
    } else if (aAt != bAt) {
      return aAt == null ? 1 : -1;
    }

    final byMessageId = (b.lastMessageId ?? 0).compareTo(a.lastMessageId ?? 0);
    return byMessageId != 0 ? byMessageId : b.id.compareTo(a.id);
  }

  String? get error =>
      chat.channelsError(siteUrl) ??
      (_needsDiscovery ? _discoveryError : null) ??
      _visibleIds
          .map((id) => chat.channelThreadsError(siteUrl, id))
          .whereType<String>()
          .firstOrNull;

  bool get hasMore =>
      _unstarted.isNotEmpty ||
      _shouldDiscover ||
      _visibleIds.any((id) => chat.channelThreadsHaveMore(siteUrl, id));

  bool get _shouldDiscover =>
      _canDiscoverMore && (_selectedId == null || selectedChannel == null);

  bool get _needsDiscovery =>
      _joinedIds.isEmpty || (_selectedId != null && selectedChannel == null);

  Future<void> _discoverNextPage() async {
    // The sidebar snapshot caps open channels. The browser also lists joined
    // closed channels and memberships beyond the cap.
    final result = await chat.fetchBrowseChannels(
      siteUrl,
      offset: _discoveryOffset,
    );
    if (!isCurrent) return;
    final page = result.page;
    _discoveryError = _needsDiscovery ? result.error : null;
    _canDiscoverMore =
        _discoveryError != null ||
        (page != null && page.hasMore && page.rowCount > 0);
    if (page != null) {
      _discoveryOffset += page.rowCount;
      final sidebarIds = {
        for (final channel in chat.publicChannels(siteUrl)) channel.id,
      };
      for (final channel in page.channels) {
        if (channel.membership.following && !sidebarIds.contains(channel.id)) {
          _discovered[channel.id] = channel;
        }
      }
    }
    _syncMembership();
  }

  bool _syncMembership() {
    final next = {for (final channel in joinedChannels) channel.id};
    final changed = !setEquals(next, _joinedIds);
    if (changed) {
      _joinedIds = next;
      _started.retainAll(next);
    }
    if (_selectedId case final selected? when !next.contains(selected)) {
      final known = chat.channel(siteUrl, selected);
      final ineligible =
          known != null &&
          (!known.membership.following || !known.threadingEnabled);
      if (!ineligible && (_canDiscoverMore || !chat.channelsLoaded(siteUrl))) {
        return changed;
      }
      final filters = chat.inboxFilters.browseFor(siteUrl);
      if (filters.threadChannelId == selected) filters.threadChannelId = null;
      _selectedId = null;
    }
    return changed;
  }

  void _chatChanged() {
    final changed = isCurrent && _syncMembership();
    if (changed && loaded && !loading && _unstarted.isNotEmpty) {
      unawaited(load());
    } else {
      notifySafely();
    }
  }

  Future<void> load({bool reset = false}) async {
    if (!isCurrent || loading) return;
    if (!reset && loaded && error == null && !hasMore) return;

    loading = true;
    notifySafely();
    Set<int>? membershipAtStart;
    int? selectedAtStart;
    try {
      final refreshMembership =
          reset ||
          !chat.channelsLoaded(siteUrl) ||
          chat.channelsError(siteUrl) != null;
      if (refreshMembership) {
        await chat.loadChannels(siteUrl, force: true);
        if (!isCurrent || chat.channelsError(siteUrl) != null) return;
      }
      if (reset) {
        final selectedInSidebar = chat
            .publicChannels(siteUrl)
            .any((channel) => channel.id == _selectedId);
        if (!selectedInSidebar) {
          _discovered.clear();
          _discoveryOffset = 0;
          _canDiscoverMore = true;
          _discoveryError = null;
        }
        _started.clear();
        _nextChannel = 0;
      }
      _syncMembership();
      if (_shouldDiscover &&
          (_discoveryOffset == 0 ||
              _discoveryError != null ||
              (_unstarted.isEmpty && error == null))) {
        await _discoverNextPage();
        if (!isCurrent) return;
      }
      membershipAtStart = _joinedIds;
      selectedAtStart = _selectedId;

      final initial = _unstarted.take(_channelsPerLoad).toList();
      if (initial.isNotEmpty) {
        for (
          var start = 0;
          start < initial.length && isCurrent;
          start += _concurrentChannelLoads
        ) {
          await Future.wait([
            for (final id in initial.skip(start).take(_concurrentChannelLoads))
              if (_visibleIds.contains(id) && _started.add(id))
                chat.loadChannelThreads(
                  siteUrl,
                  id,
                  force: reset,
                  revalidate: !reset,
                  directoryChannel: _discovered[id],
                ),
          ]);
        }
        return;
      }

      final failed = _visibleIds
          .where((id) => chat.channelThreadsError(siteUrl, id) != null)
          .toList();
      if (failed.isNotEmpty) {
        for (final id in failed) {
          if (!isCurrent) return;
          if (_visibleIds.contains(id)) {
            await chat.retryChannelThreads(siteUrl, id);
          }
        }
        return;
      }

      final pending = _visibleIds
          .where((id) => chat.channelThreadsHaveMore(siteUrl, id))
          .toList();
      if (pending.isNotEmpty) {
        final id = pending[_nextChannel++ % pending.length];
        await chat.loadChannelThreads(siteUrl, id, more: true);
      }
    } finally {
      if (isCurrent) {
        loading = false;
        loaded = true;
        if (membershipAtStart != null &&
            (!identical(membershipAtStart, _joinedIds) ||
                selectedAtStart != _selectedId) &&
            _unstarted.isNotEmpty) {
          unawaited(load());
        } else {
          notifySafely();
        }
      }
    }
  }

  @override
  void dispose() {
    chat.removeListener(_chatChanged);
    super.dispose();
  }
}
