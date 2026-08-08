import 'package:flutter/foundation.dart';

import '../../data/api_credentials.dart';
import '../../data/discourse_api_contracts.dart';
import '../../data/site_lifecycle.dart';
import '../../data/store.dart';
import '../../foundation/frame_safe_notifier.dart';
import 'chat_channel.dart';
import 'chat_message.dart';

/// What the main region knows about one channel, at one moment.
///
/// The sibling of `TopicFeed`, and ids rather than messages for the same
/// reason: the messages themselves are in the [Store], where one copy is shared
/// by the row drawing it and anything else that names it, so this is only the
/// order they go in.
@immutable
class ChatStreamState {
  const ChatStreamState({
    this.messageIds = const [],
    this.loading = false,
    this.loadingOlder = false,
    this.loadingNewer = false,
    this.canLoadMorePast = false,
    this.canLoadMoreFuture = false,
    this.fetchedOnce = false,
    this.fetches = 0,
    this.lastReadOnOpen,
    this.error,
  });

  /// Oldest first, and **contiguous** — there is never a hole in the middle.
  /// That is the invariant paging depends on: [ChatController.loadOlder] pages
  /// before the first of these and [ChatController.loadNewer] after the last,
  /// so a gap anywhere between them could never be filled.
  final List<int> messageIds;

  /// A first page is on its way and there is nothing to show behind it.
  final bool loading;

  /// A page of history is on its way, under what is already on screen.
  final bool loadingOlder;

  /// A page towards the present is on its way, over what is already on screen.
  final bool loadingNewer;

  final bool canLoadMorePast;

  /// Whether there are messages between the newest one held and the present.
  ///
  /// False for a stream fetched at the live edge, which is most of them. True
  /// only while the reader is anchored back where they left off with a backlog
  /// in front of them — which is what [ChatController.openChannel] does, and
  /// the reason [ChatController.loadNewer] exists at all.
  final bool canLoadMoreFuture;

  /// Whether the site has answered at all, which is what tells an empty channel
  /// apart from one that has not been read yet.
  final bool fetchedOnce;

  /// How many times this stream has been *replaced* — opened, or jumped to the
  /// present — as opposed to paged into.
  ///
  /// The view's cue to position itself: a fresh window means the scroll offset
  /// it is holding describes messages that are no longer there, so it has to
  /// land somewhere deliberately rather than inherit it. Paging changes the
  /// list without changing where the reader is, and leaves this alone.
  final int fetches;

  /// Where the reader had got to when this stream was fetched, which is what
  /// the unread divider is drawn from.
  ///
  /// A snapshot rather than the membership's live answer, and that is the
  /// whole point of it: [ChatController.markRead] moves the membership as the
  /// reader scrolls, so a divider that watched it would slide down the screen
  /// ahead of them and then vanish. Discourse pins the same line to a
  /// `newestMessage` captured at fetch time, for the same reason. It moves
  /// when the stream is replaced — a re-open — and not before.
  final int? lastReadOnOpen;

  final String? error;

  bool get isEmpty => fetchedOnce && error == null && messageIds.isEmpty;

  /// The message to page before. Null on an empty stream, where there is
  /// nothing to page from.
  int? get oldestId => messageIds.firstOrNull;

  /// The message to page after, and the one the reader is caught up to when
  /// there is nothing in front of it.
  int? get newestId => messageIds.lastOrNull;

  /// Whether the newest message held is the newest there is.
  bool get atPresent => !canLoadMoreFuture;

