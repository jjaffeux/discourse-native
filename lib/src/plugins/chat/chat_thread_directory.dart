import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_thread.dart';

/// Browses public channel threads, including threads the reader does not follow.
/// Discourse exposes this directory per channel; reuse the controller's cached
/// pages, revalidating their first, and load further pages only as the reader
/// scrolls or requests them.
final class ChatThreadDirectory extends FrameSafeNotifier {
  ChatThreadDirectory(this.chat, this.siteUrl) {
    chat.addListener(notifySafely);
  }

  final ChatController chat;
  final String siteUrl;
  final Map<int, ChatChannel> _channels = {};
  int _offset = 0;
  int _nextChannel = 0;
  bool _moreChannels = true;
  String? _directoryError;
  bool loading = false;
  bool loaded = false;

  List<ChatThread> get threads => [
    for (final channel in _channels.values)
      ...chat.channelThreads(siteUrl, channel.id),
  ];

  List<ChatChannel> get channels => [
    for (final channel in _channels.values)
      if (chat.channelThreads(siteUrl, channel.id).isNotEmpty) channel,
  ];

  /// A view filtered to a channel the directory has reached shows only that
  /// channel's threads, so its error, remaining pages and next load are that
  /// channel's alone: further directory pages add no rows to it. Until the
  /// directory reaches the channel, paging the directory is how it arrives.
  ChatChannel? _selected(int? channelId) => _channels[channelId];

  String? error(int? channelId) {
    if (_selected(channelId) case final channel?) {
      return chat.channelThreadsError(siteUrl, channel.id);
    }
    return _directoryError ??
        _channels.keys
            .map((id) => chat.channelThreadsError(siteUrl, id))
            .whereType<String>()
            .firstOrNull;
  }

  bool hasMore(int? channelId) {
    if (_selected(channelId) case final channel?) {
      return chat.channelThreadsHaveMore(siteUrl, channel.id);
    }
    return _moreChannels ||
        _channels.keys.any(
          (id) =>
              (channelId == null || id == channelId) &&
              chat.channelThreadsHaveMore(siteUrl, id),
        );
  }

  Future<void> load({bool reset = false, int? channelId}) async {
    if (loading || isDisposed || chat.isDisposed) return;
    if (!reset && loaded && error(channelId) == null && !hasMore(channelId)) {
      return;
    }
    loading = true;
    notifySafely();
    try {
      if (reset) {
        loaded = false;
        _channels.clear();
        _offset = 0;
        _moreChannels = true;
        _nextChannel = 0;
        _directoryError = null;
      }
      final selected = _selected(channelId);
      final failed = [
        for (final channel in _channels.values)
          if (chat.channelThreadsError(siteUrl, channel.id) != null) channel,
      ];
      if (selected != null) {
        if (chat.channelThreadsError(siteUrl, selected.id) == null) {
          await chat.loadChannelThreads(
            siteUrl,
            selected.id,
            more: true,
            directoryChannel: selected,
          );
        } else {
          await chat.retryChannelThreads(
            siteUrl,
            selected.id,
            directoryChannel: selected,
          );
        }
      } else if (failed.isNotEmpty) {
        for (final channel in failed) {
          if (isDisposed || chat.isDisposed) return;
          await chat.retryChannelThreads(
            siteUrl,
            channel.id,
            directoryChannel: channel,
          );
        }
      } else if (_moreChannels) {
        final result = await chat.fetchBrowseChannels(siteUrl, offset: _offset);
        if (isDisposed || chat.isDisposed) return;
        _directoryError = result.error;
        final page = result.page;
        if (page == null) return;
        _offset += page.rowCount;
        _moreChannels = page.hasMore && page.rowCount > 0;
        for (final channel in page.channels) {
          if (isDisposed || chat.isDisposed) return;
          if (!channel.threadingEnabled) continue;
          _channels[channel.id] = channel;
          // A list held from an earlier visit misses threads started since,
          // so reaching a channel revalidates it, as opening its list does.
          await chat.loadChannelThreads(
            siteUrl,
            channel.id,
            force: reset,
            revalidate: true,
            directoryChannel: channel,
          );
        }
      } else {
        final pending = [
          for (final channel in _channels.values)
            if ((channelId == null || channel.id == channelId) &&
                chat.channelThreadsHaveMore(siteUrl, channel.id))
              channel,
        ];
        if (pending.isNotEmpty) {
          final channel = pending[_nextChannel++ % pending.length];
          await chat.loadChannelThreads(siteUrl, channel.id, more: true);
        }
      }
    } finally {
      if (!isDisposed) {
        loading = false;
        loaded = true;
        notifySafely();
      }
    }
  }

  @override
  void dispose() {
    chat.removeListener(notifySafely);
    super.dispose();
  }
}
