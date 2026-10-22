part of 'chat_controller.dart';

sealed class _ChatThreadListId {
  const _ChatThreadListId();

  static const mine = _MyChatThreadList();
}

final class _MyChatThreadList extends _ChatThreadListId {
  const _MyChatThreadList();
}

final class _ChannelChatThreadList extends _ChatThreadListId {
  const _ChannelChatThreadList(this.channelId);

  final int channelId;

  @override
  bool operator ==(Object other) =>
      other is _ChannelChatThreadList && other.channelId == channelId;

  @override
  int get hashCode => channelId.hashCode;
}

@immutable
final class _ChatThreadListSnapshot {
  factory _ChatThreadListSnapshot({
    Iterable<int>? ids,
    int offset = 0,
    bool hasMore = false,
    bool loading = false,
    String? error,
  }) => _ChatThreadListSnapshot._(
    ids: ids == null ? null : List.unmodifiable(ids),
    offset: offset,
    hasMore: hasMore,
    loading: loading,
    error: error,
  );

  const _ChatThreadListSnapshot._({
    this.ids,
    this.offset = 0,
    this.hasMore = false,
    this.loading = false,
    this.error,
  });

  const _ChatThreadListSnapshot.empty() : this._();

  final List<int>? ids;
  final int offset;
  final bool hasMore;
  final bool loading;
  final String? error;

  bool get loaded => ids != null;

  _ChatThreadListSnapshot copyWith({
    Iterable<int>? ids,
    int? offset,
    bool? hasMore,
    bool? loading,
    String? error,
  }) => _ChatThreadListSnapshot._(
    ids: ids == null ? this.ids : List.unmodifiable(ids),
    offset: offset ?? this.offset,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    error: error ?? this.error,
  );
}

enum _ChatThreadPageMode { replace, append, prepend }

final class _ChatThreadListRequest {
  _ChatThreadListRequest(this.offset, this.mode);

  final int offset;
  final _ChatThreadPageMode mode;
  final refresh = ChatThreadListRefresh();
  late final Future<void> future;
}

final class _ChatThreadListEntry {
  _ChatThreadListSnapshot snapshot = const _ChatThreadListSnapshot.empty();
  _ChatThreadListRequest? request;
  ({List<int> ids, List<ChatThread> threads})? projection;
}

final class _ChatThreadCatalog {
  _ChatThreadCatalog({
    required this.siteUrl,
    required this.lease,
    required this.api,
    required this.requests,
    required this.store,
    required this.hydrateChannel,
    required this.onChanged,
  });

  final String siteUrl;
  final PluginSiteLease lease;
  final ChatApi api;
  final PluginRequestHost requests;
  final Store store;
  final void Function(ChatChannel) hydrateChannel;
  final void Function() onChanged;

  final Map<_ChatThreadListId, _ChatThreadListEntry> _lists = {};
  int? _projectionGeneration;
  bool _retired = false;
  bool hasThreads = false;

  bool get isCurrent => !_retired && lease.isCurrent;

  _ChatThreadListSnapshot snapshot(_ChatThreadListId id) =>
      _lists[id]?.snapshot ?? const _ChatThreadListSnapshot.empty();

  List<ChatThread> channelThreads(int channelId) {
    if (!isCurrent) return const <ChatThread>[];
    final generation = store.generationOf<ChatThread>(siteUrl);
    if (_projectionGeneration != generation) {
      for (final entry in _lists.values) {
        entry.projection = null;
      }
      _projectionGeneration = generation;
    }
    final entry = _lists[_ChannelChatThreadList(channelId)];
    final ids = entry?.snapshot.ids;
    if (entry == null || ids == null) return const <ChatThread>[];
    final projection = entry.projection;
    if (projection != null && identical(projection.ids, ids)) {
      return projection.threads;
    }
    final threads = <ChatThread>[
      for (final id in ids)
        if (store.read<ChatThread>(siteUrl, id) case final thread?
            when thread.channelId == channelId &&
                thread.originalMessage?.deletedAt == null &&
                thread.originalMessage?.id != thread.lastMessageId)
          thread,
    ];
    threads.sort(ChatController._compareChannelThreads);
    final List<ChatThread> projected = List.unmodifiable(threads);
    entry.projection = (ids: ids, threads: projected);
    return projected;
  }

  void recordThreadChange(ChatThread? before, ChatThread after) {
    if (identical(before, after)) return;
    for (final entry in _lists.values) {
      entry.request?.refresh.recordChange(before, after);
    }
  }

  Set<int> loadedIdsForChannel(int channelId) => {
    ...?snapshot(_ChatThreadListId.mine).ids,
    ...?snapshot(_ChannelChatThreadList(channelId)).ids,
  };

  void insertCreated(ChatThread thread) {
    hasThreads = true;
    for (final id in [
      _ChatThreadListId.mine,
      _ChannelChatThreadList(thread.channelId),
    ]) {
      final entry = _lists[id];
      final held = entry?.snapshot;
      final ids = held?.ids;
      if (entry == null || held == null || ids == null) continue;
      entry.snapshot = held.copyWith(
        ids: [
          thread.id,
          for (final id in ids)
            if (id != thread.id) id,
        ],
        offset: held.offset + (ids.contains(thread.id) ? 0 : 1),
      );
    }
  }