  ChatStreamState copyWith({
    List<int>? messageIds,
    bool? loading,
    bool? loadingOlder,
    bool? loadingNewer,
    bool? canLoadMorePast,
    bool? canLoadMoreFuture,
    bool? fetchedOnce,
    String? error,
    bool clearError = false,
  }) => ChatStreamState(
    messageIds: messageIds ?? this.messageIds,
    loading: loading ?? this.loading,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    loadingNewer: loadingNewer ?? this.loadingNewer,
    canLoadMorePast: canLoadMorePast ?? this.canLoadMorePast,
    canLoadMoreFuture: canLoadMoreFuture ?? this.canLoadMoreFuture,
    fetchedOnce: fetchedOnce ?? this.fetchedOnce,
    // Carried rather than settable: both belong to the fetch that built this
    // window, and every copy of one is the same window still.
    fetches: fetches,
    lastReadOnOpen: lastReadOnOpen,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatStreamState &&
          listEquals(other.messageIds, messageIds) &&
          other.loading == loading &&
          other.loadingOlder == loadingOlder &&
          other.loadingNewer == loadingNewer &&
          other.canLoadMorePast == canLoadMorePast &&
          other.canLoadMoreFuture == canLoadMoreFuture &&
          other.fetchedOnce == fetchedOnce &&
          other.fetches == fetches &&
          other.lastReadOnOpen == lastReadOnOpen &&
          other.error == error;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(messageIds),
    loading,
    loadingOlder,
    loadingNewer,
    canLoadMorePast,
    canLoadMoreFuture,
    fetchedOnce,
    fetches,
    lastReadOnOpen,
    error,
  );
}

/// Which channels a site has, and which messages are in the one on screen.
///
/// Its own notifier rather than more state on `ShellController`, the way
/// `ReactionsController` and `UpdateController` are. The sidebar navigation and
/// active channel listen directly; individual messages use their store refs.
/// Chat traffic therefore redraws the regions it can change without notifying
/// every shell dependent.
///
/// Only the *asking* and the *ordering* live here. The channels and the
/// messages go in the [Store] under their own ids, so the sidebar row and the
/// screen it opens are drawing one record rather than two copies.
class ChatController extends FrameSafeNotifier {
  ChatController({
    required this.api,
    required this.credentials,
    required this.store,
    SiteLifecycle? lifecycle,
  }) : lifecycle = lifecycle ?? SiteLifecycle();

  final ChatApi api;
  final ApiCredentialReader credentials;
  final Store store;
  final SiteLifecycle lifecycle;

  /// How many messages to ask for. The site caps it at 50 and Discourse's own
  /// client sends exactly that.
  static const int pageSize = 50;

  /// How many times a site's channel list is worth asking for.
  ///
  /// Bounded like `_ensureCustomEmojis`: nothing on screen asks for this again,
  /// so a failure that could only be retried by an event which will not happen
  /// would be a dead end for the life of the session.
  static const int maxChannelAttempts = 3;

  /// Facts about requests rather than about records, which is why they are here
  /// and not in the [Store]: a channel that has never been fetched has nowhere
  /// to hold them.
  final Set<String> _loading = {};
  final Map<String, String> _errors = {};
  final Map<String, int> _attempts = {};

  /// Channel ids in the order the sidebar draws them. The channels themselves
  /// are in the [Store]; these two lists are the orderings, which no record
  /// holds.
  final Map<String, List<int>> _publicIds = {};
  final Map<String, List<int>> _directIds = {};

  /// One channel's stream, keyed `'$siteUrl~$channelId'`.
  final Map<String, ChatStreamState> _streams = {};
  final Map<String, FrameSafeValueNotifier<ChatStreamState>> _streamRefs = {};
  final Map<String, Object> _streamGenerations = {};
  final Map<String, Object> _pageRequests = {};
  final Map<
    String,
    ({String siteUrl, int channelId, int messageId, SiteLease lease})
  >
  _queuedReadReceipts = {};
  final Map<String, Future<void>> _readReceiptTasks = {};
  final Map<String, Object> _readReceiptRuns = {};

  static String _channelsKey(String siteUrl) => '$siteUrl~channels';
  static String _streamKey(String siteUrl, int id) => '$siteUrl~$id';
  static String _olderKey(String siteUrl, int id) => '$siteUrl~$id~past';
  static String _newerKey(String siteUrl, int id) => '$siteUrl~$id~future';

  // --- reads -------------------------------------------------------------

  /// The public channels this account follows, in sidebar order. Empty before
  /// the site has answered, which is also what a site with none looks like —
  /// deliberately, since nothing is drawn for either.
  List<ChatChannel> publicChannels(String siteUrl) =>
      _resolve(siteUrl, _publicIds[siteUrl]);

  List<ChatChannel> directChannels(String siteUrl) =>
      _resolve(siteUrl, _directIds[siteUrl]);

  List<ChatChannel> _resolve(String siteUrl, List<int>? ids) => [
    for (final id in ids ?? const <int>[])
      ?store.read<ChatChannel>(siteUrl, id),
  ];

  ChatChannel? channel(String siteUrl, int channelId) =>
      store.read<ChatChannel>(siteUrl, channelId);

  /// A channel to watch rather than to read, so a row redraws itself when its
  /// record changes without anything above it rebuilding.
  Ref<ChatChannel> channelRef(String siteUrl, int channelId) =>
      store.ref<ChatChannel>(siteUrl, channelId);

  Ref<ChatMessage> messageRef(String siteUrl, int messageId) =>
      store.ref<ChatMessage>(siteUrl, messageId);

  ChatStreamState stream(String siteUrl, int channelId) =>
      _streams[_streamKey(siteUrl, channelId)] ?? const ChatStreamState();

  ValueListenable<ChatStreamState> streamListenable(
    String siteUrl,
    int channelId,
  ) {
    final key = _streamKey(siteUrl, channelId);
    return _streamRefs.putIfAbsent(
      key,
      () => FrameSafeValueNotifier(_streams[key] ?? const ChatStreamState()),
    );
  }

  void _setStream(String key, ChatStreamState stream) {
    _streams[key] = stream;
    _streamRefs[key]?.value = stream;
  }

  /// The messages of one channel, oldest first, as far as they are held.
  List<ChatMessage> messages(String siteUrl, int channelId) => [
    for (final id in stream(siteUrl, channelId).messageIds)
      ?store.read<ChatMessage>(siteUrl, id),
  ];

  String? channelsError(String siteUrl) => _errors[_channelsKey(siteUrl)];

  // --- writes ------------------------------------------------------------

  /// Fetches the channels this account follows on [siteUrl].
  ///
  /// Once per site rather than on every open, unlike the reactor lists: this
  /// decides what is in the sidebar, and a sidebar that re-fetched whenever a
  /// widget rebuilt would flicker. Keeping it fresh afterwards is what step 2's
  /// live tracking is for.
  ///
  /// Failure is silent and bounded. There is nothing on screen to put an error
  /// on — no chat section exists yet to hold one — and a site that will not
  /// answer is simply a site drawn without chat, which is the same argument
  /// `SiteConfig` makes for having no error state.
  Future<void> loadChannels(String siteUrl, {bool force = false}) async {
    final key = _channelsKey(siteUrl);
    if (!force && _publicIds.containsKey(siteUrl)) return;
    if ((_attempts[key] ?? 0) >= maxChannelAttempts) return;
    if (!_loading.add(key)) return;

    final lease = lifecycle.capture(siteUrl);
    _attempts[key] = (_attempts[key] ?? 0) + 1;

    try {
      // Inside the guard, not before it: an unsigned macOS build's keychain can
      // throw rather than answer, and reading it outside would leave this key
      // stranded in `_loading` for the life of the app.
      final channels = await api.chatChannels(
        siteUrl: siteUrl,
        apiKey: await credentials.apiKeyFor(siteUrl),
        clientId: await credentials.clientId(),
      );
      if (isDisposed) return;
      lease.commit(() {
        store.putAll(siteUrl, channels.public);
        store.putAll(siteUrl, channels.direct);
        _publicIds[siteUrl] = [for (final c in channels.public) c.id];
        _directIds[siteUrl] = [for (final c in channels.direct) c.id];
        _errors.remove(key);
        _attempts.remove(key);
      });
    } catch (_) {
      if (isDisposed) return;
      lease.commit(() {
        _errors[key] = 'Could not load this site’s chat channels.';
      });
    } finally {
      if (!isDisposed) {
        lease.commit(() {
          _loading.remove(key);
          notifySafely();
        });
      }
    }
  }