  void revokeChannel(int channelId) {
    _lists.remove(_ChannelChatThreadList(channelId))?.request = null;
    final personal = _lists[_ChatThreadListId.mine];
    if (personal == null) return;
    personal.request = null;
    personal.snapshot = personal.snapshot.copyWith(
      ids: personal.snapshot.ids?.where(
        (id) => store.read<ChatThread>(siteUrl, id)?.channelId != channelId,
      ),
      loading: false,
    );
  }

  void retire() {
    _retired = true;
    _lists.clear();
  }

  Future<void> load(
    _ChatThreadListId id, {
    bool more = false,
    bool force = false,
    bool revalidate = false,
  }) {
    if (!isCurrent) return Future.value();
    final held = snapshot(id);
    if (more && !held.hasMore) return Future.value();
    final prepend =
        id is _ChannelChatThreadList &&
        !more &&
        !force &&
        revalidate &&
        held.loaded;
    if (!more && !force && !prepend && held.loaded) return Future.value();
    final entry = _lists.putIfAbsent(id, _ChatThreadListEntry.new);
    final active = entry.request;
    final supersedesActive = !more && (force || prepend);
    if (active != null && !supersedesActive) return active.future;
    final run = _ChatThreadListRequest(
      more ? held.offset : 0,
      more
          ? _ChatThreadPageMode.append
          : prepend
          ? _ChatThreadPageMode.prepend
          : _ChatThreadPageMode.replace,
    );
    entry.request = run;
    entry.snapshot = held.copyWith(loading: true);
    bool ownsRequest() =>
        isCurrent &&
        identical(_lists[id], entry) &&
        identical(entry.request, run);
    run.future = _load(id, entry, run, ownsRequest).whenComplete(() {
      if (!ownsRequest()) return;
      entry.request = null;
      entry.snapshot = entry.snapshot.copyWith(loading: false);
      onChanged();
    });
    onChanged();
    return run.future;
  }

  Future<void> _load(
    _ChatThreadListId id,
    _ChatThreadListEntry entry,
    _ChatThreadListRequest run,
    bool Function() ownsRequest,
  ) async {
    try {
      final credentials = await requests.credentialsFor(siteUrl);
      if (!ownsRequest()) return;
      final apiKey = credentials.apiKey;
      if (apiKey == null) {
        if (id is _MyChatThreadList) {
          throw const WriteException(WriteFailure.forbidden);
        }
        return;
      }
      final page = await credentials.run(
        () => switch (id) {
          _MyChatThreadList() => api.chatThreads(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: credentials.clientId,
            offset: run.offset,
          ),
          _ChannelChatThreadList(:final channelId) => api.chatChannelThreads(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: credentials.clientId,
            channelId: channelId,
            offset: run.offset,
          ),
        },
      );
      if (!ownsRequest()) return;
      lease.commit(() {
        if (id is _MyChatThreadList) {
          for (final channel in page.channels) {
            hydrateChannel(channel);
          }
        }
        for (final thread in page.threads) {
          store.put(
            siteUrl,
            run.refresh.reconcile(
              thread,
              store.read<ChatThread>(siteUrl, thread.id),
            ),
          );
        }
        final incoming = [
          for (final thread in page.threads)
            if (id is! _ChannelChatThreadList ||
                thread.channelId == id.channelId)
              thread.id,
        ];
        final held = entry.snapshot;
        final List<int> ids;
        final int offset;
        final bool hasMore;
        if (run.mode == _ChatThreadPageMode.prepend) {
          final listed = {...?held.ids};
          final added = [
            for (final id in incoming)
              if (listed.add(id)) id,
          ];
          ids = [...added, ...?held.ids];
          // New first-page rows push the server's later pages down.
          offset = held.offset + added.length;
          hasMore = held.hasMore;
        } else {
          ids = run.offset == 0
              ? incoming
              : {...?held.ids, ...incoming}.toList();
          offset = run.offset + page.threads.length;
          hasMore = page.hasMore;
        }
        entry.snapshot = _ChatThreadListSnapshot(
          ids: ids,
          offset: offset,
          hasMore: hasMore,
          loading: true,
        );
        if (id is _MyChatThreadList) {
          if (page.threads.isNotEmpty || page.hasMore) {
            hasThreads = true;
          } else if (run.offset == 0) {
            hasThreads = false;
          }
        }
      });
    } catch (error) {
      if (!ownsRequest()) return;

      if (run.mode == _ChatThreadPageMode.prepend) return;
      lease.commit(() {
        entry.snapshot = entry.snapshot.copyWith(
          error: id is _MyChatThreadList
              ? appL10n.couldNotLoadYourChatThreads
              : appL10n.couldNotLoadThisChannelSThreads,
        );
      });
    }
  }
}