  /// Puts a channel on screen where the reader left off.
  ///
  /// Anchored rather than at the live edge, which is what Discourse's own
  /// client does — `fetchMessages({fetch_from_last_read: true})` — and the
  /// reason matters more here than it does there, because [markRead] is
  /// watching: landing on the newest message means the newest message is on
  /// screen, and a reader three hundred messages behind would have all three
  /// hundred credited to them in the half second before they could scroll.
  /// Anchoring is what makes reading a thing the reader does rather than a
  /// thing that happens to them.
  ///
  /// A reader with no last-read is answered with the newest page, by the
  /// server, for free — the target resolves to nil and the query takes its
  /// no-target branch. So a channel opened for the first time still starts at
  /// the present, without this having to ask a different question.
  ///
  /// Asked again on every open, the way the reactor lists are: this is a list of
  /// what other people have just said, it is stale within minutes, and there is
  /// nothing live yet to correct it. Whatever was fetched last time stays on
  /// screen while the answer is on its way.
  ///
  /// The answer **replaces** the stream rather than merging into it. Contiguity
  /// is what [loadOlder] and [loadNewer] depend on, and merging a window fetched
  /// around one message into a window around another would leave a hole in the
  /// middle that nothing could ever fill.
  Future<void> openChannel(String siteUrl, int channelId) =>
      _fetchWindow(siteUrl, channelId, fromLastRead: true);

  /// Puts the newest page on screen, wherever the reader was.
  ///
  /// The way out of an anchored stream, and the same two-step Discourse's
  /// `scrollToLatestMessage` makes: when there is nothing in front of what is
  /// held, the present is already on screen and this is a scroll rather than a
  /// fetch — which is the view's half of it, so this simply does nothing.
  Future<void> showLatest(String siteUrl, int channelId) {
    if (stream(siteUrl, channelId).atPresent) return Future.value();
    return _fetchWindow(siteUrl, channelId, fromLastRead: false);
  }

  Future<void> _fetchWindow(
    String siteUrl,
    int channelId, {
    required bool fromLastRead,
  }) async {
    final key = _streamKey(siteUrl, channelId);
    if (!_loading.add(key)) return;

    final lease = lifecycle.capture(siteUrl);
    final generation = Object();
    _streamGenerations[key] = generation;
    _pageRequests.remove(_olderKey(siteUrl, channelId));
    _pageRequests.remove(_newerKey(siteUrl, channelId));
    final held = stream(siteUrl, channelId);
    _setStream(
      key,
      held.copyWith(
        // Only a stream with nothing in it gets to show a spinner in place of
        // content; a re-open refreshes underneath what is already there.
        loading: held.messageIds.isEmpty,
        loadingOlder: false,
        loadingNewer: false,
        clearError: true,
      ),
    );

    try {
      final page = await api.chatMessages(
        siteUrl: siteUrl,
        channelId: channelId,
        fromLastRead: fromLastRead,
        pageSize: pageSize,
        apiKey: await credentials.apiKeyFor(siteUrl),
        clientId: await credentials.clientId(),
      );
      if (isDisposed) return;
      lease.commit(() {
        if (!identical(_streamGenerations[key], generation)) return;
        store.putAll(siteUrl, page.messages);
        _setStream(
          key,
          ChatStreamState(
            messageIds: _sortedIds(siteUrl, page.messages),
            canLoadMorePast: page.canLoadMorePast,
            canLoadMoreFuture: page.canLoadMoreFuture,
            fetchedOnce: true,
            fetches: held.fetches + 1,
            lastReadOnOpen: channel(
              siteUrl,
              channelId,
            )?.membership.lastReadMessageId,
          ),
        );
      });
    } catch (_) {
      if (isDisposed) return;
      lease.commit(() {
        if (!identical(_streamGenerations[key], generation)) return;
        final current = _streams[key] ?? const ChatStreamState();
        _setStream(
          key,
          current.copyWith(
            fetchedOnce: true,
            error: current.messageIds.isEmpty
                ? 'Could not load this channel.'
                : null,
          ),
        );
      });
    } finally {
      if (!isDisposed) {
        lease.commit(() {
          if (!identical(_streamGenerations[key], generation)) return;
          final current = _streams[key];
          if (current != null && current.loading) {
            _setStream(key, current.copyWith(loading: false));
          }
          _loading.remove(key);
        });
      }
    }
  }

  /// Prepends the page immediately before the oldest message held.
  ///
  /// Does nothing when the site has said there is no more, when a page is
  /// already on its way, or before there is an oldest message to page from —
  /// each of which the view can and does ask for anyway, because the cheapest
  /// place to answer "no" is here.
  Future<void> loadOlder(String siteUrl, int channelId) async {
    final key = _streamKey(siteUrl, channelId);
    final held = stream(siteUrl, channelId);
    final before = held.oldestId;
    if (!held.canLoadMorePast || before == null) return;

    final guard = _olderKey(siteUrl, channelId);
    if (_loading.contains(key) || _pageRequests.containsKey(guard)) return;

    final lease = lifecycle.capture(siteUrl);
    final generation = _streamGenerations.putIfAbsent(key, Object.new);
    final request = Object();
    _pageRequests[guard] = request;
    _setStream(key, held.copyWith(loadingOlder: true));

    try {
      final page = await api.chatMessages(
        siteUrl: siteUrl,
        channelId: channelId,
        before: before,
        pageSize: pageSize,
        apiKey: await credentials.apiKeyFor(siteUrl),
        clientId: await credentials.clientId(),
      );
      if (isDisposed) return;
      lease.commit(() {
        if (!identical(_streamGenerations[key], generation) ||
            !identical(_pageRequests[guard], request)) {
          return;
        }
        store.putAll(siteUrl, page.messages);
        final current = _streams[key] ?? const ChatStreamState();
        final merged = _sortedIds(
          siteUrl,
          page.messages,
          held: current.messageIds,
        );

        _setStream(
          key,
          current.copyWith(
            messageIds: merged,
            canLoadMorePast:
                merged.length > current.messageIds.length &&
                page.canLoadMorePast,
            fetchedOnce: true,
          ),
        );
      });
    } catch (_) {
      // History that would not load is not worth an error state: what is on
      // screen is still true, and scrolling up again asks again.
    } finally {
      if (!isDisposed) {
        lease.commit(() {
          if (!identical(_streamGenerations[key], generation) ||
              !identical(_pageRequests[guard], request)) {
            return;
          }
          final current = _streams[key];
          if (current != null) {
            _setStream(key, current.copyWith(loadingOlder: false));
          }
          _pageRequests.remove(guard);
        });
      }
    }
  }

  /// Appends the page immediately after the newest message held.
  ///
  /// [loadOlder] read forwards, and every argument it makes applies mirrored —
  /// including the "brought nothing new" override, which is safe for the same
  /// reason: `direction=future` answers with ids strictly above the newest held
  /// one, so anything it returns is new by construction.
  ///
  /// Only ever does anything on a stream [openChannel] anchored behind the
  /// present. On a stream fetched at the live edge `canLoadMoreFuture` is
  /// false, and this is the cheapest place to say so.
  Future<void> loadNewer(String siteUrl, int channelId) async {
    final key = _streamKey(siteUrl, channelId);
    final held = stream(siteUrl, channelId);
    final after = held.newestId;
    if (!held.canLoadMoreFuture || after == null) return;

    final guard = _newerKey(siteUrl, channelId);
    if (_loading.contains(key) || _pageRequests.containsKey(guard)) return;

    final lease = lifecycle.capture(siteUrl);
    final generation = _streamGenerations.putIfAbsent(key, Object.new);
    final request = Object();
    _pageRequests[guard] = request;
    _setStream(key, held.copyWith(loadingNewer: true));

    try {
      final page = await api.chatMessages(
        siteUrl: siteUrl,
        channelId: channelId,
        after: after,
        pageSize: pageSize,
        apiKey: await credentials.apiKeyFor(siteUrl),
        clientId: await credentials.clientId(),
      );
      if (isDisposed) return;
      lease.commit(() {
        if (!identical(_streamGenerations[key], generation) ||
            !identical(_pageRequests[guard], request)) {
          return;
        }
        store.putAll(siteUrl, page.messages);
        final current = _streams[key] ?? const ChatStreamState();
        final merged = _sortedIds(
          siteUrl,
          page.messages,
          held: current.messageIds,
        );

        _setStream(
          key,
          current.copyWith(
            messageIds: merged,
            canLoadMoreFuture:
                merged.length > current.messageIds.length &&
                page.canLoadMoreFuture,
            fetchedOnce: true,
          ),
        );
      });
    } catch (_) {
      // Same as [loadOlder]: what is on screen is still true, and scrolling
      // down again asks again.
    } finally {
      if (!isDisposed) {
        lease.commit(() {
          if (!identical(_streamGenerations[key], generation) ||
              !identical(_pageRequests[guard], request)) {
            return;
          }
          final current = _streams[key];
          if (current != null) {
            _setStream(key, current.copyWith(loadingNewer: false));
          }
          _pageRequests.remove(guard);
        });
      }
    }
  }

  /// Credits the reader with everything in a channel up to [messageId].
  ///
  /// Called from the view as the reader scrolls, debounced there — the same
  /// division Discourse draws, where the component watches the viewport and
  /// `chatApi.markChannelAsRead` is the thing it calls. What lives here is
  /// every rule about *whether* the write happens.
  ///
  /// Optimistic, and deliberately not undone when the write fails. There is
  /// nothing to tell the reader — this is not an action they took — and the
  /// site is the one keeping score: the next fetch of the channel list brings
  /// its answer, which corrects anything this got wrong. Putting a badge back
  /// under a reader who has visibly read the messages would be the worse lie.
  Future<void> markRead(String siteUrl, int channelId, int messageId) {
    if (isDisposed) return Future.value();
    final held = channel(siteUrl, channelId);
    if (held == null) return Future.value();
    final lease = lifecycle.capture(siteUrl);

    // Only a followed channel has a membership row to move. The site is blunt
    // about the rest — `find_for_user(following: true)` misses, and the answer
    // is a 404 — and this app only ever draws followed channels anyway.
    if (!held.membership.following) return Future.value();

    // Never backwards, which is both the site's rule and the reader's: paging
    // into the past must not undo what they have already seen. This also
    // de-duplicates the common second viewport tick for the same message.
    final lastRead = held.membership.lastReadMessageId;
    if (lastRead != null && lastRead >= messageId) return Future.value();

    // Both halves are load-bearing since the stream can be anchored behind the
    // present: the reader is caught up only if this is the last message held
    // *and* there is nothing in front of it. Discourse asks its loader the same
    // two questions — `!canLoadMoreFuture && firstMessage.id === last.id`.
    final window = stream(siteUrl, channelId);
    final caughtUp = window.atPresent && window.newestId == messageId;

    // Before credential storage, not after: the await below is a gap two scroll
    // ticks can both arrive in, and the guard above is only a guard once the
    // answer it reads has been written.
    store.update<ChatChannel>(
      siteUrl,
      channelId,
      (current) => current.withLastRead(messageId, caughtUp: caughtUp),
    );
    notifySafely();

    return _queueReadReceipt(
      siteUrl: siteUrl,
      channelId: channelId,
      messageId: messageId,
      lease: lease,
    );
  }

  Future<void> _queueReadReceipt({
    required String siteUrl,
    required int channelId,
    required int messageId,
    required SiteLease lease,
  }) {
    final key = _streamKey(siteUrl, channelId);
    // Only one write per channel runs at once. While it does, every viewport
    // tick supersedes the previous queued position: sending an intermediate
    // read marker has no value once the reader is already farther ahead.
    _queuedReadReceipts[key] = (
      siteUrl: siteUrl,
      channelId: channelId,
      messageId: messageId,
      lease: lease,
    );

    final running = _readReceiptTasks[key];
    if (running != null) return running;

    final run = Object();
    _readReceiptRuns[key] = run;
    final task = _drainReadReceipts(key, run);
    _readReceiptTasks[key] = task;
    return task;
  }

  Future<void> _drainReadReceipts(String key, Object run) async {
    while (true) {
      // Forgetting a site removes this run synchronously. Without checking
      // before the dequeue, its next loop could steal a receipt queued by a
      // new account session using the same site and channel key.
      if (!identical(_readReceiptRuns[key], run)) return;
      final receipt = _queuedReadReceipts.remove(key);
      if (receipt == null) {
        // Cleared in the same synchronous turn that observed an empty queue,
        // so a new caller cannot attach work to a task that has already ended.
        // Identity keeps an invalidated old session from clearing a new run.
        if (identical(_readReceiptRuns[key], run)) {
          _readReceiptRuns.remove(key);
          final _ = _readReceiptTasks.remove(key);
        }
        return;
      }
      try {
        final apiKey = await credentials.apiKeyFor(receipt.siteUrl);
        if (isDisposed || !receipt.lease.isCurrent) continue;
        // A channel on screen belongs to a connected site, so this is the
        // unsigned-macOS-keychain case rather than a reader without a key. The
        // guess stands; nothing else can be done with it.
        if (apiKey == null) continue;

        final clientId = await credentials.clientId();
        if (isDisposed || !receipt.lease.isCurrent) continue;
        await api.markChatChannelRead(
          siteUrl: receipt.siteUrl,
          apiKey: apiKey,
          channelId: receipt.channelId,
          messageId: receipt.messageId,
          clientId: clientId,
        );
      } catch (_) {
        // There is nobody to tell, and nothing to put back. A newer queued
        // position must still be attempted after this one fails.
      }
    }
  }

  /// Forgets a disconnected site.
  ///
  /// More than `ReactionsController.forget` drops, because more than the
  /// questions belong to this class: the two channel lists and every stream are
  /// orderings, and no record holds those. The channels and the messages
  /// themselves are the [Store]'s to forget.
  void forget(String siteUrl) {
    _loading.removeWhere((key) => key.startsWith('$siteUrl~'));
    _errors.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _attempts.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _streams.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _streamGenerations.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _pageRequests.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _queuedReadReceipts.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _readReceiptTasks.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _readReceiptRuns.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    final forgottenRefs = <FrameSafeValueNotifier<ChatStreamState>>[];
    _streamRefs.removeWhere((key, ref) {
      if (!key.startsWith('$siteUrl~')) return false;
      forgottenRefs.add(ref);
      return true;
    });
    // Detach before notifying. A listener can synchronously look up a stream,
    // and that new session must receive a new ref rather than putting the old
    // account's notifier back into this map. The detached ref is not disposed:
    // a widget may still be listening during the frame that removes it.
    for (final ref in forgottenRefs) {
      ref.value = const ChatStreamState();
    }
    _publicIds.remove(siteUrl);
    _directIds.remove(siteUrl);
    notifySafely();
  }

  /// Union by id, ordered by `(createdAt, id)`.
  ///
  /// Deduping by id and not by identity, because the same message arrives twice
  /// whenever a page overlaps a boundary; the store has already merged the two
  /// copies into one record, and the list must not name it twice or the row is
  /// built twice.
  ///
  /// The tiebreak is load-bearing rather than tidy. `created_at` is serialised
  /// as iso8601, so two messages written in the same second carry equal dates
  /// on the wire; Dart's sort is unstable, so a date-only comparator lets those
  /// two swap places every time a page is merged and the list visibly
  /// reshuffles under the reader. The merge also has to be idempotent — folding
  /// a page that overlaps one already held must give the identical list — and a
  /// comparator that can return zero cannot promise that. `(created_at, id)` is
  /// the site's own `ORDER BY`.
  List<int> _sortedIds(
    String siteUrl,
    Iterable<ChatMessage> arrived, {
    List<int> held = const [],
  }) {
    final dates = <int, DateTime>{
      for (final id in held)
        if (store.read<ChatMessage>(siteUrl, id) case final message?)
          id: message.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      for (final message in arrived)
        message.id: message.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    };

    return dates.keys.toList()..sort((a, b) {
      final byDate = dates[a]!.compareTo(dates[b]!);
      return byDate != 0 ? byDate : a.compareTo(b);
    });
  }

  @override
  void dispose() {
    _queuedReadReceipts.clear();
    _readReceiptTasks.clear();
    _readReceiptRuns.clear();
    for (final ref in _streamRefs.values) {
      ref.dispose();
    }
    _streamRefs.clear();
    super.dispose();
  }
}
